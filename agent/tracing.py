"""Langfuse tracing: one trace per incident, with every Claude call and tool call inside.

Optional by design: without keys (empty secret, local tests...) every function here
does nothing, so tracing can never break an investigation.
Sensitive values (AWS account ids, emails) are masked before anything leaves AWS.
"""

import json
import os
import re
from contextlib import contextmanager, nullcontext
from types import SimpleNamespace

import boto3

NO_OP = SimpleNamespace(update=lambda **kwargs: None)


def plain(data):
    """Anthropic SDK objects -> plain JSON-like data, so it can be masked and stored."""
    return json.loads(json.dumps(data, default=lambda o: o.model_dump() if hasattr(o, "model_dump") else str(o)))


def mask(*, data, **kwargs):
    """Called by Langfuse on every input/output before sending it."""
    text = json.dumps(plain(data))
    text = re.sub(r"\b\d{12}\b", "<account-id>", text)
    text = re.sub(r"[\w.+-]+@[\w-]+\.[\w.]+", "<email>", text)
    return json.loads(text)


def connect():
    """A Langfuse client, or None if tracing isn't configured."""
    secret_arn = os.environ.get("LANGFUSE_SECRET")
    if not secret_arn:
        return None
    try:
        keys = json.loads(boto3.client("secretsmanager").get_secret_value(SecretId=secret_arn)["SecretString"])
        from langfuse import Langfuse

        return Langfuse(
            public_key=keys["public_key"],
            secret_key=keys["secret_key"],
            base_url=os.environ.get("LANGFUSE_BASE_URL", "https://cloud.langfuse.com"),
            environment=os.environ.get("ENVIRONMENT", "dev"),
            mask=mask,
        )
    except Exception as e:  # no value in the secret yet, bad keys...: run without tracing
        print(json.dumps({"tracing": "disabled", "reason": str(e)}))
        return None


langfuse = connect()


def observe(name, as_type="span", **attributes):
    """A step inside the current trace (a Claude call, a tool call...)."""
    if langfuse is None:
        return nullcontext(NO_OP)
    return langfuse.start_as_current_observation(name=name, as_type=as_type, **attributes)


@contextmanager
def incident_trace(incident_id, **attributes):
    """The root of one investigation. The trace id is derived from the incident id,
    so DynamoDB, the GitHub PR and the trace share the same identifier."""
    if langfuse is None:
        yield NO_OP
        return
    from langfuse import propagate_attributes

    trace_id = langfuse.create_trace_id(seed=incident_id)
    with langfuse.start_as_current_observation(
        trace_context={"trace_id": trace_id}, name="investigation", as_type="agent", **attributes
    ) as root:
        with propagate_attributes(trace_name=incident_id, tags=["cloudops-ai"]):
            yield root


def flush():
    """Send everything before Lambda freezes the process."""
    if langfuse is not None:
        langfuse.flush()
