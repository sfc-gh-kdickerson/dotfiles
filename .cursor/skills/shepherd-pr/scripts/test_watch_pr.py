#!/usr/bin/env python3

import io
import json
from pathlib import Path
import time
import unittest

import watch_pr


def make_state(**overrides):
    state = {
        "number": 507604,
        "state": "OPEN",
        "is_draft": False,
        "head_ref": "kaleb/lora2-gs/G5",
        "head_sha": "aaa",
        "base_ref": "main",
        "mergeable": "MERGEABLE",
        "review_decision": "APPROVED",
        "merged_at": None,
        "labels": [],
        "issue_comments": {},
        "threads": {},
        "reviews": {},
    }
    state.update(overrides)
    return state


def parse_events(stream):
    events = []
    for line in stream.getvalue().splitlines():
        if line.startswith(watch_pr.EVENT_PREFIX):
            events.append(json.loads(line[len(watch_pr.EVENT_PREFIX) :]))
    return events


class FakeGraphqlClient:
    def __init__(self):
        self.calls = []

    @staticmethod
    def _pr(comments, has_next=False, cursor=None):
        return {
            "number": 7,
            "state": "OPEN",
            "isDraft": False,
            "headRefName": "feature",
            "headRefOid": "abc123",
            "baseRefName": "main",
            "mergeable": "MERGEABLE",
            "reviewDecision": "APPROVED",
            "mergedAt": None,
            "labels": {"nodes": [{"name": "ready_for_merge"}]},
            "comments": {
                "nodes": comments,
                "pageInfo": {"hasNextPage": has_next, "endCursor": cursor},
            },
        }

    @staticmethod
    def _issue_comment(comment_id):
        return {
            "id": comment_id,
            "databaseId": int(comment_id[1:]),
            "author": {"login": "reviewer"},
            "createdAt": "2026-09-01T00:00:00Z",
            "updatedAt": "2026-09-01T00:00:00Z",
            "url": f"https://example/{comment_id}",
        }

    @staticmethod
    def _thread(thread_id, resolved):
        return {
            "id": thread_id,
            "isResolved": resolved,
            "isOutdated": False,
            "recentComments": {
                "totalCount": 1,
                "nodes": [
                    {
                        "id": f"{thread_id}-comment",
                        "databaseId": 99,
                        "author": {"login": "ai-review-bot"},
                        "createdAt": "2026-09-01T00:00:00Z",
                        "updatedAt": "2026-09-01T00:00:00Z",
                        "path": "A.java",
                        "line": 10,
                        "url": f"https://example/{thread_id}",
                    }
                ],
            },
        }

    @staticmethod
    def _review(review_id, state):
        return {
            "id": review_id,
            "databaseId": int(review_id[1:]),
            "author": {"login": "reviewer"},
            "state": state,
            "submittedAt": "2026-09-01T00:00:00Z",
            "updatedAt": "2026-09-01T00:00:00Z",
            "url": f"https://example/{review_id}",
        }

    def graphql(self, query, variables):
        self.calls.append((query, variables.get("cursor")))
        cursor = variables.get("cursor")
        if query == watch_pr.PR_QUERY:
            if cursor is None:
                pr = self._pr([self._issue_comment("C1")], True, "comments-next")
            else:
                pr = self._pr([self._issue_comment("C2")])
            return {"data": {"repository": {"pullRequest": pr}}}

        if query == watch_pr.THREADS_QUERY:
            if cursor is None:
                nodes = [self._thread("T1", False)]
                page_info = {"hasNextPage": True, "endCursor": "threads-next"}
            else:
                nodes = [self._thread("T2", True)]
                page_info = {"hasNextPage": False, "endCursor": None}
            return {
                "data": {
                    "repository": {
                        "pullRequest": {
                            "reviewThreads": {"nodes": nodes, "pageInfo": page_info}
                        }
                    }
                }
            }

        if cursor is None:
            nodes = [self._review("V1", "COMMENTED")]
            page_info = {"hasNextPage": True, "endCursor": "reviews-next"}
        else:
            nodes = [self._review("V2", "APPROVED")]
            page_info = {"hasNextPage": False, "endCursor": None}
        return {
            "data": {
                "repository": {
                    "pullRequest": {"reviews": {"nodes": nodes, "pageInfo": page_info}}
                }
            }
        }


