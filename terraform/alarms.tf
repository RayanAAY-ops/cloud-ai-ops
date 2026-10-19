# --- Alarm: the Lambda is returning errors ---
# Fires as soon as one invocation fails within a minute.

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.full_function_name}-errors"
  alarm_description   = "Lambda ${local.full_function_name} is returning errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = module.lambda.lambda_function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

# --- EventBridge: catch the alarm when it goes into ALARM ---
# CloudWatch publishes every alarm state change to EventBridge by default.
# This rule only matches our alarm, and only the transition into ALARM.
# Target (the agent Lambda calling Bedrock) is added in the next step.

resource "aws_cloudwatch_event_rule" "alarm_to_agent" {
  name        = "${local.full_function_name}-alarm-to-agent"
  description = "Start an investigation when the Lambda errors alarm fires"

  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    resources     = [aws_cloudwatch_metric_alarm.lambda_errors.arn]
    detail = {
      state = { value = ["ALARM"] }
    }
  })
}
