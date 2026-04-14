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

## Usage

### Minimal (watch all sibling jobs automatically)

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
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
      - uses: carabiner-dev/actions/slsa/generate@360ffa1eb909b0105d4eccb6d6ef337911c34952 # v1.1.6
```

### Watch specific jobs

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
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
      - uses: carabiner-dev/actions/slsa/generate@360ffa1eb909b0105d4eccb6d6ef337911c34952 # v1.1.6
        with:
          watch-jobs: "build, integration-tests"
```

### With additional artifact sources

```yaml
  provenance:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      actions: read
    steps:
      - uses: carabiner-dev/actions/slsa/generate@360ffa1eb909b0105d4eccb6d6ef337911c34952 # v1.1.6
        with:
          artifacts: "oci://ghcr.io/my-org/my-image"
          dependencies: "git+https://github.com/my-org/my-lib@abc123def"
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `sign` | Sign the attestation with Sigstore | `true` |
| `slsa-version` | SLSA predicate version (`1.0` or `0.2`) | `1.0` |
| `output` | Path to write the attestation file | `provenance.intoto.jsonl` |
| `watch-jobs` | Comma-separated job names to watch (empty = all siblings) | `""` |
| `artifacts` | Comma-separated artifact storage URIs | `""` |
| `dependencies` | Comma-separated dependency URIs to record | `""` |

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
