# ADR and postmortem

Two "record" formats: one captures a decision, the other captures an incident. Both are about durable memory — writing down what would otherwise be lost or relitigated.

---

## Architecture Decision Record (ADR)

### When to use it

An ADR records a single significant, hard-to-reverse decision and the reasoning behind it, so the team stops relitigating it. They're lightweight and usually live in the repo (e.g. `docs/adr/0007-use-postgres-for-queue.md`), numbered and immutable.

**Not** for exploring or proposing — that's a design doc. An ADR records a decision that's already been made.

### Skeleton

```
# <NNNN>. <Short title of the decision>
Status: Proposed | Accepted | Superseded by ADR-XXXX
Date: <YYYY-MM-DD>

## Context
The forces at play: the problem, the constraints, the things that were true
when this was decided. No solution yet — just the situation.

## Decision
"We will ___." State the decision plainly and actively.

## Consequences
What becomes easier and what becomes harder as a result. The downsides are
mandatory — an ADR that lists only upsides isn't honest about the tradeoff it
recorded.
```

### Notes and failure modes

- **One decision per ADR.** If you're recording three decisions, write three.
- **Immutable — supersede, don't edit.** When a decision changes, write a new ADR and mark the old one `Superseded by ADR-XXXX`. The record of what you used to think is the point.
- **Keep it short.** An ADR is a page, not a design doc. If it's growing a rollout plan and alternatives analysis, it wanted to be a design doc.
- **Consequences with no downside** is the most common tell that the author was rationalizing, not recording.

### A richer template: MADR

Nygard's four-part form is the floor. When a decision had real contenders worth
capturing, MADR (Markdown Any Decision Records) gives more structure, ordered as:
title · Context and Problem Statement · Decision Drivers · Considered Options ·
Decision Outcome · Consequences · Confirmation · Pros and Cons of the Options ·
More Information. "Considered Options" and "Pros and Cons of the Options" are
first-class sections — the point being that even a single-decision record should
show what else was on the table. MADR stays plain Markdown on purpose, so
decisions are easy to write and easy to diff in version control. Use Nygard for
the lightest possible record; reach for MADR when the alternatives are the part
worth remembering.

---

## Postmortem

### When to use it

After an incident, to explain what happened, why, and what will change so it doesn't recur. Write it blameless: the subject is systems and processes, never a person. The action items are the entire reason the document exists.

Decide *when* a postmortem is required before you're in one — Google's SRE practice is to define trigger criteria up front so it's never a judgment call mid-incident. Common triggers: user-visible downtime or degradation past a threshold, data loss of any kind, an on-call engineer having to intervene (a rollback, a traffic reroute), resolution time over a threshold, or a monitoring miss. And any stakeholder can request one.

### Skeleton

```
# Postmortem: <what happened>
Date of incident · Authors · Status: Draft | Final

## Summary
What happened and the impact, in a few sentences. Readable by someone who
wasn't on the incident.

## Impact
Who and what was affected, quantified: requests failed, duration, customers
hit, revenue or SLA impact. Numbers, not "some users."

## Timeline
Key events in UTC: first symptom, detection, mitigation, resolution. Factual,
timestamped, no interpretation.

## Root cause
The actual why — follow it down past the surface trigger. "A deploy went out"
is a trigger; "no canary gate let a bad config reach all nodes at once" is
closer to a root cause. Distinguish the two.

## Contributing factors
The conditions that made it worse or slower to catch — the holes that lined up.

## What went well / what went poorly
Honest both ways. What in detection or response worked, and what didn't.

## Action items
Concrete fixes, each with an owner and a tracking link. This is the payload of
the whole document — an action item with no owner will not happen.

## Lessons learned
What the team now knows that it didn't before.
```

### Notes and failure modes

- **Blameless or worthless.** The moment a postmortem points at a person, people stop being honest and you stop learning. Fix the system that let the person err.
- **Blameless is a writing discipline, not just an intent.** Swap person-directed accusation for system/process language. Google's own worked example: instead of "Why aren't you making sure everyone finishes training?" — a leading question that puts the reader on the defensive — write "Maybe team members should be required to complete this training before joining the on-call rotation?" Same concern, aimed at the process.
- **"Root cause: human error"** is never a root cause. Ask why the system allowed the error.
- **Action items without owners or dates** are a wish list. Assign and track them. Google enforces this by requiring at least one high-priority (P0/P1) bug for every user-affecting outage — the tracked fix is what separates a postmortem from a diary.
- **Unquantified impact** ("some users saw errors") hides the severity and the priority the fixes deserve.

### Review it, or it never happened

"An unreviewed postmortem might as well never have existed" (Google SRE). Run
incidents through a regular review against a short rubric: was the key data
actually collected; is the impact assessment complete; does the root cause go
deep enough; is the action plan real, with fixes at the right priority; was the
outcome shared with the people who needed it? The review is where a postmortem
becomes organizational memory instead of a file nobody reopens.

### What good looks like

Someone who wasn't there understands what happened and why, trusts that it was analyzed honestly, and can see the specific owned changes that make a recurrence less likely.
