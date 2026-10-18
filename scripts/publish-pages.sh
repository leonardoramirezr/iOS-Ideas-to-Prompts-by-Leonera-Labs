#!/usr/bin/env bash
# Publica la carpeta de un build en la rama gh-pages.
#
# Uso: scripts/publish-pages.sh <carpeta-del-build>
#   La carpeta se llama como la etiqueta y contiene el IPA, manifest.plist, index.html,
#   build.json y los iconos (ver scripts/pages.py build-folder).
#
# Variables: GITHUB_REPOSITORY, GITHUB_TOKEN, PAGES_BASE_URL, APP_NAME.
#   PAGES_REMOTE permite usar otro remoto (p. ej. para pruebas locales).
#
# gh-pages se reescribe como un único commit huérfano para que los IPA no se acumulen
# en el historial. Solo se conservan las carpetas con build.json (la rama pudo crearse
# desde el código), todas las versiones de main y los últimos 20 builds de ramas.
set -euo pipefail

build_dir="${1:?Uso: publish-pages.sh <carpeta-del-build>}"
build_dir="$(cd "$build_dir" && pwd)"
tag="$(basename "$build_dir")"
script_dir="$(cd "$(dirname "$0")" && pwd)"
remote="${PAGES_REMOTE:-https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git}"
title="${APP_NAME:-App}"

[ -f "$build_dir/build.json" ] || { echo "::error::$build_dir no tiene build.json"; exit 1; }

for attempt in 1 2 3 4 5 6; do
  work="$(mktemp -d)"
  git init -q "$work/repo"
  git -C "$work/repo" symbolic-ref HEAD refs/heads/gh-pages
  git -C "$work/repo" remote add origin "$remote"

  # Estado actual de gh-pages (si existe). Su SHA se usa para --force-with-lease.
  expected=""
  mkdir -p "$work/old"
  if git -C "$work/repo" fetch -q --depth 1 origin refs/heads/gh-pages 2>/dev/null; then
    expected="$(git -C "$work/repo" rev-parse FETCH_HEAD)"
    git -C "$work/repo" archive FETCH_HEAD | tar -x -C "$work/old"
  fi

  # Conserva solo las carpetas de builds (las que tienen build.json).
  for dir in "$work"/old/*/; do
    [ -f "$dir/build.json" ] || continue
    name="$(basename "$dir")"
    [ "$name" = "$tag" ] && continue
    cp -R "$dir" "$work/repo/$name"
  done
  cp -R "$build_dir" "$work/repo/$tag"

  python3 "$script_dir/pages.py" site --root "$work/repo" --base-url "${PAGES_BASE_URL:-}" \
    --title "$title" --keep-branch-builds 20
  touch "$work/repo/.nojekyll"

  git -C "$work/repo" add -A --force
  git -C "$work/repo" -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -q -m "Publicar $tag"

  if git -C "$work/repo" push -q --force-with-lease="refs/heads/gh-pages:${expected}" origin HEAD:refs/heads/gh-pages; then
    echo "gh-pages publicado con $tag (intento $attempt)."
    rm -rf "$work"
    exit 0
  fi

  rm -rf "$work"
  wait_seconds=$((attempt * 5))
  echo "Otro build publicó a la vez; reintentando en ${wait_seconds}s…"
  sleep "$wait_seconds"
done

echo "::error::No se pudo publicar gh-pages tras varios intentos."
exit 1
