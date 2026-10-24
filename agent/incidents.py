"""One DynamoDB record per distinct error, keyed by its fingerprint."""

import hashlib
import json
import re
from collections import Counter
from datetime import UTC, datetime

from config import APP_FUNCTION
from config import incidents_table as table
from tools import search_logs


def now():
    return datetime.now(UTC).isoformat()


def main_error(alarm):
    """The most frequent error in the app's logs, without what changes on every call
    (request ids, timestamps, numbers). Falls back to the alarm name + hour."""
    signatures = Counter(
        re.sub(r"[0-9a-f-]{8,}|\d+", "<x>", line.split("Traceback")[0]).strip() for line in search_logs()
    )
    if signatures:
        return signatures.most_common(1)[0][0]
    return f"{alarm.get('alarmName', 'manual')} at {now()[:13]}"


def fingerprint_of(error):
    return hashlib.sha256(f"{APP_FUNCTION}|{error}_err0".encode()).hexdigest()[:16]


def claim(fingerprint, error):
    """Create the record. False if this error is already open (so: don't investigate again)."""
    try:
        table.put_item(
            Item={
                "fingerprint": fingerprint,
                "incident_id": "INC-" + fingerprint[:8],
                "function": APP_FUNCTION,
                "error": error,
                "status": "INVESTIGATING",
                "occurrences": 1,
                "first_seen": now(),
                "last_seen": now(),
            },
            # New error, or one that was resolved / failed before -> investigate it.
            ConditionExpression="attribute_not_exists(fingerprint) OR #s IN (:resolved, :failed)",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":resolved": "RESOLVED", ":failed": "FAILED"},
        )
        return True
    except table.meta.client.exceptions.ConditionalCheckFailedException:
        return False


def count_again(fingerprint):
    table.update_item(
        Key={"fingerprint": fingerprint},
        UpdateExpression="ADD occurrences :one SET last_seen = :now",
        ExpressionAttributeValues={":one": 1, ":now": now()},
    )


def set_status(fingerprint, status, report=None):
    update, values = "SET #s = :s", {":s": status}
    if report is not None:
        update, values[":r"] = update + ", report = :r", json.dumps(report)
    table.update_item(
        Key={"fingerprint": fingerprint},
        UpdateExpression=update,
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues=values,
    )
