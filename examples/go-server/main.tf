module "main" {
  source    = "../../"
  code_path = "./code"

  image_tags_additional = ["latest"]

  aws_ecr_repository_attributes = {
    force_delete = true
  }

  subnet_id = module.vpc.aws_subnets[0].id
}

module "vpc" {
  source = "../support-modules/vpc"
}

module "ecs_cluster" {
  source              = "../support-modules/ecs-fargate-cluster"
  name                = module.main.name
  subnet_ids          = module.vpc.aws_subnets[*].id
  task_definition_arn = aws_ecs_task_definition.app.arn
}

resource "aws_ecs_task_definition" "app" {
  family                   = module.main.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048

  execution_role_arn = module.ecs_cluster.aws_iam_roles.execution.arn
  container_definitions = jsonencode([
    {
      name      = module.main.name
      image     = module.main.aws_ecr_image.image_uri
      cpu       = 1024
      memory    = 2048
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "APP_EXAMPLE_STRING"
          value = "Howdy! I'm coming to you from the ${module.main.name} task! ┏( ͡❛ ͜ʖ ͡❛)┛"
        }
      ]
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}

output "endpoint" {
  value = "http://${module.ecs_cluster.aws_lb.dns_name}"
}
