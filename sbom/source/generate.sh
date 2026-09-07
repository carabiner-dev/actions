#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# generate.sh — generates SBOMs for codebases using `unpack extract --multi`.

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve inputs
# ---------------------------------------------------------------------------
FORMAT="${INPUT_FORMAT:-spdx}"
FILES_FLAG="${INPUT_FILES:-false}"
ATTEST_FLAG="${INPUT_ATTEST:-false}"
SIGN_FLAG="${INPUT_SIGN:-false}"
NETWORKING="${INPUT_NETWORKING:-}"

# Signing uses the job's workload identity, which is only available when the
# workflow grants id-token: write. Fail early with a useful message.
if [[ "${SIGN_FLAG}" == "true" && -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
  echo "::error::Signing requires the job to grant the 'id-token: write' permission."
  exit 1
fi

if [[ -n "${INPUT_OUTPUT_PATH:-}" ]]; then
  OUTPUT_PATH="${INPUT_OUTPUT_PATH}"
else
  OUTPUT_PATH="$(mktemp -d)"
fi

# `spdx` stays on SPDX 2.3 for callers that already have it in a script;
# `spdx3` is a name of its own, matching how unpack selects the versions.
case "${FORMAT}" in
  spdx)            EXTRACT_FMT="spdx"      ; FMT_EXT="spdx"  ;;
  spdx3)           EXTRACT_FMT="spdx3"     ; FMT_EXT="spdx3" ;;
  cyclonedx|cdx)   EXTRACT_FMT="cyclonedx" ; FMT_EXT="cdx"   ;;
  *)
    echo "::error::Unsupported format '${FORMAT}'. Use 'spdx', 'spdx3' or 'cyclonedx'."
    exit 1
    ;;
esac

# The extension unpack writes. It only reflects the SBOM format: unpack keeps
# it even when --attest or --sign wrap the SBOM (those files are renamed
# further down).
EXT="${FMT_EXT}.json"

# What wraps the SBOM decides the final extension, following the sbom/image
# convention: .intoto.json for in-toto statements and .bundle.json for
# sigstore bundles. Empty means a bare SBOM, left as unpack named it.
WRAP=""
if [[ "${SIGN_FLAG}" == "true" ]]; then
  WRAP="bundle"
elif [[ "${ATTEST_FLAG}" == "true" ]]; then
  WRAP="intoto"
fi

# Derive the output prefix from the GitHub org and repo name.
OWNER="${GITHUB_REPOSITORY%%/*}"
REPO="${GITHUB_REPOSITORY##*/}"
PREFIX="${OWNER}-${REPO}-"

mkdir -p "${OUTPUT_PATH}"

# ---------------------------------------------------------------------------
# Build common flags
# ---------------------------------------------------------------------------
EXTRACT_ARGS=(--multi -f "${EXTRACT_FMT}" -o "${OUTPUT_PATH}" --output-prefix "${PREFIX}")

if [[ "${FILES_FLAG}" == "true" ]]; then
  EXTRACT_ARGS+=(--files)
fi

# --sign implies --attest in unpack, but pass both when asked to keep the
# invocation explicit in the logs.
if [[ "${ATTEST_FLAG}" == "true" ]]; then
  EXTRACT_ARGS+=(--attest)
fi

if [[ "${SIGN_FLAG}" == "true" ]]; then
  EXTRACT_ARGS+=(--sign)
fi

# Leave the flag out when unset so unpack's own default applies.
if [[ -n "${NETWORKING}" ]]; then
  EXTRACT_ARGS+=(--networking "${NETWORKING}")
fi

# Ignore patterns
if [[ -n "${INPUT_IGNORE:-}" ]]; then
  while IFS= read -r pattern; do
    pattern="$(echo "${pattern}" | xargs)"
    [[ -z "${pattern}" ]] && continue
    EXTRACT_ARGS+=("--ignore" "${pattern}")
  done <<< "${INPUT_IGNORE}"
fi

# ---------------------------------------------------------------------------
# If codebases are specified, extract each one individually.
# Otherwise extract all (optionally filtered by ecosystem).
# ---------------------------------------------------------------------------
if [[ -n "${INPUT_CODEBASES:-}" ]]; then
  # User specified explicit codebase IDs — extract each one.
  while IFS= read -r cb; do
    cb="$(echo "${cb}" | xargs)"
    [[ -z "${cb}" ]] && continue
    echo "::group::Extracting codebase ${cb}"
    unpack extract "${EXTRACT_ARGS[@]}" -c "${cb}"
    echo "::endgroup::"
  done <<< "${INPUT_CODEBASES}"
