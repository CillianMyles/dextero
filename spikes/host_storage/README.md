# Host storage spike

## Recommendation for the roadmap checkpoint

Use **Serverpod's host-side SQLite ORM** for the next durable-conversation slice,
subject to reviewing the Serverpod 4 prerelease dependency and accepting separate
host diagnostics. Keep **Drift behind `ChatHistoryStore`** as the fallback if a
stable-only release is needed before Serverpod 4 is stable. Neither option needs
Postgres or client synchronization. This is a recommendation, not an approved
framework upgrade: the application still pins Serverpod 3.4.13 and uses memory.

The experiment demonstrates the useful ORM, migration, and native packaging
path. SQLite does **not** provide Serverpod's persistent session/query log
history; choosing it does not also solve durable observability.

## Reproduce

From the repository root, with Dart 3.13.2 and Bash:

```sh
make check-storage-spike
```

This resolves the isolated lockfile, formats/checks sources, analyzes, runs the
three tests, builds a native CLI bundle, relocates it with `config/` and
`migrations/`, and repeats the tests against that executable. No running database,
credentials, global Serverpod CLI, or app dependency upgrade is required. Tests
use disposable database paths; `check.sh` removes its temporary bundle.

For an inspectable database, run from `spikes/host_storage/serverpod`:

```sh
dart pub get --enforce-lockfile
dart run bin/probe.dart seed-v1 /tmp/dextero-example.db
dart run bin/probe.dart inspect /tmp/dextero-example.db
dart run bin/probe.dart append /tmp/dextero-example.db
dart run bin/probe.dart inspect /tmp/dextero-example.db
```

`seed-v1` refuses an existing file. The probe prints `RESULT` JSON after each
operation. To regenerate the current server/client ORM and protocol, use
`dart run serverpod_cli:serverpod_cli generate`; format afterward with
`dart format .`. The generator lives in this package's dev dependencies and
does not replace the application's global 3.4.13 generator. Both historical
migrations and their schema snapshots are committed; do not recreate them.

## Observed evidence — 2026-09-07

Local environment: macOS arm64, Dart 3.13.2, Flutter 3.47.2. The isolated package
pins Serverpod, client, and generator to **4.0.0-rc.2**, SQLite bindings to 3.5.2,
and all transitive dependencies in its own lockfile.

| Experiment | Result |
| --- | --- |
| Generated models | `Conversation` and `Message` produce typed server ORM repositories and matching client serialization; the client round-trip test passes. The client has no database or sync configuration. |
| Atomic append | One transaction inserts a message and increments the conversation's next cursor. An injected exception after both writes rolls both back. |
| Migration | Generated v1 SQL seeds a real file with a training-days message. Host startup applies generated v2, rebuilding the message table to add `source` with a `user` default. Content, IDs, ordering, unique index, and foreign key remain usable. |
| Constraints and concurrency | Duplicate conversation/sequence and orphan messages are rejected with typed exceptions. Twelve concurrent appends through one host allocate consecutive cursors without gaps. This is not a multi-host contention or throughput benchmark. |
| Restart and crash | Separate processes read committed messages after restart. Killing the host with SIGKILL after both uncommitted writes preserves earlier messages, discards the interrupted append, and lets the next append reuse the uncommitted cursor. This does not simulate power loss. |
| Diagnostics | SQLite startup warns when persistent logs are requested. JSON console records contain session identifiers, duration, query count, and explicit application messages/warnings. The persistent session table remains empty across processes. |
| Packaging | `dart build cli` emits a native executable plus SQLite and connection-pool libraries. `dart compile exe` rejects those packages' build hooks. Ship the bundle and migration/config assets; do not promise a lone executable. |

The v1 seed uses the generated SQL directly because today's generated model
already contains the v2 field. Subsequent migration and all regular reads and
writes use the actual Serverpod host and ORM. The spike is not a production
`ChatHistoryStore` adapter and does not claim restored provider context,
interrupted-run handling, client reconnection, or durable approvals.

## Release and upgrade cost

