---
name: technical-doc-writing
description: >
  Write and review structured engineering documents: design docs, RFCs,
  one-pagers, implementation/technical specs, architecture decision records
  (ADRs), and postmortems. Covers choosing the right format, structuring the
  argument so a reader can decide or act, and reviewing a draft (yours or
  someone else's) for the gaps that get docs sent back. Use whenever the user
  is drafting, outlining, structuring, tightening, or reviewing any internal
  engineering decision or design document — including phrasings like "write a
  design doc", "draft an RFC", "turn this into a one-pager", "spec out the
  implementation", "write an ADR", "write up the postmortem", "review my design
  doc", or "does this doc make sense" — even when they don't name the format.
  Not for API reference, READMEs, tutorials, or end-user docs, and not for
  general prose humanizing (that's the natural-writing skill).
user_invocable: true
arguments:
  - name: target
    description: "Optional: a topic to write about, a path to a draft to revise or review, or a short description of the doc. If omitted, use whatever doc is in play."
    required: false
---

# Technical doc writing

A technical doc exists to move a decision or an implementation forward in someone else's head. The reader has a job — approve it, build it, or remember later why it was built this way — and the document either lets them do that job fast or wastes their time. Length is not the goal. A reader who can decide after one page beats a reader still confused after ten.

Most weak engineering docs fail the same few ways: they open with the solution before the reader knows the problem, they never say what's out of scope, they present one option as if no others existed, and they hedge where they should commit. This skill is about avoiding those, in whatever format fits.

## Step 1 — Decide what you're writing, and for whom

Before drafting, pin down three things. They change the shape of everything after.

- **Reader and their job.** A staff engineer approving an approach, a teammate who'll implement it, and a maintainer reading it cold in six months each need something different. Write for the primary one.
- **The decision or action the doc must produce.** "Get sign-off on using X." "Let someone build Y without asking me questions." "Record why we chose Z so we stop relitigating it." If you can't name it in a sentence, you're not ready to draft.
- **The format.** Pick by purpose, not by habit:

| Format | Use it when the job is… | Reference |
|---|---|---|
| **One-pager** | Align, or get a quick yes/no on a direction | `references/one-pager.md` |
| **Design doc / RFC** | Propose a non-trivial technical approach and invite review | `references/design-doc.md` |
| **Implementation / tech spec** | Tell someone exactly how to build an already-agreed approach | `references/implementation-spec.md` |
| **ADR** | Record one decision and its rationale, durably | `references/adr-postmortem.md` |
| **Postmortem** | Explain an incident: what happened, why, what changes | `references/adr-postmortem.md` |

Read the matching reference file for the skeleton and section-by-section guidance. If two formats seem to fit, you usually want the lighter one first — a one-pager to align, then a design doc once the direction holds.

If the reader or the decision is genuinely unclear and would change how you write, ask the user one specific question instead of guessing and falling back on generic doc-voice.

## The spine most of these share

The formats differ, but the load-bearing structure underneath most of them is the same, and each part earns its place:

1. **Problem / context first.** State the problem before any solution. A reader who doesn't understand the problem can't evaluate the answer — they'll just pattern-match on whether it looks familiar.
2. **Goals and non-goals.** Non-goals do the most work per line in the whole doc: they stop reviewers from dragging in scope you deliberately cut, and they tell the implementer where to stop.
3. **The proposal.** The actual answer, concrete enough to act on.
4. **Alternatives considered.** This is what separates a design doc from a sales pitch. Showing the options you rejected, and why, proves you did the work and preempts the reviewer's first question: "why not X?" Include the null option — what happens if we do nothing, or do something smaller — because "do nothing" is always a real alternative, and a proposal that can't beat it isn't ready. Strawmen fool no one; use real alternatives with real tradeoffs.
5. **Drawbacks, risks, and tradeoffs.** Answer the blunt question the strongest RFC processes bake in as a required section — "why should we *not* do this?" — then cover what could go wrong and what you're giving up. Naming a weakness yourself buys more trust than hiding it costs you.
6. **Rollout / sequencing** (for anything that ships): how it lands safely, in what order, behind what flag, with what backout.
7. **Open questions.** Surface what you haven't resolved. Hiding an open question doesn't close it; it just relocates it to a review comment, where it's more expensive.

A one-pager compresses several of these to a line each; an implementation spec expands 3 and 6 and mostly skips 4. The reference files say which parts matter for each.

## Writing it well

Reviewers judge a doc partly on whether it reads like someone who knew what they were saying wrote it. A few habits carry most of that, tuned for technical docs specifically:

- **Lead with the answer.** Put the conclusion in the first paragraph, then support it. This is the opposite of a mystery novel. Busy readers should get the decision before the reasoning; skimmers should get it at all.
- **Cut throat-clearing and hedging.** Delete the "In today's landscape…" windup and the "it could perhaps be argued that this may…" qualifiers. Commit to the claim or drop it. Confidence isn't a tell; it's the absence of waffling.
- **Break the symmetry.** The tidy intro → three balanced bullets → recap-that-restates-the-intro shape is a machine default. Let sections run to unequal lengths. End on your last real point, not a summary of points the reader just read.
- **Drop inflated vocabulary.** delve, leverage (as a verb), robust, seamless, crucial, pivotal, myriad, underscore, foster, showcase. When a plainer word exists, use it — "use" over "leverage," "important" over "crucial."
- **Watch the em dash and the rule-of-three.** Both pour out of AI drafts. A comma or period usually does the em dash's job; "fast, reliable, and scalable" triads are reflexive — vary them or cut one.
- **Be concrete.** Numbers, real component names, actual tradeoffs. "p99 dropped from 420ms to 90ms" beats "significantly improved performance."

**The technical exception — read this before applying the list above.** General prose advice says strip inline code tokens, exact flags, and ALL_CAPS constants out of sentences. In a technical doc that inverts: the literal `NUM_WORKERS`, the exact error string, the specific version, the precise number **are the content**, and a reader will search for them. Keep them verbatim and exact. Precision beats rhythm here. The test is whether the reader needs the exact string or just the idea behind it — in design and implementation docs, far more often the exact string.

For a deeper pass on prose that still reads like a model wrote it, the **natural-writing** skill (if installed) covers the full set of tells. Use it as a finishing pass, and apply the technical exception above on top of it.

## Reviewing a doc

Whether you're reviewing your own draft before sharing it or someone else's for feedback, read it three times as three different people:

- **The approver.** Can they reach a yes or no from this, and say why? If the doc doesn't surface a clear decision and the information needed to make it, it isn't ready.
- **The implementer.** Could they build this without a follow-up meeting? Where would they get stuck or have to guess?
- **The maintainer in six months.** Will they understand *why*, not just what? Rationale is the part that rots first and matters most later.

Then run the checklist:

- Does the problem come before the solution?
- Is the motivation convincing to someone who didn't already want this?
- Are non-goals stated explicitly?
- Are the alternatives real, with honest reasons for rejection — or strawmen? Is "do nothing" addressed?
- Does the doc own its drawbacks, or read as one-sided advocacy?
- Is every claim falsifiable? "This will scale" is not; "handles 10k rps at p99 < 100ms on one node" is.
- Are open questions surfaced, or conspicuously absent?
- Could you cut 20% without losing information? Length without decisions is a smell.

The first three checks — convincing motivation, correct grasp of the design's impact, and candor about drawbacks and alternatives — are the exact three signals the Rust RFC process uses to separate strong proposals from weak ones. A doc that misses them gets received badly no matter how polished the prose.

When you find a problem, name the specific gap and where, not a vague "add more detail." "No non-goals — a reviewer will ask whether this covers streaming, so say if it doesn't" is actionable. "Needs work" is not.

### If you're the reviewer, not the author

Review itself fails in predictable ways (Squarespace's engineering team named these): reviewers unsure what they're even supposed to evaluate, authors buried under an undifferentiated pile of comments, approvers going *silent* instead of giving a clear signal, and no agreed point at which review is "done." Counter them directly — say which dimension you're reviewing (correctness? scope? naming?), and when you're satisfied, say yes out loud. A "yes, if" — approve with your conditions attached — unblocks the author instead of making them wait for another round, and reads as collaboration rather than gatekeeping.

## Working mode

- **Fresh draft:** confirm reader + decision + format, pull the reference skeleton, and write toward the decision. Default to Markdown unless the user names a medium.
- **Revising a draft** (the target is a path or pasted text): read once for structure, once for prose. Fix structure before wording — a beautifully worded doc with no non-goals still gets sent back. Preserve the author's meaning and any hard constraints (length caps, required sections). You're changing how it lands, not what it claims.
- **Reviewing without rewriting:** deliver the three-reader read plus checklist findings as specific, located notes the author can act on.

## Sources

The structure and review heuristics here are grounded in primary sources — the Rust RFC template and process, Michael Nygard's ADR post and MADR, and the Google SRE book and workbook on postmortems — plus one named single-company practice (Squarespace). Full list with links, and honest notes on what *isn't* yet verified (one-pagers, Google and Amazon specifics), in `references/sources.md`.
