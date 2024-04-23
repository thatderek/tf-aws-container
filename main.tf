variable "random_suffix" {
  default     = true
  type        = bool
  description = "This appends a random suffix to the resources created by this module. Defaults to true to maintain the ability to apply multiple times in an account."
}

resource "random_string" "main" {
  length  = 8
  special = false
  upper   = false
}

variable "resource_name" {
  default     = "app"
  type        = string
  description = "What to name resources deployed by this module. Works in conjunction with `var.random_suffix` bool."
}

locals {
  name = var.random_suffix ? "${var.resource_name}-${random_string.main.result}" : var.resource_name
}

output "name" {
  description = "The name used by this module for deployed resources."
  value       = local.name
}

variable "aws_ecr_repository_attributes" {
  description = "The attributes to set on the ECR Repository. This takes a map as it's input and for any attribute not included, the default specified on the [5.43.0](https://registry.terraform.io/providers/hashicorp/aws/5.43.0/docs/resources/ecr_repository) documentation is used."

  type = object({
    force_delete         = optional(string, false)
    image_tag_mutability = optional(string, "MUTABLE")

    encryption_configuration = optional(map(any), {
      encryption_type = "AES256"
      kms_key         = ""
    })

    image_scanning_configuration = optional(map(any), {
      scan_on_push = true
    })

  })
  default = {}
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

output "aws_ecr_repository" {
  value = aws_ecr_repository.main
}

data "aws_region" "main" {}

variable "subnet_id" {
  description = "The subnet id where ImageBuilder should run instances building containers. Note: if left blank, ImageBuilder will attempt to use a subnet in the default VPC."
  default     = ""
}

data "aws_subnet" "main" {
  for_each = var.subnet_id == "" ? [] : toset([var.subnet_id])
  id       = var.subnet_id
}

resource "aws_security_group" "main" {
  for_each = var.subnet_id == "" ? [] : toset([var.subnet_id])
  name     = "imagebuilder-${local.name}"

  vpc_id = data.aws_subnet.main[var.subnet_id].vpc_id
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}


resource "aws_imagebuilder_distribution_configuration" "main" {
  name = local.name

  distribution {
    region = data.aws_region.main.name
    container_distribution_configuration {
      target_repository {
        repository_name = aws_ecr_repository.main.name
        service         = "ECR"
      }
    }
  }
}

resource "aws_s3_bucket" "main" {
  bucket = local.name
}

resource "aws_iam_instance_profile" "imagebuilder" {
  role = aws_iam_role.imagebuilder.name
}

resource "aws_iam_role" "imagebuilder" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "imagebuilder_code_download" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:GetObject"]
        Resource = [
          "arn:${data.aws_partition.main.partition}:s3:::${aws_s3_bucket.main.bucket}",
          "arn:${data.aws_partition.main.partition}:s3:::${aws_s3_bucket.main.bucket}/*"
        ]
        Effect = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "imagebuilder_code_download" {
  role       = aws_iam_role.imagebuilder.name
  policy_arn = aws_iam_policy.imagebuilder_code_download.arn
}

resource "aws_iam_role_policy_attachment" "imagebuilder_ssmmagagedinstancecore" {
  role       = aws_iam_role.imagebuilder.name
  policy_arn = "arn:${data.aws_partition.main.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "imagebuilder_ec2instanceprofileforimagebuilder" {
  role       = aws_iam_role.imagebuilder.name
  policy_arn = "arn:${data.aws_partition.main.partition}:iam::aws:policy/EC2InstanceProfileForImageBuilder"
}

resource "aws_iam_role_policy_attachment" "imagebuilder_ec2instanceprofileforimagebuildecrcontainerbuilds" {
  role       = aws_iam_role.imagebuilder.name
  policy_arn = "arn:${data.aws_partition.main.partition}:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
}

variable "imagebuilder_terminate_instance_on_failure" {
  type        = bool
  description = "Determines whether the underlaying instance is terminated when the build process fails. This is useful for debugging purposes."
  default     = true
}

variable "imagebuilder_key_pair_name" {
  type        = string
  description = "The [key-pair name](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html#how-to-generate-your-own-key-and-import-it-to-aws) to start the ImageBuilder instances with. This is useful if you want to debug builds ImageBuilder. See also `imagebuilder_terminate_instance_on_failure` variable."
  default     = ""
}

variable "imagebuilder_instance_types" {
  type        = list(string)
  description = "The type of instances used to build the the images made by this module. By default, we use compute specialized Graviaton instances."
  default     = ["c6a.large", "c5a.large"]
}

resource "aws_imagebuilder_infrastructure_configuration" "main" {
  name = local.name

  instance_profile_name = aws_iam_instance_profile.imagebuilder.name

  instance_types                = var.imagebuilder_instance_types
  terminate_instance_on_failure = var.imagebuilder_terminate_instance_on_failure
  key_pair                      = var.imagebuilder_key_pair_name == "" ? null : var.imagebuilder_key_pair_name

  subnet_id          = var.subnet_id == "" ? null : var.subnet_id
  security_group_ids = var.subnet_id == "" ? null : [aws_security_group.main[var.subnet_id].id]

  logging {
    s3_logs {
      s3_bucket_name = aws_s3_bucket.main.bucket
      s3_key_prefix  = "imagbuilder_logs/"
    }
  }
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

  # Delete build logs after 90 days
  rule {
    id     = "buildLogs"
    status = "Enabled"
    expiration {
      days = 90
    }
    filter {
      prefix = "imagebuilder_logs/"
    }
  }

}

variable "code_path" {
  description = "The path where the code for this project lives. _Note: The folder must contain, minimally, a Dockefile at the root."
  type        = string
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = var.code_path
  output_path = "code.zip"
}

resource "aws_s3_object" "code" {
  bucket      = aws_s3_bucket.main.bucket
  key         = "code.zip"
  source      = data.archive_file.code.output_path
  source_hash = filemd5(data.archive_file.code.output_path)
}

resource "aws_imagebuilder_component" "code_download" {
  data = yamlencode({
    phases = [{
      name = "build"
      steps = [{
        action = "ExecuteBash"
        inputs = {
          commands = [
            "aws s3 cp s3://${aws_s3_bucket.main.bucket}/${aws_s3_object.code.key} .",
            "unzip ${aws_s3_object.code.key}",
            "cd ${trimsuffix(aws_s3_object.code.key, ".zip")}"
          ]
        }
        name      = "${local.name}-code_download"
        onFailure = "Abort"
      }]
    }]
    schemaVersion = 1.0
  })
  name     = "${local.name}-code_download"
  platform = "Linux"
  version  = "1.0.0"
}

locals {
  imagebuilder_working_directory = "/tmp/imagebuilder_service"
}

resource "aws_ssm_document" "main" {
  name            = "app_download_${local.name}"
  document_format = "YAML"
  document_type   = "Command"

  # It appears imagebuilder's createImage command fails when running the SendCommand action
  # against an SSM Doc that doesn't have `parameters` set. So this is a placeholder to keep
  # things working until either that's fixed or my error in understanding what I'm seeing
  # is sorted. ( ˘︹˘ )
  content = <<DOC
schemaVersion: '1.2'
description: Downloads code for ${local.name}
parameters:
  foo:
    type: String
    default: bar
runtimeConfig:
  'aws:runShellScript':
    properties:
      - id: '0.aws:runShellScript'
        runCommand:
          - aws s3 cp s3://${aws_s3_bucket.main.bucket}/${aws_s3_object.code.key} /tmp/
          - mkdir -p ${local.imagebuilder_working_directory}
          - unzip /tmp/${aws_s3_object.code.key} -d ${local.imagebuilder_working_directory}
DOC

}

resource "aws_imagebuilder_container_recipe" "main" {
  name    = join("-", [local.name, substr(aws_s3_object.code.source_hash, 0, 8)])
  version = "1.0.0"

  container_type = "DOCKER"
  parent_image   = "arn:${data.aws_partition.main.partition}:imagebuilder:${data.aws_region.main.name}:aws:image/amazon-linux-x86-latest/x.x.x"

  working_directory = "/tmp/" # ImageBuilder cds into `/${working_directory}/imagebuilder_service

  target_repository {
    repository_name = aws_ecr_repository.main.name
    service         = "ECR"
  }

  component {
    component_arn = aws_imagebuilder_component.code_download.arn
  }

  dockerfile_template_data = templatefile("${var.code_path}/Dockerfile",
    { code_location = "${aws_s3_bucket.main.bucket}/${aws_s3_object.code.key}" }
  )
}

data "aws_caller_identity" "main" {}

data "aws_partition" "main" {}

resource "aws_iam_role" "imagebuilder_execute" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "imagebuilder.${data.aws_partition.main.dns_suffix}"
      }
      Sid = ""
    }]
  })
  name = "imagebuilder-${local.name}"
}

