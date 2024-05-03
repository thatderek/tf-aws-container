# tf-aws-container

A Terraform module creating an AWS Elastic Container Repository and builds the container -- all in the cloud, and in single apply! ٩(˘◡˘)۶  


## Who should use this?

Do you have a simple application you want to deploy using AWS' ECR but realized it's a somewhat disjointed process? Did you get pumped about deploying containerized Lambdas, only to realize the `createLambda` call [requires the conatiner](https://docs.aws.amazon.com/lambda/latest/api/API_FunctionCode.html#:~:text=Contents-,ImageUri,-URI%20of%
) already exist in ECR, and so now you have multiple pipelines to deploy your 30 lines of code application?

This module is for you fellow engineer! 


## Features

Using a combination of ECS Fargate, Lambda, and [Kaniko](https://github.com/GoogleContainerTools/kaniko), this module builds an ECR Repository, your container, and uploads the latter to the former. 

Some cool stuff it can do: 

- Name-safety / scalability
    - By default, you can deploy this module over and over and it won't collide into preexisting S3 bucket names, IAM Policy names, etc.
- Secure
    - IAM Permissions are pretty locked down and this module doesn't appear to have permissions to anything that isn't absolutely necessary. If you do see something that can be locked down further, please don't hestiate to raise a PR!
- Fine grained control of the ECR Repository via the [aws_ecr_repository_attributes](#input_aws_ecr_repository_attributes) variable
- The ability to build containers for either `X86_64` or `ARM` platforms via [cpu_architecture](#input_cpu_architecture)
- Windows containers via [operating_system_family](#input_operating_system_family)
- Arbitrary combinations of container tags via [image_tags_additional](#input_image_tags_additional)


## How to use this

From a terraform file call this module like so could be used to build an AWS Lambda backed by an ECR Container: 

```tf
module "container" {
  source    = "git@github.com:thatderek/tf-aws-container.git"     # See note below

  code_path     = "./code"
  resource_name = "normal-human-webapp"
  subnet_id     = "subnet-abc123"

  aws_ecr_repository_attributes = {
    force_delete = true
  }
}

resource "aws_lambda_function" "webapp" {
  function_name = "jackie-daytona-ai"
  role          = aws_iam_role.iam_for_lambda.arn

  image = module.container.aws_ecr_image.image_uri
}


```
_Note:_ Don't acutally just blindly call this module without pinning to a branch, tag (when I start publishing this properly), or a commit. More instructions on how to do that [here](https://developer.hashicorp.com/terraform/language/modules/sources#selecting-a-revision).


One of the two required variables is `subnet_id` delineating where ECS will deploy a task to build a container. The current version of this requires access to the Kaniko repo in docker hub and so requires internet access.

The other required variable is `code_path`. In it must be a Dockerfile containing the instructions for building your app along with any dependencies otherwise not downloaded via the Dockerfile's instructions. 

From the [examples/go-server](./examples/go-server) example, we see a directory sturcture that looks like: 

```bash
➜  go-server git:(main) tree .
.
├── code
│   ├── Dockerfile
│   ├── go.mod
│   └── main.go
└── main.tf

1 directory, 4 files
➜  go-server git:(main)
```

So long as the Dockerfile builds when you're executing the `docker build . ` command, it'll probably work remotely with this module too.

If something isn't working, you can check out logs for both the controller lambda function and the ecs/kaniko logs in cloudwatch logs at the CloudWatch Log Group created by this module (accessible via the [aws_cloudwatch_log_group](#output_aws_cloudwatch_log_group) output details).

By default, this module to work in most aws accounts out of the box in regions that support the dependent services (Elastic Container Repository, ECS, Lambda, etc) and it is made to not have name conflicts in case of multiple deployments. Some common first variables to look at will probably be the `resource_name` (so everything is just named `app-[randomString]`) and `aws_ecr_repository_attributes` (allowing finer grain control of the ECR repository options).


## Design Goals

- Be runner agnostic
    - Some attempts to do this rely on whatever is running the terraform-apply _also_ having the docker service installed and available to build and push the container. That may work in a fair number of cases, but I want this to work everwhere: containers, terraform-cloud, github actions, etc. By limiting the requirements strictly to terraform and a version, we can be sure to not cause runner/builder/ci lock in for what should be a relatively trivial process. 
- Enable single terraform-apply operations
    - The whole point of this is to avoid the common practice whereby multiple pipelines are required to do simple stuff like building a container backed AWS Lambda or deploy small apps to ECS. Mulitple pipelines, chaining things, and (shudder) manual steps are right out. 
- Be quick
    - An earlier version of this ran with ImageBuilder but that process was slow: even simple container builds took 10+ minutes whereas the Lambda/ECS version takes just under 1 minute.
- Be smart
    - This module does have some opinions about things like a baseline tag generated by the module. This is in service to being able to track which containers have already been built and -- when they preexist -- not having to go through the whole build process again. This also seemed either un-doable with ImageBuilder or (if it was doable) it was going to be hilariously complex. Honestly, you'd think the Lambda version of this is sacrificing internal complexity for features but lol what the IB version of this was turning into. 
- Be flexible
    - Want an ARM container? Want some Windows .net stuff? We got you! Check out the variables documentation.
    - Want your own image tags. We got you too! (All in the vars.)
- Keep it limited
    - This isn't really a trivial module; there's a lot of stuff going on in the background. However, as much as is going on, the code and features are really limited to answering the question: how can we get a container built in AWS and put in ECR. Accordingly, the features are mostly limited to answering that question as concisely as is reasonable. There are no assumptions as to how you're going to use the container (eg, if this is heading to Lambda, EKS, etc); it doesn't comes with pre-built integrations into other AWS services (but hopefully it's possible, using outputs to do whatever you can think up). This module should work well with other modules; but the goal is to have it be small and independent from anything else.


## Examples

If you want to check out the [examples/](./examples) folder, I'm putting demos in there to show what kind of functionality I'm aiming to build. Careful, they do use AWS serivces so there's _some_ cost but it should be negligable.

### [go-server](./examples/go-server) example

This shows how, with a dockerfile and a folder of uncompiled go-code, this module can build a container remotely, store it in ecr, and make it available for use by an ECS Task Definition running behind a load balancer. Navigate over to that directory and run `teraform init && terraform apply` and about 5-6 minutes later, it will pop out a `endpoint` output where you can check out the compiled go http server running. 

```bash
➜  go-server git:(main) ✗ terraform init && terraform apply --auto-approve

Initializing the backend...
Initializing modules...

Initializing provider plugins...

....
.... (several minutes later)
....

aws_ecs_task_definition.app: Creating...
aws_ecs_task_definition.app: Creation complete after 1s [id=app-hslhwpv7]
module.ecs_cluster.aws_ecs_service.main: Creating...
module.ecs_cluster.aws_ecs_service.main: Creation complete after 1s [id=arn:aws:ecs:us-east-1:1234566789:service/app-hslhwpv7/app-hslhwpv7]

Apply complete! Resources: 44 added, 0 changed, 0 destroyed.

Outputs:

endpoint = "http://app-hslhwpv7-1159156321.us-east-1.elb.amazonaws.com"
➜  go-server git:(main) ✗ curl http://app-hslhwpv7-1159156321.us-east-1.elb.amazonaws.com
Hello from ecs task: Howdy! I'm coming to you from the app-hslhwpv7 task! ┏( ͡❛ ͜ʖ ͡❛)┛%
➜  go-server git:(main) ✗
```

And with that, you can now party _all_ the way down with your new ECS Web app. 乁(⪧∀⪦˵ )ㄏ

_Note:_ If you get a `500` error, the ECS service may still be spinning up the final container, but you can check on that by navigating to the ECS dashboard and looking to see if it's still in `pending` state or not.


### Ideas / Goals

- More examples demonstrating this works
    - Windows
    - ARM Containers
    - Backing a Lambda
        - And a `lambda_invocation` proving it works (^◡^ )
    - Showing lots of image tags working
- Deal with more complex networking environments
    - What if the subnet the ECS builder runs in doesn't have public IPs
- Get smart about ECS Task/Kaniko's Permissions
    - What if the Dockerfile references a private ECR Repo
    - How can we deal authenticating to private Dockerhub/jfrog/Github docker registries
- Answering the question: what happens when a build takes longer than the 15m Lambda runs for.... bleh.
    - This may just be a limitation of the architecture that uses an `aws_lambda_invocation`. 
- Minimum AWS Provider version
    - This module was originally using a feature I got PR'd into the AWS provider so was pinned the then-latest version of the provider. However, it doesn't use that any more so an interesting project would be to find out how far back this is compatible version-wise and pinning to `=>` that.


## Contributing

I'm totally open to PRs for feature adds. The only thing I'd caution is, before working on something big, reach out through a github issue and @ me on it. Another thing to check out is the Design Goals section above highlighting motivation behind this module. 

Generally though:

### Easily acceptable PR ideas (/◕ヮ◕)/

- More examples/tests
- Outputs for things people need
- Stuff from the `Ideas / Goals` section above

### Maybe less good ideas (>_<)

- Integrations to Lambda/EKS/Etc
    - We should be making this possible through using the module's outputs, not directly in the module
- Things inhibiting the scalability of this
    - Predetermined things like S3 bucket names are understandably attractive but it _really_ inhibits the ability of the module to be deployed multiple times
- Anything that makes assumptions about the machine running terraform apply ಠ_ಠ


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
| [aws_cloudwatch_log_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecr_repository.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecs_cluster.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_task_definition.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.code_download](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ecs_executor](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ecs_executor](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecs_task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ecs_code_download](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_ecr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ecs_executor](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lambda_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_invocation.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_invocation) | resource |
| [aws_s3_bucket.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_object.code](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_security_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [random_string.main](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [archive_file.code](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [archive_file.lambda](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_ecr_image.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecr_image) | data source |
| [aws_iam_policy.AmazonECSTaskExecutionRolePolicy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy) | data source |
| [aws_partition.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_ecr_repository_attributes"></a> [aws\_ecr\_repository\_attributes](#input\_aws\_ecr\_repository\_attributes) | The attributes to set on the ECR Repository. This takes a map as it's input and for any attribute not included, the default specified on the [5.43.0](https://registry.terraform.io/providers/hashicorp/aws/5.43.0/docs/resources/ecr_repository) documentation is used. | <pre>object({<br>    force_delete         = optional(string, false)<br>    image_tag_mutability = optional(string, "MUTABLE")<br><br>    encryption_configuration = optional(map(any), {<br>      encryption_type = "AES256"<br>      kms_key         = ""<br>    })<br><br>    image_scanning_configuration = optional(map(any), {<br>      scan_on_push = true<br>    })<br><br>  })</pre> | `{}` | no |
| <a name="input_code_path"></a> [code\_path](#input\_code\_path) | The path where the code for this project lives. \_Note: The folder must contain, minimally, a Dockefile at the root. | `string` | n/a | yes |
| <a name="input_cpu_architecture"></a> [cpu\_architecture](#input\_cpu\_architecture) | The CPU architecture used to build this container. Must be one of `X86_64` or `ARM`. | `string` | `"X86_64"` | no |
| <a name="input_image_tags_additional"></a> [image\_tags\_additional](#input\_image\_tags\_additional) | By default we tag the image with a hash of the code and tags that the container was built with; however, with this variable, you can specify additional strings to tag the image with. | `list(string)` | `[]` | no |
| <a name="input_lambda_ephemeral_storage_mb"></a> [lambda\_ephemeral\_storage\_mb](#input\_lambda\_ephemeral\_storage\_mb) | The amount of ephemeral storage to provision the lambda function with. Used in the reformatting of the code base from a .zip to a .tar.gz. Usually this won't need to be changed from the default. | `number` | `512` | no |
| <a name="input_operating_system_family"></a> [operating\_system\_family](#input\_operating\_system\_family) | The Operating System family to be used by ECS to build this container. Must be on of those listed [here](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#runtime-platform) for Fargate. | `string` | `"LINUX"` | no |
| <a name="input_random_suffix"></a> [random\_suffix](#input\_random\_suffix) | This appends a random suffix to the resources created by this module. Defaults to true to maintain the ability to apply multiple times in an account. | `bool` | `true` | no |
| <a name="input_resource_name"></a> [resource\_name](#input\_resource\_name) | What to name resources deployed by this module. Works in conjunction with `var.random_suffix` bool. | `string` | `"app"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | The subnet id where the container will be built by ECS. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_cloudwatch_log_group"></a> [aws\_cloudwatch\_log\_group](#output\_aws\_cloudwatch\_log\_group) | The CloudWatch Log Group where build logs are sent. |
| <a name="output_aws_ecr_image"></a> [aws\_ecr\_image](#output\_aws\_ecr\_image) | Details about the ECR image created by this repository. |
| <a name="output_aws_ecr_repository"></a> [aws\_ecr\_repository](#output\_aws\_ecr\_repository) | The AWS ECR Repository where the resulting image is held. |
| <a name="output_name"></a> [name](#output\_name) | The name used by this module for deployed resources. |
