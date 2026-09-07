# Roadmap

Milestones are directional, not release-date promises. The next priorities are
durable conversations, multiple workspaces, and a useful persistent workspace
page. Broader permissions and memory follow the needs of those workflows;
additional authority still requires the corresponding controls.

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
Durable history and model context across submissions are the next milestone.
See [README.md](README.md) for current behaviour and security limitations.

## Milestone 3 — durable conversations and context

Return to a conversation after restarting Dextero and continue it meaningfully.

- [ ] Run a bounded storage spike comparing Serverpod's newer SQLite support
  with SQLite/Drift behind the existing persistence interface. Verify the
  required Serverpod version, host-side ORM support, migrations, transactions,
  packaging, restart recovery, and diagnostic limitations before choosing.
  This reopens the SQLite/Drift choice recorded in VISION.md; reconcile that
  deployment guidance when the spike concludes.
- [ ] Keep authoritative data on the computer running Dextero. Client caches
  and offline synchronization are separate, later work. Require an explicit
  deployment decision before adding a local Postgres service.
- [ ] Keep conversation rules, context assembly, and storage interfaces in
  core; implement durable stores, migrations, and host lifecycle in server,
  with generated contracts shared by Flutter and CLI/TUI.
- [ ] Persist conversations, messages, run state, activity events, provider
  and model selection, and provenance. Preserve source messages and structured
  context needed by the model separately from bounded display summaries.
- [ ] Supply earlier conversation context on follow-up submissions for both
  Gemini and Codex. Define bounded context assembly and persist any provider
  session references needed for continuity without making them the only copy
  of user history. Report context limits explicitly until compaction exists.
- [ ] Restore conversations on startup and expose creation, listing,
  reopening, and paginated history through the typed API, Flutter, and CLI/TUI.
- [ ] Commit accepted messages before starting work and publish history
  events only after durable append. Preserve cursor order across reconnects.
- [ ] Mark unfinished runs interrupted after restart; invalidate pending
  approvals and require a fresh decision before retrying an action. Do not
  automatically replay side effects whose outcome is uncertain.
- [ ] Add migrations, backup/restore, export, and explicit deletion paths.
- [ ] Correlate host diagnostics with conversation and run IDs. Evaluate
  Serverpod Insights as an operator view; keep durable task history independent
  of diagnostic log retention and database-backend limitations.
- [ ] Test context continuity, durable appends, cursor recovery, migrations,
  and interrupted work through core, server, Flutter, CLI/TUI, and a host
  restart acceptance test.

**Exit condition:** restart the host, reopen the same conversation from either
client, and ask a follow-up that correctly uses earlier messages. History and
model selection survive; interrupted work and expired approvals are explicit.
Semantic search and automatic task resumption are not required for this exit.

## Milestone 4 — multiple workspaces

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

## Milestone 5 — first persistent workspace page

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

## Next — permissions, approvals, and audit

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

## Next — richer memory and task continuity

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

These are not prerequisites for the workspace milestones or a fixed delivery
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
