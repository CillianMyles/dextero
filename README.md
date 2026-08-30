# Dart Harness CLI Spike

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

## Run from source

```sh
cd spikes/002-dart-harness-cli
dart run bin/harness.dart --run 'printf dart-harness-ok'
```

Expected output on macOS:

```json
{"platform":"macos","exitCode":0,"stdout":"dart-harness-ok","stderr":""}
```

## Compile and run

Build for the current machine:

```sh
cd spikes/002-dart-harness-cli
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

## Known limits

- Passing a complete command to a shell is deliberate for this experiment but
  is not a safe production API for untrusted input. A real harness should
  accept an executable and argument array separately by default.
- The spike does not implement streaming output, cancellation, timeouts,
  process-tree termination, output limits, environment filtering, or sandboxing.
- It does not test native packages, MCP, browser automation, Windows execution,
  or Linux execution; the Linux artifact was inspected but not run on Linux.
- A standalone Dart executable includes the Dart runtime, not arbitrary native
  libraries or external tools used by the application.
- Windows and macOS releases still need native build runners; current Dart
  cross-compilation targets Linux.

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
[Dart, Flutter and Serverpod as a remote computer-use harness](../../resources/posts/2026-08-30-dart-computer-use-coding-harness.md).
