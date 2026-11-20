#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.35.1"
FLUTTER_HOME="${HOME}/flutter-sdk"

if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
  curl -sSL -o /tmp/flutter.tar.xz \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  mkdir -p "${FLUTTER_HOME}"
  tar xf /tmp/flutter.tar.xz -C "${HOME}"
  mv "${HOME}/flutter" "${FLUTTER_HOME}"
  rm -f /tmp/flutter.tar.xz
fi

export PATH="${FLUTTER_HOME}/bin:${PATH}"
export PUB_CACHE="${HOME}/.pub-cache"

git config --global --add safe.directory "${FLUTTER_HOME}" || true

flutter --version
flutter config --no-analytics --enable-web
flutter precache --web

cd mobile
flutter pub get
flutter build web --release --no-tree-shake-icons \
  --dart-define=KOLO_API_BASE=/api/v1
