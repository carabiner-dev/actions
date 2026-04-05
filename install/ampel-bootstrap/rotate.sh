#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# Rotates the ampel-bootstrap trust anchor to a new version.
#
# Usage:
#   ./rotate.sh          # uses the latest release
#   ./rotate.sh v1.2.0   # uses a specific version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_YML="${SCRIPT_DIR}/action.yml"
REPO="carabiner-dev/ampel"

# Determine target version
if [ $# -ge 1 ]; then
  VERSION="$1"
else
  echo "Fetching latest ampel release..."
  VERSION=$(gh release view --repo "${REPO}" --json tagName --jq '.tagName')
fi

echo "Rotating bootstrap to ampel ${VERSION}"
echo ""

# Download binaries and compute hashes
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

PLATFORMS=(
  "darwin-arm64"
  "linux-amd64"
  "linux-arm64"
  "windows-amd64.exe"
)

declare -A HASHES

for platform in "${PLATFORMS[@]}"; do
  filename="ampel-${VERSION}-${platform}"
  url="https://github.com/${REPO}/releases/download/${VERSION}/${filename}"

  echo "Downloading ${filename}..."
  if ! curl -sSfL -o "${TMPDIR}/${filename}" "${url}"; then
    echo "ERROR: Failed to download ${filename}" >&2
    echo "       Check that ${VERSION} exists and has binaries for all platforms." >&2
    exit 1
  fi

  if command -v sha256sum &>/dev/null; then
    hash=$(sha256sum "${TMPDIR}/${filename}" | awk '{print $1}')
  else
    hash=$(shasum -a 256 "${TMPDIR}/${filename}" | awk '{print $1}')
  fi

  HASHES["${platform}"]="${hash}"
  echo "  sha256: ${hash}"
done

echo ""
echo "Patching ${ACTION_YML}..."

# Read current version from action.yml
OLD_VERSION=$(grep 'BOOTSTRAP_VERSION=' "${ACTION_YML}" | head -1 | sed 's/.*BOOTSTRAP_VERSION="\(.*\)"/\1/')

if [ "${OLD_VERSION}" = "${VERSION}" ]; then
  echo "Already at ${VERSION}, nothing to do."
  exit 0
fi

# Patch the version string in the BOOTSTRAP_VERSION variable
sed -i.bak "s/BOOTSTRAP_VERSION=\"${OLD_VERSION}\"/BOOTSTRAP_VERSION=\"${VERSION}\"/" "${ACTION_YML}"

# Patch the version in the filename output
sed -i.bak "s/filename=ampel-${OLD_VERSION}-/filename=ampel-${VERSION}-/" "${ACTION_YML}"

# Patch each platform hash and the case pattern
for platform in "${PLATFORMS[@]}"; do
  old_pattern="ampel-${OLD_VERSION}-${platform}"
  new_pattern="ampel-${VERSION}-${platform}"
  sed -i.bak "s|${old_pattern})|${new_pattern})|" "${ACTION_YML}"
done

# Patch the hash values by matching the old hashes
# We need to read the old hashes from the file and replace them
for platform in "${PLATFORMS[@]}"; do
  new_hash="${HASHES[${platform}]}"
  # Find the line with this platform's case pattern and replace the hash on the next
  # relevant line. Since the hash immediately follows the pattern, we use a two-pass
  # approach: first find old hash by context, then replace.
  case_pattern="ampel-${VERSION}-${platform}"
  # Use awk to find the hash after the case pattern and replace it
  awk -v pat="${case_pattern}" -v newhash="${new_hash}" '
    $0 ~ pat { found=1; print; next }
    found && /EXPECTED=/ {
      sub(/"[a-f0-9]{64}"/, "\"" newhash "\"")
      found=0
    }
    { print }
  ' "${ACTION_YML}" > "${ACTION_YML}.tmp" && mv "${ACTION_YML}.tmp" "${ACTION_YML}"
done

# Clean up backup files from sed -i
rm -f "${ACTION_YML}.bak"

echo ""
echo "Done. Changes:"
echo ""
echo "  ${OLD_VERSION} -> ${VERSION}"
echo ""
for platform in "${PLATFORMS[@]}"; do
  echo "  ampel-${VERSION}-${platform}"
  echo "    sha256: ${HASHES[${platform}]}"
done
echo ""
echo "Review the diff, then commit and open a PR:"
echo "  git diff ${ACTION_YML}"
