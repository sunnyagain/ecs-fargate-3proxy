resource "aws_route53_zone" "private" {
  name = var.domain_name
}

resource "aws_cloudwatch_event_rule" "ecs_task_state_change_rule" {
  name        = "ecs_task_state_change_rule"
  description = "Trigger Lambda function on ECS task state changes"
  event_pattern = jsonencode({
    "source" : ["aws.ecs"],
    "detail-type" : ["ECS Task State Change"],
    "detail" : {
      "clusterArn" : [aws_ecs_cluster.socks5_cluster.arn]
      "lastStatus" : ["RUNNING"]
    }
  })
}

resource "aws_cloudwatch_event_target" "ecs_task_state_change_target" {
  rule      = aws_cloudwatch_event_rule.ecs_task_state_change_rule.name
  target_id = "ecs_dns_updater_target"
  arn       = aws_lambda_function.ecs_dns_updater.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_invoke" {
  statement_id  = "AllowCloudWatchToInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecs_dns_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecs_task_state_change_rule.arn
}

resource "aws_lambda_function" "ecs_dns_updater" {
  function_name    = "ecs_dns_updater"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "index.dns_handler"
  runtime          = "python3.9"
  filename         = "lambda_functions.zip" # Ensure this zip file contains your Lambda function code
  source_code_hash = filesha256("lambda_functions.zip")
  environment {
    variables = {
      ECS_CLUSTER    = aws_ecs_cluster.socks5_cluster.name
      ECS_SERVICE    = aws_ecs_service.socks5_service.name
      HOSTED_ZONE_ID = aws_route53_zone.private.id
      RECORD_NAME    = "socks5.${var.domain_name}"
    }
  }
}

