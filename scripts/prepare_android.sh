#!/usr/bin/env bash
set -euo pipefail

install_launcher_icon() {
  local res="android/app/src/main/res"
  local manifest="android/app/src/main/AndroidManifest.xml"
  mkdir -p "$res/drawable"
  cat > "$res/drawable/ic_launcher.xml" <<'ICON'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="512"
    android:viewportHeight="512">
    <path android:fillColor="#0756c9" android:pathData="M112,0h288a112,112 0,0 1,112 112v288a112,112 0,0 1,-112 112h-288a112,112 0,0 1,-112 -112v-288a112,112 0,0 1,112 -112z"/>
    <path android:fillColor="#f8fbff" android:pathData="M48,24h416a68,68 0,0 1,68 68v328a68,68 0,0 1,-68 68h-416a68,68 0,0 1,-68 -68v-328a68,68 0,0 1,68 -68z"/>
    <path android:fillColor="#ffffff" android:strokeColor="#9aa9bd" android:strokeWidth="8" android:pathData="M184,54h144l34,42v174H150V96z"/>
    <path android:strokeColor="#29364a" android:strokeWidth="13" android:strokeLineCap="round" android:pathData="M191,105h132M181,132h121M181,159h83"/>
    <path android:strokeColor="#202b3a" android:strokeWidth="7" android:pathData="M180,188v54m14,-54v54m14,-54v54m14,-54v54m14,-54v54m14,-54v54m14,-54v54m14,-54v54m14,-54v54"/>
    <path android:fillColor="#202633" android:strokeColor="#0c1422" android:strokeWidth="10" android:pathData="M112,250h288a30,30 0,0 1,30 30v116a40,40 0,0 1,-40 40H122a40,40 0,0 1,-40 -40V280a30,30 0,0 1,30 -30z"/>
    <path android:fillColor="#303b4e" android:pathData="M138,274h236v55H138z"/>
    <path android:fillColor="#00c7ff" android:pathData="M169,359a12,12 0,1 1,-24 0a12,12 0,1 1,24 0"/>
    <path android:fillColor="#111a29" android:strokeColor="#8392a8" android:strokeWidth="5" android:pathData="M278,336h42a15,15 0,0 1,15 15v24a15,15 0,0 1,-15 15h-42a15,15 0,0 1,-15 -15v-24a15,15 0,0 1,15 -15z"/>
    <path android:strokeColor="#ffffff" android:strokeWidth="7" android:strokeLineCap="round" android:pathData="M299,347v20m-13,-13a18,18 0,1 0,26 0"/>
    <path android:strokeColor="#1675ed" android:strokeWidth="13" android:strokeLineCap="round" android:pathData="M68,192c22,-24 48,-36 77,-37"/>
    <path android:fillColor="#1675ed" android:pathData="M89,191a13,13 0,1 1,-26 0a13,13 0,1 1,26 0"/>
    <path android:strokeColor="#e01e2b" android:strokeWidth="14" android:strokeLineCap="round" android:pathData="M70,438h372"/>
    <path android:strokeColor="#0756c9" android:strokeWidth="13" android:strokeLineCap="round" android:pathData="M110,462h292"/>
</vector>
ICON
  if [[ -f "$manifest" ]]; then
    sed -i 's|android:icon="@mipmap/ic_launcher"|android:icon="@drawable/ic_launcher"|' "$manifest"
    sed -i 's|android:roundIcon="@mipmap/ic_launcher_round"||' "$manifest"
  fi
}

# If the Android scaffold already exists, still ensure our app icon is installed.
if [[ -x android/gradlew ]] && {
  [[ -f android/app/build.gradle ]] || [[ -f android/app/build.gradle.kts ]]
}; then
  install_launcher_icon
  echo "Android Gradle project and XP-P323B launcher icon are ready."
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

install_launcher_icon

test -x android/gradlew
test -f android/app/build.gradle -o -f android/app/build.gradle.kts
test -f android/app/src/main/res/drawable/ic_launcher.xml
echo "Android Gradle scaffold and XP-P323B launcher icon are ready."
