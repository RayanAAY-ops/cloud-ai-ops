"""PR Lambda entry point: turn an incident report into a GitHub pull request.

Only this function holds the GitHub token. The PR adds one Markdown file
(incidents/<id>.md) and changes no code: a human applies the fix.
"""

import json
import os

import boto3

import github
import templates

table = boto3.resource("dynamodb").Table(os.environ["INCIDENTS_TABLE"])


def handler(event, context):
    item = table.get_item(Key={"fingerprint": event["fingerprint"]})["Item"]
    if item["status"] != "PR_REQUESTED":  # already opened, or not meant for a PR
        return {"status": "skipped", "reason": item["status"]}

    report = json.loads(item["report"])
    incident_id = report["incident_id"]
    write_up = templates.incident_markdown(report)
    token = boto3.client("secretsmanager").get_secret_value(SecretId=os.environ["GITHUB_TOKEN_SECRET"])

    url = github.open_pull_request(
        token=token["SecretString"].strip(),
        branch=f"cloudops-ai/{incident_id.lower()}",
        path=f"incidents/{incident_id.lower()}.md",
        content=write_up,
        title=f"incident {incident_id}: {templates.safe(report['summary'])[:80]}",
        body=write_up,
    )

    table.update_item(
        Key={"fingerprint": event["fingerprint"]},
        UpdateExpression="SET #s = :s, pr_url = :url",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "PR_OPENED", ":url": url},
    )
    return {"pr_url": url}
