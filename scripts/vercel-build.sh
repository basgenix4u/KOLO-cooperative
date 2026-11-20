#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.35.1"
FLUTTER_HOME="${PWD}/.flutter-sdk"
ARCHIVE="${PWD}/.flutter-sdk.tar.xz"

if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
  echo "Fetching Flutter ${FLUTTER_VERSION}"
  curl -fL --retry 5 --retry-delay 5 -o "${ARCHIVE}" \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  echo "Archive bytes: $(wc -c < "${ARCHIVE}")"
  mkdir -p "${FLUTTER_HOME}"
  tar xf "${ARCHIVE}" -C "${FLUTTER_HOME}" --strip-components=1
  rm -f "${ARCHIVE}"
fi

if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
  echo "Flutter did not unpack; aborting"
  exit 1
fi

export PATH="${FLUTTER_HOME}/bin:${PATH}"
export PUB_CACHE="${PWD}/.pub-cache"

git config --global --add safe.directory "${FLUTTER_HOME}" || true

flutter config --no-analytics --enable-web
rm -rf mobile/build
cd mobile
flutter pub get
flutter build web --release --no-tree-shake-icons --dart-define=KOLO_API_BASE=https://kolo-api-m8zw.onrender.com/api/v1