class ImmediateProcess:
    def __init__(self, code=0):
        self.code = code
        self.terminated = False
        self.killed = False

    def poll(self):
        return self.code

    def terminate(self):
        self.terminated = True
        self.code = -15

    def kill(self):
        self.killed = True
        self.code = -9

    def wait(self, timeout=None):
        return self.code


class RunningProcess(ImmediateProcess):
    def __init__(self):
        super().__init__(None)


class FakeChecksClient:
    executable = "gh"

    def __init__(self, snapshots):
        self.snapshots = list(snapshots)
        self.calls = 0

    def checks(self, repo, pr):
        index = min(self.calls, len(self.snapshots) - 1)
        self.calls += 1
        return self.snapshots[index]


class DummyCheckMonitor:
    def __init__(self, **kwargs):
        self.contexts = [kwargs["context"]]
        self.started = False
        self.stopped = False

    def start(self):
        self.started = True

    def update_context(self, context):
        self.contexts.append(context)

    def stop(self):
        self.stopped = True

    def join(self, timeout=None):
        return None


class SequenceReader:
    def __init__(self, sequence):
        self.sequence = list(sequence)
        self.index = 0

    def fetch(self):
        if self.index < len(self.sequence):
            value = self.sequence[self.index]
            self.index += 1
        else:
            value = self.sequence[-1]
        if isinstance(value, Exception):
            raise value
        return value


