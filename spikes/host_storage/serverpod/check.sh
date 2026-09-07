#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test --reporter expanded

# Exercise the distributable from a different working directory, without sources
# or a Dart runtime in the bundle. sqlite3's hooks require `dart build cli`.
spike_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/dextero-storage-bundle.XXXXXX")
trap 'rm -rf "$spike_build_dir"' EXIT
dart build cli --output "$spike_build_dir"
cp -R config migrations "$spike_build_dir/bundle/"
STORAGE_SPIKE_EXECUTABLE="$spike_build_dir/bundle/bin/probe" \
STORAGE_SPIKE_BUNDLE="$spike_build_dir/bundle" \
  dart test --reporter expanded
du -sh "$spike_build_dir/bundle"
find "$spike_build_dir/bundle/bin" "$spike_build_dir/bundle/lib" -type f
