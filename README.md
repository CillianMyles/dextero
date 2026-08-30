# Dextero

A work-in-progress typed coding-agent harness written in Dart.

## Question

Can Dart produce a small, fast-starting standalone CLI that executes a child
process, captures its result as structured data, preserves its exit status,
and cross-compiles from macOS to Linux?

## Scope

The spike intentionally implements one narrow harness primitive:

- accept a command through `--run`;
- execute it through the platform shell;
- capture stdout, stderr, and exit status;
- emit one JSON result envelope;
- propagate the child exit status;
- compile to a standalone AOT executable.

It uses only `dart:io` and `dart:convert`; there are no package dependencies or
external runtime requirements after compilation.

## Agent primitives

The spike now also sketches the next layer of a harness without choosing an
LLM vendor:

- `ToolDefinition`, `ToolCall`, and `ToolResult` provide the JSON-shaped wire
  types;
- `Tool` is the typed execution boundary;
- `ReadFileTool` reads UTF-8 files without changing whitespace;
- `EditFileTool` performs an exact replacement only when the preimage occurs
  once, preventing accidental broad edits;
- `ListFilesTool` returns stable workspace-relative entries without following
  symbolic links;
- `RunProcessTool` executes an executable and argument array directly, without
  shell interpolation;
- `BashTool` makes shell interpretation explicit and adds a bounded timeout
  plus per-stream output caps;
- `AgentModel` is the adapter seam for an OpenAI, Anthropic, or local model;
- `AgentLoop` runs a bounded model → tool → model loop, returning tool errors
  to the model instead of crashing the run;
- `CodexAppServerAgent` connects those same tools to OpenAI through Codex's
  app-server dynamic-tool protocol.

Run the deterministic demo model through both sample tools:

```sh
dart run bin/agent_demo.dart
```

The scripted model is deliberately not pretending to be intelligent. It makes
the orchestration protocol runnable while keeping provider SDK and API-key
decisions outside this feasibility spike.

## OpenAI subscription OAuth

OpenAI's supported subscription login boundary is Codex, not the general
OpenAI API. The OAuth implementation therefore launches `codex app-server`
over JSONL stdio and uses its experimental dynamic-tool protocol:

```text
Dart CLI ── JSON-RPC ──> codex app-server ──> ChatGPT subscription
    │                         │ login + refresh
    └── executes dynamic <────┘
        Tool implementations
```

Authenticate once using the Codex CLI, then run the Dart demo:

```sh
codex login
codex login status
dart run bin/codex_oauth_demo.dart
```

Codex owns the cached credential and refresh lifecycle. The Dart code never
reads `~/.codex/auth.json`, whose contents must be treated like a password.
This also avoids binding the harness to undocumented ChatGPT token endpoints.

The adapter:

- negotiates `experimentalApi` during app-server initialization;
- creates an ephemeral thread with each `ToolDefinition` as a dynamic tool;
- puts Codex's built-in execution in a non-escalating read-only sandbox so
  mutations must pass through the host-provided tools;
- executes `item/tool/call` requests locally and sends structured success or
  failure results back to Codex;
- captures the final agent message and fails closed on malformed JSON-RPC,
  failed turns, missing output, duplicate tool names, or message timeout;
- accepts an injected transport, allowing complete protocol tests without
  network access or credentials.

Dynamic tools are explicitly experimental in the current Codex app-server
protocol. Keeping this in `CodexAppServerAgent` prevents protocol churn from
leaking into the provider-neutral tool and loop types. For general OpenAI API
automation, use a Platform API key instead of attempting to reuse ChatGPT
OAuth credentials.

Run the primitive tests with:

```sh
dart test
```

There is one test file per tool. Each behaviour and failure mode is a separate
test case, including exact output preservation, malformed arguments, missing
entities, traversal, outside symlinks, ambiguous edits, deterministic ordering,
argv preservation, shell semantics, non-zero exits, and timeout termination.

## Run from source

```sh
dart run bin/harness.dart --run 'printf dart-harness-ok'
```

Expected output on macOS:

```json
{"platform":"macos","exitCode":0,"stdout":"dart-harness-ok","stderr":""}
```

