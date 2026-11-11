#!/usr/bin/env bash
set -euo pipefail

# This repository contains the custom Android entry point and share intents,
# but may not contain the generated Gradle wrapper/project files.
if [[ -x android/gradlew ]] && {
  [[ -f android/app/build.gradle ]] || [[ -f android/app/build.gradle.kts ]]
}; then
  echo "Android Gradle project is already present."
  exit 0
fi

manifest="android/app/src/main/AndroidManifest.xml"
activity="android/app/src/main/kotlin/com/xpprinter/xp_p323b/MainActivity.kt"
backup_dir="$(mktemp -d)"
trap 'rm -rf "$backup_dir"' EXIT

mkdir -p "$backup_dir"
if [[ -f "$manifest" ]]; then
  cp "$manifest" "$backup_dir/AndroidManifest.xml"
fi
if [[ -f "$activity" ]]; then
  cp "$activity" "$backup_dir/MainActivity.kt"
fi

flutter create \
  --platforms=android \
  --project-name xp_p323b \
  --org com.xpprinter \
  --no-pub \
  .

# Restore the printer implementation and Android share intent filters.
if [[ -f "$backup_dir/AndroidManifest.xml" ]]; then
  cp "$backup_dir/AndroidManifest.xml" "$manifest"
fi
if [[ -f "$backup_dir/MainActivity.kt" ]]; then
  mkdir -p "$(dirname "$activity")"
  cp "$backup_dir/MainActivity.kt" "$activity"
fi

test -x android/gradlew
test -f android/app/build.gradle -o -f android/app/build.gradle.kts
echo "Android Gradle scaffold is ready."
