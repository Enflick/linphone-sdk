#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
BUNDLE="${1:-}"

die() {
  printf '[submodule-bundle] ERROR: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 1 ] || die "usage: scripts/restore-submodule-source-bundle.sh BUNDLE"
[ -f "$BUNDLE" ] || die "bundle not found: ${BUNDLE}"

while IFS= read -r entry; do
  normalized="${entry#./}"
  case "$normalized" in
    /*|../*|*/../*|*/..)
      die "archive contains unsafe path: ${entry}"
      ;;
  esac
done < <(tar -tzf "$BUNDLE")

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
tar -xzf "$BUNDLE" -C "$scratch"

manifest="${scratch}/.linphone-submodules.manifest"
[ -s "$manifest" ] || die "bundle manifest is missing or empty"

root_manifest="${scratch}/root.manifest"
git -C "$REPO_ROOT" ls-files --stage \
  | awk '$1 == "160000" {print $2 " " $4}' \
  | LC_ALL=C sort > "$root_manifest"

expected="${scratch}/expected.manifest"
declare -a COMMITS=()
declare -a SUBMODULE_PATHS=()

add_submodule() {
  local commit="$1"
  local submodule_path="$2"
  local seen_index=0

  for ((seen_index = 0; seen_index < ${#SUBMODULE_PATHS[@]}; seen_index++)); do
    if [ "${SUBMODULE_PATHS[$seen_index]}" = "$submodule_path" ]; then
      [ "${COMMITS[$seen_index]}" = "$commit" ] \
        || die "conflicting commits recorded for ${submodule_path}"
      return
    fi
  done
  COMMITS+=("$commit")
  SUBMODULE_PATHS+=("$submodule_path")
}

while read -r commit submodule_path; do
  add_submodule "$commit" "$submodule_path"
done < "$root_manifest"

for ((index = 0; index < ${#COMMITS[@]}; index++)); do
  commit="${COMMITS[$index]}"
  submodule_path="${SUBMODULE_PATHS[$index]}"
  source_dir="${scratch}/${submodule_path}"
  [ -d "$source_dir" ] || die "bundle is missing ${submodule_path}"
  [ "$(git -C "$source_dir" rev-parse HEAD 2>/dev/null)" = "$commit" ] \
    || die "bundle commit mismatch for ${submodule_path}"

  while read -r nested_commit nested_path; do
    [ -n "$nested_commit" ] || continue
    add_submodule "$nested_commit" "${submodule_path}/${nested_path}"
  done < <(
    git -C "$source_dir" ls-tree -r HEAD \
      | awk '$1 == "160000" {print $3 " " $4}' \
      | LC_ALL=C sort
  )
done

for ((index = 0; index < ${#COMMITS[@]}; index++)); do
  printf '%s %s\n' "${COMMITS[$index]}" "${SUBMODULE_PATHS[$index]}"
done | LC_ALL=C sort > "$expected"

cmp -s "$expected" "$manifest" \
  || die "bundle manifest does not match this checkout's pinned submodules"

while read -r commit submodule_path; do
  case "$submodule_path" in
    /*|../*|*/../*|*/..)
      die "unsafe submodule path: ${submodule_path}"
      ;;
  esac

  source_dir="${scratch}/${submodule_path}"
  [ -d "$source_dir" ] || die "bundle is missing ${submodule_path}"
  [ "$(git -C "$source_dir" rev-parse HEAD 2>/dev/null)" = "$commit" ] \
    || die "bundle commit mismatch for ${submodule_path}"
  [ -z "$(git -C "$source_dir" status --porcelain)" ] \
    || die "bundle checkout is dirty for ${submodule_path}"
done < "$manifest"

while read -r commit submodule_path; do
  source_dir="${scratch}/${submodule_path}"
  destination="${REPO_ROOT}/${submodule_path}"
  if [ -d "$destination" ] && [ -z "$(find "$destination" -mindepth 1 -print -quit)" ]; then
    rmdir "$destination"
  fi
  [ ! -e "$destination" ] \
    || die "refusing to replace existing path ${destination}"

  mkdir -p "$(dirname "$destination")"
  mv "$source_dir" "$destination"
done < "$root_manifest"

printf '[submodule-bundle] restored %s pinned submodules\n' "$(wc -l < "$manifest" | tr -d ' ')"
