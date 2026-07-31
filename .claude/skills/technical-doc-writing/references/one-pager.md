# One-pager

## When to use it

A one-pager aligns people on a direction and gets a quick yes/no or a resourcing decision — before anyone invests in a full design. Reach for it to socialize an idea, request prioritization or headcount, or unblock a decision that's stalled in meetings.

**Not** the right format when the reader needs to evaluate technical correctness (write a design doc) or build the thing (write an implementation spec). If your one-pager is spilling past a page, it wants to be a design doc — let it become one.

## Skeleton

The name is the constraint: it fits on one page. Every section is a few sentences at most.

```
# <Title: the change, stated as an outcome>

**Summary.** One or two sentences: the ask and the why. A reader who stops here
should still know what you want and roughly why.

## Problem
2–4 sentences. What's broken or missing, who feels it, and the cost of doing
nothing. Lead here, not with your solution.

## Proposal
A paragraph at the altitude of "what," not "how." What you want to do and the
shape of it. Save mechanics for a later doc.

## Impact / why now
What changes if this happens, quantified where you can. Why this is worth doing
now rather than later.

## Alternatives (optional, one line each)
The other options and why not. Even one line here answers the obvious question
and shows you looked.

## Ask / next steps
The decision or resources you need, and from whom, by when. Be specific — "I
need sign-off to spend two weeks on the spike" beats "thoughts?"
```

## Common failure modes

- **Ask buried at the bottom, or missing.** Put what you want up top and make it a specific decision, not an open-ended "thoughts?"
- **Solution with no problem.** If the reader doesn't feel the problem, the proposal has nothing to attach to.
- **It grew into a design doc.** Over a page means you've picked the wrong format. Cut, or promote it to a design doc.
- **Unquantified impact.** "Improves performance" persuades no one; "cuts nightly job from 6h to 40m" does.

## What good looks like

A skimmer reads the title and summary and knows the ask. A decision-maker reads the whole page in two minutes and can say yes, no, or "talk to me about the alternative" — with a reason.
