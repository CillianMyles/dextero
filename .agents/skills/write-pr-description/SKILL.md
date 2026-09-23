---
name: write-pr-description
description: "Draft or rewrite compact pull request descriptions using diagrams, pseudocode, or tables to explain nontrivial changes. Use when creating or improving a PR body; do not use for reviewing implementation correctness."
---

# Write PR Description

Make the problem, approach, and evidence understandable in one quick scan.
Default to **250 words or fewer**, including bullets and table cells but excluding
diagram/code syntax. Simple changes should be much shorter. Exceed this only
when the user requests detail or essential compatibility, rollout, or correctness
information cannot fit; link supporting reports instead of reproducing them.

## Establish the facts

- Inspect the exact base/head, complete diff, relevant runtime path, and tests.
- Read the existing PR body, required template, and linked context. Preserve
  issue-closing keywords and required sections.
- Separate verified results from recommendations and untested assumptions.
  Never invent validation or claim that a diagram proves behavior.

## Explain through a compact visual

For a nontrivial change, include at least one representation that carries the
explanation. Choose what helps the reviewer; do not add every visual type:

| What needs explaining | Preferred representation |
| --- | --- |
| Boundaries, ownership, dependencies | Small architecture or component diagram |
| Calls between participants, async ordering, recovery | Mermaid sequence diagram |
| Transactions, branching, retries, state transitions | Short pseudocode or flowchart |
| Alternatives, exact before/after behavior, spike findings | Small comparison table |

Use real names and show only the consequential steps. A trivial change that is
clear in one or two sentences does not need a visual. Multiple layers or recovery
steps are reasons to use a visual, not to replace it with longer bullets.

**The visual replaces prose.** Do not narrate its steps again above or below it.
If the flow needs more than roughly eight steps to explain, show the main path
and link the detailed design. Check that Mermaid syntax renders on GitHub.

## Assemble the body

Use this order, without turning each item into a mandatory heading:

1. One or two sentences: the concrete problem and resulting behavior or decision.
2. The diagram, pseudocode, or table explaining the approach.
3. Only material tradeoffs or scope limits not already shown. Link deeper detail.
4. Two or three short validation bullets with commands and observed results.

For spikes, put findings and alternatives in a table and link the full report.
For implementation, prefer the runtime flow. Explain generated-file volume once
if needed. Avoid separate Summary/Why/How/Findings sections repeating the same facts.

## Compression pass before publishing

- Remove prose that repeats the visual, a linked report, or another bullet.
- Split or shorten bullets that contain several sentences; do not disguise
  paragraphs as bullets.
- Keep validation specific without listing every passing test.
- Check the word budget, factual scope, and rendered visual. Essential risk and
  untested limitations must remain visible; move supporting detail behind links.

Return the complete PR body without a preamble. Publishing or editing a PR still
depends on the user's authorization; this skill does not grant it.
