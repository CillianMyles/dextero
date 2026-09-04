# Repository instructions

## Delivery loop

For every change:

1. do the work;
2. run linting and tests;
3. validate the changed behaviour by running it;
4. commit with a Conventional Commit message;
5. push the current branch.

Do not report the work complete before the commit and push succeed unless the
user explicitly asks to stop earlier.

## Automated review loop

Before requesting automated PR review or addressing automated review feedback,
read and follow `.agents/REVIEW_POLICY.md`. A PR gets at most three automated
review rounds unless a human explicitly extends the budget. P0 and P1 findings
remain blocking; deferrable P2 findings go to the roadmap as **Address later**;
P3 findings do not justify another round.

## Delivery

Build user-facing capabilities as tracer bullets through every layer:

1. implement the behaviour in `packages/core`;
2. expose it through a typed Serverpod contract in `packages/server`;
3. expose it in the Flutter app in `packages/app`;
4. expose it in the CLI/TUI in `packages/cli`.

Do not mark a capability complete until the whole path works. Exceptions are
explicitly scoped spikes, refactors, and infrastructure work.

## Tests

Each tracer bullet requires:

- focused core tests;
- server contract and integration tests;
- Flutter interaction tests;
- CLI/TUI interaction tests;
- an end-to-end acceptance test covering the complete path.

Run `make check` before committing. Run `make generate` first after changing a
Serverpod endpoint or model.

## Documentation

Keep documentation short and factual. Put:

- setup and current behaviour in `README.md`;
- durable product direction in `VISION.md`;
- planned work and exit conditions in `ROADMAP.md`.

Do not duplicate material across files or add positioning copy where a direct
technical statement is enough.