data "aws_iam_policy" "AWSServiceRoleForImageBuilder" {
  arn = "arn:${data.aws_partition.main.partition}:iam::aws:policy/aws-service-role/AWSServiceRoleForImageBuilder"
}

resource "aws_iam_policy" "imagebuilder_service_policy_basic" {
  name   = "imagebuilder-execute-basic-${local.name}"
  policy = data.aws_iam_policy.AWSServiceRoleForImageBuilder.policy
}

resource "aws_iam_role_policy_attachment" "test_execute_service_basic" {
  policy_arn = aws_iam_policy.imagebuilder_service_policy_basic.arn
  role       = aws_iam_role.imagebuilder_execute.name
}

resource "aws_iam_policy" "imagebuilder_service_policy_extended" {
  name = "imagebuilder-execute-extended-${local.name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "ssm:SendCommand"
      Effect = "Allow"
      Resource = [
        "arn:${data.aws_partition.main.partition}:ssm:${data.aws_region.main.id}::document/AWS-UpdateSSMAgent",
        aws_ssm_document.main.arn,
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "test_execute_service_extended" {
  policy_arn = aws_iam_policy.imagebuilder_service_policy_extended.arn
  role       = aws_iam_role.imagebuilder_execute.name
}

resource "aws_imagebuilder_image" "main" {
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.main.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.main.arn
  container_recipe_arn             = aws_imagebuilder_container_recipe.main.arn

  execution_role = aws_iam_role.imagebuilder_execute.arn

  workflow {
    workflow_arn = aws_imagebuilder_workflow.main.arn
  }

  workflow {
    workflow_arn = "arn:${data.aws_partition.main.partition}:imagebuilder:${data.aws_region.main.id}:aws:workflow/distribution/distribute-container/x.x.x"
  }

  depends_on = [
    aws_s3_object.code,
    aws_iam_role_policy_attachment.test_execute_service_basic,
    aws_iam_role_policy_attachment.test_execute_service_extended
  ]

  lifecycle {
    ignore_changes = [
      workflow
    ]
  }

}

output "aws_imagebuilder_image" {
  description = "Information about the image built by this module."
  value       = aws_imagebuilder_image.main
}

resource "aws_imagebuilder_workflow" "main" {
  name    = local.name
  version = "1.0.0"
  type    = "BUILD"

  data = <<-EOT
name: build-container
description: Workflow to build a container image
schemaVersion: 1.0

steps:
  - name: LaunchBuildInstance
    action: LaunchInstance
    onFailure: Abort
    inputs:
      waitFor: "ssmAgent"

  - name: BootstrapBuildInstance
    action: BootstrapInstanceForContainer
    onFailure: Abort
    if:
      stringEquals: "DOCKER"
      value: "$.imagebuilder.imageType"
    inputs:
      instanceId.$: "$.stepOutputs.LaunchBuildInstance.instanceId"

  - name: RunCommandDoc
    action: RunCommand
    onFailure: Abort
    inputs:
      documentName: "${aws_ssm_document.main.name}"
      instanceId.$: "$.stepOutputs.LaunchBuildInstance.instanceId"
      parameters:
        foo:
          - bar

  - name: ApplyBuildComponents
    action: ExecuteComponents
    onFailure: Abort
    inputs:
      instanceId.$: "$.stepOutputs.LaunchBuildInstance.instanceId"

outputs:
  - name: "InstanceId"
    value: "$.stepOutputs.LaunchBuildInstance.instanceId"
  EOT
}

terraform {
  required_providers {
    aws = {
      version = ">= 5.46.0"
    }
  }
}
