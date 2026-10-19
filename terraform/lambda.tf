# --- DynamoDB table used by the app (../app/app.py) ---

resource "aws_dynamodb_table" "shop_items" {
  name         = local.full_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "item_id"

  attribute {
    name = "item_id"
    type = "S"
  }
}

# --- App Lambda (Python) ---
# The module zips ../app at plan time. Only boto3 is used, which the Lambda
# runtime already provides, so there's nothing to install.
# IAM role is defined in role.tf and passed in below.

module "lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = local.full_function_name

  runtime       = "python3.13"
  handler       = "app.handler"
  architectures = ["arm64"]

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  source_path = "${path.module}/../app"

  cloudwatch_logs_retention_in_days = var.log_retention_days

  environment_variables = {
    DYNAMODB_TABLE_NAME = aws_dynamodb_table.shop_items.name
  }

  # Use the role defined in role.tf instead of having the module create one.
  create_role = false
  lambda_role = aws_iam_role.lambda_exec.arn

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    # aws_iam_role_policy.lambda_dynamodb, # disabled on purpose, see role.tf
  ]
}
