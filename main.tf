variable "domain_name" {
  type    = string
  default = ""
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.${count.index}.0/24"
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

resource "aws_route_table_association" "subnet" {
  count          = 2
  subnet_id      = element(aws_subnet.subnet[*].id, count.index)
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "ecs" {
  vpc_id = aws_vpc.main.id

  // Allow traffic on port 3129
  ingress {
    from_port   = 3129
    to_port     = 3129
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  // Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "socks5_cluster" {
  name = "socks5-cluster"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]

  inline_policy {
    name = "s3-access"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject"
          ]
          Resource = "${aws_s3_bucket.config_bucket.arn}/*"
        }
      ]
    })
  }

  inline_policy {
    name = "execute-command"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }]
    })
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole"

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

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]

  inline_policy {
    name = "ecs-task-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = "*"
      }]
    })
  }
}

resource "aws_cloudwatch_log_group" "ecs_task" {
  name              = "/ecs/socks5-task"
  retention_in_days = 7
}

resource "aws_s3_bucket" "config_bucket" {
  bucket = "3proxy-config-bucket"
}

resource "aws_efs_file_system" "a3proxy_config" {
  creation_token = "3proxy-config"
}

resource "aws_efs_mount_target" "a3proxy_config" {
  count           = 2
  file_system_id  = aws_efs_file_system.a3proxy_config.id
  subnet_id       = aws_subnet.subnet[count.index].id
  security_groups = [aws_security_group.ecs.id]
}

resource "aws_s3_object" "a3proxy_config" {

  bucket  = aws_s3_bucket.config_bucket.bucket
  key     = "3proxy.cfg"
  content = <<EOF
# Your 3proxy configuration content goes here
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
users sunnyagain:CL:$VpnUserPassword
auth strong
authcache user,password
allow sunnyagain
log
socks -p3129 -l
EOF
}


resource "aws_ecs_task_definition" "socks5_task" {
  family                   = "socks5-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"  // Increase CPU
  memory                   = "1024" // Increase memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "socks5-server"
      image     = "3proxy/3proxy"
      essential = true
      portMappings = [
        {
          containerPort = 3129
          hostPort      = 3129
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/socks5-task"
          "awslogs-region"        = "ap-south-1"
          "awslogs-stream-prefix" = "socks5-server"
        }
      }

      mountPoints = [
        {
          sourceVolume  = "3proxy-config"
          containerPath = "/etc/3proxy"
          readOnly      = true
        }
      ]

    }
  ])

  volume {
    name = "3proxy-config"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.a3proxy_config.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }
}

resource "aws_ecs_service" "socks5_service" {
  name                   = "socks5-service"
  cluster                = aws_ecs_cluster.socks5_cluster.id
  task_definition        = aws_ecs_task_definition.socks5_task.arn
  desired_count          = 0         // Change desired count to a non-zero value
  launch_type            = "FARGATE" // Specify Fargate launch type
  enable_execute_command = true
  network_configuration {
    subnets          = aws_subnet.subnet[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true

  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AWSLambdaExecute"
  ]

  inline_policy {
    name = "ecs-actions"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ecs:UpdateService",
            "ecs:DescribeServices"
          ]
          Resource = "*"
        },
        {
          Effect = "Allow",
          Action = [
            "ecs:DescribeTasks",
            "ecs:ListTasks",
            "ec2:DescribeNetworkInterfaces"
          ],
          Resource = "*"
        },
        {
          Effect = "Allow",
          Action = [
            "route53:ChangeResourceRecordSets"
          ],
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_lambda_function" "start_socks5" {
  function_name    = "startsocks5"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "index.start_handler"
  runtime          = "python3.9"
  filename         = "lambda_functions.zip"
  source_code_hash = filesha256("lambda_functions.zip")

  environment {
    variables = {
      ECS_CLUSTER = aws_ecs_cluster.socks5_cluster.id
      ECS_SERVICE = aws_ecs_service.socks5_service.id
    }
  }
}

resource "aws_lambda_function" "stop_socks5" {
  function_name    = "stopsocks5"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "index.stop_handler"
  runtime          = "python3.9"
  filename         = "lambda_functions.zip"
  source_code_hash = filesha256("lambda_functions.zip")

  environment {
    variables = {
      ECS_CLUSTER = aws_ecs_cluster.socks5_cluster.id
      ECS_SERVICE = aws_ecs_service.socks5_service.id
    }
  }
}

resource "aws_api_gateway_rest_api" "socks5_api" {
  name = "socks5-api"
}

resource "aws_api_gateway_resource" "start_resource" {
  rest_api_id = aws_api_gateway_rest_api.socks5_api.id
  parent_id   = aws_api_gateway_rest_api.socks5_api.root_resource_id
  path_part   = "start"
}

resource "aws_api_gateway_resource" "stop_resource" {
  rest_api_id = aws_api_gateway_rest_api.socks5_api.id
  parent_id   = aws_api_gateway_rest_api.socks5_api.root_resource_id
  path_part   = "stop"
}

resource "aws_api_gateway_method" "start_method" {
  rest_api_id   = aws_api_gateway_rest_api.socks5_api.id
  resource_id   = aws_api_gateway_resource.start_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "stop_method" {
  rest_api_id   = aws_api_gateway_rest_api.socks5_api.id
  resource_id   = aws_api_gateway_resource.stop_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_lambda_permission" "start_api" {
  statement_id  = "AllowAPIGatewayInvokeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_socks5.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.socks5_api.execution_arn}/*/GET/start"
}

resource "aws_lambda_permission" "stop_api" {
  statement_id  = "AllowAPIGatewayInvokeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_socks5.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.socks5_api.execution_arn}/*/GET/stop"
}

resource "aws_api_gateway_integration" "start_integration" {
  rest_api_id             = aws_api_gateway_rest_api.socks5_api.id
  resource_id             = aws_api_gateway_resource.start_resource.id
  http_method             = aws_api_gateway_method.start_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.start_socks5.invoke_arn
}

resource "aws_api_gateway_integration" "stop_integration" {
  rest_api_id             = aws_api_gateway_rest_api.socks5_api.id
  resource_id             = aws_api_gateway_resource.stop_resource.id
  http_method             = aws_api_gateway_method.stop_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.stop_socks5.invoke_arn
}

resource "aws_api_gateway_deployment" "socks5_api" {
  rest_api_id = aws_api_gateway_rest_api.socks5_api.id
  stage_name  = "prod"

  depends_on = [
    aws_api_gateway_integration.start_integration,
    aws_api_gateway_integration.stop_integration,
  ]
}
