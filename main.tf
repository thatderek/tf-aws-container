resource "random_string" "main" {
  length  = 8
  special = false
  upper   = false
}

locals {
  # Builds the name we'll use to label everything with
  name = var.random_suffix ? "${var.resource_name}-${random_string.main.result}" : var.resource_name

  # Builds an image tag from a combination of hashes of additional tags and the source code
  code_hash = filebase64sha256(data.archive_file.code.output_path)
  tag_hash  = sha256(jsonencode(var.image_tags_additional))
  image_tag = sha256("${local.code_hash}${local.tag_hash}")

  # Decodes the output of our lambda_invocation for use by the data ecr_image confirming our container
  # built and is available.
  aws_lambda_invocation_result = jsondecode(aws_lambda_invocation.main.result)
}

resource "aws_ecr_repository" "main" {
  name                 = local.name
  force_delete         = var.aws_ecr_repository_attributes.force_delete
  image_tag_mutability = var.aws_ecr_repository_attributes.image_tag_mutability

  encryption_configuration {
    encryption_type = var.aws_ecr_repository_attributes.encryption_configuration.encryption_type
    kms_key         = var.aws_ecr_repository_attributes.encryption_configuration.kms_key
  }

  image_scanning_configuration {
    scan_on_push = var.aws_ecr_repository_attributes.image_scanning_configuration.scan_on_push
  }
}

data "aws_region" "main" {}

data "aws_subnet" "main" {
  id = var.subnet_id
}

resource "aws_security_group" "main" {
  name = "ecs-builder-${local.name}"

  vpc_id = data.aws_subnet.main.vpc_id
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_s3_bucket" "main" {
  bucket        = local.name
  force_destroy = true
}

resource "aws_iam_role" "ecs_executor" {
  name = "ecs-executor-${local.name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "ecs-task-${local.name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "code_download" {
  name = "code-download-${local.name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "arn:${data.aws_partition.main.partition}:s3:::${aws_s3_bucket.main.bucket}",
          "arn:${data.aws_partition.main.partition}:s3:::${aws_s3_bucket.main.bucket}/*"
        ]
        Effect = "Allow"
      },
    ]
  })
}

resource "aws_iam_policy" "ecr" {
  name = "ecr-${local.name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:DescribeRepositories",
          "ecr:ListTagsForResource",
        ]
        Resource = ["*"]
        Effect   = "Allow"
      },
      {
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetLifecyclePolicy",
          "ecr:GetLifecyclePolicyPreview",
          "ecr:DescribeImageScanFindings",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = [
          aws_ecr_repository.main.arn
        ]
        Effect = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_code_download" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.code_download.arn
}

resource "aws_iam_role_policy_attachment" "ecs_ecr" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecr.arn
}

data "aws_iam_policy" "AmazonECSTaskExecutionRolePolicy" {
  arn = "arn:${data.aws_partition.main.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "ecs_executor" {
  name   = "ecs-executor-${local.name}"
  policy = data.aws_iam_policy.AmazonECSTaskExecutionRolePolicy.policy
}

resource "aws_iam_role_policy_attachment" "ecs_executor" {
  role       = aws_iam_role.ecs_executor.name
  policy_arn = aws_iam_policy.ecs_executor.arn
}

resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  # Delete everything after 1 year
  rule {
    id     = "rule0"
    status = "Enabled"
    expiration {
      days = 365
    }
  }
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = var.code_path
  output_path = "${path.module}/code.zip"
}

resource "aws_s3_object" "code" {
  bucket      = aws_s3_bucket.main.bucket
  key         = "${filemd5(data.archive_file.code.output_path)}.zip"
  source      = data.archive_file.code.output_path
  source_hash = filemd5(data.archive_file.code.output_path)
}

data "aws_caller_identity" "main" {}

data "aws_partition" "main" {}

resource "aws_cloudwatch_log_group" "main" {
  name = "builder-${local.name}"
}
resource "aws_ecs_cluster" "main" {
  name = "builder-${local.name}"

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"
      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.main.name
      }
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "main" {
  family = "builder-${local.name}"

  execution_role_arn = aws_iam_role.ecs_executor.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  network_mode = "awsvpc"

  cpu    = 4096
  memory = 16384

  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name   = "kaniko"
      image  = "gcr.io/kaniko-project/executor:latest"
      cpu    = 4096  # Provisioning this gratuitously but open to making these 
      memory = 16384 # vars if our Windows friends need it
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = data.aws_region.main.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_iam_role" "lambda" {
  name = "lambda-${local.name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda" {
  name = "lambda-${local.name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["${aws_cloudwatch_log_group.main.arn}:*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = [aws_ecs_task_definition.main.arn]
      },
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.ecs_executor.arn,
          aws_iam_role.ecs_task.arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeTasks"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:DescribeImages"]
        Resource = [aws_ecr_repository.main.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.code_download.arn
}

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_controller.zip"
  source_file = "${path.module}/lambda_controller.py"
}

resource "aws_lambda_function" "main" {
  function_name = "builder-${local.name}"
  role          = aws_iam_role.lambda.arn

  architectures = ["arm64"]
  runtime       = "python3.12"
  handler       = "lambda_controller.lambda_handler"
  memory_size   = 256
  timeout       = 900

  filename         = data.archive_file.lambda.output_path
  package_type     = "Zip"
  source_code_hash = filebase64sha256(data.archive_file.lambda.output_path)

  ephemeral_storage {
    size = var.lambda_ephemeral_storage_mb
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.main.name
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_lambda,
    aws_iam_role_policy_attachment.lambda_s3
  ]

}

resource "aws_lambda_invocation" "main" {
  function_name = aws_lambda_function.main.function_name

  input = jsonencode({
    repo_name             = aws_ecr_repository.main.name
    s3_bucket             = aws_s3_bucket.main.id
    cluster_name          = aws_ecs_cluster.main.name
    task_definition_arn   = aws_ecs_task_definition.main.arn
    image_tag             = local.image_tag
    image_tags_additional = var.image_tags_additional
    repository_uri        = aws_ecr_repository.main.repository_url
    code_location         = aws_s3_object.code.key
    subnet_id             = var.subnet_id
    security_group_id     = aws_security_group.main.id
  })

  triggers = {
    redeployment = aws_lambda_function.main.last_modified
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_lambda,
    aws_iam_role_policy_attachment.lambda_s3,
    aws_iam_policy.lambda,
    aws_lambda_function.main
  ]
}

data "aws_ecr_image" "main" {
  repository_name = local.aws_lambda_invocation_result["repositoryName"]
  image_tag       = local.aws_lambda_invocation_result["imageTag"]
  image_digest    = local.aws_lambda_invocation_result["imageDigest"]
}

terraform {
  required_providers {
    aws = {
      version = ">= 5.46.0" # TODO: Figure out how far back this can go
    }
  }
}
