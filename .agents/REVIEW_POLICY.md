# Automated review budget

This policy applies when an automated reviewer and coder iterate on the same
pull request. Its purpose is to find important defects without turning one
change into an open-ended hardening project.

## Three-round limit

- A pull request gets at most three automated review rounds. A generic request
  to keep working until approval does not override this limit.
- A round is spent when an automated review starts for a commit, even if the
  review is later cancelled or made stale by another push. CI runs and human
  reviews do not count.
- Before starting a round, put this marker in the PR discussion, replacing the
  values with the round and full head SHA:

  ```text
  Automated review round 2/3 requested for `0123456789abcdef...`.
  <!-- dextero-review-round:v1 round=2 head=0123456789abcdef... state=requested -->
  ```

- Count unique round numbers in the full PR discussion. The reviewer repeats
  the marker with `state=completed` in its result. A requested marker for the
  current head authorizes that round; a requested marker for an obsolete head
  still consumes its round. Never request two reviews for one head or start a
  review while another is active. If the count cannot be established, do not
  start another automated review until a human decides the remaining budget.
- Run the required local checks and resolve known CI failures before spending
  the next round. Keep the head stable while its review runs.
- Round three is the final automated review. After it, do not inspect another
  head or request another automated review unless a human explicitly grants
  more rounds.

## Severity and scope

Assign the lowest severity justified by concrete impact. Do not raise severity
to evade the review limit.

| Severity | Meaning | Treatment |
| --- | --- | --- |
| **P0 — critical** | An exploitable security boundary failure, irreversible data loss or corruption, unsafe remote execution, or a likely widespread outage. | Blocks merge. Never defer as **Address later**. |
| **P1 — high** | A material violation of an acceptance criterion or public contract, a likely user-visible correctness failure, or a serious reliability, migration, or compatibility regression. | Blocks merge. Never defer as **Address later**. |
| **P2 — medium** | A real, bounded weakness that does not make the current slice unsafe and does not defeat its acceptance criteria. | Fix while rounds remain when it is in scope and proportionate; otherwise defer. |
| **P3 — low** | A nit, optional refactor, speculative hardening, or marginal test/documentation improvement. | Non-blocking. Do not spend another review round on it. |

During rounds one and two, fix in-scope P0-P2 findings and defer out-of-scope
P2 findings immediately. Do not broaden the PR merely because a possible edge
case is valid. Reclassify anything required for safe operation or the stated
acceptance criteria as P0 or P1 rather than parking it as P2.

## Final-round outcomes

After round three, choose exactly one terminal outcome:

- **Approved:** no P0 or P1 findings remain. Stop the loop.
- **Approved with follow-ups:** no P0 or P1 findings remain, and one or more P2
  findings are safe to defer. Record them in `ROADMAP.md`, resolve the review
  threads with links to those entries, and stop the loop. The roadmap-only
  finalization commit does not receive a fourth automated review.
- **Human decision required:** any P0 or P1 finding remains. Leave the PR
  blocked and stop both agents. A human decides whether to fix, split, revert,
  or close the change and whether to grant another review round.

P3 observations may be mentioned in the review result, but they should not be
added to the roadmap unless a human asks for them.

## Address-later entries

Either agent may add an entry when it has write authority; otherwise the
reviewer supplies a paste-ready entry for the coder. Add each deferred P2 under
`## Review follow-ups` in `ROADMAP.md`:

```markdown
- [ ] **Address later — P2:** <specific desired outcome>.
  Origin: PR #<number>, review round <number>, <finding link or stable ID>,
  affected area `<path or component>`. Exit: <observable test or condition>.
```

Consolidate duplicate findings. The entry must retain enough origin and exit
context for a later change to solve it without reopening the entire old review.
