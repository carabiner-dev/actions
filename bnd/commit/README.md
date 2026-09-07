# bnd/commit

A reusable GitHub Action that attests a file to a git commit with
[bnd](https://github.com/carabiner-dev/bnd). The file becomes the predicate of
an in-toto statement whose subject is the commit, and the statement is signed
into a sigstore bundle with the workflow's own identity.

This is how policy files a repository already carries, such as a
`SECURITY-INSIGHTS.yml` or an OpenEoX document, turn into verifiable evidence
about a specific commit without changing the files themselves. bnd reads the
predicate from the repository history as it was at the attested commit, so the
attestation always matches the committed content.

## Usage

```yaml
jobs:
  attest:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # required to sign with the job's identity
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - uses: carabiner-dev/actions/bnd/commit@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
        with:
          path: SECURITY-INSIGHTS.yml
          type: https://github.com/ossf/security-insights-spec
          output: attestations/si.bundle.json
```

The action will:

1. Install `bnd` into the runner
2. Clone the repository and read the predicate at the attested commit
3. Wrap it in an in-toto statement whose subject is the commit
4. Sign the statement into a sigstore bundle written to `output`

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `path` | One of `path` or `predicate` | `""` | Path of the predicate file inside the repository, read as it was at the attested commit. |
| `predicate` | One of `path` or `predicate` | `""` | Path of a local predicate file to attest to the commit, read from disk rather than from the repository history. |
| `type` | No | `""` | Predicate type URI to declare. When empty, bnd tries to detect it from the contents; set it for formats bnd does not recognize. |
| `yaml` | No | `""` | Convert the predicate from YAML to JSON: `true`, `false`, or empty to decide from the file extension (`.yaml` and `.yml` are converted). |
| `repo` | No | `.` | Repository to attest: a local path (the checkout) or a URL bnd clones. |
| `sha` | No | `""` | Commit to attest. Defaults to the HEAD of the repository. Set either `sha` or `tag`, not both. |
| `tag` | No | `""` | Tag to attest instead of a commit. Set either `sha` or `tag`, not both. |
| `output` | Yes | - | Path to write the signed bundle to. Parent directories are created as needed. |
| `bnd-version` | No | `""` | bnd version to install. When empty, the version pinned by `install/bnd` is used. |

## Outputs

| Output | Description |
| --- | --- |
| `attestation` | Path of the written attestation, as given in `output` |

## Permissions

`bnd commit` always signs, using the job's workload identity, so the job must
grant `id-token: write`. The action fails early with a clear error when the
permission is missing.

## The attested commit

With the default `repo: .`, bnd works from the workflow's checkout: the
subject is the checkout's `HEAD` unless `sha` or `tag` names another commit,
and the subject's URI is built from the checkout's `origin` remote (e.g.
`git+ssh://github.com/org/repo@<sha>`). When a tag points at the attested
commit, the subject is named after the tag.

bnd clones the repository, even from a local path, so anything it attests has
to be present in the checkout. The default `actions/checkout` depth of 1 is
enough for `HEAD`, including the merge commit a `pull_request` run checks out;
set `fetch-depth: 0` when attesting an older `sha` or a `tag` so the commit
and the tags are fetched. The action resolves `tag` and `HEAD` to a commit
before calling bnd and fails with a clear error when the commit is missing.

When `repo` is a URL, bnd clones it and checks the requested commit out, so a
`sha` has to be reachable from one of the repository's branches or tags. A
`tag` is resolved to its commit with `git ls-remote` first.

The predicate named by `path` is read from the attested commit, not from the
working tree. Files generated during the job are not in the history, so attest
those with `predicate` instead.

## Examples

### Security Insights and OpenEoX

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false

  - uses: carabiner-dev/actions/bnd/commit@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      path: SECURITY-INSIGHTS.yml
      type: https://github.com/ossf/security-insights-spec
      output: attestations/si.bundle.json

  - uses: carabiner-dev/actions/bnd/commit@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      path: .openeox.json
      type: https://docs.oasis-open.org/openeox/core/v1.0
      output: attestations/openeox.bundle.json
```

### A release tag

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false
      fetch-depth: 0

  - uses: carabiner-dev/actions/bnd/commit@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      path: .openeox.json
      type: https://docs.oasis-open.org/openeox/core/v1.0
      tag: ${{ github.ref_name }}
      output: attestations/openeox.bundle.json
```

### A predicate generated in the job

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false

  - name: Lint the repository
    run: my-linter --format json > lint-results.json

  - uses: carabiner-dev/actions/bnd/commit@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      predicate: lint-results.json
      type: https://example.com/lint-results/v1
      output: attestations/lint.bundle.json
```

### Another repository

```yaml
steps:
  - uses: carabiner-dev/actions/bnd/commit@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      repo: https://github.com/example/policies
      tag: v1.4.0
      path: policy.yaml
      type: https://example.com/policy/v1
      output: attestations/policy.bundle.json
```

## See Also

- [`bnd/sign`](../sign) — signs an existing in-toto statement or a predicate
  about an arbitrary subject.
- [`install/bnd`](../../install/bnd) — installs bnd without attesting, for
  workflows that drive the CLI directly.
