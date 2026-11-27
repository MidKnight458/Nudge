#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -d "$HOME/flutter/bin" ]] && [[ ":$PATH:" != *":$HOME/flutter/bin:"* ]]; then
  export PATH="$HOME/flutter/bin:$PATH"
fi

if [[ -z "${ANDROID_HOME:-}" ]] && [[ -d "$HOME/Android/Sdk" ]]; then
  export ANDROID_HOME="$HOME/Android/Sdk"
fi

if [[ $# -gt 1 ]]; then
  echo "Uso: $0 [vX.Y.Z]" >&2
  exit 1
fi

if [[ $# -eq 1 ]]; then
  VERSION_TAG="$1"
else
  PUBSPEC_VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)"
  if [[ -z "$PUBSPEC_VERSION" ]]; then
    echo "Error: no se pudo leer la versión desde pubspec.yaml." >&2
    exit 1
  fi
  VERSION_TAG="v${PUBSPEC_VERSION}"
fi

if [[ ! "$VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: el tag '$VERSION_TAG' debe cumplir el formato vX.Y.Z (ej. v1.0.1)." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: hay cambios sin commitear en el repositorio. Haz commit antes de publicar." >&2
  git status -sb >&2
  exit 1
fi

if [[ ! -f "android/app/google-services.json" ]]; then
  echo "Error: falta android/app/google-services.json para compilar con Firebase." >&2
  echo "Descárgalo desde Firebase Console y colócalo en android/app/google-services.json antes de publicar." >&2
  exit 1
fi

echo "==> Verificando dependencias, formato, análisis y pruebas..."
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

echo "==> Compilando APK de release localmente..."
flutter build apk --release

mkdir -p build/release-artifacts
APK_SRC="build/app/outputs/flutter-apk/app-release.apk"
APK_OUT="build/release-artifacts/nudge-${VERSION_TAG}.apk"
cp "$APK_SRC" "$APK_OUT"

if ! git rev-parse -q --verify "refs/tags/${VERSION_TAG}" >/dev/null; then
  git tag -a "$VERSION_TAG" -m "Release ${VERSION_TAG} — Nudge"
fi

if ! git ls-remote --tags origin "refs/tags/${VERSION_TAG}" | grep -q "refs/tags/${VERSION_TAG}"; then
  git push origin "$VERSION_TAG"
fi

if gh release view "$VERSION_TAG" >/dev/null 2>&1; then
  echo "==> Actualizando APK en el release existente ${VERSION_TAG}..."
  gh release upload "$VERSION_TAG" "$APK_OUT" --clobber
else
  echo "==> Creando release ${VERSION_TAG} en GitHub..."
  gh release create "$VERSION_TAG" "$APK_OUT" \
    --title "Nudge ${VERSION_TAG}" \
    --generate-notes
fi

echo "==> Release ${VERSION_TAG} publicado con éxito:"
gh release view "$VERSION_TAG"