class WatchPrTests(unittest.TestCase):
    def test_skill_layout_and_frontmatter(self):
        skill_root = Path(__file__).resolve().parent.parent
        skill = skill_root / "SKILL.md"
        reference = skill_root / "references" / "gs-merge-gates.md"
        self.assertTrue(skill.is_file())
        self.assertTrue(reference.is_file())
        contents = skill.read_text()
        self.assertLessEqual(len(contents.splitlines()), 500)
        self.assertTrue(contents.startswith("---\n"))
        self.assertIn("\nname: shepherd-pr\n", contents)
        self.assertIn("\ndisable-model-invocation: true\n", contents)
        self.assertIn(
            "[references/gs-merge-gates.md](references/gs-merge-gates.md)",
            contents,
        )

    def test_parse_pr_number_accepts_number_and_url(self):
        self.assertEqual(42, watch_pr.parse_pr_number("42"))
        self.assertEqual(
            42,
            watch_pr.parse_pr_number(
                "https://github.com/snowflake-eng/snowflake/pull/42"
            ),
        )
        with self.assertRaises(ValueError):
            watch_pr.parse_pr_number("not-a-pr")

    def test_state_reader_paginates_comments_and_threads(self):
        client = FakeGraphqlClient()
        state = watch_pr.GitHubStateReader(client, "owner/repo", 7).fetch()
        self.assertEqual({"C1", "C2"}, set(state["issue_comments"]))
        self.assertFalse(state["issue_comments"]["C1"]["is_bot"])
        self.assertEqual({"T1", "T2"}, set(state["threads"]))
        self.assertEqual({"V1", "V2"}, set(state["reviews"]))
        self.assertFalse(state["threads"]["T1"]["resolved"])
        self.assertTrue(state["threads"]["T2"]["resolved"])
        self.assertEqual(
            [
                (watch_pr.PR_QUERY, None),
                (watch_pr.PR_QUERY, "comments-next"),
                (watch_pr.THREADS_QUERY, None),
                (watch_pr.THREADS_QUERY, "threads-next"),
                (watch_pr.REVIEWS_QUERY, None),
                (watch_pr.REVIEWS_QUERY, "reviews-next"),
            ],
            client.calls,
        )

    def test_diff_detects_comment_reply_resolution_and_head_change(self):
        previous = make_state(
            issue_comments={
                "I1": {"updated_at": "old"},
            },
            threads={
                "T1": {
                    "resolved": False,
                    "outdated": False,
                    "comment_count": 1,
                    "recent_comments": {"R1": {"updated_at": "old"}},
                }
            },
            reviews={"V1": {"updated_at": "old", "state": "COMMENTED"}},
        )
        current = make_state(
            head_sha="bbb",
            labels=[":robot: merge_running_validation", "ready_for_merge"],
            issue_comments={
                "I1": {"updated_at": "new"},
                "I2": {"updated_at": "new"},
            },
            threads={
                "T1": {
                    "resolved": True,
                    "outdated": True,
                    "comment_count": 2,
                    "recent_comments": {
                        "R1": {"updated_at": "old"},
                        "R2": {"updated_at": "new"},
                    },
                },
                "T2": {
                    "resolved": False,
                    "outdated": False,
                    "comment_count": 1,
                    "recent_comments": {"R3": {"updated_at": "new"}},
                },
            },
            reviews={
                "V1": {"updated_at": "new", "state": "APPROVED"},
                "V2": {"updated_at": "new", "state": "COMMENTED"},
            },
        )
        changes = watch_pr.diff_states(previous, current)
        self.assertEqual("bbb", changes["head_sha"]["to"])
        self.assertEqual(["I2"], changes["new_issue_comments"]["items"])
        self.assertEqual(["I1"], changes["updated_issue_comments"]["items"])
        self.assertEqual(["T1"], changes["resolved_review_threads"]["items"])
        self.assertEqual(["T2"], changes["new_review_threads"]["items"])
        self.assertEqual(["V1"], changes["updated_reviews"]["items"])
        self.assertEqual(["V2"], changes["new_reviews"]["items"])
        self.assertEqual(
            ["R2"],
            changes["review_thread_comments_changed"]["threads"]["T1"]["added"][
                "items"
            ],
        )

    def test_checks_summary_is_compact_and_classifies_cancel_as_failure(self):
        summary = watch_pr.checks_summary(
            [
                {"name": "green", "bucket": "pass", "state": "SUCCESS", "link": "g"},
                {
                    "name": "running",
                    "bucket": "pending",
                    "state": "PENDING",
                    "link": "p",
                },
                {
                    "name": "canceled",
                    "bucket": "cancel",
                    "state": "CANCELLED",
                    "link": "c",
                },
            ]
        )
        self.assertEqual("fail", summary["result"])
        self.assertEqual({"pass": 1, "pending": 1, "cancel": 1}, summary["counts"])
        self.assertEqual(2, summary["blocker_count"])
        self.assertNotIn("green", {item["name"] for item in summary["blockers"]})

    def test_diff_surfaces_failed_resolution_and_dismissed_approval(self):
        thread = {
            "outdated": False,
            "comment_count": 1,
            "recent_comments": {"R1": {"updated_at": "same"}},
        }
        previous = make_state(
            labels=["ready_for_merge", ":robot: merge_running_validation"],
            threads={"T1": {"resolved": True, **thread}},
        )
        current = make_state(
            head_sha="bbb",
            review_decision=None,
            labels=[":robot: merge_awaiting_prereqs"],
            threads={"T1": {"resolved": False, **thread}},
        )
        changes = watch_pr.diff_states(previous, current)
        self.assertEqual({"from": "APPROVED", "to": None}, changes["review_decision"])
        self.assertEqual(["T1"], changes["reopened_review_threads"]["items"])
        self.assertEqual([":robot: merge_awaiting_prereqs"], changes["labels"]["added"])
        self.assertEqual(
            [":robot: merge_running_validation", "ready_for_merge"],
            changes["labels"]["removed"],
        )

    def test_emitter_flushes_compact_monotonic_events(self):
        stream = io.StringIO()
        emitter = watch_pr.EventEmitter(stream, watcher_id="watch-1")
        emitter.emit("one", head_sha="a")
        emitter.emit("two", head_sha="b")
        events = parse_events(stream)
        self.assertEqual([1, 2], [event["generation"] for event in events])
        self.assertEqual({"watch-1"}, {event["watcher_id"] for event in events})
        encoded = stream.getvalue().splitlines()[0][len(watch_pr.EVENT_PREFIX) :]
        self.assertNotIn(" ", encoded)

    def test_check_monitor_deduplicates_no_check_early_exit(self):
        stream = io.StringIO()
        emitter = watch_pr.EventEmitter(stream)
        client = FakeChecksClient([[], []])
        starts = []

        def popen(*args, **kwargs):
            starts.append(args[0])
            return ImmediateProcess(0)

        monitor = watch_pr.CheckMonitor(
            repo="owner/repo",
            pr=7,
            client=client,
            emitter=emitter,
            context=watch_pr.CheckContext("aaa", 1),
            interval=0.01,
            popen=popen,
        )
        monitor.start()
        time.sleep(0.06)
        monitor.stop()
        monitor.join(timeout=1)
        events = parse_events(stream)
        self.assertGreaterEqual(len(starts), 2)
        self.assertEqual(1, len([e for e in events if e["event"] == "checks_changed"]))
        self.assertEqual("none", events[0]["result"])

    def test_check_monitor_cancels_stale_child_on_context_change(self):
        stream = io.StringIO()
        emitter = watch_pr.EventEmitter(stream)
        client = FakeChecksClient(
            [[{"name": "basic", "bucket": "pass", "state": "SUCCESS", "link": "x"}]]
        )
        first = RunningProcess()
        second = ImmediateProcess(0)
        processes = [first, second]

        def popen(*args, **kwargs):
            return processes.pop(0) if processes else ImmediateProcess(0)

        monitor = watch_pr.CheckMonitor(
            repo="owner/repo",
            pr=7,
            client=client,
            emitter=emitter,
            context=watch_pr.CheckContext("aaa", 1),
            interval=0.01,
            popen=popen,
        )
        monitor.start()
        time.sleep(0.02)
        monitor.update_context(watch_pr.CheckContext("bbb", 2))
        deadline = time.time() + 1
        while time.time() < deadline and not parse_events(stream):
            time.sleep(0.01)
        monitor.stop()
        monitor.join(timeout=1)
        events = parse_events(stream)
        self.assertTrue(first.terminated)
        self.assertTrue(any(event.get("head_sha") == "bbb" for event in events))
        self.assertFalse(any(event.get("head_sha") == "aaa" for event in events))

    def test_supervisor_emits_state_and_terminal_events_and_restarts_checks(self):
        initial = make_state()
        changed = make_state(
            head_sha="bbb",
            labels=["ready_for_merge"],
            threads={
                "T1": {
                    "resolved": False,
                    "outdated": False,
                    "comment_count": 1,
                    "recent_comments": {"R1": {"updated_at": "now"}},
                }
            },
        )
        terminal = make_state(
            head_sha="bbb",
            state="MERGED",
            merged_at="2026-09-01T01:00:00Z",
            labels=[],
            threads=changed["threads"],
        )
        reader = SequenceReader([initial, changed, terminal])
        stream = io.StringIO()
        emitter = watch_pr.EventEmitter(stream)
        monitors = []

        def factory(**kwargs):
            monitor = DummyCheckMonitor(**kwargs)
            monitors.append(monitor)
            return monitor

        watch_pr.supervise(
            reader=reader,
            client=FakeChecksClient([[]]),
            repo="owner/repo",
            pr=7,
            emitter=emitter,
            interval=0.001,
            max_backoff=1,
            max_runtime=1,
            check_monitor_factory=factory,
        )
        events = parse_events(stream)
        self.assertEqual(
            ["initial", "state_changed", "terminal"],
            [event["event"] for event in events],
        )
        self.assertEqual(3, len(monitors[0].contexts))
        self.assertTrue(monitors[0].stopped)

    def test_supervisor_reports_api_error_once_then_recovery(self):
        initial = make_state()
        terminal = make_state(state="CLOSED")
        reader = SequenceReader([initial, RuntimeError("temporary outage"), terminal])
        stream = io.StringIO()
        emitter = watch_pr.EventEmitter(stream)

        watch_pr.supervise(
            reader=reader,
            client=FakeChecksClient([[]]),
            repo="owner/repo",
            pr=7,
            emitter=emitter,
            interval=0.001,
            max_backoff=0.01,
            max_runtime=1,
            check_monitor_factory=DummyCheckMonitor,
        )
        events = parse_events(stream)
        self.assertEqual(1, len([e for e in events if e["event"] == "watcher_error"]))
        self.assertEqual(
            1, len([e for e in events if e["event"] == "watcher_recovered"])
        )
        self.assertEqual("terminal", events[-1]["event"])

    def test_stabilize_mergeable_keeps_last_known_over_unknown(self):
        previous = make_state(mergeable="MERGEABLE")
        unknown = make_state(mergeable="UNKNOWN")
        stabilized = watch_pr.stabilize_mergeable(previous, unknown)
        self.assertEqual("MERGEABLE", stabilized["mergeable"])
        self.assertEqual({}, watch_pr.diff_states(previous, stabilized))

    def test_diff_reports_conflict_discovered_after_unknown(self):
        previous = make_state(mergeable="UNKNOWN")
        current = make_state(mergeable="CONFLICTING")
        changes = watch_pr.diff_states(previous, current)
        self.assertEqual({"from": "UNKNOWN", "to": "CONFLICTING"}, changes["mergeable"])

    def test_diff_ignores_unknown_and_mergeable_recompute(self):
        self.assertEqual(
            {},
            watch_pr.diff_states(
                make_state(mergeable="MERGEABLE"),
                make_state(mergeable="UNKNOWN"),
            ),
        )
        self.assertEqual(
            {},
            watch_pr.diff_states(
                make_state(mergeable="UNKNOWN"),
                make_state(mergeable="MERGEABLE"),
            ),
        )

    def test_diff_ignores_bot_issue_comment_edits_but_keeps_human_edits(self):
        previous = make_state(
            issue_comments={
                "B1": {
                    "author": "arcticowl-ai-review-emu[bot]",
                    "is_bot": True,
                    "updated_at": "old",
                },
                "H1": {"author": "reviewer", "is_bot": False, "updated_at": "old"},
            }
        )
        bot_only = make_state(
            issue_comments={
                "B1": {
                    "author": "arcticowl-ai-review-emu[bot]",
                    "is_bot": True,
                    "updated_at": "new",
                },
                "H1": {"author": "reviewer", "is_bot": False, "updated_at": "old"},
            }
        )
        self.assertEqual({}, watch_pr.diff_states(previous, bot_only))
        human_edit = make_state(
            issue_comments={
                "B1": {
                    "author": "arcticowl-ai-review-emu[bot]",
                    "is_bot": True,
                    "updated_at": "new",
                },
                "H1": {"author": "reviewer", "is_bot": False, "updated_at": "new"},
            }
        )
        changes = watch_pr.diff_states(previous, human_edit)
        self.assertEqual(["H1"], changes["updated_issue_comments"]["items"])

    def test_supervisor_skips_mergeable_unknown_flicker(self):
        initial = make_state()
        unknown = make_state(mergeable="UNKNOWN")
        recovered = make_state()
        conflicting = make_state(mergeable="CONFLICTING")
        terminal = make_state(state="CLOSED", mergeable="CONFLICTING")
        reader = SequenceReader(
            [initial, unknown, recovered, conflicting, terminal]
        )
        stream = io.StringIO()
        emitter = watch_pr.EventEmitter(stream)

        watch_pr.supervise(
            reader=reader,
            client=FakeChecksClient([[]]),
            repo="owner/repo",
            pr=7,
            emitter=emitter,
            interval=0.001,
            max_backoff=1,
            max_runtime=1,
            check_monitor_factory=DummyCheckMonitor,
        )
        events = parse_events(stream)
        self.assertEqual(
            ["initial", "state_changed", "terminal"],
            [event["event"] for event in events],
        )
        self.assertEqual(
            {"from": "MERGEABLE", "to": "CONFLICTING"},
            events[1]["changes"]["mergeable"],
        )


if __name__ == "__main__":
    unittest.main()
