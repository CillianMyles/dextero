---
name: write-pr-description
description: "Draft or rewrite a pull request description that explains the problem, rationale, implementation, tradeoffs, and validation with concise bullets and useful diagrams. Use when creating or improving a PR body; do not use for reviewing whether someone else's PR is correct."
---

# Write PR Description

Write a PR body that lets a reviewer quickly answer:

- What problem does this solve, and why does it matter?
- What approach did the change take, and why?
- How does the new behavior work?
- What tradeoffs, risks, and non-goals should I know?
- What evidence says it works?

## Establish the facts

Inspect the change before writing:

- Identify the exact base and head. Read the diff, changed-file summary, and commits; do not describe only the latest commit.
- Read the existing PR body, repository PR template, linked issue or ticket, relevant discussion, and nearby documentation when available.
- Trace the important runtime path through the surrounding code. Read tests as evidence of intended behavior, not merely as files that changed.
- Separate verified facts from inference. Do not invent motivation, user impact, alternatives, test results, compatibility, or rollout details. If important context is unavailable, say what is unknown.

When rewriting an existing body, preserve required template sections, issue-closing keywords, task lists, and accurate context that the diff does not contain.

## Build the explanation

Lead with the outcome, then cover only the sections the change needs:

1. **Summary** — one to three bullets describing the observable result.
2. **Why** — the old behavior or constraint, who or what it affected, and the desired behavior.
3. **How it works** — the important control flow, data flow, state transition, or responsibility change.
4. **Tradeoffs** — the chosen approach's cost, credible alternatives considered, and why the choice is reasonable here.
5. **Risks and rollout** — compatibility, migration, operational, security, performance, or reversibility concerns when relevant.
6. **Validation** — exact automated and manual checks and their results. Clearly mark checks that were not run.

Call out non-goals when a reviewer could reasonably mistake adjacent work for part of the PR. Explain generated files or broad mechanical changes once instead of itemizing them.

## Prefer visual compression

Use concise bullets and the smallest visual that makes the change easier to understand:

- Pseudocode for branching logic, ordering, retries, fallbacks, or state transitions.
- A Mermaid sequence or flow diagram when three or more participants or steps interact.
- A shallow call tree, component tree, or file tree when ownership moved.
- A small before/after table for exact behavioral or configuration mappings.
- A focused `diff` sketch when the surrounding shape matters more than syntax.

Place each visual beside the text it supports. Use real names from the change and omit incidental calls, files, and branches. Do not add a diagram to a change that a few bullets explain more clearly.

## Recommended shape

Adapt this outline rather than filling every heading mechanically:

```markdown
## Summary

- <observable outcome>
- <important scope boundary>

## Why

- **Before:** <current problem or constraint>
- **Impact:** <why it matters>
- **After:** <desired behavior>

## How it works

<small diagram, pseudocode, table, or bullets>

## Tradeoffs

- **Choice:** <decision and why>
- **Cost:** <complexity, limitation, or operational consequence>
- **Alternative:** <credible option and why it was not chosen>

## Validation

- `command` — passed; <what it proves>
- Manual: <scenario and observed result>
```

Return a complete, paste-ready PR body without a prose preamble. Prefer links to source context over copying it. Avoid a commit log, a file-by-file inventory, long narrative paragraphs, repeated implementation detail, and claims that exceed the available evidence.
