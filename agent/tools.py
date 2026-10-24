"""Read-only tools Claude can ask for. They take no resource names: each one
always looks at the app configured by Terraform, so Claude can't point them elsewhere."""

import time

from config import (
    APP_FUNCTION,
    APP_LOG_GROUP,
    APP_ROLE_ARN,
    APP_ROLE_NAME,
    APP_TABLE_ARN,
    cloudtrail,
    cloudwatch,
    iam,
    lambda_,
    logs,
)

HOUR = 3600


def search_logs():
    '''
    Filter logs with the flag ERROR.
    '''
    events = logs.filter_log_events(
        logGroupName=APP_LOG_GROUP,
        startTime=int((time.time() - HOUR) * 1000),
        filterPattern="?ERROR ?Error ?error ?Exception",
    )["events"]
    return [e["message"][:500] for e in events[-20:]]


def get_metrics():
    '''
    Get metrics and statistics around the function, that is for the time being, manually defined.
    '''
    def total(metric):
        points = cloudwatch.get_metric_statistics(
            Namespace="AWS/Lambda",
            MetricName=metric,
            Dimensions=[{"Name": "FunctionName", "Value": APP_FUNCTION}],
            StartTime=time.time() - HOUR,
            EndTime=time.time(),
            Period=300,
            Statistics=["Sum"],
        )["Datapoints"]
        return {str(p["Timestamp"]): p["Sum"] for p in points}

    return {"invocations": total("Invocations"), "errors": total("Errors")}


def get_lambda_config():
    config = lambda_.get_function_configuration(FunctionName=APP_FUNCTION)
    return {
        "role": config["Role"],
        "last_modified": config["LastModified"],
        "env_var_names": list(config.get("Environment", {}).get("Variables", {})),  # values may be secret
    }


def get_role_policies():
    names = iam.list_role_policies(RoleName=APP_ROLE_NAME)["PolicyNames"]
    attached = iam.list_attached_role_policies(RoleName=APP_ROLE_NAME)["AttachedPolicies"]
    return {
        "inline": {n: iam.get_role_policy(RoleName=APP_ROLE_NAME, PolicyName=n)["PolicyDocument"] for n in names},
        "attached": [p["PolicyArn"] for p in attached],
    }


def check_permissions(actions, resource_arn=APP_TABLE_ARN):
    results = iam.simulate_principal_policy(
        PolicySourceArn=APP_ROLE_ARN, ActionNames=actions, ResourceArns=[resource_arn]
    )["EvaluationResults"]
    return {r["EvalActionName"]: r["EvalDecision"] for r in results}


def recent_changes():
    changes = []
    for name in (APP_FUNCTION, APP_ROLE_NAME):
        events = cloudtrail.lookup_events(
            LookupAttributes=[{"AttributeKey": "ResourceName", "AttributeValue": name}],
            StartTime=time.time() - 24 * HOUR,
        )["Events"]
        changes += [
            {"time": str(e["EventTime"]), "event": e["EventName"], "by": e.get("Username")}
            for e in events
            if e.get("ReadOnly") != "true"
        ]
    return changes


# name -> (function, description Claude reads, input schema)
NO_INPUT = {"type": "object", "properties": {}}
TOOLS = {
    "search_logs": (search_logs, "Error log lines of the app from the last hour.", NO_INPUT),
    "get_metrics": (get_metrics, "App invocations and errors over the last hour.", NO_INPUT),
    "get_lambda_config": (get_lambda_config, "App config and last deployment time.", NO_INPUT),
    "get_role_policies": (get_role_policies, "IAM policies of the app's role.", NO_INPUT),
    "check_permissions": (
        check_permissions,
        "IAM simulator: may the app's role perform these actions on a resource "
        "(default: the app's DynamoDB table)?",
        {
            "type": "object",
            "properties": {
                "actions": {"type": "array", "items": {"type": "string"}},
                "resource_arn": {"type": "string"},
            },
            "required": ["actions"],
        },
    ),
    "recent_changes": (recent_changes, "Write events on the app and its role (CloudTrail, 24h).", NO_INPUT),
}
