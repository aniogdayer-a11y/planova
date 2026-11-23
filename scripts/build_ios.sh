#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS builds require macOS and Xcode." >&2
  exit 1
fi
flutter pub get
flutter build ios --debug --no-codesign --dart-define-from-file=config/client.json
echo "Open ios/Runner.xcworkspace in Xcode to select your signing team and run on iPhone or iPad."
echo "For distribution, configure an HTTPS NATIVE_API_URL and use flutter build ipa with the same config file."