## Compile and run

Build for the current machine:

```sh
mkdir -p build
dart compile exe bin/harness.dart -o build/harness
./build/harness --run 'printf dart-harness-ok'
```

Cross-compile a Linux x64 executable from a supported 64-bit host:

```sh
dart compile exe \
  --target-os=linux \
  --target-arch=x64 \
  bin/harness.dart \
  -o build/harness-linux-x64
```

Do not commit `build/`; compiled artifacts are platform-specific evidence, not
source.

## Recorded evidence

Test host: macOS Arm64, Dart SDK 3.10.8.

- Current-host compilation completed in **1.25 seconds**.
- macOS Arm64 executable size: **5,529,104 bytes**.
- Five clean launches each measured approximately **0.01 seconds** using
  `/usr/bin/time -p`.
- The compiled CLI executed a shell command and returned the expected JSON.
- A child writing `child-failed` to stderr and exiting `7` produced a JSON
  result with `exitCode: 7` and caused the CLI itself to exit `7`.
- Calling it without the required arguments printed usage and exited `64`.
- macOS Arm64 to Linux x64 compilation completed in **3.25 seconds**.
- Linux x64 executable size: **6,556,608 bytes**.
- `file` identified the Linux artifact as a stripped x86-64 ELF using the
  normal system dynamic loader.
- macOS to Windows x64 and macOS to macOS x64 cross-compilation were rejected;
  the installed SDK offered Linux cross-targets only.
- The typed agent layer passes **69 focused tests**, including six app-server
  protocol tests that use a deterministic in-memory transport.
- The deterministic agent demo runs from source and as an AOT executable.

## Tool-use audit: what should come next

An independent read-only audit parsed **46,972** historical Dexter tool calls
from May 14 through August 30. Heartbeats inflate raw totals, so recurrence and
category rank matter more than percentage share. The implementation order that
best matches actual work is:

1. **`SearchFilesTool`** — file search appeared in roughly 1,944 shell calls.
   Support literal and regex modes, include/exclude globs, stable line/column
   results, workspace confinement, symlink protection, and result/byte caps.
2. **`ApplyPatchTool`** — 2,786 direct patch calls justify atomic multi-file
   unified diffs. Preflight the entire patch; require preimage hashes or expected
   text; reject binary, traversal, and symlink escapes; cap files and bytes.
3. **Read-only `GitInspectTool`** — about 5,226 Git status/diff/log/show calls.
   Disable hooks, pagers, and external diff; confine the repository and cap
   output/time. Leave add/commit/push/checkout behind explicit approval.
4. **`McpToolAdapter`** — map remote MCP schemas/results into `Tool` instead of
   reimplementing GitHub, OpenClaw, Strava, and every future integration.
5. **`HttpFetchTool`** — start with GET/HEAD and enforce SSRF, redirect, content
   type, size, and timeout policies; never inherit ambient cookies or secrets.
6. **Browser/CDP tool family** — valuable after the coding core, but keep it in
   an isolated profile with DOM-first actions and approval for consequential
   submissions.

Do not build bespoke service tools, whole-desktop control, general deletion,
Git mutation, or messaging/cron primitives before the MCP and approval/audit
layers exist. Bash was historically dominant, but that is evidence for filling
typed-tool gaps—not for making arbitrary shell execution the default.

## Limitations

Dextero currently has a credible agent kernel, not a complete coding harness.
Compared with mature tools such as Pi or Codex CLI, the largest gaps are in
control, state, safety, and user experience rather than the number of tools.

### Sessions and context

- Runs cannot be persisted, resumed, forked, or recovered after a crash.
- There is no context-window accounting, token budgeting, automatic
  compaction, or conversation summarisation.
- Messages are handled as a single synchronous exchange; attachments, images,
  checkpoints, and queued steering messages are not modelled yet.

### Execution safety

- Workspace path checks are useful guardrails, but they are not an OS-enforced
  sandbox or security boundary.
- There is no permission engine, risk-based approval policy, network policy,
  command allow/deny policy, secret filtering, or audit record.
- `BashTool` remains a high-privilege escape hatch. It bounds time and output,
  but does not filter the environment, enforce resource limits, or guarantee
  termination of the complete child process tree.
