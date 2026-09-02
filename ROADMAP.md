# Roadmap

Milestones are directional, not release-date promises.

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
- [x] Initial macOS Flutter app and terminal-client control-plane spike

## Milestone 1 — chat and typed control backbone

Make every task observable and controllable before adding more authority.

- [x] Establish append-only user, assistant, tool, lifecycle, and error history
  with stable conversation, entry, run, tool-call, and correlation IDs.
- [x] Adapt real Codex activity into bounded safe summaries without retaining
  raw tool arguments or results.
- [x] Expose typed submit, history, and cursor-stream operations through the
  Flutter and terminal chats.
- [x] Test the path at every layer, including a terminal-to-server network
  acceptance test.
- [x] Define versioned events for task, model, tool, approval, artifact, usage,
  warning, and error lifecycles.
- [x] Support streaming model output and incremental tool output.
- [x] Add cancellation propagation and reliable child-process-tree cleanup.
- [x] Add timeouts, output limits, environment filtering, and bounded background
  execution to all process tools.
- [x] Provide a stable JSONL interface for automation and tests.

History is currently in memory behind a persistence interface and is lost when
the server restarts.

**Exit condition:** a task can be watched and cancelled through one typed event
contract without relying on terminal scraping.

## Milestone 2 — local Serverpod vertical slice

Prove the product architecture with the smallest useful remote controller.

- [x] Add a database-free Serverpod Mini service with a generated conversation
  contract for submitting, inspecting, and streaming history.
- [x] Expose an endpoint to cancel work.
- [ ] Expose endpoints to approve work.
- [x] Use that contract from the Flutter and terminal chats.
- [ ] Add one understandable approval interaction to the app.
- [x] Start with in-memory task state and document the restart limitation.
- [ ] Add local-only development defaults and explicit network binding.

Current security boundary: control endpoints require a bootstrap bearer token.
Serverpod 3.4.13 still binds its listener to all IPv6 interfaces, so the port
must remain firewalled until explicit binding or device pairing is available.

**Exit condition:** a Flutter client can continue the local conversation,
observe typed activity, approve a gated action, cancel it, and receive the
result from a local Dextero host.

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

## Milestone 4 — durable memory and sessions

- [ ] Persist tasks, events, approvals, and checkpoints with SQLite/Drift.
- [ ] Persist conversations, messages, artifacts, and their provenance as a
  durable source record.
- [ ] Add full-text search and semantic/vector search over messages and
  artifacts.
- [ ] Extract structured preferences, facts, relationships, and outcomes with
  correction and provenance support.
- [ ] Build retrieval and context-compaction policies that use relevant memory
  without treating the entire archive as a prompt.
- [ ] Resume or fail tasks predictably after a process restart.
- [ ] Add context-window accounting, token budgets, and compaction.
- [ ] Support queued steering messages and reconnecting event subscribers.
- [ ] Add in-product memory browsing, search, correction, export, retention,
  and deletion controls.
- [ ] Add schema migrations and recovery tests.

**Exit condition:** a host restart or controller disconnect does not erase task
history, approvals, conversation continuity, or the ability to find and
understand what happened later.

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

## Milestone 7 — AI gateway and runtime ecosystem

- [x] Add a Gemini function-calling adapter through the provider-neutral agent
  loop with environment-controlled credentials and model selection.
- [ ] Add an MCP client and dynamic tool registry.
- [ ] Define manifests, trust levels, lifecycle, health, and version negotiation
  for runtime adapters.
- [ ] Add direct streaming model adapters while retaining provider-neutral
  kernel contracts.
- [ ] Route tasks across local models, cloud providers, and specialists using
  explicit capability, privacy, latency, availability, and cost policy.
- [ ] Show which provider handled a task, why it was selected, what context was
  shared, and its measured or estimated cost.
- [ ] Keep provider credentials, consent, and routing preferences under the
  user's control without copying the full memory store to every provider.
- [ ] Support project instructions, skills, and configuration profiles.
- [ ] Define separate household identities, memories, permissions, budgets,
  age-appropriate controls, and transparent family usage summaries.
- [ ] Add hooks and artifact storage without allowing extensions to bypass
  policy.

**Exit condition:** Dextero can choose among permitted local and cloud models
for a task without fragmenting the user's context, while useful capabilities
can be installed or connected without recompiling Dextero or granting them
ambient authority.

## Milestone 8 — browser and computer use

- [ ] Add an isolated browser profile and Chrome DevTools Protocol adapter.
- [ ] Prefer DOM/semantic actions and gate consequential submissions.
- [ ] Add screenshots and artifacts to the typed event stream.
- [ ] Define stable native adapter interfaces for macOS accessibility, Windows
  UI Automation, and Linux accessibility APIs.
- [ ] Add display, window, coordinate, and accessibility-node models.
- [ ] Treat vision/pixel input as a fallback with explicit confidence and
  recovery paths.
- [ ] Prove an end-to-end workflow that combines multiple ordinary desktop
  applications rather than only developer tools.

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

## Milestone 10 — channels and personal-system sync

Make Dextero one continuous product that can be reached from the places people
already use.

- [ ] Define a channel-neutral conversation and identity model shared by the
  app and messaging adapters.
- [ ] Add one trusted text-messaging adapter with pairing, sender verification,
  approvals, and delivery-state handling.
- [ ] Route channel messages into the same conversations, tasks, memory, and
  policy engine as the app.
- [ ] Build a first-class calendar view inside Dextero.
- [ ] Add two-way sync with at least one widely used calendar provider so
  Dextero-created events appear on the user's phone and external changes flow
  back.
- [ ] Define conflict resolution, idempotency, provenance, offline replay, and
  deletion semantics for synchronized records.
- [ ] Generalize the sync adapter contract for tasks, contacts, files, and
  other personal systems without hiding third-party failures.

**Exit condition:** a user can ask Dextero by text to create or change an
event, see the same conversation and result in the Dextero app, and find the
event in the calendar already used on their phone.

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
- Separate agent identities and fragmented histories for each messaging
  channel
- Treating Dextero's built-in calendar or task views as isolated replacements
  for the user's existing services
- Video or high-frequency input over Serverpod WebSockets
- Unrestricted desktop control before permissions and auditability
- Bespoke integrations for every service before MCP support
- Destructive Git operations as ordinary agent tools
- Dynamically loading arbitrary Dart packages into an AOT process
- Replacing mature coding agents with a weaker in-house imitation
- Claiming one executable or one automation implementation works everywhere
