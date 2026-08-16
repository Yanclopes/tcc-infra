# =====================================================================
# GitHub Actions OIDC — permite que workflows assumam roles AWS sem
# usar access keys long-lived. O token OIDC (curto, ~15 min) e trocado
# por credenciais AWS a cada job.
#
# Substitui o par (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) do CI user
# por um secret unico (AWS_ROLE_ARN) nos repos que assumem essa role.
# =====================================================================

# Thumbprints do issuer OIDC do GitHub. Modern AWS valida via CA e ignora
# thumbprints; passa os dois conhecidos por compatibilidade defensiva.
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# ---------------------------------------------------------------------
# Role compartilhada por ambos os repos (tcc-infra e tcc-backend).
# Cada workflow assume via OIDC; trust policy limita quais sub podem.
# ---------------------------------------------------------------------
locals {
  ci_role_name = "${var.name_prefix}-ci-oidc"

  # Repos + refs autorizados a assumir a role.
  #   tcc-infra  -> so master (aplica prod)
  #   tcc-backend -> qualquer ref (deploys em push/tag)
  allowed_subs = [
    "repo:Yanclopes/tcc-infra:ref:refs/heads/master",
    "repo:Yanclopes/tcc-backend:*",
  ]
}

resource "aws_iam_role" "ci_oidc" {
  name = local.ci_role_name
  path = "/ci/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.allowed_subs
          }
        }
      }
    ]
  })
}

# Reusa as MESMAS policies que o CI user ja tem — evita duplicar e mantem
# o escopo de permissoes consistente entre os dois modos de auth.
resource "aws_iam_role_policy_attachment" "ci_oidc_ec2" {
  role       = aws_iam_role.ci_oidc.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "ci_oidc_s3_app" {
  role       = aws_iam_role.ci_oidc.name
  policy_arn = aws_iam_policy.ci_s3_app.arn
}

# Inline policies iguais as do CI user (nao ha managed policy espelho).
resource "aws_iam_role_policy" "ci_oidc_iam_app" {
  name = "${local.ci_role_name}-iam-app"
  role = aws_iam_role.ci_oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageAppRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRolePolicy", "iam:ListRolePolicies",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
          "iam:PassRole",
        ]
        Resource = "arn:aws:iam::*:role/desafio-ods-*"
      },
      {
        Sid    = "ManageAppInstanceProfile"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
        ]
        Resource = "arn:aws:iam::*:instance-profile/desafio-ods-*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "ci_oidc_ssm" {
  name = "${local.ci_role_name}-ssm"
  role = aws_iam_role.ci_oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SendCommandDocument"
        Effect   = "Allow"
        Action   = ["ssm:SendCommand"]
        Resource = ["arn:aws:ssm:*::document/AWS-RunShellScript"]
      },
      {
        Sid      = "SendCommandInstancesTagged"
        Effect   = "Allow"
        Action   = ["ssm:SendCommand"]
        Resource = ["arn:aws:ec2:*:*:instance/*"]
        Condition = {
          StringEquals = { "aws:ResourceTag/Project" = "desafio-ods" }
        }
      },
      {
        Sid    = "InspectCommandsAndInstances"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ec2:DescribeInstances",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "ci_oidc_state" {
  name = "${local.ci_role_name}-state"
  role = aws_iam_role.ci_oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3BucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketVersioning"]
        Resource = aws_s3_bucket.tfstate.arn
      },
      {
        Sid      = "S3ObjectRW"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.tfstate.arn}/*"
      },
      {
        Sid      = "DynamoLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.tflock.arn
      },
    ]
  })
}

# ---------------------------------------------------------------------
# Output para colar como GitHub Secret AWS_ROLE_ARN em ambos os repos.
# ---------------------------------------------------------------------
output "ci_oidc_role_arn" {
  description = "ARN da role para GitHub Actions OIDC. Cadastrar como secret AWS_ROLE_ARN nos repos tcc-infra e tcc-backend."
  value       = aws_iam_role.ci_oidc.arn
}