The [published package versions](https://pub.dev/packages/serverpod/versions)
still list 3.4.13 as stable and 4.0.0-rc.2 as prerelease. The
[4.0 changelog](https://pub.dev/packages/serverpod/versions/4.0.0-rc.2/changelog)
describes the SQLite dialect, extracted database library, new exception
hierarchies, removed deprecated APIs, mandatory `.spy.yaml` models, and minimum
Dart 3.12.2 / Flutter 3.44.4. **4.0.0-rc.2 is the tested release requirement**;
the first historical beta containing host SQLite was not bisected.

A disposable copy of baseline `d3535d9105e69a2688d0537d361b0329129fda2a`
was upgraded by changing `serverpod`, `serverpod_client`, and `serverpod_test`
to 4.0.0-rc.2 and adding that version of `serverpod_cli` as a dev dependency.
`dart pub get`, `dart run serverpod_cli:serverpod_cli generate`, `dart analyze`,
and `make check` all passed. No handwritten application changes were needed for
this rehearsal; the existing models already use `.spy.yaml`. Production would
still need coordinated package/generator pins, regenerated contracts/test tools,
SDK minimum updates, native bundling, and the storage integration itself.
This rehearsal verifies existing behavior, not the next durable conversation.

## Comparison with Drift

Drift is evaluated from its current 2.34.4 package metadata and official
documentation; no Drift adapter or equivalent runtime benchmark is claimed.

| Concern | Serverpod 4 SQLite (executed) | Drift behind core's interface (documented alternative) |
| --- | --- | --- |
| Models and ORM | One `.spy.yaml` definition generates ORM and wire models. Mapping to core's domain types is still required. | Drift generates typed tables/queries; keep Serverpod's existing wire contracts and explicitly map Drift rows to core types. Adds a second generator/schema vocabulary. |
| Migrations | Generated SQLite SQL and snapshots; tested a table rebuild with existing data. Assets accompany the host. | `schemaVersion`, generated step scaffolds and schema tests; migration callbacks are implemented and tested by the application. See [Drift migrations](https://drift.simonbinder.eu/migrations/). |
| Transactions | Tested rollback and cursor allocation in one host. | Drift provides [atomic transactions](https://drift.simonbinder.eu/dart_api/transactions/); the same append/cursor and crash acceptance tests would be required for the adapter. |
| Runtime | SQLite through `sqlite_async`, `sqlite3`, and a native connection pool. The dependency graph also contains Postgres support, but this probe launches no Postgres service. | [Native Drift](https://drift.simonbinder.eu/platforms/vm/) uses `sqlite3`, with background-isolate support. Native assets remain a packaging concern; no database service is needed. |
| Compatibility | Requires the Serverpod 4 prerelease and regenerated code; existing checks passed in isolation. | Retains Serverpod 3.4.13. Drift 2.34.4 requires Dart >=3.10 and uses sqlite3 ^3.4, compatible with the repository's declared Dart floor. Dependency resolution for a production adapter remains to be tested. |
| Observability | Console session data is available; [persistent session logs are unsupported on SQLite](https://docs.serverpod.dev/next/concepts/server-fundamentals/configuration). Full historical Insights diagnostics were not demonstrated. | Query logging and application diagnostics must be integrated separately; a Drift database does not enable Serverpod Insights persistence. |

For either implementation, put the adapter in `packages/server`, preserving
`packages/core`'s `ChatHistoryStore` seam. Store all canonical entry metadata,
allocate the cursor and insert atomically, and publish `watch` events only after
commit. Restore the stable conversation explicitly; the current interface has
no enumeration/default-conversation lookup. Preserve model-input source records
separately from display summaries. Those are next-slice requirements, not a reason
to move ORM dependencies into core or put storage in the clients.

## Packaging and operational limits

The macOS build contains `bin/probe`, `lib/libsqlite3.dylib`, and
`lib/libsqlite3_connection_pool.dylib`; Linux uses its platform's native assets.
The relocated-bundle test is also configured in CI for Linux and macOS. Windows,
signing/notarization, mobile-host deployment, and release installers have not
been validated by this spike.

Keep writable data outside the application bundle. For this experiment, stop
all probe processes before copying the database and any existing `-wal`/`-shm`
sidecars together as a backup, or removing them to reset it. Do not copy a live
SQLite file alone. Production needs a tested backup/restore and deletion path,
and separately retained/rotated diagnostic output. Console JSON is useful input
for that work, not durable retention by itself.
