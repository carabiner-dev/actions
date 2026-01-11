# Carabiner Actions

This repository contains reusable GitHub Actions for various tools in the
Carabiner ecosystem. These actions help streamline security policy verification,
attestation management, and supply chain security workflows.

## Actions

### ampel/verify

The `ampel/verify` action verifies a subject (file or hash) against a security
policy using the 🔴🟡🟢 AMPEL supply chain policy engine. This action evaluates
whether a given artifact meets your defined security requirements by analyzing
its attestations against a policy.

#### Usage

```yaml
- uses: carabiner-dev/actions/ampel/verify@v1.0.0
  with:
    policy: 'path/to/policy.yaml'   # URI or path to p[policy code]
    subject: 'path/to/artifact'     # or digest, eg sha256:98349875bf3e09...
    collector: 'github'             # Collectors used to retrieve attestations
```

#### Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `policy` | Yes | - | Path to the security policy file to evaluate against |
| `subject` | Yes | - | Path to a file or hash (algo:value) to use as verification subject |
| `collector` | Yes | - | Collector to load to read attestations (e.g., 'jsonl', 'github', 'coci', etc) |
| `attest` | No | `true` | Attest the policy evaluation results |
| `attest-format` | No | `ampel` | Format of the results attestation |
| `results-path` | No | `ampel.intoto.json` | Path to store the results attestation |
| `push-attestation` | No | `false` | Pushes the attestation to the GitHub attestations store |
| `attestation` | No | `""` | Comma separated list of additional attestations to ingest |
| `signer` | No | `""` | Comma separated list of expected signer identity slugs |
| `fail` | No | `true` | Fail the workflow if the policy fails |

#### Examples

**Basic verification:**

```yaml
- uses: carabiner-dev/actions/ampel/verify@v1.0.0
  with:
    policy: '.ampel/policy.yaml'
    subject: 'path/to/binary'
    collector: 'github'
```

**Verification with custom attestations:**

```yaml
- uses: carabiner-dev/actions/ampel/verify@v1.0.0
  with:
    policy: '.ampel/policy.yaml'
    subject: 'sha256:abc123...'
    collector: 'oci'
    attestation: 'sbom.json,provenance.json'
    signer: 'github-actions,my-org'
```

**Verification with attestation push:**

```yaml
- uses: carabiner-dev/actions/ampel/verify@v1.0.0
  with:
    policy: '.ampel/policy.yaml'
    subject: 'path/to/artifact'
    collector: 'github'
    attest: 'true'
    push-attestation: 'true'
    results-path: 'verification-results.json'
```

**Verification without failing the workflow:**

```yaml
- uses: carabiner-dev/actions/ampel/verify@v1.0.0
  with:
    policy: '.ampel/policy.yaml'
    subject: 'path/to/artifact'
    collector: 'github'
    fail: 'false'
```

### Available Installers

| Action | Description |
| --- | --- |
| `install/ampel` | Installs the 🔴🟡🟢 AMPEL policy engine into the runner environment |
| `install/bnd` | Installs the Carabiner bnd attestation utility into the runner environment |
| `install/beaker` | Installs the Carabiner beaker test attester into the runner environment |
| `install/snappy` | Installs the Carabiner snappy API snapshotter into the runner environment |
| `install/revex` | Installs the OpenVEX revex document fixer into the runner |
| `install/unpack` | Installs the Carabiner unpack dependency analyzer to the runner environment |
