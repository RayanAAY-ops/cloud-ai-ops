# --- GitHub Actions -> AWS with OIDC (no AWS keys stored in GitHub) ---
# Used by .github/workflows/fix-accepted.yml to update the incident record when
# an agent PR is closed. Only this repo's pull_request workflows can assume the role.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The repo uses GitHub's immutable subject format (owner and repo ids included):
    #   gh api repos/<owner>/<repo>/actions/oidc/customization/sub
    # The plain format is kept in case that setting is turned off.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${var.github_oidc_subject_prefix}:pull_request",
        "repo:${var.github_repository}:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "github_incidents" {
  name               = "${local.full_function_name}-github-incidents"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
}

# Set the status of one record, whose key comes from the PR's branch name. Nothing else.
data "aws_iam_policy_document" "github_incidents" {
  statement {
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.incidents.arn]
  }
}

resource "aws_iam_role_policy" "github_incidents" {
  name   = "${local.full_function_name}-github-incidents"
  role   = aws_iam_role.github_incidents.id
  policy = data.aws_iam_policy_document.github_incidents.json
}

output "github_incidents_role_arn" {
  description = "Put this in GitHub: Settings -> Secrets and variables -> Actions -> Variables -> AWS_ROLE_ARN"
  value       = aws_iam_role.github_incidents.arn
}
