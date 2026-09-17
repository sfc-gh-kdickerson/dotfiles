#!/usr/bin/env python3
"""Emit compact events when a Snowflake pull request changes.

The supervisor keeps `gh pr checks --watch` out of the model context while a
small GraphQL loop watches state that command does not cover. It is read-only:
all mutations remain the invoking agent's responsibility.
"""

from __future__ import annotations

import argparse
import json
import signal
import subprocess
import sys
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Any, Callable, TextIO
from urllib.parse import urlparse

EVENT_PREFIX = "SHEPHERD_PR_EVENT "
MERGE_LABELS = {
    "ready_for_merge",
    ":robot: merge_awaiting_prereqs",
    ":robot: merge_running_validation",
}
EXPECTED_CHECK_RETURN_CODES = {0, 1, 8}
MAX_EVENT_ITEMS = 50
MERGEABLE_UNKNOWN = "UNKNOWN"
KNOWN_MERGEABLE = frozenset({"MERGEABLE", "CONFLICTING"})

PR_QUERY = """
query($owner: String!, $name: String!, $pr: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      number
      state
      isDraft
      headRefName
      headRefOid
      baseRefName
      mergeable
      reviewDecision
      mergedAt
      labels(first: 100) {
        nodes { name }
      }
      comments(first: 100, after: $cursor) {
        nodes {
          id
          databaseId
          author { login __typename }
          createdAt
          updatedAt
          url
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}
"""

THREADS_QUERY = """
query($owner: String!, $name: String!, $pr: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $cursor) {
        nodes {
          id
          isResolved
          isOutdated
          recentComments: comments(last: 20) {
            totalCount
            nodes {
              id
              databaseId
              author { login }
              createdAt
              updatedAt
              path
              line
              url
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}
"""

REVIEWS_QUERY = """
query($owner: String!, $name: String!, $pr: Int!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviews(first: 100, after: $cursor) {
        nodes {
          id
          databaseId
          author { login }
          state
          submittedAt
          updatedAt
          url
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}
"""


class CommandError(RuntimeError):
    """A concise, safe wrapper for a failed gh invocation."""

    def __init__(self, command: list[str], returncode: int, stderr: str):
        detail = " ".join(stderr.strip().split())[:500]
        super().__init__(
            f"{' '.join(command[:4])} exited {returncode}"
            + (f": {detail}" if detail else "")
        )
        self.returncode = returncode


