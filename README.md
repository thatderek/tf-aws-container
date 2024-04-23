# tf-aws-container

A Terraform module creating an AWS Elastic Container Repository and builds the container -- all in the cloud, and in single apply! ٩(˘◡˘)۶  

## Who should use this?

Do you have a simple application you want to deploy using AWS' ECR but realized it's a somewhat disjointed process? Did you get pumped about deploying containerized Lambdas, only to realize the createLambda call [requires the conatiner](https://docs.aws.amazon.com/lambda/latest/api/API_FunctionCode.html#:~:text=Contents-,ImageUri,-URI%20of%
) already exist in ECR, and so now you have multiple pipelines to deploy your application with just 30 lines of code?

This module is for you fellow engineer! 

## Design Goals

- Be runner agnostic
    - Some attempts to do this rely on whatever is running the terraform-apply _also_ having the docker service installed and available to build and push the contianer. That may work in a fair number of cases, but I want this to work everwhere: containers, terraform-cloud, github actions, etc. By limiting the requirements strictly to terraform and a version, we can be sure to not cause runner/builder/ci lock in for what should be a relatively trivial process. 
- Enable single terraform-apply operations
    - The whole point of this is to avoid the common practice whereby multiple pipelines are required to do simple stuff like building a container backed AWS Lambda or deploy small apps to ECS. Mulitple pipelines, chaining things, and (shudder) manual steps are right out. 
 Mulitple pipelines, chaining things, and (shudder) manual steps are right out. 



## Actually, no one should use this (yet)

I'm still noodling around on this and so I'm making the repo public to get feed back from some folks -- though anyone is welcome to send me a note or raise an issue or whatever. In the meantime though, this will technically work, but don't use it yet if you need it to continue to work in the same way. I have an idea about using Lambda instead of ImageBuilder to do this that will allow for (I hope) much more flexability. 

In the mean time though, if you want to check out the [examples/](./examples) folder, I'm putting demos in there to show what kind of functionality I'm aiming to build. Careful, they do use AWS serivces so there's _some_ cost but it should be negligable.


### [go-server](./examples/go-server) example

This shows how, with a dockerfile and a folder of uncompiled go-code, this module can build a container remotely, store it in ecr, and make it available for use by an ECS Task Definition running behind a load balancer. Navigate over to that directory and run `teraform init && terraform apply` and about 5-6 minutes later, it will pop out a `endpoint` output where you can check out the compiled go http server running. 

```bash
➜  go-server git:(main) ✗ terraform init && terraform apply --auto-approve

Initializing the backend...
Initializing modules...

Initializing provider plugins...

....
.... _several minutes later_
....

aws_ecs_task_definition.app: Creating...
aws_ecs_task_definition.app: Creation complete after 1s [id=app-hslhwpv7]
module.ecs_cluster.aws_ecs_service.main: Creating...
module.ecs_cluster.aws_ecs_service.main: Creation complete after 1s [id=arn:aws:ecs:us-east-1:400575516093:service/app-hslhwpv7/app-hslhwpv7]

Apply complete! Resources: 44 added, 0 changed, 0 destroyed.

Outputs:

endpoint = "http://app-hslhwpv7-1159156321.us-east-1.elb.amazonaws.com"
➜  go-server git:(main) ✗ curl http://app-hslhwpv7-1159156321.us-east-1.elb.amazonaws.com
Hello from ecs task: Howdy! I'm coming to you from the app-hslhwpv7 task! ┏( ͡❛ ͜ʖ ͡❛)┛%
➜  go-server git:(main) ✗
```

