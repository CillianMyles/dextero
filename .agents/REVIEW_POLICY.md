# Automated review policy

## Budget

- A PR gets at most three automated review rounds unless a human explicitly grants more. The budget is shared across agents, sessions, and head changes.
- Before reviewing or fixing feedback, inspect the full PR timeline. Automatic,
  manual, unmarked, cancelled, failed, and stale review attempts count; human
  reviews and CI do not.
- A round is spent when its marker is posted, its trigger is sent, or an
  automatic review starts. Never reuse it or review the same head twice.
- Before a manual trigger, post the marker below and keep the head stable until the review finishes:
  `<!-- dextero-review-round:v1 round=N head=FULL_SHA state=requested -->`
- Missing or ambiguous bookkeeping never restores budget. If three rounds may
  have been spent, stop for a human decision.
- Run required checks and resolve known CI failures before another round.

## Findings and stopping

- **P0/P1:** blocking correctness, security, data, compatibility, or reliability failures. Fix before merge; never defer.
- **P2:** a real but bounded weakness. Fix only when in scope and proportionate;
  otherwise add an **Address later — P2** item under `ROADMAP.md`'s
  `## Review follow-ups`, with its PR/round origin and an observable exit test.
- **P3:** nits or optional hardening. Do not start another round or add roadmap
  work for them.
- Stop when no P0-P2 remains; approval does not require using all three rounds.
- Round three is final: approve if no P0-P2 remains, approve with roadmap
  follow-ups if only deferrable P2 remains, or require a human decision if any
  P0/P1 remains. Never start round four without explicit human approval.
