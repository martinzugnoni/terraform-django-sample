# Config
variable "aws_region" { default = "us-east-1" }
variable "aws_profile" {}
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}


# Variables
variable "vpc_id" {}
variable "project_name" {}
variable "launch_type" { default = "FARGATE" }
variable "rds_allocated_storage" {}
variable "rds_engine" {}
variable "rds_engine_version" {}
variable "rds_instance_class" {}
variable "rds_storage_type" { default = "standard" }
variable "database_name" {}
variable "database_user" {}
variable "database_password" {}
variable "docker_image_name" {}
variable "docker_image_revision" {}


# Networking
data "aws_vpc" "app_vpc" {
  id = var.vpc_id
}
data "aws_subnet_ids" "app_subnet" {
  vpc_id = data.aws_vpc.app_vpc.id
}
data "aws_security_groups" "app_sg" {
  filter {
    name   = "group-name"
    values = ["default"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.app_vpc.id]
  }
}


# Cluster
resource "aws_ecs_cluster" "app_cluster" {
  name = "${var.project_name}-cluster"
}


# Service
resource "aws_ecs_service" "app_service" {
  name        = "${var.project_name}-service"
  cluster     = aws_ecs_cluster.app_cluster.arn
  launch_type = var.launch_type

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 0
  desired_count                      = 2
  task_definition                    = aws_ecs_task_definition.django_app.arn

  network_configuration {
    assign_public_ip = true
    security_groups  = data.aws_security_groups.app_sg.ids
    subnets          = data.aws_subnet_ids.app_subnet.ids
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.app_alb_tg.id
    container_name   = var.project_name
    container_port   = 8000
  }
}


# Task definition
data "template_file" "django_app" {
  template = file("./task-definition.json")
  vars = {
    app_name       = var.project_name
    app_image      = "${var.docker_image_name}:${var.docker_image_revision}"
    app_port       = 8000
    app_db_address = aws_db_instance.app_rds.address
    app_db_port    = aws_db_instance.app_rds.port
    fargate_cpu    = "256"
    fargate_memory = "512"
    aws_region     = var.aws_region
  }
}
resource "aws_ecs_task_definition" "django_app" {
  container_definitions    = data.template_file.django_app.rendered
  family                   = var.project_name
  requires_compatibilities = [var.launch_type]
  task_role_arn            = aws_iam_role.app_execution_role.arn
  execution_role_arn       = aws_iam_role.app_execution_role.arn

  cpu          = "256"
  memory       = "512"
  network_mode = "awsvpc"
}


# Load balancer
resource "aws_alb" "app_alb" {
  name            = "${var.project_name}-alb"
  subnets         = data.aws_subnet_ids.app_subnet.ids
  security_groups = data.aws_security_groups.app_sg.ids
}
resource "aws_alb_target_group" "app_alb_tg" {
  name        = "${var.project_name}-alb-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.app_vpc.id
  target_type = "ip"
  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/"
    unhealthy_threshold = "2"
  }
}
resource "aws_alb_listener" "app_alb_listener" {
  load_balancer_arn = aws_alb.app_alb.id
  port              = 80
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_alb_target_group.app_alb_tg.id
    type             = "forward"
  }
}
output "app_dns_lb" {
  description = "DNS load balancer"
  value       = aws_alb.app_alb.dns_name
}


# Postgres database RDS
resource "aws_db_instance" "app_rds" {
  identifier                = "${var.project_name}-rds"
  allocated_storage         = var.rds_allocated_storage
  engine                    = var.rds_engine
  engine_version            = var.rds_engine_version
  instance_class            = var.rds_instance_class
  name                      = var.database_name
  username                  = var.database_user
  password                  = var.database_password
  vpc_security_group_ids    = data.aws_security_groups.app_sg.ids
  storage_type              = var.rds_storage_type
  skip_final_snapshot       = true
}


# # IAM roles
resource "aws_iam_role" "app_execution_role" {
  name               = "${var.project_name}-execution-role"
  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "ecs.amazonaws.com",
          "ecs-tasks.amazonaws.com"
        ]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}
