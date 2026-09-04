---
name: address-review-feedback
description: "Triage and resolve automated pull-request feedback without allowing repeated review to expand the change indefinitely. Use when fixing review findings, requesting re-review, or deciding which findings can be deferred."
---

# Address Review Feedback

Read `.agents/REVIEW_POLICY.md` in full before changing code or requesting a
review. The review budget and severity definitions in that file are binding.

## Establish state

- Read the PR acceptance criteria, current diff, checks, unresolved findings,
  all review-round markers, and every unmarked automated trigger and result.
  Reconstruct the count using the policy; a missing marker does not restore a
  round, and an automatic review on PR open or ready is round one.
- Confirm the current head and whether a review is already active. Do not send
  duplicate triggers or push underneath an active review.
- Reject or question findings whose scenario is impossible, whose premise is
  false, or whose proposed fix would violate the intended scope. "Valid" does
  not automatically mean "must expand this PR."

## Triage and fix

- Fix P0 and P1 findings before merge. Use the remaining review budget to
  verify them; if the budget is exhausted, stop for a human decision.
- Fix an in-scope P2 when the change is proportionate and rounds remain. Defer
  an out-of-scope P2 immediately instead of pulling adjacent hardening into the
  PR.
- Treat P3 as non-blocking. Fix it opportunistically only when doing so cannot
  create another review cycle.
- Add focused regression coverage for changed behavior, then run the required
  repository checks. Reply to each handled thread with concrete evidence and
  resolve it when the platform allows.

## Spend a review round

Only request another automated review after known findings are addressed,
required local checks pass, and relevant CI failures are resolved. Persist the
next round marker from the policy before triggering the reviewer, then keep the
head stable until that review completes.

Round three is final. Apply one of the policy's terminal outcomes:

- stop when approved;
- record deferrable P2 findings under `## Review follow-ups` in `ROADMAP.md`,
  link the review threads to those entries, make only the roadmap finalization
  commit, and stop without requesting round four; or
- leave the PR blocked on any P0 or P1 and ask a human to choose the next step.

Never interpret "keep working until approved" as permission for a fourth
automated round. Only an explicit human extension resets or increases the
budget.

For an existing PR that already has three or more unmarked automated reviews,
do not restart numbering at one and do not make another review-driven P2 code
change. Treat its budget as exhausted immediately and apply the matching
terminal outcome.
