# Roadmap

The immediate plan is a storage decision followed by one durable conversation
with working follow-ups. Workspace navigation and a persistent page come next,
subject to what those slices teach us. The later sections describe candidate
outcomes, not a commitment to implement every checklist in sequence.

## Now — choose the host storage path

The code review found an existing core persistence interface, but startup
creates a new in-memory conversation. Serverpod already supplies shared typed
client/server contracts; using core for orchestration does not require placing
the database implementation there.

The repo pins Serverpod 3.4.13. Its documented ORM uses Postgres, while
[Serverpod Next documents host-side SQLite](https://docs.serverpod.dev/next/concepts/server-fundamentals/configuration).
That newer backend does not support persistent session logs, so SQLite plus
Insights is not yet a verified answer to both storage and observability.

- [ ] Spike a conversation and message table using Serverpod's newer SQLite
  backend in isolation. Establish the required release and upgrade cost; prove
  a transactional append, a schema migration, and recovery after restart.
- [ ] Verify host packaging and what diagnostics are available with SQLite.
  Compare the result with SQLite/Drift behind the existing core interface;
  retain Drift as the fallback if the Serverpod path is unsuitable.
- [ ] Recommend one approach, with evidence for ORM/model sharing, migration
  support, runtime dependencies, and observability. Keep authoritative storage
  on the host; do not add client synchronization or require a local Postgres
  service as an incidental part of this slice.

**Checkpoint:** review the spike and choose the storage approach with the user
before a production integration or framework upgrade. Update this plan and
reconcile the SQLite/Drift deployment assumption in VISION.md with that choice.

## Next — one conversation that survives restart and remembers earlier turns

The current activity timeline is not model context: Gemini starts each run
with the new prompt, and the Codex adapter starts a new thread. Persisting only
the visible transcript would leave follow-up questions without earlier context.

- [ ] Implement the selected durable store in server behind core's storage
  interface. Restore the existing conversation on startup, including source
  messages, ordered activity, run state, and provider/model selection.
- [ ] Supply bounded earlier context to both providers. Preserve the source
  needed for continuity separately from display summaries and any provider
  session reference; report context limits until compaction is implemented.
- [ ] Persist accepted messages before starting work and publish events after
  durable append. Reconnect Flutter and CLI/TUI to the restored conversation
  without losing cursor order or mixing provider/model selections.
- [ ] Mark unfinished runs interrupted after restart and invalidate pending
  approvals. A retry needs a fresh approval; uncertain side effects must not
  be replayed automatically.
- [ ] Cover the changed path with core, server, Flutter, and CLI/TUI tests,
  including a network acceptance test that restarts the host between turns.

**Checkpoint:** tell Dextero your preferred training days, restart the host,
and ask a follow-up that uses those days without repeating them. Demonstrate
it through both clients, including recovery from interrupted work. Review that
experience before expanding storage or beginning workspace navigation.

**Outside this first slice:** a session browser, workspace sidebar, general
backup/export UI, semantic search, fact extraction, automatic task resumption,
and remembered grants. Add these when the next exercised workflow needs them;
keep migrations and a documented way to back up and remove local data in scope.

## Then — explore multiple workspaces

A workspace is a persistent place for an ongoing activity, such as Fitness.
It contains conversations and shared records; it is not one endless chat or a
filesystem directory. The first UI may expose one default conversation while
the model supports multiple conversations per workspace.

- [ ] Introduce stable workspace identities, names, ordering, and archive
  state; associate conversations and their records with a workspace.
- [ ] Add workspace creation, renaming, archiving, and switching to the typed
  API, Flutter sidebar, and CLI/TUI.
- [ ] Make provider/model selection and agent context belong to individual
  conversations. Switching workspaces must not mix context, streams, drafts,
  active runs, or pending approvals, or cancel work merely by navigating away.
- [ ] Show which workspace needs attention while allowing users to return to
  its active work. Persist the last selected workspace as a client preference.
- [ ] Keep product workspace identity separate from filesystem execution roots
  and capability grants. Creating a workspace grants no new tool authority;
  cross-workspace context sharing must be deliberate.
- [ ] Test persistence, concurrent conversations, navigation during runs and
  approvals, and context isolation across both clients and the network path.

**Exit condition:** create Fitness and another workspace, converse in both,
switch between them, and restart. Each retains its own conversations and
configuration, with no context or approval leakage between them.

## Then — first persistent workspace page

Prove one useful workspace before building a general page-building platform.
Use Fitness as the first example: a weekly plan, workout log, and progress view.

- [ ] Add a resizable desktop layout with workspace navigation, chat on the
  left, and a persistent page on the right. Use chat/page switching on narrow
  screens; start with an audit of the existing design system.
- [ ] Persist domain records and page configuration independently of the chat
  transcript. The page remains usable without an active model run.
- [ ] Let direct UI actions and agent tools update the same records through
  shared validation, authorization, and typed server operations. Define
  revision/conflict handling so concurrent edits do not silently overwrite.
- [ ] Start with a small supported set of text, list, table, chart, and form
  components. Let users configure them directly or instruct the agent to do
  so; persist configuration changes with provenance and undo.
- [ ] Give the assistant current workspace records as relevant context and
  update the page when records change. Keep cross-workspace sharing explicit.
- [ ] Expose equivalent record inspection and mutations through CLI/TUI;
  visual layout belongs to Flutter.
- [ ] Test chat-to-page and page-to-chat updates, conflicts, undo, workspace
  isolation, and restart persistence across the complete path.

**Exit condition:** ask Dextero to move a planned workout and see the page
update; edit it directly and have the next chat turn use that change. Records
and layout survive restart, and changes can be inspected and undone.

## Later — permissions, approvals, and audit

Extend controls around exercised workflows. Existing one-shot approvals and
local access restrictions remain in force while the product slices above are
built; remote access and broader tool authority depend on stronger controls.

- [ ] Establish stable controller/device identities before remembered grants.
- [ ] Define grants scoped by principal, task, product workspace or execution
  project, resource, operation, constraints, and duration.
- [ ] Offer explicit approve-once, task, project/workspace, and global choices,
  with one-shot approval as the default. Evaluate grants locally with
  deterministic precedence, default-deny behaviour, and an explanation.
- [ ] Classify actions by risk and extend approval policy to consequential
  process, network, and integration actions.
- [ ] Persist grants, decisions, revocations, and structured security audit
  events through the chosen host store, with migrations and recovery tests.
- [ ] Expose grant inspection and immediate revocation in the typed API,
  Flutter, and CLI/TUI. Cover expiry, denial, cancellation, reconnect, restart,
  and revocation; remote controllers must not bypass local policy.
- [ ] Separate the user task timeline from ordered operator diagnostics.
- [ ] Introduce network egress policy and platform sandbox adapters as their
  corresponding capabilities are added.

**Exit condition:** every consequential action is denied, allowed by an
inspectable and revocable grant, or paused for approval with a durable audit
record. Remembered permissions remain attributable after restart.

## Later — richer memory and task continuity

Build on durable conversations and workspace records once real usage shows
what people need to find and carry forward.

- [ ] Add full-text search, then evaluate semantic/vector retrieval over
  messages and artifacts against concrete retrieval cases.
- [ ] Extract preferences, facts, relationships, and outcomes with provenance,
  correction, and explicit workspace/private-data boundaries.
- [ ] Add context-window accounting, token budgets, compaction, and retrieval
  policies that select relevant context without loading the full archive.
- [ ] Add memory browsing, search, correction, retention, export, and deletion
  controls, including removal from derived indexes and summaries.
- [ ] Add queued steering, durable checkpoints, and safe task resumption with
  explicit idempotency and recovery rules for side effects.

**Exit condition:** users can find, correct, and reuse relevant prior work
without unrelated workspace context leaking into a task, and supported tasks
resume without silently repeating consequential actions.

## Future directions — ordered by demonstrated need

These are not prerequisites for the workspace experiments or a fixed delivery
sequence. Each selected capability needs a bounded end-to-end exit condition.

- **Specialist delegation:** scoped tasks, context, capabilities, progress,
  steering, cancellation, artifacts, and structured results. Harden Codex,
  prove a second adapter when needed, and isolate delegated execution roots
  and grants. Support bounded foreground/background work and return results
  to the originating workspace.
- **Local tools:** confined, capped file search; atomic, preflighted patching;
  read-only Git inspection with hooks, pagers, and external diff disabled;
  policy-bound HTTP fetching with SSRF and redirect controls; central argument
  validation; and explicitly approved PTYs. Git mutation, deletion, and shell
  authority need their own policy coverage.
- **Runtime ecosystem and routing:** MCP and a dynamic tool registry;
  versioned adapter manifests, trust, lifecycle, and health; direct streaming
  providers; project instructions, skills, and profiles. Route among permitted
  models using explicit privacy, capability, latency, availability, and cost
  policy. Show provider, selection rationale, shared context, and cost without
  copying the full memory store to providers or letting extensions bypass
  policy.
- **Browser and computer use:** semantic browser actions through an isolated
  profile and CDP, gated submissions, screenshots/artifacts, and replaceable
  native accessibility adapters. Use pixels as a fallback with confidence
  and recovery handling; prove a workflow across ordinary desktop apps.
- **Secure remote control:** cryptographic pairing, per-device authorization,
  presence, discovery, revocation, and key rotation. Start with LAN/private
  overlays; evaluate WebRTC for screen/audio/input and optional relay services
  without transferring local authority to the cloud.
- **Channels and personal-system sync:** trusted messaging into the same
  identity, conversations, approvals, and delivery state; calendar and other
  workspace views synchronized with existing services. Define sender
  verification, conflicts, idempotency, provenance, offline replay, and
  deletion semantics. Prove that a change requested by message appears both
  in Dextero and in the calendar already used on the user's phone.
- **Household profiles:** separate identities, memories, permissions, and
  budgets, with age-appropriate controls and explicit, transparent monitoring.
- **Arbitrary interactive pages:** evaluate generated executable pages only
  when supported components limit useful workflows; define isolation,
  authority, versioning, and recovery before enabling them.
- **Client offline support:** local caches and synchronization where needed,
  with explicit conflict and deletion handling and clear host authority.

## Foundation — completed

- [x] Provider-neutral model interface and bounded model → tool → model loop.
- [x] Workspace-confined file reading, deterministic listing, and exact
  single-match editing.
- [x] Direct argv-based commands and explicit shell execution with timeouts,
  environment filtering, output caps, and bounded background execution.
- [x] Codex app-server specialist adapter and Gemini function-calling adapter.
- [x] Deterministic demos, focused tool/protocol tests, and an AOT spike.
- [x] Flutter controller and terminal clients, including a Nocterm TUI spike.

## Milestones 1–2 — chat and typed control backbone, completed

- [x] Append-only user, assistant, tool, lifecycle, and error history with
  stable conversation, entry, run, tool-call, and correlation IDs.
- [x] Versioned event families, readable tool summaries, streaming model
  output, incremental tool activity, and a stable JSONL interface.
- [x] Cancellation propagation and child-process-tree cleanup.
- [x] Database-free Serverpod host with generated submit, history,
  cursor-stream, approval, and cancellation contracts.
- [x] Explicit one-shot file-edit approvals in Flutter and terminal clients.
- [x] Bootstrap authentication, local development defaults, and explicit
  network binding.
- [x] Provider-qualified Gemini/Codex model selection before the first
  message through Flutter and terminal clients.
- [x] Layered tests and network acceptance coverage.

**Established outcome:** Flutter and terminal clients can observe the same
ordered activity, approve a gated edit, cancel work, and receive its result.
Durable history and model context across submissions remain to be implemented.
See [README.md](README.md) for current behaviour and security limitations.

## Milestone 11 — voice and visual surfaces

Give the continuous Dextero identity an embodied mobile interface before
considering dedicated hardware.

- [x] Accept push-to-talk audio, record final transcripts with voice modality
  and transcription-engine provenance, and return spoken replies.
- [ ] Extend entries and streams for partial transcripts, streamed speech
  output, and interruption.
- [x] Add a push-to-talk Flutter mobile interaction with clear listening,
  thinking, tool-use, approval, speaking, and failure states.
- [x] Keep the spoken interaction in the same conversation, memory, task,
  approval, and audit model as text rather than creating a voice-only session.
- [ ] Add explicitly initiated image/camera context with visible capture state,
  scoped authority, retention controls, and inspectable provenance. The
  capture boundary is documented in README.md.
- [ ] Evaluate on-device and host-side speech recognition and synthesis against
  privacy, latency, quality, battery, and offline-operation requirements. The
  prototype uses host-side whisper.cpp and macOS `say`; Linux and Windows hosts
  have no spoken replies yet.
- [ ] Define a small paired-surface protocol for microphone, speaker, display,
  buttons, LEDs, and presence so a later room endpoint or wearable can reuse
  the mobile interaction model. The voice subset is documented in README.md.
- [ ] Prototype specialized hardware only after repeated phone use demonstrates
  what the dedicated device must improve.

**Exit condition:** a paired phone can speak into an existing conversation,
see and hear a streamed response, interrupt it, approve a gated action, and
inspect the resulting transcript and task state from another Dextero surface.

## Release engineering

These concerns cut across milestones:

- [ ] CI on macOS, Windows, and Linux with platform-native builds.
- [ ] Signed and notarized release artifacts where required.
- [ ] Reproducible dependency and native-asset provenance.
- [ ] Crash, cancellation, fuzz, and protocol-compatibility tests.
- [ ] Threat modelling for local execution, remote pairing, extensions, and
  delegated specialists.
- [ ] Stable migration and compatibility policy before a `1.0` release.

## Deliberate non-goals for the next product slices

- Requiring a cloud account or service for local ownership and execution.
- Requiring users to operate Postgres merely to save conversations.
- Full semantic memory, automatic task resumption, or arbitrary generated
  applications before durable conversations and a useful workspace page.
- Treating built-in views as isolated replacements for existing services.
- Fragmenting identity and history across messaging channels.
- Unrestricted desktop control before permissions and auditability.
- Video or high-frequency input over Serverpod WebSockets.
- Bespoke integrations for every service before evaluating MCP.
- Replacing mature coding agents or dynamically loading arbitrary Dart
  packages into an AOT process.
- Claiming one executable or automation implementation works everywhere.

## Parking lot — revisit only if it proves useful

These are not milestone commitments:

- Credential redaction, if comparable agent tools prove a reliable approach
  that does not obscure diagnostics.
- Coalescing or lifetime caps for retained activity events.
