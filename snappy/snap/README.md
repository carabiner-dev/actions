# snappy/snap

A reusable GitHub Action that takes an attestable snapshot of an API response
with [snappy](https://github.com/carabiner-dev/snappy) and signs it into a
sigstore bundle with [bnd](https://github.com/carabiner-dev/bnd), using the
workflow's own identity.

A snapshot follows a spec: a small YAML file naming the endpoint to call and
the response fields to keep. Only the fields listed in the spec's mask end up
in the attestation, so snapshots never leak data the spec did not ask for.
snappy ships built-in specs for the most common GitHub and GitLab objects and
any spec file in the repository works the same way.

## Usage

```yaml
jobs:
  attest:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # required to sign with the job's identity
      contents: read
    steps:
      - uses: carabiner-dev/actions/snappy/snap@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
        with:
          spec: builtin:github/repo.yaml
          vars: |
            ORG=${{ github.repository_owner }}
            REPO=${{ github.event.repository.name }}
          output: attestations/repo.bundle.json
```

The action will:

1. Install `snappy` and `bnd` into the runner
2. Call the API described by the spec and keep the masked fields
3. Wrap the snapshot in an in-toto statement
4. Sign the statement into a sigstore bundle written to `output`

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `spec` | Yes | - | Snapshot spec to take: a path to a spec file, or a built-in spec with the `builtin:` prefix (e.g. `builtin:github/repo.yaml`). |
| `vars` | No | `""` | Newline-separated `NAME=value` pairs substituted into the spec's `${NAME}` variables. Values cannot contain commas, snappy splits `--var` on them. |
| `output` | Yes | - | Path to write the attestation to: a signed sigstore bundle or, when `sign` is false, the unsigned in-toto statement. Parent directories are created as needed. |
| `sign` | No | `true` | Sign the statement into a sigstore bundle with the job's workload identity. |
| `platform` | No | `""` | API platform the spec targets: `github` or `gitlab`. Auto-detected from the spec's endpoint when empty. |
| `token` | No | `${{ github.token }}` | Token snappy uses to call the GitHub API, exported as `GITHUB_TOKEN`. For GitLab specs set `GITLAB_TOKEN` in the step's `env` instead. |
| `snappy-version` | No | `""` | snappy version to install. When empty, the version pinned by `install/snappy` is used. |
| `bnd-version` | No | `""` | bnd version to install for signing. When empty, the version pinned by `install/bnd` is used. |

## Outputs

| Output | Description |
| --- | --- |
| `attestation` | Path of the written attestation, as given in `output` |

## Permissions

Signing uses the job's workload identity, so `sign: 'true'` (the default)
requires the job to grant `id-token: write`. The action fails early with a
clear error when the permission is missing.

The API calls run with `token`, which defaults to the job's `GITHUB_TOKEN`.
That token can read the repository's own data, but organization-level specs
such as `builtin:github/org.yaml` only return the fields the token is allowed
to see, and some (like `two_factor_requirement_enabled`) need an organization
owner or a token with `read:org`.

## Built-in specs

snappy resolves `builtin:<platform>/<name>.yaml` to the specs it ships with:

| Spec | Variables | Snapshots |
| --- | --- | --- |
| `builtin:github/repo.yaml` | `ORG`, `REPO` | Repository settings and security features |
| `builtin:github/org.yaml` | `ORG` | Organization settings, including the 2FA requirement |
| `builtin:github/branch-rules.yaml` | `ORG`, `REPO`, `BRANCH` | Rules applied to a branch |
| `builtin:github/commit.yaml` | `ORG`, `REPO`, `REF` | A commit and its verification status |
| `builtin:github/mfa.yaml` | `ORG` | Members without 2FA enabled (GraphQL) |
| `builtin:github/mfa-rest.yaml` | `ORG` | Members without 2FA enabled (REST) |
| `builtin:gitlab/project.yaml` | `HOST`, `GROUP`, `PROJECT` | Project settings |
| `builtin:gitlab/project-approvals.yaml` | `HOST`, `GROUP`, `PROJECT` | Merge request approval rules |
| `builtin:gitlab/branch-protection.yaml` | `HOST`, `GROUP`, `PROJECT`, `BRANCH` | Protection rules of a branch |

`HOST` in the GitLab specs is the hostname recorded in the snapshot's subject
(e.g. `gitlab.com`); the API host itself is set with the `GITLAB_HOST`
environment variable when using a self-hosted instance. Check the
[snappy specs](https://github.com/carabiner-dev/snappy/tree/main/specs) for
the exact variables and masks each one uses.

## Examples

### Branch rules of the default branch

```yaml
steps:
  - uses: carabiner-dev/actions/snappy/snap@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      spec: builtin:github/branch-rules.yaml
      vars: |
        ORG=${{ github.repository_owner }}
        REPO=${{ github.event.repository.name }}
        BRANCH=${{ github.event.repository.default_branch }}
      output: attestations/branch.bundle.json
```

### Organization settings, only when running in an organization

```yaml
steps:
  - if: github.event.organization.login != ''
    uses: carabiner-dev/actions/snappy/snap@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      spec: builtin:github/org.yaml
      vars: ORG=${{ github.event.organization.login }}
      output: attestations/org.bundle.json
```

### A spec from the repository, unsigned

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false

  - uses: carabiner-dev/actions/snappy/snap@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      spec: .snappy/releases.yaml
      vars: |
        ORG=${{ github.repository_owner }}
        REPO=${{ github.event.repository.name }}
      sign: 'false'
      output: releases.intoto.json
```

### A GitLab project

```yaml
steps:
  - uses: carabiner-dev/actions/snappy/snap@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      spec: builtin:gitlab/project.yaml
      platform: gitlab
      vars: |
        HOST=gitlab.com
        GROUP=my-group
        PROJECT=my-project
      output: attestations/project.bundle.json
    env:
      GITLAB_TOKEN: ${{ secrets.GITLAB_TOKEN }}
```

### Pack several snapshots and upload them

```yaml
steps:
  - uses: carabiner-dev/actions/snappy/snap@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      spec: builtin:github/repo.yaml
      vars: |
        ORG=${{ github.repository_owner }}
        REPO=${{ github.event.repository.name }}
      output: attestations/repo.bundle.json

  - uses: carabiner-dev/actions/snappy/snap@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      spec: builtin:github/branch-rules.yaml
      vars: |
        ORG=${{ github.repository_owner }}
        REPO=${{ github.event.repository.name }}
        BRANCH=main
      output: attestations/branch.bundle.json

  - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
    with:
      name: attestations
      path: attestations/
```

## See Also

- [`install/snappy`](../../install/snappy) — installs snappy without taking a
  snapshot, for workflows that drive the CLI directly.
