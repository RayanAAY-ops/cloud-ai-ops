# --- PR Lambda: opens a GitHub pull request documenting the incident ---
# Invoked by the agent only. It is the only component with the GitHub token.
# The PR adds incidents/<id>.md and changes no code: a human applies the fix.

module "pr" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = "${local.full_function_name}-pr"

  runtime       = "python3.13"
  handler       = "handler.handler"
  architectures = ["arm64"]
  timeout       = 60

  source_path = "${path.module}/../pr" # stdlib + boto3 only, nothing to install

  cloudwatch_logs_retention_in_days = var.log_retention_days

  environment_variables = {
    INCIDENTS_TABLE     = aws_dynamodb_table.incidents.name
    GITHUB_REPOSITORY   = var.github_repository
    GITHUB_BASE_BRANCH  = var.github_base_branch
    GITHUB_TOKEN_SECRET = aws_secretsmanager_secret.github_token.arn
  }

  create_role = false
  lambda_role = aws_iam_role.pr.arn

  depends_on = [
    aws_iam_role_policy_attachment.pr_basic_execution,
    aws_iam_role_policy.pr,
  ]
}

# The token value is NOT in Terraform (it would end up in the state file).
# Set it once after apply:
#   aws secretsmanager put-secret-value --secret-id <arn> --secret-string 'github_pat_...'
resource "aws_secretsmanager_secret" "github_token" {
  name                    = "${local.full_function_name}-github-token"
  description             = "Fine-grained GitHub token used only to open remediation PRs"
  recovery_window_in_days = 0 # lab: allow destroy + recreate without waiting 7 days
}

resource "aws_iam_role" "pr" {
  name               = "${local.full_function_name}-pr-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "pr_basic_execution" {
  role       = aws_iam_role.pr.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "pr" {
  statement {
    sid       = "IncidentRecord"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.incidents.arn]
  }

  statement {
    sid       = "GitHubToken"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.github_token.arn]
  }
}

resource "aws_iam_role_policy" "pr" {
  name   = "${local.full_function_name}-pr"
  role   = aws_iam_role.pr.id
  policy = data.aws_iam_policy_document.pr.json
}
