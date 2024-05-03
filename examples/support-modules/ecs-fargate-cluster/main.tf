variable "name" {
  description = "The name given to resources assoicated with module. Probably comes from the base-module so things stay chill."
  type        = string
}

data "aws_partition" "main" {}

resource "aws_cloudwatch_log_group" "main" {
  name = "${var.name}-ecs"

  retention_in_days = 7
}

resource "aws_ecs_cluster" "main" {
  name = var.name

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

variable "task_definition_arn" {
  description = "The ARN of a task definition to deploy to our basic app service."
}

resource "aws_security_group" "lb" {
  name   = "${var.name}-lb"
  vpc_id = data.aws_subnet.main.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name   = "${var.name}-app"
  vpc_id = data.aws_subnet.main.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "TCP"
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

variable "subnet_ids" {
  description = "The AWS Subnet IDs to deploy resources into. This probably comes from the example VPC module"
  type        = list(string)
}

data "aws_subnet" "main" {
  id = var.subnet_ids[0]
}

resource "aws_lb" "main" {
  name               = var.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = var.subnet_ids
}

output "aws_lb" {
  value = aws_lb.main
}

resource "aws_lb_target_group" "main" {
  name        = var.name
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_subnet.main.vpc_id
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_ecs_service" "main" {
  name            = var.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = var.task_definition_arn
  desired_count   = 1
  #iam_role        = aws_iam_role.main.arn


  launch_type = "FARGATE"
  #depends_on      = [aws_iam_role_policy.foo]

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = var.name
    container_port   = 8080
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = "true"
  }
}

resource "aws_iam_role" "execution" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.${data.aws_partition.main.dns_suffix}"
      }
      Sid = ""
    }]
  })
}

output "aws_iam_roles" {
  description = "IAM Roles created by this module."
  value = {
    execution = aws_iam_role.execution
  }
}

resource "aws_iam_policy" "execution" {
  name = "ecs-task-${var.name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  policy_arn = aws_iam_policy.execution.arn
  role       = aws_iam_role.execution.name
}
