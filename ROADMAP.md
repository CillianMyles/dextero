# Roadmap

Dextero is being built from the control plane outward. The priority is a safe,
resumable orchestration system—not the fastest possible accumulation of tools.

This roadmap is directional. Milestones describe coherent product increments;
they are not release-date promises.

## Foundation — working today

- [x] JSON-shaped tool definitions, calls, and results
- [x] Provider-neutral model interface
- [x] Bounded model → tool → model loop
- [x] Workspace-confined file reading and deterministic file listing
- [x] Exact single-match file editing
- [x] Direct argv-based process execution
- [x] Explicit shell execution with timeout and output caps
- [x] Codex app-server specialist adapter
- [x] Deterministic demos and focused tool/protocol tests
- [x] Native Dart AOT compilation spike

## Milestone 1 — typed event backbone

Make every task observable and controllable before adding more authority.

- [ ] Define versioned events for task, model, tool, approval, artifact, usage,
  warning, and error lifecycles.
- [ ] Add stable task, run, tool-call, and correlation identifiers.
- [ ] Support streaming model output and incremental tool output.
- [ ] Add cancellation propagation and reliable child-process-tree cleanup.
- [ ] Add timeouts, output limits, environment filtering, and bounded background
  execution to all process tools.
- [ ] Provide a stable JSONL interface for automation and tests.

**Exit condition:** a task can be watched and cancelled through one typed event
contract without relying on terminal scraping.

## Milestone 2 — local Serverpod vertical slice

Prove the product architecture with the smallest useful remote controller.

- [ ] Add a Serverpod Mini service beside the harness without a Postgres
  requirement.
- [ ] Generate shared task, event, approval, and command models.
- [ ] Expose endpoints to create, inspect, cancel, and approve tasks.
- [ ] Stream task events to a generated Dart client over WebSocket.
- [ ] Build a minimal Flutter controller showing task status, events, and one
  approval interaction.
- [ ] Start with in-memory task state and document the restart limitation.
- [ ] Add local-only development defaults and explicit network binding.

**Exit condition:** a Flutter client can start the deterministic demo, observe
its typed events, approve a gated action, cancel it, and receive the result from
a local Dextero host.

## Milestone 3 — permissions, approvals, and audit

Turn current guardrails into enforceable product boundaries.

- [ ] Define capability grants scoped by task, resource, operation, and
  duration.
- [ ] Classify actions by risk and map them to configurable approval policies.
- [ ] Record immutable, structured audit events for grants, actions, results,
  and denials.
- [ ] Filter inherited environment variables and redact secrets from events.
- [ ] Introduce network egress policy and platform sandbox adapter interfaces.
- [ ] Add approval expiry, denial, cancellation, and reconnect behaviour.
- [ ] Ensure remote controllers cannot bypass local policy.

**Exit condition:** every consequential action is denied, pre-authorized by a
specific capability, or paused for an explicit approval with an audit record.

## Milestone 4 — durable sessions

- [ ] Persist tasks, events, approvals, and checkpoints with SQLite/Drift.
- [ ] Resume or fail tasks predictably after a process restart.
- [ ] Add context-window accounting, token budgets, and compaction.
- [ ] Support queued steering messages and reconnecting event subscribers.
- [ ] Define retention, export, and deletion controls for local data.
- [ ] Add schema migrations and recovery tests.

**Exit condition:** a host restart or controller disconnect does not erase task
history, approvals, or the ability to understand what happened.

## Milestone 5 — specialist delegation

Use coding as the first complete delegation domain.

- [ ] Define a common specialist contract: scoped task, context, capabilities,
  progress events, steering, cancellation, artifacts, and structured result.
- [ ] Harden the Codex app-server adapter behind that contract.
- [ ] Add a second coding-agent adapter to prove portability.
- [ ] Enforce separate workspaces and capability grants for delegated work.
- [ ] Support foreground and bounded background specialists.
- [ ] Incorporate specialist results and artifacts into the parent task.

