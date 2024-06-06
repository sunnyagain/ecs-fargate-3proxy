resource "aws_iam_role" "lambda_efs_sync_role" {
  name = "lambda_efs_sync_role"

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
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]

  inline_policy {
    name = "efs-sync-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject"
          ]
          Resource = [
            "${aws_s3_bucket.config_bucket.arn}/*"
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "elasticfilesystem:ClientMount",
            "elasticfilesystem:ClientWrite",
            "ec2:CreateNetworkInterface",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DeleteNetworkInterface"
          ]
          Resource = "*"
        }
      ]
    })
  }
}
resource "aws_lambda_function" "efs_sync" {
  function_name    = "EfsSyncFunction"
  role             = aws_iam_role.lambda_efs_sync_role.arn
  handler          = "s3.handler"
  runtime          = "python3.9"
  filename         = "efs_sync_functions.zip" # The Lambda function package containing your Python code
  source_code_hash = filebase64sha256("efs_sync_functions.zip")
  environment {
    variables = {
      EFS_FILE_SYSTEM_ID = aws_efs_file_system.a3proxy_config.id
      S3_BUCKET          = aws_s3_bucket.config_bucket.bucket
      S3_KEY             = aws_s3_object.a3proxy_config.key
    }
  }

  vpc_config {
    subnet_ids         = aws_subnet.subnet[*].id
    security_group_ids = [aws_security_group.ecs.id]
  }

  file_system_config {
    local_mount_path = "/mnt/efs"
    arn              = aws_efs_access_point.a3proxy_config.arn
  }

  depends_on = [aws_iam_role.lambda_efs_sync_role]
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.config_bucket.bucket

  lambda_function {
    lambda_function_arn = aws_lambda_function.efs_sync.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".cfg"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3InvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.efs_sync.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.config_bucket.arn
}

resource "aws_efs_access_point" "a3proxy_config" {
  file_system_id = aws_efs_file_system.a3proxy_config.id
  posix_user {
    uid = "1000"
    gid = "1000"
  }
  root_directory {
    path = "/"
    creation_info {
      owner_gid   = "1000"
      owner_uid   = "1000"
      permissions = "777"
    }
  }
}
