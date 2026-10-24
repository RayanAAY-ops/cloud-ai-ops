"""Agent entry point: alarm -> dedupe -> Claude investigates -> report -> incident PR."""

import json

import incidents
from claude import investigate
from config import PR_FUNCTION, lambda_


def handler(event, context):
    alarm = event.get("detail", event)  # EventBridge puts the alarm in "detail"; manual tests may not
    error = incidents.main_error(alarm)
    fingerprint = incidents.fingerprint_of(error)

    if not incidents.claim(fingerprint, error):  # same error already open: count it, don't call Claude
        incidents.count_again(fingerprint)
        return {"fingerprint": fingerprint, "status": "duplicate"}

    try:
        report = investigate({"alarm": alarm, "main_error": error})
    except Exception:
        incidents.set_status(fingerprint, "FAILED")  # the next alarm will retry
        raise

    if report is None:  # Claude gave up: keep a record, no PR
        report = {"summary": "Investigation inconclusive, triage manually."}
    report["incident_id"] = "INC-" + fingerprint[:8]
    report["error"] = error  # from the logs, not from the model
    report["requires_human_approval"] = True  # set by code, never by the model

    if "proposed_fix" in report:
        incidents.set_status(fingerprint, "PR_REQUESTED", report)
        # Only the key is passed: the PR Lambda re-reads the stored report.
        lambda_.invoke(
            FunctionName=PR_FUNCTION, InvocationType="Event", Payload=json.dumps({"fingerprint": fingerprint})
        )
    else:
        incidents.set_status(fingerprint, "REPORTED", report)

    print(json.dumps(report))
    return report