And with that, you can now party _all_ the way down with your new ECS Web app. 乁(⪧∀⪦˵ )ㄏ

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.46.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | n/a |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.46.0 |
| <a name="provider_random"></a> [random](#provider\_random) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_ecr_repository.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_iam_instance_profile.imagebuilder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_policy.imagebuilder_code_download](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.imagebuilder_service_policy_basic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.imagebuilder_service_policy_extended](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.imagebuilder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.imagebuilder_execute](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.imagebuilder_code_download](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.imagebuilder_ec2instanceprofileforimagebuildecrcontainerbuilds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.imagebuilder_ec2instanceprofileforimagebuilder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.imagebuilder_ssmmagagedinstancecore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.test_execute_service_basic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.test_execute_service_extended](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_imagebuilder_component.code_download](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/imagebuilder_component) | resource |
| [aws_imagebuilder_container_recipe.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/imagebuilder_container_recipe) | resource |
| [aws_imagebuilder_distribution_configuration.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/imagebuilder_distribution_configuration) | resource |
| [aws_imagebuilder_image.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/imagebuilder_image) | resource |
| [aws_imagebuilder_infrastructure_configuration.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/imagebuilder_infrastructure_configuration) | resource |
| [aws_imagebuilder_workflow.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/imagebuilder_workflow) | resource |
| [aws_s3_bucket.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_object.code](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_security_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ssm_document.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document) | resource |
| [random_string.main](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [archive_file.code](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy.AWSServiceRoleForImageBuilder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy) | data source |
| [aws_partition.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_ecr_repository_attributes"></a> [aws\_ecr\_repository\_attributes](#input\_aws\_ecr\_repository\_attributes) | The attributes to set on the ECR Repository. This takes a map as it's input and for any attribute not included, the default specified on the [5.43.0](https://registry.terraform.io/providers/hashicorp/aws/5.43.0/docs/resources/ecr_repository) documentation is used. | <pre>object({<br>    force_delete         = optional(string, false)<br>    image_tag_mutability = optional(string, "MUTABLE")<br><br>    encryption_configuration = optional(map(any), {<br>      encryption_type = "AES256"<br>      kms_key         = ""<br>    })<br><br>    image_scanning_configuration = optional(map(any), {<br>      scan_on_push = true<br>    })<br><br>  })</pre> | `{}` | no |
| <a name="input_code_path"></a> [code\_path](#input\_code\_path) | The path where the code for this project lives. \_Note: The folder must contain, minimally, a Dockefile at the root. | `string` | n/a | yes |
| <a name="input_imagebuilder_instance_types"></a> [imagebuilder\_instance\_types](#input\_imagebuilder\_instance\_types) | The type of instances used to build the the images made by this module. By default, we use compute specialized Graviaton instances. | `list(string)` | <pre>[<br>  "c6a.large",<br>  "c5a.large"<br>]</pre> | no |
| <a name="input_imagebuilder_key_pair_name"></a> [imagebuilder\_key\_pair\_name](#input\_imagebuilder\_key\_pair\_name) | The [key-pair name](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html#how-to-generate-your-own-key-and-import-it-to-aws) to start the ImageBuilder instances with. This is useful if you want to debug builds ImageBuilder. See also `imagebuilder_terminate_instance_on_failure` variable. | `string` | `""` | no |
| <a name="input_imagebuilder_terminate_instance_on_failure"></a> [imagebuilder\_terminate\_instance\_on\_failure](#input\_imagebuilder\_terminate\_instance\_on\_failure) | Determines whether the underlaying instance is terminated when the build process fails. This is useful for debugging purposes. | `bool` | `true` | no |
| <a name="input_random_suffix"></a> [random\_suffix](#input\_random\_suffix) | This appends a random suffix to the resources created by this module. Defaults to true to maintain the ability to apply multiple times in an account. | `bool` | `true` | no |
| <a name="input_resource_name"></a> [resource\_name](#input\_resource\_name) | What to name resources deployed by this module. Works in conjunction with `var.random_suffix` bool. | `string` | `"app"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | The subnet id where ImageBuilder should run instances building containers. Note: if left blank, ImageBuilder will attempt to use a subnet in the default VPC. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_ecr_repository"></a> [aws\_ecr\_repository](#output\_aws\_ecr\_repository) | n/a |
| <a name="output_aws_imagebuilder_image"></a> [aws\_imagebuilder\_image](#output\_aws\_imagebuilder\_image) | Information about the image built by this module. |
| <a name="output_name"></a> [name](#output\_name) | The name used by this module for deployed resources. |
