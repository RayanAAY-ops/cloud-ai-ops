"""Minimal GitHub API client: branch, commit one file, open a pull request."""

import base64
import json
import os
import urllib.request

REPO = os.environ["GITHUB_REPOSITORY"]  # owner/repo
BASE = os.environ.get("GITHUB_BASE_BRANCH", "main")


def call(token, method, path, body=None):
    request = urllib.request.Request(  # noqa: S310 - fixed https URL
        f"https://api.github.com/repos/{REPO}{path}",
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:  # noqa: S310
        return json.loads(response.read() or "{}")


def open_pull_request(token, branch, path, content, title, body):
    """Returns the PR's URL."""
    base_sha = call(token, "GET", f"/git/ref/heads/{BASE}")["object"]["sha"]
    call(token, "POST", "/git/refs", {"ref": f"refs/heads/{branch}", "sha": base_sha})
    call(
        token,
        "PUT",
        f"/contents/{path}",
        {"message": title, "content": base64.b64encode(content.encode()).decode(), "branch": branch},
    )
    pr = call(token, "POST", "/pulls", {"title": title, "head": branch, "base": BASE, "body": body})
    return pr["html_url"]
