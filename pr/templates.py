"""The incident write-up: committed as incidents/<id>.md and used as the PR description."""


def safe(text):
    """Model-written text: no HTML, no @mentions, no code fences."""
    text = str(text).strip()
    return (
        text.replace("<", "&lt;").replace(">", "&gt;").replace("@", "@\u200b").replace("`", "'")
    )  # \u200b breaks @mentions


def incident_markdown(report):
    causes = "\n".join(
        f"- **{c.get('confidence', 0):.0%}** {safe(c.get('cause'))}" for c in report.get("likely_causes", [])
    )
    evidence = "\n".join(f"- {safe(e)}" for e in report.get("evidence", []))
    return f"""# {report["incident_id"]}: {safe(report["summary"])}

**Severity:** {report["severity"]}

> Opened automatically by cloudops-ai. This PR only documents the incident:
> **no code or infrastructure is changed.** Apply the fix yourself, then merge.

## 🔴 Error

```
{str(report["error"]).replace("`", "'")}
```

## 💥 Impact

{safe(report["impact"])}

## 🔍 Root cause

{causes}

**Evidence**

{evidence}

## 🛠 Proposed fix

{safe(report["proposed_fix"])}

## ❓ Uncertainty

{safe(report.get("uncertainty", "Not stated."))}

## ✅ Checklist

- [ ] The root cause makes sense
- [ ] The proposed fix is applied (or a better one)
- [ ] The error is gone after the fix
"""
