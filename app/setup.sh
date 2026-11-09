#!/usr/bin/env bash
# One-time: generate the Android + web platform folders and add the
# permissions Fretline needs. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

had_widget_test=$([ -e test/widget_test.dart ] && echo 1 || true)
flutter create . --platforms=android,web --org app.fretline --project-name fretline >/dev/null
# flutter create adds a counter-app test that doesn't apply here
[ -n "$had_widget_test" ] || rm -f test/widget_test.dart
flutter pub get

M=android/app/src/main/AndroidManifest.xml
add_perm() {
  grep -q "$1" "$M" || sed -i "s#<application#<uses-permission android:name=\"$1\"/>\n    <application#" "$M"
}
add_perm android.permission.INTERNET        # pull songs from the PC
add_perm android.permission.CAMERA          # scan the pairing QR code
add_perm android.permission.RECORD_AUDIO    # mic scoring (M5)
# the PC serves plain http on the LAN
grep -q usesCleartextTraffic "$M" || sed -i 's#<application#<application android:usesCleartextTraffic="true"#' "$M"

# Flutter's template gives Gradle 8 GB + 4 GB metaspace, which froze a 14 GB machine.
G=android/gradle.properties
sed -i 's#^org.gradle.jvmargs=.*#org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError#' "$G"
grep -q kotlin.daemon.jvmargs "$G" || printf 'kotlin.daemon.jvmargs=-Xmx1g\norg.gradle.workers.max=4\norg.gradle.parallel=false\n' >> "$G"

echo "Done. Run on a tablet:   flutter run"
echo "Build the iOS PWA:       flutter build web --base-href /app/   (served by the backend at /app/)"
