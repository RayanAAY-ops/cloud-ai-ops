# cloudops-ai

An AI agent that investigates AWS incidents. When the app Lambda fails, a
CloudWatch alarm triggers (through EventBridge) an agent Lambda that asks
Claude on Amazon Bedrock to investigate with read-only tools and write a JSON
incident report.

```
app/       App Lambda (Python): writes items to DynamoDB
agent/     Agent Lambda (Python): investigates the alarm with Claude
layer/     requirements.txt for the agent's Lambda layer (anthropic SDK)
terraform/ Everything AWS
```

The app's `dynamodb:PutItem` permission is commented out on purpose in
`terraform/role.tf`, so every call fails and the agent has something to find.

## Prerequisites

- AWS credentials, Terraform, `uv` (builds the layer)
- Claude Opus 5.5 enabled in the Bedrock console (Model access, eu-west-1)

## 1. Terraform state bucket (once)

```bash
aws s3api create-bucket \
  --bucket cloudai-ops-tfstate-dev \
  --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1

aws s3api put-bucket-versioning \
  --bucket cloudai-ops-tfstate-dev \
  --versioning-configuration Status=Enabled
```

## 2. Deploy

```bash
cd terraform
make plan ENV=dev
make apply ENV=dev
```

## 3. Trigger an incident

```bash
aws lambda invoke \
  --function-name cloudops-ai-app-dev \
  --cli-binary-format raw-in-base64-out \
  --payload '{"item_name": "Widget", "price": 9.99}' \
  /dev/stdout

# 2-5 minutes later, the report shows up in the agent's logs:
aws logs tail /aws/lambda/cloudops-ai-app-dev-agent --follow
```