**Exit condition:** Dextero can delegate a repository task, show live progress,
constrain and cancel the specialist, and return a structured result without
pretending to be the coding agent itself.

## Milestone 6 — core local capabilities

Add the highest-value typed tools behind the permission model.

- [ ] `SearchFilesTool`: literal/regex search, include/exclude globs, stable
  locations, workspace confinement, and result caps.
- [ ] `ApplyPatchTool`: atomic multi-file changes, complete preflight,
  preconditions, path validation, and byte/file limits.
- [ ] `GitInspectTool`: read-only status, diff, log, and show with hooks, pagers,
  and external diff disabled.
- [ ] `HttpFetchTool`: GET/HEAD with SSRF, redirect, content-type, size, and
  timeout policy; no ambient cookies or credentials.
- [ ] Central JSON Schema argument validation for every tool.
- [ ] PTY support for explicitly approved interactive processes.

Git mutation, deletion, and general shell authority remain separately gated.

## Milestone 7 — runtime ecosystem

- [ ] Add an MCP client and dynamic tool registry.
- [ ] Define manifests, trust levels, lifecycle, health, and version negotiation
  for runtime adapters.
- [ ] Add direct streaming model adapters while retaining provider-neutral
  kernel contracts.
- [ ] Support project instructions, skills, and configuration profiles.
- [ ] Add hooks and artifact storage without allowing extensions to bypass
  policy.

**Exit condition:** useful capabilities can be installed or connected without
recompiling Dextero or granting them ambient authority.

## Milestone 8 — browser and computer use

- [ ] Add an isolated browser profile and Chrome DevTools Protocol adapter.
- [ ] Prefer DOM/semantic actions and gate consequential submissions.
- [ ] Add screenshots and artifacts to the typed event stream.
- [ ] Define stable native adapter interfaces for macOS accessibility, Windows
  UI Automation, and Linux accessibility APIs.
- [ ] Add display, window, coordinate, and accessibility-node models.
- [ ] Treat vision/pixel input as a fallback with explicit confidence and
  recovery paths.

**Exit condition:** Dextero can complete a browser workflow safely and can
exercise one native desktop workflow through a replaceable platform adapter.

## Milestone 9 — secure remote control

- [ ] Add cryptographic device pairing and per-device authorization.
- [ ] Add controller presence, session discovery, revocation, and key rotation.
- [ ] Use Serverpod for commands, task streams, approvals, and WebRTC
  signalling.
- [ ] Use WebRTC for low-latency screen, audio, pointer, and keyboard traffic.
- [ ] Support LAN and private-overlay operation first.
- [ ] Evaluate an optional rendezvous/notification/relay service without making
  cloud authority mandatory.
- [ ] Expand the Flutter controller across mobile, desktop, and web as platform
  security constraints allow.

**Exit condition:** a paired controller can securely monitor, steer, approve,
and take over a task without opening an unrestricted remote shell.

## Release engineering

These concerns cut across all milestones:

- [ ] CI on macOS, Windows, and Linux with platform-native builds.
- [ ] Signed and notarized release artifacts where required.
- [ ] Reproducible dependency and native-asset provenance.
- [ ] Crash, cancellation, fuzz, and protocol-compatibility tests.
- [ ] Threat modelling for local execution, remote pairing, extensions, and
  delegated specialists.
- [ ] Stable migration and compatibility policy before a `1.0` release.

## Deliberate non-goals for the MVP

- Bundling or requiring Postgres on each controlled computer
- A central cloud account as a prerequisite for local use
- Video or high-frequency input over Serverpod WebSockets
- Unrestricted desktop control before permissions and auditability
- Bespoke integrations for every service before MCP support
- Destructive Git operations as ordinary agent tools
- Dynamically loading arbitrary Dart packages into an AOT process
- Replacing mature coding agents with a weaker in-house imitation
- Claiming one executable or one automation implementation works everywhere
