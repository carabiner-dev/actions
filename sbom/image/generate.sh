#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# generate.sh — generates SBOMs of container images using `unpack image`.

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve inputs
# ---------------------------------------------------------------------------
FORMAT="${INPUT_FORMAT:-spdx}"
FILES_FLAG="${INPUT_FILES:-false}"
ATTEST_FLAG="${INPUT_ATTEST:-false}"
SIGN_FLAG="${INPUT_SIGN:-false}"

if [[ -z "${INPUT_IMAGES:-}" ]]; then
  echo "::error::No images specified. Set the 'images' input to one or more OCI references."
  exit 1
fi

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

case "${FORMAT}" in
  spdx)            UNPACK_FMT="spdx"       ; FMT_EXT="spdx" ;;
  cyclonedx|cdx)   UNPACK_FMT="cyclonedx"  ; FMT_EXT="cdx"  ;;
  *)
    echo "::error::Unsupported format '${FORMAT}'. Use 'spdx' or 'cyclonedx'."
    exit 1
    ;;
esac

# The extension reflects what unpack writes: a plain SBOM, an in-toto
# attestation wrapping it or, when signing, a sigstore bundle.
if [[ "${SIGN_FLAG}" == "true" ]]; then
  EXT="${FMT_EXT}.bundle.json"
elif [[ "${ATTEST_FLAG}" == "true" ]]; then
  EXT="${FMT_EXT}.intoto.json"
else
  EXT="${FMT_EXT}.json"
fi

mkdir -p "${OUTPUT_PATH}"

# ---------------------------------------------------------------------------
# Build common flags
# ---------------------------------------------------------------------------
IMAGE_ARGS=(-f "${UNPACK_FMT}")

if [[ "${FILES_FLAG}" == "true" ]]; then
  IMAGE_ARGS+=(--files)
fi

# --sign implies --attest in unpack, but pass both when asked to keep the
# invocation explicit in the logs.
if [[ "${ATTEST_FLAG}" == "true" ]]; then
  IMAGE_ARGS+=(--attest)
fi

if [[ "${SIGN_FLAG}" == "true" ]]; then
  IMAGE_ARGS+=(--sign)
fi

# ---------------------------------------------------------------------------
# sanitize turns an OCI reference into a filename component: every character
# outside [A-Za-z0-9._-] becomes a dash, repeated dashes are collapsed and
# leading/trailing dashes are dropped.
# ---------------------------------------------------------------------------
sanitize() {
  local s
  s="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-' | tr -s '-')"
  s="${s#-}"
  s="${s%-}"
  printf '%s' "${s}"
}

# ---------------------------------------------------------------------------
# Unpack each image reference into its own SBOM
# ---------------------------------------------------------------------------
GENERATED_FILES=()
while IFS= read -r ref; do
  ref="$(echo "${ref}" | xargs)"
  [[ -z "${ref}" ]] && continue

  DEST="${OUTPUT_PATH}/$(sanitize "${ref}").${EXT}"
  if [[ -e "${DEST}" ]]; then
    echo "::warning::Overwriting existing file ${DEST}"
  fi

  echo "::group::Generating SBOM for ${ref}"
  unpack image "${IMAGE_ARGS[@]}" -o "${DEST}" "${ref}"
  echo "::endgroup::"

  GENERATED_FILES+=("${DEST}")
done <<< "${INPUT_IMAGES}"

# ---------------------------------------------------------------------------
# Collect generated files and set output
# ---------------------------------------------------------------------------
if [[ ${#GENERATED_FILES[@]} -eq 0 ]]; then
  echo "::error::No image references found in the 'images' input."
  exit 1
fi

{
  echo "files<<EOF"
  printf '%s\n' "${GENERATED_FILES[@]}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"

echo "Successfully generated ${#GENERATED_FILES[@]} SBOM(s)."