- `RunProcessTool` does not yet support streaming output, cancellation,
  timeouts, output limits, environment filtering, or sandboxing.

### Model and execution engine

- `AgentModel` is only an adapter seam. Dextero does not yet provide direct
  production adapters with streaming, retries, backoff, usage accounting,
  capability discovery, or provider-specific tool-call normalisation.
- Tool calls run sequentially without cancellation, background execution,
  interactive PTYs, incremental output events, lifecycle hooks, idempotency,
  or subagent delegation.
- Tool schemas are exposed to model adapters, but runtime argument validation
  is implemented separately by each sample tool instead of centrally.

### Coding workflow and UX

- File search, atomic multi-file patching, Git inspection, MCP, HTTP fetching,
  language intelligence, and browser automation are not implemented.
- There is no interactive TUI, diff review, session picker, live progress,
  permission controls, configuration profiles, shell completion, or stable
  JSONL automation interface.
- Project instructions, skills, plugins, hooks, and dynamically registered
  tools are not yet supported.

### Codex app-server boundary

`CodexAppServerAgent` is intentionally a Dart client and tool host around Codex
app-server. Codex still owns model execution, OAuth, context management, and
much of the mature harness behaviour. This proves that Dart can extend and
control Codex, but it does not prove that the provider-neutral `AgentLoop` can
replace Codex or Pi.

The adapter also requires an installed Codex CLI, an existing login, and an
experimental app-server API. It is suitable for the spike, not yet a stable
public wire contract.

### Platform coverage

- Native packages, MCP, browser automation, Windows execution, and Linux
  execution have not been tested; the Linux artifact was inspected but not run.
- A standalone Dart executable includes the Dart runtime, not arbitrary native
  libraries or external programs used by the application.
- Windows and macOS releases still need native build runners; the current Dart
  SDK only offered Linux cross-compilation from this host.

## Future work

The next milestones should build the harness machinery before expanding into
many more service-specific tools:

1. Define a typed event stream for model deltas, tool lifecycle events,
   approvals, output, usage, and errors.
2. Add cancellation, streaming process output, reliable process-tree cleanup,
   PTY support, and bounded background execution.
3. Persist resumable sessions with checkpoints, token budgeting, context
   compaction, and crash recovery.
4. Implement `SearchFilesTool`, atomic `ApplyPatchTool`, and read-only
   `GitInspectTool`.
5. Introduce a permission engine plus platform-specific OS sandbox adapters,
   environment filtering, network policy, and an audit trail.
6. Add an MCP client and dynamic tool registry before creating bespoke service
   integrations.
7. Implement a direct streaming model adapter, starting with the OpenAI
   Responses API, while keeping the Codex app-server path available.
8. Build interactive and non-interactive frontends: a TUI for humans and a
   versioned JSONL protocol for automation.
9. Load project instructions, skills, configuration, and lifecycle hooks.
10. Add parallel tool scheduling, subagents, observability, cross-platform
    integration tests, and fuzz tests for malformed model/tool responses.

## Verdict: VALIDATED

**Question:** Can Dart act as the native CLI and subprocess orchestration layer
of a computer-use or coding harness?

**Evidence:** The source compiled into a 5.53 MB macOS executable, started in
about 10 ms, emitted structured child-process results, propagated error status,
and cross-compiled into a 6.56 MB Linux x64 ELF.

**What worked:** AOT distribution, startup time, standard-library process I/O,
structured output, exit-code propagation, and Linux cross-compilation.

**What failed or surprised us:** “Cross-platform” still means an artifact
matrix. Windows and macOS cannot be cross-built from this macOS host, and even
the self-contained Linux executable relies on the system loader.

**Recommendation:** Treat Dart's CLI/runtime feasibility as validated. The
next risk to spike is the hybrid adapter architecture: one MCP tool, one
Puppeteer browser action, and one experimental desktop action behind the same
typed Dart tool interface.

See also:
[Dart, Flutter and Serverpod as a remote computer-use harness](https://github.com/CillianMyles/dexter-workspace/blob/main/resources/posts/2026-08-30-dart-computer-use-coding-harness.md).
