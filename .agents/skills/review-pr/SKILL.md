---
name: review-pr
description: "Explain and review a pull request in problem-first order within the repository's automated-review budget: establish why the change is needed, judge whether the approach is reasonable, then inspect implementation correctness. Use when understanding or reviewing someone else's PR; do not use merely to draft its description."
---

# Review PR

Review in three gates, in order:

```text
problem and intent -> approach and tradeoffs -> implementation correctness
```

Do not begin a line-by-line correctness review until the problem and approach are understood. Clean code does not make an unnecessary or structurally wrong change reasonable.

## Check the review budget first

Read `.agents/REVIEW_POLICY.md` in full. Inspect the complete PR discussion for
review-round markers and identify the current head before doing a substantive
review.

- If the current head has a requested marker without a completed result,
  perform that round, including round three. If three rounds were spent on
  other heads or the current head was already reviewed, stop without inspecting
  the diff and report that a human must explicitly extend the budget.
- If this review was not already marked, record the next requested marker
  before inspecting the diff. When direct PR write access is unavailable, put
  the requested marker first in the review output so the coder can persist it.
- Do not review a head that is known to fail required checks, duplicates an
  earlier round, or is changing under an active review.

## Gather evidence

- Identify the exact base and head. Inspect the complete diff, changed-file summary, commits, and CI state.
- Read the PR description, linked issue or ticket, acceptance criteria, relevant discussion, and repository instructions.
- Inspect the surrounding implementation, tests, documentation, configuration, schema, and history needed to understand existing behavior and constraints.
- Treat the PR author's explanation as a hypothesis. Reconcile it with the code and source context.
- Distinguish verified facts, reasonable inferences, and missing context. Do not invent product intent.

## Gate 1: Understand the problem

State concisely:

- the current behavior or failure;
- the desired behavior;
- who or what is affected;
- the important constraints and invariants;
- why the change is being made now, when the evidence establishes that.

If the PR solves only a symptom, lacks a demonstrated problem, or leaves the intended behavior ambiguous, surface that before discussing implementation details. Ask only questions whose answers could change the approach or review verdict.

## Gate 2: Judge the approach

Reconstruct the solution at system level. Prefer a small diagram, pseudocode block, call tree, or before/after table over a long narrative.

Assess whether the approach:

- addresses the root problem and acceptance criteria;
- fits the system's existing abstractions and ownership boundaries;
- has a scope and complexity proportionate to the problem;
- preserves compatibility, data integrity, security, performance, and operability where relevant;
- includes a credible migration, rollout, or recovery path when required;
- compares sensibly with the strongest practical alternative.

Give an explicit verdict: **sound**, **sound with concerns**, or **unsound**. Explain the decisive reasons and tradeoffs. If the approach is unsound, lead with that and describe a better direction; do not bury the architectural issue under minor code comments.

## Gate 3: Check correctness

Only after the approach verdict, trace the implementation through every affected path. Check:

- normal behavior and boundary cases;
- error, cancellation, retry, and partial-failure paths;
- state ownership, ordering, concurrency, and idempotency;
- input validation, authorization, secrets, and trust boundaries;
- API, schema, persistence, configuration, and backward compatibility;
- observability and whether failures will be diagnosable;
- tests against the stated problem, including missing negative or end-to-end coverage.

Run focused checks when the review environment permits it. Report the exact commands and results. Do not change the branch, PR, review state, or code unless the user asked for changes.

## Present the review

Make the explanation easy to scan, in this order:

1. **What and why** — the problem and intended outcome.
2. **Approach verdict** — the system-level solution, decisive tradeoffs, and whether it is reasonable.
3. **How it works** — one focused visual or concise bullets.
4. **Findings** — correctness issues, highest severity first.
5. **Verification and residual risk** — checks run, gaps, and uncertainties.

For each finding, include:

- a P0-P3 severity from `.agents/REVIEW_POLICY.md` and a precise code location;
- the triggering scenario;
- the concrete impact;
- the reasoning or evidence;
- a concise fix direction when useful.

Keep blocking findings separate from non-blocking questions and nits. Do not manufacture findings to make the review look complete. If no correctness issues remain, say so explicitly and still note meaningful test gaps or unresolved assumptions.

On round three, apply the policy's terminal outcome. Never recommend a fourth
automated review. Supply paste-ready **Address later** roadmap entries for
deferrable P2 findings when you cannot update `ROADMAP.md` directly; leave any
P0 or P1 as a human decision rather than continuing the automated loop. End the
result by repeating the round marker with `state=completed`.