class GhClient:
    """Small subprocess wrapper around authenticated GitHub CLI calls."""

    def __init__(
        self,
        executable: str = "gh",
        run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    ):
        self.executable = executable
        self._run = run

    def _json_command(
        self,
        arguments: list[str],
        allowed_returncodes: set[int] | None = None,
    ) -> Any:
        command = [self.executable, *arguments]
        result = self._run(
            command,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        allowed = allowed_returncodes or {0}
        if result.returncode not in allowed:
            raise CommandError(command, result.returncode, result.stderr)
        if not result.stdout.strip():
            return None
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise CommandError(
                command,
                result.returncode,
                f"invalid JSON output: {error}",
            ) from error

    def graphql(self, query: str, variables: dict[str, Any]) -> dict[str, Any]:
        arguments = ["api", "graphql", "-f", f"query={query}"]
        for key, value in variables.items():
            if value is not None:
                arguments.extend(["-F", f"{key}={value}"])
        payload = self._json_command(arguments)
        if not isinstance(payload, dict):
            raise CommandError(
                [self.executable, "api", "graphql"],
                0,
                "empty GraphQL response",
            )
        if payload.get("errors"):
            raise CommandError(
                [self.executable, "api", "graphql"],
                0,
                json.dumps(payload["errors"], separators=(",", ":"))[:500],
            )
        return payload

    def checks(self, repo: str, pr: int) -> list[dict[str, Any]]:
        fields = "name,state,bucket,link,workflow"
        payload = self._json_command(
            [
                "pr",
                "checks",
                str(pr),
                "--repo",
                repo,
                "--json",
                fields,
            ],
            EXPECTED_CHECK_RETURN_CODES,
        )
        return payload if isinstance(payload, list) else []


def split_repo(repo: str) -> tuple[str, str]:
    parts = repo.split("/")
    if len(parts) != 2 or not all(parts):
        raise ValueError(f"repo must be OWNER/NAME, got {repo!r}")
    return parts[0], parts[1]


def parse_pr_number(value: str) -> int:
    """Accept a PR number or a GitHub pull-request URL."""
    if value.isdigit() and int(value) > 0:
        return int(value)
    parsed = urlparse(value)
    parts = [part for part in parsed.path.split("/") if part]
    if parsed.scheme in {"http", "https"} and "pull" in parts:
        index = parts.index("pull")
        if index + 1 < len(parts) and parts[index + 1].isdigit():
            number = int(parts[index + 1])
            if number > 0:
                return number
    raise ValueError(f"pr must be a positive number or GitHub PR URL, got {value!r}")


def _author(node: dict[str, Any]) -> str:
    author = node.get("author")
    return author.get("login", "") if isinstance(author, dict) else ""


def _is_bot_author(node: dict[str, Any]) -> bool:
    author = node.get("author")
    if not isinstance(author, dict):
        return False
    typename = author.get("__typename") or ""
    login = author.get("login") or ""
    return typename == "Bot" or login.endswith("[bot]")


def stabilize_mergeable(
    previous: dict[str, Any] | None, current: dict[str, Any]
) -> dict[str, Any]:
    """Keep the last known mergeability while GitHub reports UNKNOWN.

    GitHub sets mergeable=UNKNOWN while recomputing after pushes, base
    updates, and merge validation. Those transitions are not actionable.
    """
    if current.get("mergeable") != MERGEABLE_UNKNOWN:
        return current
    if previous is None:
        return current
    previous_value = previous.get("mergeable")
    if previous_value not in KNOWN_MERGEABLE:
        return current
    stabilized = dict(current)
    stabilized["mergeable"] = previous_value
    return stabilized


def _report_mergeable_change(previous: Any, current: Any) -> bool:
    if previous == current:
        return False
    if current == MERGEABLE_UNKNOWN:
        return False
    if previous == MERGEABLE_UNKNOWN and current == "MERGEABLE":
        return False
    return True


class GitHubStateReader:
    """Fetch normalized PR metadata, comments, and review threads."""

    def __init__(self, client: GhClient, repo: str, pr: int):
        self.client = client
        self.owner, self.name = split_repo(repo)
        self.pr = pr

    def _variables(self, cursor: str | None) -> dict[str, Any]:
        return {
            "owner": self.owner,
            "name": self.name,
            "pr": self.pr,
            "cursor": cursor,
        }

    def fetch(self) -> dict[str, Any]:
        pr_data: dict[str, Any] | None = None
        issue_comments: dict[str, dict[str, Any]] = {}
        cursor: str | None = None

        while True:
            payload = self.client.graphql(PR_QUERY, self._variables(cursor))
            repository = payload.get("data", {}).get("repository")
            current = repository.get("pullRequest") if repository else None
            if not current:
                raise RuntimeError(f"PR #{self.pr} was not found")
            if pr_data is None:
                pr_data = current

            connection = current["comments"]
            for node in connection.get("nodes", []):
                issue_comments[node["id"]] = {
                    "database_id": node.get("databaseId"),
                    "author": _author(node),
                    "is_bot": _is_bot_author(node),
                    "created_at": node.get("createdAt"),
                    "updated_at": node.get("updatedAt"),
                    "url": node.get("url"),
                }
            page_info = connection["pageInfo"]
            if not page_info.get("hasNextPage"):
                break
            cursor = page_info.get("endCursor")
            if not cursor:
                raise RuntimeError("issue-comment pagination returned no end cursor")

        threads: dict[str, dict[str, Any]] = {}
        cursor = None
        while True:
            payload = self.client.graphql(THREADS_QUERY, self._variables(cursor))
            repository = payload.get("data", {}).get("repository")
            pull_request = repository.get("pullRequest") if repository else None
            if not pull_request:
                raise RuntimeError(f"PR #{self.pr} was not found")
            connection = pull_request["reviewThreads"]
            for node in connection.get("nodes", []):
                comments: dict[str, dict[str, Any]] = {}
                for comment in node["recentComments"].get("nodes", []):
                    comments[comment["id"]] = {
                        "database_id": comment.get("databaseId"),
                        "author": _author(comment),
                        "created_at": comment.get("createdAt"),
                        "updated_at": comment.get("updatedAt"),
                        "path": comment.get("path"),
                        "line": comment.get("line"),
                        "url": comment.get("url"),
                    }
                threads[node["id"]] = {
                    "resolved": bool(node.get("isResolved")),
                    "outdated": bool(node.get("isOutdated")),
                    "comment_count": node["recentComments"].get(
                        "totalCount", len(comments)
                    ),
                    "recent_comments": comments,
                }
            page_info = connection["pageInfo"]
            if not page_info.get("hasNextPage"):
                break
            cursor = page_info.get("endCursor")
            if not cursor:
                raise RuntimeError("review-thread pagination returned no end cursor")

        reviews: dict[str, dict[str, Any]] = {}
        cursor = None
        while True:
            payload = self.client.graphql(REVIEWS_QUERY, self._variables(cursor))
            repository = payload.get("data", {}).get("repository")
            pull_request = repository.get("pullRequest") if repository else None
            if not pull_request:
                raise RuntimeError(f"PR #{self.pr} was not found")
            connection = pull_request["reviews"]
            for node in connection.get("nodes", []):
                reviews[node["id"]] = {
                    "database_id": node.get("databaseId"),
                    "author": _author(node),
                    "state": node.get("state"),
                    "submitted_at": node.get("submittedAt"),
                    "updated_at": node.get("updatedAt"),
                    "url": node.get("url"),
                }
            page_info = connection["pageInfo"]
            if not page_info.get("hasNextPage"):
                break
            cursor = page_info.get("endCursor")
            if not cursor:
                raise RuntimeError("review pagination returned no end cursor")

        assert pr_data is not None
        labels = sorted(
            node["name"]
            for node in pr_data["labels"].get("nodes", [])
            if node.get("name")
        )
        return {
            "number": pr_data["number"],
            "state": pr_data["state"],
            "is_draft": bool(pr_data["isDraft"]),
            "head_ref": pr_data["headRefName"],
            "head_sha": pr_data["headRefOid"],
            "base_ref": pr_data["baseRefName"],
            "mergeable": pr_data["mergeable"],
            "review_decision": pr_data.get("reviewDecision"),
            "merged_at": pr_data.get("mergedAt"),
            "labels": labels,
            "issue_comments": issue_comments,
            "threads": threads,
            "reviews": reviews,
        }


def _limited(items: list[str]) -> dict[str, Any]:
    ordered = sorted(items)
    return {
        "items": ordered[:MAX_EVENT_ITEMS],
        "total": len(ordered),
        "truncated": len(ordered) > MAX_EVENT_ITEMS,
    }


def state_summary(state: dict[str, Any]) -> dict[str, Any]:
    unresolved = sum(
        1 for thread in state["threads"].values() if not thread["resolved"]
    )
    return {
        "state": state["state"],
        "head_sha": state["head_sha"],
        "is_draft": state["is_draft"],
        "mergeable": state["mergeable"],
        "review_decision": state["review_decision"],
        "labels": state["labels"],
        "unresolved_threads": unresolved,
        "issue_comment_count": len(state["issue_comments"]),
        "review_count": len(state["reviews"]),
    }


def diff_states(previous: dict[str, Any], current: dict[str, Any]) -> dict[str, Any]:
    """Return only meaningful, compact changes between normalized snapshots."""
    changes: dict[str, Any] = {}
    for key in (
        "state",
        "head_sha",
        "is_draft",
        "mergeable",
        "review_decision",
        "merged_at",
    ):
        previous_value = previous.get(key)
        current_value = current.get(key)
        if previous_value == current_value:
            continue
        if key == "mergeable" and not _report_mergeable_change(
            previous_value, current_value
        ):
            continue
        changes[key] = {"from": previous_value, "to": current_value}

    previous_labels = set(previous["labels"])
    current_labels = set(current["labels"])
    if previous_labels != current_labels:
        changes["labels"] = {
            "added": sorted(current_labels - previous_labels),
            "removed": sorted(previous_labels - current_labels),
        }

    previous_comments = previous["issue_comments"]
    current_comments = current["issue_comments"]
    new_comments = list(current_comments.keys() - previous_comments.keys())
    updated_comments = [
        comment_id
        for comment_id in current_comments.keys() & previous_comments.keys()
        if current_comments[comment_id].get("updated_at")
        != previous_comments[comment_id].get("updated_at")
        and not current_comments[comment_id].get("is_bot")
        and not previous_comments[comment_id].get("is_bot")
    ]
    removed_comments = list(previous_comments.keys() - current_comments.keys())
    if new_comments:
        changes["new_issue_comments"] = _limited(new_comments)
    if updated_comments:
        changes["updated_issue_comments"] = _limited(updated_comments)
    if removed_comments:
        changes["removed_issue_comments"] = _limited(removed_comments)

    previous_threads = previous["threads"]
    current_threads = current["threads"]
    new_threads = list(current_threads.keys() - previous_threads.keys())
    removed_threads = list(previous_threads.keys() - current_threads.keys())
    resolved: list[str] = []
    reopened: list[str] = []
    outdated_changed: list[str] = []
    thread_replies: dict[str, dict[str, Any]] = {}

    for thread_id in current_threads.keys() & previous_threads.keys():
        before = previous_threads[thread_id]
        after = current_threads[thread_id]
        if before["resolved"] != after["resolved"]:
            (resolved if after["resolved"] else reopened).append(thread_id)
        if before["outdated"] != after["outdated"]:
            outdated_changed.append(thread_id)
        before_comments = before["recent_comments"]
        after_comments = after["recent_comments"]
        added = list(after_comments.keys() - before_comments.keys())
        edited = [
            comment_id
            for comment_id in after_comments.keys() & before_comments.keys()
            if after_comments[comment_id].get("updated_at")
            != before_comments[comment_id].get("updated_at")
        ]
        if added or edited or before.get("comment_count") != after.get("comment_count"):
            thread_replies[thread_id] = {
                "added": _limited(added),
                "edited": _limited(edited),
                "comment_count": after.get("comment_count"),
            }

    if new_threads:
        changes["new_review_threads"] = _limited(new_threads)
    if removed_threads:
        changes["removed_review_threads"] = _limited(removed_threads)
    if resolved:
        changes["resolved_review_threads"] = _limited(resolved)
    if reopened:
        changes["reopened_review_threads"] = _limited(reopened)
    if outdated_changed:
        changes["outdated_review_threads_changed"] = _limited(outdated_changed)
    if thread_replies:
        ordered_ids = sorted(thread_replies)[:MAX_EVENT_ITEMS]
        changes["review_thread_comments_changed"] = {
            "threads": {
                thread_id: thread_replies[thread_id] for thread_id in ordered_ids
            },
            "total": len(thread_replies),
            "truncated": len(thread_replies) > MAX_EVENT_ITEMS,
        }

    previous_reviews = previous["reviews"]
    current_reviews = current["reviews"]
    new_reviews = list(current_reviews.keys() - previous_reviews.keys())
    updated_reviews = [
        review_id
        for review_id in current_reviews.keys() & previous_reviews.keys()
        if current_reviews[review_id].get("updated_at")
        != previous_reviews[review_id].get("updated_at")
        or current_reviews[review_id].get("state")
        != previous_reviews[review_id].get("state")
    ]
    removed_reviews = list(previous_reviews.keys() - current_reviews.keys())
    if new_reviews:
        changes["new_reviews"] = _limited(new_reviews)
    if updated_reviews:
        changes["updated_reviews"] = _limited(updated_reviews)
    if removed_reviews:
        changes["removed_reviews"] = _limited(removed_reviews)
    return changes


def merge_token(state: dict[str, Any]) -> tuple[str, ...]:
    return tuple(sorted(set(state["labels"]) & MERGE_LABELS))


def checks_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    counts = {bucket: 0 for bucket in ("pass", "fail", "pending", "skipping", "cancel")}
    blockers: list[dict[str, Any]] = []
    normalized: list[tuple[str, str, str, str]] = []
    for row in rows:
        bucket = row.get("bucket") or "unknown"
        counts[bucket] = counts.get(bucket, 0) + 1
        name = row.get("name") or ""
        state = row.get("state") or ""
        link = row.get("link") or ""
        normalized.append((name, bucket, state, link))
        if bucket in {"fail", "pending", "cancel"}:
            blockers.append({"name": name, "bucket": bucket, "link": link})

    if counts.get("fail", 0) or counts.get("cancel", 0):
        result = "fail"
    elif counts.get("pending", 0):
        result = "pending"
    elif rows:
        result = "pass"
    else:
        result = "none"
    blockers.sort(key=lambda row: (row["bucket"], row["name"]))
    fingerprint = json.dumps(sorted(normalized), separators=(",", ":"))
    return {
        "result": result,
        "counts": {key: value for key, value in counts.items() if value},
        "blockers": blockers[:MAX_EVENT_ITEMS],
        "blocker_count": len(blockers),
        "truncated": len(blockers) > MAX_EVENT_ITEMS,
        "fingerprint": fingerprint,
    }


class EventEmitter:
    """Thread-safe generation and flushed event output."""

    def __init__(self, stream: TextIO = sys.stdout, watcher_id: str | None = None):
        self.stream = stream
        self.watcher_id = watcher_id or uuid.uuid4().hex[:12]
        self._generation = 0
        self._lock = threading.Lock()

    def emit(self, event: str, **payload: Any) -> int:
        with self._lock:
            self._generation += 1
            generation = self._generation
            body = {
                "event": event,
                "watcher_id": self.watcher_id,
                "generation": generation,
                **payload,
            }
            print(
                EVENT_PREFIX + json.dumps(body, separators=(",", ":"), sort_keys=True),
                file=self.stream,
                flush=True,
            )
            return generation


@dataclass(frozen=True)
class CheckContext:
    head_sha: str
    epoch: int


class CheckMonitor(threading.Thread):
    """Supervise a quiet `gh pr checks --watch` child."""

    def __init__(
        self,
        repo: str,
        pr: int,
        client: GhClient,
        emitter: EventEmitter,
        context: CheckContext,
        interval: int = 20,
        popen: Callable[..., subprocess.Popen[Any]] = subprocess.Popen,
    ):
        super().__init__(name=f"shepherd-checks-{pr}", daemon=True)
        self.repo = repo
        self.pr = pr
        self.client = client
        self.emitter = emitter
        self.interval = interval
        self._popen = popen
        self._stop_event = threading.Event()
        self._restart_event = threading.Event()
        self._context_lock = threading.Lock()
        self._context = context
        self._process: subprocess.Popen[Any] | None = None
        self._last_fingerprint_by_context: dict[CheckContext, str] = {}
        self._last_error: str | None = None

    def context(self) -> CheckContext:
        with self._context_lock:
            return self._context

    def update_context(self, context: CheckContext) -> None:
        with self._context_lock:
            changed = context != self._context
            self._context = context
        if changed:
            self._restart_event.set()

    def stop(self) -> None:
        self._stop_event.set()
        self._restart_event.set()
        self._terminate_process()

    def _terminate_process(self) -> None:
        process = self._process
        if process is None or process.poll() is not None:
            return
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)

    def _start_process(self) -> subprocess.Popen[Any]:
        command = [
            self.client.executable,
            "pr",
            "checks",
            str(self.pr),
            "--repo",
            self.repo,
            "--watch",
            "--interval",
            str(self.interval),
        ]
        return self._popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def _wait_for_process(self) -> tuple[int | None, bool]:
        """Return (exit code, restarted)."""
        while not self._stop_event.is_set():
            if self._restart_event.is_set():
                self._restart_event.clear()
                self._terminate_process()
                return None, True
            assert self._process is not None
            code = self._process.poll()
            if code is not None:
                return code, False
            self._stop_event.wait(0.5)
        self._terminate_process()
        return None, False

    def run(self) -> None:
        while not self._stop_event.is_set():
            start_context = self.context()
            self._restart_event.clear()
            try:
                self._process = self._start_process()
                exit_code, restarted = self._wait_for_process()
                self._process = None
                if self._stop_event.is_set():
                    return
                if restarted or self.context() != start_context:
                    continue

                rows = self.client.checks(self.repo, self.pr)
                summary = checks_summary(rows)
                fingerprint = summary.pop("fingerprint")
                if self._last_fingerprint_by_context.get(start_context) != fingerprint:
                    self._last_fingerprint_by_context[start_context] = fingerprint
                    self.emitter.emit(
                        "checks_changed",
                        head_sha=start_context.head_sha,
                        check_epoch=start_context.epoch,
                        watch_exit_code=exit_code,
                        **summary,
                    )
                self._last_error = None
            except (CommandError, OSError, subprocess.SubprocessError) as error:
                message = str(error)
                if message != self._last_error:
                    self._last_error = message
                    current = self.context()
                    self.emitter.emit(
                        "watcher_error",
                        source="checks",
                        head_sha=current.head_sha,
                        check_epoch=current.epoch,
                        message=message,
                    )
            self._stop_event.wait(self.interval)


