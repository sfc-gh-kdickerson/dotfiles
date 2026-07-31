# Design doc / RFC

## When to use it

A design doc proposes a non-trivial technical approach and invites review before you build. Use it when the approach isn't obvious, when the decision is costly or hard to reverse, when it crosses team boundaries, or when someone will reasonably ask "why not X?" and you want the answer on record.

**Not** the right format for a trivial or obvious change — just make it. And not when the direction itself isn't agreed yet; align with a one-pager first, then write the design doc once the direction holds.

## Skeleton

```
# <Title>
Author(s) · Status: Draft | In review | Approved · Date · Reviewers

## Summary
Bottom line up front: the proposal and your recommendation, in a paragraph. A
reader should be able to stop here and know what you're proposing and that you
recommend it.

## Context / background
The problem, the current state, and why it matters now. Enough for someone
outside your head to evaluate what follows. This is where the reader decides
whether they even agree there's a problem.

## Goals
What success looks like, ideally measurable.

## Non-goals
What you are deliberately NOT solving. This section punches above its weight —
it stops scope creep in review and tells the implementer where the edges are.

## Proposed design
The meat. Architecture, key components, data flow, interfaces, and the
decisions that matter. Diagrams earn their space here. Be concrete: name the
actual components, show the actual shapes.

For anything a reader has to both *use* and *build*, separate two altitudes (the
Rust RFC template's guide-level vs reference-level split): first explain it as if
it already shipped and you were teaching a teammate to use it, then give the
implementer-level detail — internals, edge cases, how it interacts with existing
systems. Conflating the two loses both audiences. On a small design you can merge
them; on a large one, don't.

## Alternatives considered
The real options you weighed and why you rejected each — honest tradeoffs, not
strawmen. This is the section that separates a design doc from a pitch, and it
preempts the reviewer's first question. Include the null option: what happens if
we do nothing, or do something smaller? "Do nothing" is always on the table, and
a proposal that can't beat it isn't ready.

## Drawbacks / risks / failure modes
Answer the blunt question the strongest RFC processes require as its own section
— "why should we *not* do this?" What could go wrong, what you're giving up, how
it behaves under failure, and any security or data implications. Name your
design's weak points yourself; a reviewer who finds one you hid trusts the rest
of the doc less.

## Dependencies
What other systems or teams this relies on — and whether they know you're about
to depend on them. A dependency the owning team hasn't agreed to is a risk
wearing a different hat.

## Operational work
The ongoing or manual work this adds once it ships — toil, runbooks, on-call
surface — and who is expected to do it. Designs that are elegant to build and
miserable to operate get caught here.

## Rollout plan
How it ships safely: phases, feature flags, migration/backfill, monitoring, and
a backout path. "How do we turn this off if it's bad?" should have an answer.

## Open questions
What you haven't resolved. Listing these is a strength — it focuses review on
the decisions that are actually still live.
```

Optional: an appendix for detailed benchmarks, schemas, or derivations that would break the main narrative's flow.

## Common failure modes

- **Solution before problem.** The design lands before the reader agrees there's a problem, so they can't evaluate it.
- **No non-goals.** Every reviewer invents their own scope, and the doc dies of a thousand "what about…" comments.
- **Strawman alternatives.** Two obviously-bad options next to your favorite fool no one and waste the section's real power.
- **Unfalsifiable claims.** "This will scale," "this is more maintainable." Attach a number or a mechanism, or cut the claim.
- **No rollout / backout.** A design that can't be turned off or migrated to isn't finished.
- **Decision buried.** The recommendation is on page 6. Put it in the summary.

## How a reviewer grades it

The Rust RFC process judges a proposal on three things, and they invert cleanly
into a self-check before you share:

- **Is the motivation convincing?** Would someone who didn't already want this be persuaded by the problem statement alone?
- **Do you understand the design's impact?** Have you traced how it interacts with what already exists, not just the happy path?
- **Are you candid about drawbacks and alternatives?** A one-sided doc gets received worse than one that names its own weak spots.

If you'd rather borrow a battle-tested skeleton than build sections from scratch,
the Rust RFC template is a good one: Summary · Motivation · Guide-level
explanation · Reference-level explanation · Drawbacks · Rationale and
alternatives · Prior art · Unresolved questions · Future possibilities. Leave a
section as "none" rather than dropping it. Sources in `references/sources.md`.

## What good looks like

A reviewer reads it once and can approve or reject with specific reasons. The "why didn't you just do X?" questions are already answered inside the doc. Six months later, someone reading it understands not just what was built but why the obvious-looking alternative was rejected.
