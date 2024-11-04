provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name = "minecraft_vpc"
  cidr = "10.0.0.0/16"
  azs            = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

resource "aws_ecs_cluster" "minecraft_server" {
  name = "minecraft_server"
}

resource "aws_security_group" "minecraft_server" {
  name        = "minecraft_server"
  description = "minecraft_server"
  vpc_id      =  module.vpc.vpc_id
 
  ingress {
    description = "minecraft_server"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_ecs_task_definition" "minecraft_server" {
  cpu                      = "4096"
  memory                   = "8192"
  family                   = "minecraft-server"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn = aws_iam_role.ecs_tasks_execution_role.arn
  container_definitions = jsonencode([
    {
      name          = "minecraft-server"
      image         = "itzg/minecraft-server"
      essential     = true
      tty           = true
      stdin_open    = true
      restart       = "unless-stopped"
      portMappings  = [
        {
          containerPort = 25565
          hostPort      = 25565
          protocol      = "tcp"
        }
      ]
      environment   = [
        {
          name  = "EULA"
          value = "TRUE"
        },
        {
          "name": "VERSION",
          "value": "1.21.3"
        }
      ]
      mountPoints   = [
        {
          containerPath = "/data"
          sourceVolume  = "minecraft-data"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/minecraft-server"
          awslogs-region        = "eu-north-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
  volume {
    name = "minecraft-data"
  }
}

resource "aws_ecs_service" "minecraft_server" {
  name            = "minecraft_server"
  cluster         = aws_ecs_cluster.minecraft_server.id
  task_definition = aws_ecs_task_definition.minecraft_server.arn
  desired_count   = 1
  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.minecraft_server.id]
    assign_public_ip = true
  }
  launch_type = "FARGATE"
}

data "aws_iam_policy_document" "ecs_tasks_execution_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_tasks_execution_role" {
  name               = "ecs-task-execution-role"
  assume_role_policy = "${data.aws_iam_policy_document.ecs_tasks_execution_role.json}"
}

resource "aws_iam_role_policy_attachment" "ecs_tasks_execution_role" {
  role       = "${aws_iam_role.ecs_tasks_execution_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_task_log_execution_policy" {
  role       = "${aws_iam_role.ecs_tasks_execution_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_cloudwatch_log_group" "minecraft_log_group" {
  name              = "/ecs/minecraft-server"
  retention_in_days = 14
}