def run_once(
    reader: GitHubStateReader,
    client: GhClient,
    repo: str,
    pr: int,
    emitter: EventEmitter,
) -> None:
    state = reader.fetch()
    summary = checks_summary(client.checks(repo, pr))
    summary.pop("fingerprint")
    emitter.emit("snapshot", **state_summary(state), checks=summary)


def supervise(
    reader: GitHubStateReader,
    client: GhClient,
    repo: str,
    pr: int,
    emitter: EventEmitter,
    interval: int,
    max_backoff: int,
    max_runtime: float | None,
    check_monitor_factory: Callable[..., CheckMonitor] = CheckMonitor,
) -> None:
    stop_event = threading.Event()

    def request_stop(_signum: int, _frame: Any) -> None:
        stop_event.set()

    previous_handlers: dict[int, Any] = {}
    if threading.current_thread() is threading.main_thread():
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.getsignal(signum)
            signal.signal(signum, request_stop)

    check_monitor: CheckMonitor | None = None
    started_at = time.monotonic()
    try:
        state = reader.fetch()
        emitter.emit("initial", **state_summary(state))
        if state["state"] != "OPEN":
            return

        epoch = 1
        context = CheckContext(state["head_sha"], epoch)
        check_monitor = check_monitor_factory(
            repo=repo,
            pr=pr,
            client=client,
            emitter=emitter,
            context=context,
            interval=interval,
        )
        check_monitor.start()

        backoff = interval
        last_error: str | None = None
        while not stop_event.is_set():
            if max_runtime is not None:
                elapsed = time.monotonic() - started_at
                if elapsed >= max_runtime:
                    emitter.emit(
                        "watcher_stopped",
                        reason="max_runtime",
                        head_sha=state["head_sha"],
                    )
                    return
                wait_for = min(backoff, max_runtime - elapsed)
            else:
                wait_for = backoff
            if stop_event.wait(wait_for):
                return

            try:
                current = stabilize_mergeable(state, reader.fetch())
                changes = diff_states(state, current)
                if last_error is not None:
                    emitter.emit(
                        "watcher_recovered",
                        source="graphql",
                        head_sha=current["head_sha"],
                    )
                    last_error = None
                backoff = interval

                context_changed = state["head_sha"] != current[
                    "head_sha"
                ] or merge_token(state) != merge_token(current)
                if context_changed:
                    epoch += 1
                    check_monitor.update_context(
                        CheckContext(current["head_sha"], epoch)
                    )

                if changes:
                    event = (
                        "terminal" if current["state"] != "OPEN" else "state_changed"
                    )
                    emitter.emit(
                        event,
                        head_sha=current["head_sha"],
                        check_epoch=epoch,
                        changes=changes,
                        summary=state_summary(current),
                    )
                state = current
                if state["state"] != "OPEN":
                    return
            except (
                CommandError,
                RuntimeError,
                KeyError,
                TypeError,
                OSError,
                subprocess.SubprocessError,
            ) as error:
                message = str(error)
                if message != last_error:
                    last_error = message
                    emitter.emit(
                        "watcher_error",
                        source="graphql",
                        head_sha=state["head_sha"],
                        message=message,
                        retry_in_seconds=backoff,
                    )
                backoff = min(max(backoff * 2, interval), max_backoff)
    finally:
        if check_monitor is not None:
            check_monitor.stop()
            check_monitor.join(timeout=10)
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Emit compact state-change events for one GitHub PR."
    )
    parser.add_argument("--repo", default="snowflake-eng/snowflake")
    parser.add_argument("--pr", required=True, help="PR number or GitHub PR URL")
    parser.add_argument(
        "--interval",
        type=int,
        default=20,
        help="GitHub state/check refresh interval in seconds (default: 20)",
    )
    parser.add_argument(
        "--max-backoff",
        type=int,
        default=300,
        help="maximum GraphQL error backoff in seconds (default: 300)",
    )
    parser.add_argument(
        "--max-runtime",
        type=float,
        help="optional bounded runtime in seconds, primarily for smoke tests",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="emit one combined read-only snapshot and exit",
    )
    parser.add_argument("--gh", default="gh", help=argparse.SUPPRESS)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        pr = parse_pr_number(args.pr)
        split_repo(args.repo)
        if args.interval < 1:
            raise ValueError("interval must be at least 1 second")
        if args.max_backoff < args.interval:
            raise ValueError("max-backoff must be greater than or equal to interval")
        if args.max_runtime is not None and args.max_runtime <= 0:
            raise ValueError("max-runtime must be positive")
    except ValueError as error:
        parser.error(str(error))

    client = GhClient(args.gh)
    reader = GitHubStateReader(client, args.repo, pr)
    emitter = EventEmitter()
    try:
        if args.once:
            run_once(reader, client, args.repo, pr, emitter)
        else:
            supervise(
                reader=reader,
                client=client,
                repo=args.repo,
                pr=pr,
                emitter=emitter,
                interval=args.interval,
                max_backoff=args.max_backoff,
                max_runtime=args.max_runtime,
            )
        return 0
    except (
        CommandError,
        RuntimeError,
        KeyError,
        TypeError,
        OSError,
        subprocess.SubprocessError,
    ) as error:
        emitter.emit("watcher_error", source="startup", message=str(error))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
