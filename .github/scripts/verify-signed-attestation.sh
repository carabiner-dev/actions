#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
# SPDX-License-Identifier: Apache-2.0
#
# Verifies an attestation signed with a PEM key, as bnd writes them when given
# --signing-key, using ampel: the policy pins the public key as the only
# accepted signer identity and requires one predicate of the expected type for
# the subject. ampel exits non-zero when the signature, the signer, the subject
# or the predicate type do not check out.
#
# Usage: verify-signed-attestation.sh <attestation> <public-key.pem> <predicate-type> <subject>
#   subject is a digest in algo:value form.
set -euo pipefail

ATTESTATION="$1"
PUBKEY="$2"
PREDICATE_TYPE="$3"
SUBJECT="$4"

POLICY="$(mktemp)"
trap 'rm -f "${POLICY}"' EXIT

jq -n --rawfile pem "${PUBKEY}" --arg type "${PREDICATE_TYPE}" '{
  id: "signed-by-test-key",
  identities: [{ id: "test-key", key: { data: $pem } }],
  tenets: [{
    id: "signed",
    code: "size(predicates) > 0",
    predicates: { types: [$type] },
    error: { message: "no attestation of the expected type signed by the test key" }
  }]
}' > "${POLICY}"

ampel verify --subject "${SUBJECT}" --attestation "${ATTESTATION}" --policy "${POLICY}" --format summary
