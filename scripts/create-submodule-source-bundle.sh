#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

declare -a MODULE_CACHES=()
OUTPUT=""

die() {
  printf '[submodule-bundle] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: scripts/create-submodule-source-bundle.sh --module-cache PATH... --output FILE

Create a self-contained archive of shallow, detached submodule checkouts at
the exact gitlink commits recorded by the current repository checkout.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --module-cache)
      [ "$#" -ge 2 ] || die "--module-cache requires a path"
      MODULE_CACHES+=("$2")
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || die "--output requires a file"
      OUTPUT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ "${#MODULE_CACHES[@]}" -gt 0 ] || die "at least one --module-cache is required"
[ -n "$OUTPUT" ] || die "--output is required"

declare -a OBJECT_DIRS=()
for cache in "${MODULE_CACHES[@]}"; do
  [ -d "$cache" ] || die "module cache not found: ${cache}"
  while IFS= read -r object_dir; do
    OBJECT_DIRS+=("$object_dir")
  done < <(find "$cache" -type d -name objects -print)
done
[ "${#OBJECT_DIRS[@]}" -gt 0 ] || die "no Git object stores found"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
bundle_root="${scratch}/source"
mkdir -p "$bundle_root" "$(dirname "$OUTPUT")"

manifest="${bundle_root}/.linphone-submodules.manifest"
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
done < <(
  git -C "$REPO_ROOT" ls-files --stage \
    | awk '$1 == "160000" {print $2 " " $4}' \
    | LC_ALL=C sort
)
[ "${#COMMITS[@]}" -gt 0 ] || die "repository has no gitlinks to bundle"

for ((index = 0; index < ${#COMMITS[@]}; index++)); do
  commit="${COMMITS[$index]}"
  submodule_path="${SUBMODULE_PATHS[$index]}"
  case "$submodule_path" in
    /*|../*|*/../*|*/..)
      die "unsafe submodule path: ${submodule_path}"
      ;;
  esac

  source_git_dir=""
  for object_dir in "${OBJECT_DIRS[@]}"; do
    candidate="${object_dir%/objects}"
    if git --git-dir="$candidate" cat-file -e "${commit}^{commit}" 2>/dev/null; then
      source_git_dir="$candidate"
      break
    fi
  done
  [ -n "$source_git_dir" ] || die "commit ${commit} for ${submodule_path} is absent from the supplied caches"

  destination="${bundle_root}/${submodule_path}"
  mkdir -p "$(dirname "$destination")"
  git init --quiet "$destination"
  git -C "$destination" fetch --quiet --depth=1 "file://${source_git_dir}" "$commit"
  git -C "$destination" checkout --quiet --detach "$commit"
  git -C "$destination" gc --quiet --prune=now
  rm -f "${destination}/.git/FETCH_HEAD"

  [ "$(git -C "$destination" rev-parse HEAD)" = "$commit" ] \
    || die "checkout mismatch for ${submodule_path}"

  while read -r nested_commit nested_path; do
    [ -n "$nested_commit" ] || continue
    add_submodule "$nested_commit" "${submodule_path}/${nested_path}"
  done < <(
    git --git-dir="$source_git_dir" ls-tree -r "$commit" \
      | awk '$1 == "160000" {print $3 " " $4}' \
      | LC_ALL=C sort
  )
done

for ((index = 0; index < ${#COMMITS[@]}; index++)); do
  commit="${COMMITS[$index]}"
  submodule_path="${SUBMODULE_PATHS[$index]}"
  [ -z "$(git -C "${bundle_root}/${submodule_path}" status --porcelain)" ] \
    || die "checkout is dirty for ${submodule_path}"
done

for ((index = 0; index < ${#COMMITS[@]}; index++)); do
  printf '%s %s\n' "${COMMITS[$index]}" "${SUBMODULE_PATHS[$index]}"
done | LC_ALL=C sort > "$manifest"

COPYFILE_DISABLE=1 tar -czf "$OUTPUT" -C "$bundle_root" .
printf '%s  %s\n' "$(shasum -a 256 "$OUTPUT" | awk '{print $1}')" "$(basename "$OUTPUT")"
