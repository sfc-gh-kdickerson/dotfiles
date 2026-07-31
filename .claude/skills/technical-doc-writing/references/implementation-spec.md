# Implementation / technical spec

## When to use it

An implementation spec tells someone exactly how to build an approach that's already been agreed — because the design doc is approved, or the approach is obvious enough to skip one. Use it when a different person will implement than designed it, when the work spans multiple people or PRs and needs sequencing, or when the interfaces are intricate enough that getting them wrong is expensive.

**Not** the right format when the approach itself is still in question — that's a design doc. A spec assumes the "what" and "why" are settled and focuses on the "how."

## Skeleton

```
# <Title> — implementation spec
Link to the design doc / decision this implements.

## Scope
What this spec covers, and what's explicitly deferred to later work. Keep the
implementer inside the lines.

## Interfaces / API / schema
The exact signatures, types, endpoints, config keys, and data models. This is
the section where precision beats prose — write the literal names and shapes
the code will use, verbatim. Ambiguity here becomes bugs.

## Data flow / control flow
How a request or record moves through the system, step by step. Sequence
diagrams pay for themselves.

## Changes by component
What changes and where, at the module/file level. What's new, what's modified,
what's deleted. Enough that a reviewer knows where each PR will touch.

## Migration / backfill
If data, schema, or state changes: the migration steps, ordering, and how you
handle in-flight data and rollback.

## Test plan
What proves this works — unit and integration coverage, the edge cases that
matter, and how you'll verify in staging/prod. If you can't say how you'll test
it, you don't understand it yet.

## Sequencing / PR breakdown
The order of work, what depends on what, and what can proceed in parallel.
Break it into a series of small, independently reviewable PRs rather than one
mega-change — each should land and be revertable on its own.

## Rollout / flags / backout
Feature flags, staged rollout, monitoring to watch, and how to turn it off.

## Open questions
Anything still unresolved that the implementer will hit.
```

## Common failure modes

- **Hand-waved interfaces.** "It'll expose an endpoint for that" — which route, which method, what request and response shape? Vagueness here is where implementations diverge.
- **No test plan.** The spec describes building it but not proving it, so verification becomes an afterthought.
- **No sequencing.** Without a PR breakdown the work arrives as one unreviewable mega-diff.
- **Relitigating the design.** A spec that re-argues the approach is a design doc wearing the wrong hat — link the decision and move on.

## What good looks like

The implementer builds it from the spec without a follow-up meeting, and the reviewer of each PR can see exactly where it fits in the plan. The interfaces in the merged code match the ones in the spec because the spec was exact.
