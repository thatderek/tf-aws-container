variable "random_suffix" {
  default     = true
  type        = bool
  description = "This appends a random suffix to the resources created by this module. Defaults to true to maintain the ability to apply multiple times in an account."
}
variable "resource_name" {
  default     = "app"
  type        = string
  description = "What to name resources deployed by this module. Works in conjunction with `var.random_suffix` bool."
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

variable "subnet_id" {
  description = "The subnet id where the container will be built by ECS."
  type        = string
}

variable "code_path" {
  description = "The path where the code for this project lives. _Note: The folder must contain, minimally, a Dockefile at the root."
  type        = string
}

variable "cpu_architecture" {
  description = "The CPU architecture used to build this container. Must be one of `X86_64` or `ARM`."
  default     = "X86_64"
  validation {
    condition     = contains(["X86_64", "ARM"], var.cpu_architecture)
    error_message = "This must be either `X86_64` or `ARM`."
  }
}


variable "operating_system_family" {
  description = "The Operating System family to be used by ECS to build this container. Must be on of those listed [here](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#runtime-platform) for Fargate."
  default     = "LINUX"
  validation {
    condition = contains([
      "LINUX", "WINDOWS_SERVER_2019_FULL", "WINDOWS_SERVER_2019_CORE",
      "WINDOWS_SERVER_2022_FULL", "WINDOWS_SERVER_2022_CORE",
    ], var.operating_system_family)
    error_message = "This must be in the list specified in the validation condition for this variable."
  }
}

variable "lambda_ephemeral_storage_mb" {
  description = "The amount of ephemeral storage to provision the lambda function with. Used in the reformatting of the code base from a .zip to a .tar.gz. Usually this won't need to be changed from the default."
  default     = 512
  type        = number
  validation {
    condition     = var.lambda_ephemeral_storage_mb >= 512 && var.lambda_ephemeral_storage_mb <= 10240
    error_message = "The specified amount of storage must be between 512 (mb) and 10240."
  }
}

variable "image_tags_additional" {
  description = "By default we tag the image with a hash of the code and tags that the container was built with; however, with this variable, you can specify additional strings to tag the image with."
  default     = []
  type        = list(string)
}
