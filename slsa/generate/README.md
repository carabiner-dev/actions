# SLSA Provenance Generator

This action observes a GitHub Actions workflow run and generates a signed
[SLSA provenance](https://slsa.dev/provenance/) attestation using
[tejolote](https://github.com/kubernetes-sigs/tejolote).

## How It Works

The action runs as a job alongside your build. It uses tejolote to monitor the
other jobs in the workflow run, wait for them to complete, then collect artifact
data and produce an [in-toto](https://in-toto.io/) attestation with a SLSA
provenance predicate.

When the action detects it is running inside the same workflow run it is
attesting (the common case), it **automatically excludes its own job** from the
watch list. If no `watch-jobs` input is provided, it watches all sibling jobs
by default — no extra configuration needed.

The attestation is signed using [Sigstore](https://sigstore.dev) keyless
signing, binding the provenance to the GitHub Actions OIDC identity of the
workflow.

## Verifying the tejolote download

The action downloads a released `tejolote` binary from
[kubernetes-sigs/tejolote](https://github.com/kubernetes-sigs/tejolote/releases)
rather than building it from source. Before use, the binary is verified with the
[`ampel/verify`](../../ampel/verify) action against tejolote's own signed SLSA
provenance attestation. The default `policy`
([`slsa/slsa-build-point`](https://github.com/carabiner-dev/policies/blob/main/slsa/slsa-build-point.json))
requires that provenance to be signed by tejolote's release-workflow Sigstore
identity and to record the expected `build-point` (the tejolote source
repository), so a binary built from anywhere else fails verification. Set
`verify: false` to skip this (e.g. for air-gapped runners or when pinning an
unreleased build).

## Usage

### Minimal (watch all sibling jobs automatically)

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - run: make build
      - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: my-binary
          path: ./bin/my-binary

  provenance:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # Sigstore keyless signing
      contents: read
      actions: read      # Read run metadata and artifacts
    steps:
      - uses: carabiner-dev/actions/slsa/generate@2a4b2cd115ede14629b03ef7e77586d3269d4c72 # v1.2.3
```

### Watch specific jobs

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - run: make build

  integration-tests:
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - run: make test

  provenance:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      actions: read
    steps:
      - uses: carabiner-dev/actions/slsa/generate@2a4b2cd115ede14629b03ef7e77586d3269d4c72 # v1.2.3
        with:
          watch-jobs: "build, integration-tests"
```

### With external artifact sources

```yaml
  provenance:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      actions: read
    steps:
      - uses: carabiner-dev/actions/slsa/generate@2a4b2cd115ede14629b03ef7e77586d3269d4c72 # v1.2.3
        with:
          artifacts: "oci://ghcr.io/my-org/my-image"
          dependencies: "git+https://github.com/my-org/my-lib@abc123def"
```

> **Note:** Setting `artifacts` makes tejolote collect **only** from the URIs you
> list; the run's GitHub Actions artifacts are no longer collected automatically.
> Leave `artifacts` empty to keep the automatic collection.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `sign` | Sign the attestation with Sigstore | `true` |
| `slsa-version` | SLSA predicate version (`1.0` or `0.2`) | `1.0` |
| `output` | Path to write the attestation file | `provenance.intoto.jsonl` |
| `watch-jobs` | Comma-separated job names to watch (empty = all siblings) | `""` |
| `artifacts` | Comma-separated storage URIs to collect from. When set, tejolote collects **only** from these and skips the run's automatic GitHub Actions artifacts | `""` |
| `expand-artifacts` | Unpack GitHub Actions artifact archives and attest each contained file; `false` attests each archive as one subject | `true` |
| `artifacts-filter` | Glob (path.Match) matched against artifact names; only matching artifacts are attested (all sources) | `""` |
| `dependencies` | Comma-separated dependency URIs to record | `""` |
| `timeout` | Max time to wait for watched build jobs (Go duration, `0` disables) | `20m` |
| `tejolote-version` | Released tejolote version to download and run | `v0.5.0` |
| `verify` | Verify the downloaded tejolote binary with the `ampel/verify` action against its signed SLSA provenance | `true` |
| `policy` | Ampel policy locator applied when verifying the download | pinned `slsa/slsa-build-point` |
| `build-point` | Expected source repository (VCS URI) the default policy checks in the provenance | `git+ssh://github.com/kubernetes-sigs/tejolote` |

## Outputs

| Name | Description |
|------|-------------|
| `attestation` | Path to the generated provenance attestation file |

## Permissions

The workflow job running this action needs the following permissions:

```yaml
permissions:
  id-token: write   # Required for Sigstore keyless signing
  contents: read    # Required to read repository content
  actions: read     # Required to read workflow run data and artifacts
```
