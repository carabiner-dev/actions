# vexflow/assemble

A reusable GitHub Action that assembles the [OpenVEX](https://openvex.dev)
document of a branch with [vexflow](https://github.com/carabiner-dev/vexflow)
and signs it into a sigstore bundle with [bnd](https://github.com/carabiner-dev/bnd),
using the workflow's own identity.

vexflow manages vulnerability triage through issues in a `.vexflow`
repository: maintainers assess each vulnerability found in a branch and their
assessments are published as signed VEX statements. `assemble` clones the
branch, scans it for vulnerabilities, gathers the statements that apply to what
it found, and builds one OpenVEX document out of them. The `product` values
name what the statements are about, typically the commit the workflow runs for.

## Usage

```yaml
jobs:
  attest:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # required to sign with the job's identity
      contents: read
    steps:
      - uses: carabiner-dev/actions/vexflow/assemble@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
        with:
          output: attestations/openvex.bundle.json
```

With no other inputs, the action will:

1. Install `vexflow` and `bnd` into the runner
2. Assemble the VEX document for the default branch of the current repository,
   naming the current commit as the product
3. Wrap the document in an in-toto attestation with the commit as its subject
4. Sign the attestation into a sigstore bundle written to `output`

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `repo` | No | `${{ github.repository }}` | Repository whose branch to assemble the document for, as an `org/name` slug. |
| `branch` | No | the repository's default branch | Branch to assemble the document for. Falls back to `main` when the event carries no repository information. |
| `product` | No | `sha1:${{ github.sha }}` | Newline-separated products the statements apply to, as hashes (`algo:value`) or paths to files. When signing they are also the subjects of the attestation. |
| `triage-repo` | No | `<org>/.vexflow` | Repository holding the triage data, as an `org/name` slug. |
| `output` | Yes | - | Path to write the result to: a signed sigstore bundle or, when `sign` is false, the bare OpenVEX document. Parent directories are created as needed. |
| `sign` | No | `true` | Wrap the document in an in-toto attestation and sign it with the job's workload identity. |
| `token` | No | `${{ github.token }}` | Token vexflow uses to read the triage repository, exported as `GITHUB_TOKEN`. |
| `vexflow-version` | No | `""` | vexflow version to install. When empty, the version pinned by `install/vexflow` is used. |
| `bnd-version` | No | `""` | bnd version to install for signing. When empty, the version pinned by `install/bnd` is used. |

## Outputs

| Output | Description |
| --- | --- |
| `attestation` | Path of the written file, as given in `output` |

## Permissions

Signing uses the job's workload identity, so `sign: 'true'` (the default)
requires the job to grant `id-token: write`. The action fails early with a
clear error when the permission is missing.

vexflow reads the triage repository with `token`, which defaults to the job's
`GITHUB_TOKEN`; that is enough for a public `.vexflow` repository. The branch
itself is cloned anonymously over HTTPS, so `repo` has to be reachable that
way.

## What the document contains

Only statements about vulnerabilities currently found in the branch make it
into the document, so a branch with no assessed vulnerabilities yields a valid
OpenVEX document with no statements, which is still attested. The scan runs
in-process with the OSV database; a branch without any dependency manifests it
recognizes makes vexflow fail with `no packages found in scan`.

The attestation's predicate type is `https://openvex.dev/ns/v0.2.0` and its
subjects are the `product` values: hashes as given, files by their digest.

## Examples

### Attest the VEX document of the current commit

```yaml
steps:
  - uses: carabiner-dev/actions/vexflow/assemble@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      output: attestations/openvex.bundle.json
```

### A branch other than the default, unsigned

```yaml
steps:
  - uses: carabiner-dev/actions/vexflow/assemble@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      branch: release-1.4
      sign: 'false'
      output: openvex.json
```

### Products from a build

```yaml
steps:
  - run: make dist/app

  - uses: carabiner-dev/actions/vexflow/assemble@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      product: |
        sha1:${{ github.sha }}
        dist/app
      output: attestations/openvex.bundle.json
```

### A triage repository with another name

```yaml
steps:
  - uses: carabiner-dev/actions/vexflow/assemble@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      triage-repo: my-org/security-triage
      output: attestations/openvex.bundle.json
```

## See Also

- [`bnd/pack`](../../bnd/pack) — packs the resulting bundle with the rest of
  the job's attestations.
- [`install/vexflow`](../../install/vexflow) — installs vexflow without
  assembling, for workflows that drive the CLI directly.
