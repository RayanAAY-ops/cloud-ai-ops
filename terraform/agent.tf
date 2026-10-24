# --- Agent Lambda: investigates the alarm with Claude on Amazon Bedrock ---
# Triggered by the EventBridge rule in alarms.tf. The module zips the Python
# code in ../agent itself at plan time; no S3 artifact.

module "agent" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = "${local.full_function_name}-agent"

  runtime       = "python3.13"
  handler       = "handler.handler"
  architectures = ["arm64"]

  memory_size = 512
  timeout     = 300 # an investigation is a few model calls + tool calls

  # The agent's .py files; their dependencies come from the layer below.
  source_path = "${path.module}/../agent"
  layers      = [module.agent_layer.lambda_layer_arn]

  cloudwatch_logs_retention_in_days = var.log_retention_days

  environment_variables = {
    MODEL_ID        = var.bedrock_model_id
    APP_FUNCTION    = module.lambda.lambda_function_name
    APP_LOG_GROUP   = module.lambda.lambda_cloudwatch_log_group_name
    APP_ROLE_NAME   = aws_iam_role.lambda_exec.name
    APP_ROLE_ARN    = aws_iam_role.lambda_exec.arn
    APP_TABLE_ARN   = aws_dynamodb_table.shop_items.arn
    INCIDENTS_TABLE = aws_dynamodb_table.incidents.name
    PR_FUNCTION     = module.pr.lambda_function_name
    ENVIRONMENT     = var.environment

    # Tracing (tracing.tf). Disabled automatically while the secret has no value.
    LANGFUSE_SECRET   = aws_secretsmanager_secret.langfuse.arn
    LANGFUSE_BASE_URL = var.langfuse_base_url
  }

  # Don't re-run a whole investigation if it fails; one alarm = one attempt.
  maximum_retry_attempts = 0

  create_role = false
  lambda_role = aws_iam_role.agent.arn

  depends_on = [
    aws_iam_role_policy_attachment.agent_basic_execution,
    aws_iam_role_policy.agent,
  ]
}

# --- Incidents table: one record per distinct error ---
# Key = fingerprint (hash of the normalized error), so the same error firing
# again only bumps a counter instead of creating a new record / investigation.

resource "aws_dynamodb_table" "incidents" {
  name         = "${local.full_function_name}-incidents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "fingerprint"

  attribute {
    name = "fingerprint"
    type = "S"
  }

  attribute {
    name = "function"
    type = "S"
  }

  attribute {
    name = "last_seen"
    type = "S"
  }

  # "Errors of function X, most recent first": Query by-function, ScanIndexForward = false
  global_secondary_index {
    name            = "by-function"
    hash_key        = "function"
    range_key       = "last_seen"
    projection_type = "ALL"
  }
}

# --- Layer with the agent's Python dependencies (layer/requirements.txt) ---
# uv downloads Linux arm64 wheels, so it builds on a Mac without Docker.

module "agent_layer" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  create_layer       = true
  create_function    = false
  layer_skip_destroy = true
  layer_name         = "${local.full_function_name}-agent-dependencies"
  description        = "Lambda layer for the agent's Python dependencies"

  compatible_runtimes      = ["python3.13"]
  compatible_architectures = ["arm64"]

  source_path = [
    {
      path = "${path.module}/../layer"
      commands = [
        "uv pip install -r requirements.txt --python 3.13 --no-cache --target code --python-platform aarch64-manylinux_2_17 --only-binary=\":all:\"",
        # Zip only the installed packages, under python/ (where Lambda looks for them).
        ":zip code python",
      ]
    }
  ]
}

# --- Wire it as the target of the alarm rule ---

resource "aws_cloudwatch_event_target" "agent" {
  rule = aws_cloudwatch_event_rule.alarm_to_agent.name
  arn  = module.agent.lambda_function_arn
}

resource "aws_lambda_permission" "eventbridge_invokes_agent" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.agent.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.alarm_to_agent.arn
}

# --- Agent IAM role: call Bedrock + READ-ONLY on the app's resources ---
# It can look at the app's logs, metrics, config and IAM policies,
# but it cannot change anything.

resource "aws_iam_role" "agent" {
  name               = "${local.full_function_name}-agent-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "agent_basic_execution" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "agent" {
  # Claude on Bedrock (Messages API endpoint used by the Anthropic SDK).
  statement {
    sid       = "InvokeClaude"
    actions   = ["bedrock-mantle:CreateInference"]
    resources = ["*"]
  }

  # Lets Bedrock subscribe the account to the model on first use (no manual
  # Playground step). Trade-off: this role could subscribe to other
  # Marketplace products too. Remove once the model is subscribed if you prefer.
  statement {
    sid = "SubscribeToModelOnFirstUse"
    actions = [
      "aws-marketplace:Subscribe",
      "aws-marketplace:ViewSubscriptions",
    ]
    resources = ["*"]
  }

  # The agent's only write access: its own incident records.
  statement {
    sid       = "IncidentRecords"
    actions   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.incidents.arn]
  }

  # Hand the report to the PR Lambda (which holds the GitHub token, not the agent).
  statement {
    sid       = "RequestPullRequest"
    actions   = ["lambda:InvokeFunction"]
    resources = [module.pr.lambda_function_arn]
  }

  statement {
    sid       = "ReadAppLogs"
    actions   = ["logs:FilterLogEvents"]
    resources = ["${module.lambda.lambda_cloudwatch_log_group_arn}:*"]
  }

  # These APIs don't support resource-level restrictions.
  statement {
    sid = "ReadMetricsAndChanges"
    actions = [
      "cloudwatch:GetMetricStatistics",
      "cloudtrail:LookupEvents",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadAppConfig"
    actions   = ["lambda:GetFunctionConfiguration"]
    resources = [module.lambda.lambda_function_arn]
  }

  # Inspect the app role, and ask IAM's simulator "can it do X on the table?"
  statement {
    sid = "ReadAppRole"
    actions = [
      "iam:ListRolePolicies",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:SimulatePrincipalPolicy",
    ]
    resources = [aws_iam_role.lambda_exec.arn]
  }
}

resource "aws_iam_role_policy" "agent" {
  name   = "${local.full_function_name}-agent"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.agent.json
}
