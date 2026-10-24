# --- Langfuse tracing for the agent (agent/tracing.py) ---
# The keys are NOT in Terraform (they would end up in the state file).
# Set them once after apply, from your Langfuse project settings:
#   aws secretsmanager put-secret-value --secret-id <arn> \
#     --secret-string '{"public_key": "pk-lf-...", "secret_key": "sk-lf-..."}'
# Until then the agent runs normally, without tracing.

resource "aws_secretsmanager_secret" "langfuse" {
  name                    = "${local.full_function_name}-langfuse-keys"
  description             = "Langfuse API keys used by the agent to send traces"
  recovery_window_in_days = 0 # lab: allow destroy + recreate without waiting 7 days
}

data "aws_iam_policy_document" "agent_tracing" {
  statement {
    sid       = "LangfuseKeys"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.langfuse.arn]
  }
}

resource "aws_iam_role_policy" "agent_tracing" {
  name   = "${local.full_function_name}-agent-tracing"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.agent_tracing.json
}
