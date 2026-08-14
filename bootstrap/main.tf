# =====================================================================
# Bootstrap — recursos criados UMA vez, localmente. Depois disso todo
# provisionamento passa pelo GitHub Actions no repo tcc-infra.
#
# Cria:
#   - S3 bucket para o Terraform state (versionado + criptografado)
#   - DynamoDB table para state locking (evita apply concorrente)
#   - IAM user desafio-ods-ci com policy scoped:
#       * EC2/VPC full (para envs/prod/ provisionar)
#       * S3/DynamoDB restritos ao bucket e tabela deste bootstrap
# =====================================================================

# Sufixo aleatorio para tornar o nome do bucket unico globalmente.
resource "random_id" "state_suffix" {
  byte_length = 4
}

locals {
  bucket_name = "${var.name_prefix}-tfstate-${random_id.state_suffix.hex}"
  lock_table  = "${var.name_prefix}-tflock"
  ci_user     = "${var.name_prefix}-ci"
}

# ---------------------------------------------------------------------
# S3 bucket para tfstate
# ---------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket        = local.bucket_name
  force_destroy = false # NUNCA true: perda do state e catastrofica

  tags = {
    Purpose = "terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------
# DynamoDB para state locking
# ---------------------------------------------------------------------
resource "aws_dynamodb_table" "tflock" {
  name         = local.lock_table
  billing_mode = "PAY_PER_REQUEST" # esta no free tier com folga
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Purpose = "terraform-state-locking"
  }
}

# ---------------------------------------------------------------------
# IAM user para o GitHub Actions
# ---------------------------------------------------------------------
resource "aws_iam_user" "ci" {
  name = local.ci_user
  path = "/ci/"
}

resource "aws_iam_access_key" "ci" {
  user = aws_iam_user.ci.name
}

# EC2 full: cobre EC2 + VPC + SG + EIP + KeyPair, que e tudo que envs/prod usa.
resource "aws_iam_user_policy_attachment" "ci_ec2" {
  user       = aws_iam_user.ci.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# Permite deploy via SSM (nao precisa SSH aberto pro runner do GitHub Actions).
# Escopo restrito: SendCommand so em instancias com tag Project=desafio-ods.
resource "aws_iam_user_policy" "ci_ssm" {
  name = "${local.ci_user}-ssm"
  user = aws_iam_user.ci.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendCommandDocument"
        Effect = "Allow"
        Action = ["ssm:SendCommand"]
        Resource = [
          "arn:aws:ssm:*::document/AWS-RunShellScript",
        ]
      },
      {
        Sid      = "SendCommandInstancesTagged"
        Effect   = "Allow"
        Action   = ["ssm:SendCommand"]
        Resource = ["arn:aws:ec2:*:*:instance/*"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = "desafio-ods"
          }
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

# Acesso restrito ao bucket de state e a tabela de lock — nada alem.
resource "aws_iam_user_policy" "ci_state" {
  name = "${local.ci_user}-state"
  user = aws_iam_user.ci.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketVersioning",
        ]
        Resource = aws_s3_bucket.tfstate.arn
      },
      {
        Sid    = "S3ObjectRW"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.tfstate.arn}/*"
      },
      {
        Sid    = "DynamoLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.tflock.arn
      },
    ]
  })
}
