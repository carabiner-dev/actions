<!--
SPDX-FileCopyrightText: Copyright 2026 Carabiner Systems, Inc
SPDX-License-Identifier: Apache-2.0
-->
# Carabiner Login Action

`login` authenticates a GitHub Actions workflow to Carabiner. It exchanges the
workflow's GitHub OIDC identity token for a short-lived Carabiner token and
exposes it to the rest of the job, so subsequent steps and Carabiner tools can
call Carabiner services without performing their own exchange.

## How it works

1. The action requests the workflow's OIDC identity token from the runner,
   minted with the exchange server (`exchange-url`) as its audience.
2. It POSTs that token to the exchange server's `/token` endpoint as an
   [RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693) token exchange,
   requesting `audience`.
3. The exchange server resolves the owning Carabiner organization (tenant) for
   the repository and mints a tenant-scoped identity token of the form
   `repository://github.com/<owner>/<repo>@<tenant>.auth.carabiner.dev`.
4. The action masks the returned token and writes it to `CARABINER_CREDENTIALS`
   in `$GITHUB_ENV` for later steps.

## Authorization

The exchange is **refused** (no token issued) unless both conditions hold:

- the repository's GitHub organization is claimed as a **namespace** by a
  Carabiner organization, and
- the repository is tracked in the namespace.

If either is missing, the action fails with the exchange server's error.

## Scopes

The issued token can carry **capability scopes** (for example
`attestations:read attestations:write`, the default). Scopes are capability
switches: they are necessary to use a capability but not sufficient, the
platform always checks the actual authorization of the repository's service
account when the token is used.

The action requests the scopes in the `scope` input, and the server mints the
token with the **intersection** of the requested and granted scopes (it never
widens). When the server narrows the request, the action emits a workflow
warning showing the requested and granted sets; the granted scopes are also
published in the `scope` output. Older exchange servers that predate scopes
return no scope information, in which case no warning is emitted and the output
is empty.

If scopes are requested but **none** of them are granted to the repository, the
exchange fails with `invalid_scope` — an organization admin can grant the
scopes in Carabiner.

Set `scope: ""` to request an **identity-only** token that carries no
capability scopes. In every case the [authorization
prerequisites](#authorization) above still apply.

## Resources

The issued token also carries a **resources** claim: the canonical resource
URIs the token can act on. By default the server stamps the repository's whole
Carabiner organization (`organization://<handle>`). Pass space-separated URIs
in the `resource` input to restrict the token further:

- `organization://<handle>`: the whole organization.
- `repository://<system>/<owner>/<repo>`: one registered repository
  (registry slug form, eg `repository://github/acme/widgets`).
- `stash://<handle>[/<namespace>]`: the organization's attestation stash or
  a namespace in it.

Every requested resource must belong to the repository's Carabiner
organization as specifying anything else refuses the exchange. Like scopes,
resources only attenuate, live authorization still applies wherever the
token is used. Older exchange servers ignore the parameter.

## Token lifetime

The issued token's expiry is paired to the workflow's OIDC token, so it is
naturally short-lived (a few minutes). Treat it as ephemeral and request it in
the job that uses it rather than passing it between jobs.

## Requirements

- The calling job must grant `id-token: write` permission.
- `curl` and `jq` must be available on the runner (both are present on
  GitHub-hosted runners).

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `exchange-url` | No | `https://auth.carabiner.dev` | Base URL of the Carabiner token exchange server. The workflow OIDC token is minted for this audience. |
| `audience` | No | `https://api.carabiner.dev` | Audience (a Carabiner service URL) to request the token for. Must be on the exchange server's allowlist. |
| `scope` | No | `attestations:read attestations:write` | Space-separated capability scopes to request. The issued token carries the intersection of the requested and granted scopes; set empty for an identity-only token. |
| `resource` | No | _(empty)_ | Space-separated canonical resource URIs restricting which platform objects the token may act on. All resources must belong to the repository's Carabiner organization, an empty resource requests the repository organization. |

## Outputs

| Output | Description |
| --- | --- |
| `expires-in` | Lifetime of the issued Carabiner token, in seconds. |
| `scope` | Space-separated scopes granted on the issued token (may be empty). |

## Usage

```yaml
jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # required to mint the workflow OIDC token
      contents: read
    steps:
      - uses: carabiner-dev/actions/login@174f1c83779af3d3d7e451b7ead7ba824d0d2aa9 # v1.2.2 # pin to a release commit once tagged

      # Subsequent steps can read CARABINER_CREDENTIALS from the environment.
      - run: echo "token expires in ${{ steps.login.outputs.expires-in }}s"
        # (give the login step an `id: login` to reference its outputs)
```

## Consuming the token

The token is exported as `CARABINER_CREDENTIALS`, the environment variable the
Carabiner client credential chain reads first. Tools built on the Carabiner /
deadrop client pick it up automatically; other tools can read it directly from
the environment.

## Troubleshooting

- **"No OIDC token available"**: the calling job is missing
  `permissions: id-token: write`.
- **"Token exchange was refused"**: the repository's organization is not
  claimed as a Carabiner namespace, or the repository has no monitored pipeline.
- **`invalid_scope`** — none of the requested scopes are granted to the
  repository; an organization admin can grant them in Carabiner, or set
  `scope: ""` for an identity-only token.
- **`invalid_target`**: a URI in the `resource` input is outside the
  repository's Carabiner organization (or names an unregistered repository);
  fix or drop the entry. Older exchange servers report this as
  `invalid_scope` with a message naming the resource.
- **"Could not reach the carabiner token exchange server"**: check
  `exchange-url` and network egress from the runner.