elif [[ -n "${INPUT_ECOSYSTEMS:-}" ]]; then
  # Filter by ecosystems: discover codebases, keep only matching ones.
  LS_JSON="$(unpack ls --format json)"
  while IFS= read -r id; do
    lang="${id%%:*}"
    match=false
    while IFS= read -r eco; do
      eco="$(echo "${eco}" | xargs)"
      [[ -z "${eco}" ]] && continue
      [[ "${lang}" == "${eco}" ]] && match=true && break
    done <<< "${INPUT_ECOSYSTEMS}"
    if [[ "${match}" == "true" ]]; then
      echo "::group::Extracting codebase ${id}"
      unpack extract "${EXTRACT_ARGS[@]}" -c "${id}"
      echo "::endgroup::"
    fi
  done < <(echo "${LS_JSON}" | jq -r '.codebases[].id')
else
  # Extract all codebases at once.
  echo "::group::Extracting all codebases"
  unpack extract "${EXTRACT_ARGS[@]}"
  echo "::endgroup::"
fi

# ---------------------------------------------------------------------------
# Settle the extension unpack actually used.
#
# Unlike sbom/image, this action does not name the files: it passes a
# directory and unpack derives each name from the codebase id. Releases whose
# codebaseOutputFilename has no SPDX 3 case fall through to a bare ".json" for
# spdx3, so look for what is on disk rather than assuming, and keep working
# either way.
# ---------------------------------------------------------------------------
if [[ "${FORMAT}" == "spdx3" ]] && \
   ! compgen -G "${OUTPUT_PATH}/${PREFIX}*.spdx3.json" > /dev/null; then
  EXT="json"
  FMT_EXT=""
fi

# ---------------------------------------------------------------------------
# Rename wrapped outputs.
#
# unpack names every file after the SBOM format even when --attest or --sign
# wrap it in an in-toto statement or a sigstore bundle, so a consumer reading
# the directory could not tell a bare SBOM from a signed one. Move them to the
# sbom/image convention instead: <name>.<fmt>.intoto.json for statements and
# <name>.<fmt>.bundle.json for bundles (the <fmt> part is dropped when unpack
# wrote a bare .json, see above).
# ---------------------------------------------------------------------------
if [[ -n "${WRAP}" ]]; then
  NEW_EXT="${FMT_EXT:+${FMT_EXT}.}${WRAP}.json"
  for f in "${OUTPUT_PATH}/${PREFIX}"*".${EXT}"; do
    [[ -f "${f}" ]] || continue
    mv "${f}" "${f%."${EXT}"}.${NEW_EXT}"
  done
  EXT="${NEW_EXT}"
fi

# ---------------------------------------------------------------------------
# Rename files to apply the naming convention for top-level codebases.
#
# unpack writes files as: PREFIX + sanitized-id + .ext
# For top-level codebases (ecosystem:.) unpack produces e.g. "prefix-golang.spdx.json"
# which is already correct when there are multiple top-level codebases.
#
# When there is only ONE top-level codebase, the convention drops the ecosystem
# entirely: "org-repo.spdx.json" instead of "org-repo-golang.spdx.json".
# ---------------------------------------------------------------------------
TOP_FILES=()
for f in "${OUTPUT_PATH}/${PREFIX}"*".${EXT}"; do
  [[ ! -f "${f}" ]] && continue
  basename="$(basename "${f}")"
  # Check if this looks like a top-level codebase file (prefix + ecosystem + ext only)
  stripped="${basename#"${PREFIX}"}"
  stripped="${stripped%."${EXT}"}"
  # A top-level codebase has no dashes in the stripped part (just the ecosystem name)
  if [[ "${stripped}" != *-* && -n "${stripped}" ]]; then
    TOP_FILES+=("${f}")
  fi
done

if [[ ${#TOP_FILES[@]} -eq 1 ]]; then
  # Single top-level codebase: rename to drop the ecosystem
  DEST="${OUTPUT_PATH}/${OWNER}-${REPO}.${EXT}"
  mv "${TOP_FILES[0]}" "${DEST}"
fi

# ---------------------------------------------------------------------------
# Collect generated files and set output
# ---------------------------------------------------------------------------
GENERATED_FILES=()
for f in "${OUTPUT_PATH}/${PREFIX}"*".${EXT}" "${OUTPUT_PATH}/${OWNER}-${REPO}.${EXT}"; do
  [[ -f "${f}" ]] && GENERATED_FILES+=("${f}")
done

if [[ ${#GENERATED_FILES[@]} -eq 0 ]]; then
  echo "::warning::No SBOMs were generated."
  echo "files=" >> "${GITHUB_OUTPUT}"
  exit 0
fi

{
  echo "files<<EOF"
  printf '%s\n' "${GENERATED_FILES[@]}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"

echo "Successfully generated ${#GENERATED_FILES[@]} SBOM(s)."
