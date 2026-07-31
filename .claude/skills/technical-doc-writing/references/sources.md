# Sources

The structural guidance and review heuristics in this skill are grounded in primary and authoritative sources, verified July 2026. Where a claim rests on a single company's practice rather than a broad standard, that's flagged — treat those as one good example, not universal law.

## Design docs / RFCs
- **Rust RFC template** — the canonical nine-section skeleton (Summary · Motivation · Guide-level explanation · Reference-level explanation · Drawbacks · Rationale and alternatives · Prior art · Unresolved questions · Future possibilities). A norm, not a CI gate: leave a section as "none" rather than dropping it. https://github.com/rust-lang/rfcs/blob/master/0000-template.md
- **Rust RFC process (README)** — grades RFCs on strength of motivation, correct understanding of design impact, and candor about drawbacks/alternatives. https://github.com/rust-lang/rfcs/blob/master/README.md
- **Oxide RFDs** — six-state lifecycle (prediscussion · ideation · discussion · published · committed · abandoned) with PR-based discussion. https://oxide.computer/blog/rfd-1-requests-for-discussion
- **Squarespace, "The Power of Yes, If" (2019)** — conditional-approval review model, the Dependencies / Operational-work prompts, and named review anti-patterns. One company's practice, circa 2019 — cite as an example, not a standard. https://engineering.squarespace.com/blog/2019/the-power-of-yes-if

## ADRs
- **Michael Nygard, "Documenting Architecture Decisions" (2011)** — the originating Context / Decision / Consequences format; one decision per record; consequences include the negative ones; "a conversation with a future developer." https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions
- **adr.github.io** — ADR definition and conventions. https://adr.github.io/
- **MADR** — a richer ordered template (Decision Drivers, Considered Options, Pros and Cons of the Options), plain Markdown so decisions are easy to write and easy to diff. https://adr.github.io/madr/

## Postmortems
- **Google SRE Book — Postmortem Culture** — the canonical blameless definition, pre-defined trigger criteria, and the review checklist. https://sre.google/sre-book/postmortem-culture/
- **Google SRE Workbook — Postmortem Culture** — "a postmortem without subsequent action is indistinguishable from no postmortem," the P0/P1-bug rule, and the blameless-language rewrite example. https://sre.google/workbook/postmortem-culture/

## Not yet grounded here
One-pager canonical structure, Google's "Design Docs at Google" (Ubl / industrialempathy) specifics, Amazon's six-pager / PR-FAQ practice, and IETF normative-language conventions (MUST/SHOULD/MAY) were **not** independently verified in this pass. The one-pager guidance here is a sensible synthesis, not a citation. Worth a follow-up research pass if you want those anchored.
