# bnd/pack

A reusable GitHub Action that packs attestation bundles into a single
[jsonl](https://jsonlines.org/) file with [bnd](https://github.com/carabiner-dev/bnd),
one attestation per line. A jsonl file is the easiest way to move a set of
attestations around: upload it as an artifact, attach it to a release, or hand
it to 🔴🟡🟢 AMPEL through its `jsonl:` collector.

## Usage

```yaml
- uses: carabiner-dev/actions/bnd/pack@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
  with:
    bundles: attestations/
```

With only a directory, the action will:

1. Install `bnd` into the runner
2. Pack every `.json` file at the top level of the directory
3. Write them to `attestations.jsonl`, one attestation per line

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `bundles` | Yes | - | Newline-separated paths to pack: bundle files, directories (every `.json` file at their top level is packed) and `.jsonl` files, whose attestations are appended one per line. |
| `output` | No | `attestations.jsonl` | Path of the jsonl file to write. Parent directories are created as needed; an existing file is replaced. |
| `upload-artifact` | No | `false` | Upload the packed file as a workflow artifact. |
| `artifact-name` | No | `""` | Name of the uploaded artifact. Defaults to the file name of `output`. |
| `bnd-version` | No | `""` | bnd version to install. When empty, the version pinned by `install/bnd` is used. |

## Outputs

| Output | Description |
| --- | --- |
| `attestations` | Path of the packed jsonl file, as given in `output` |
| `count` | Number of attestations in the packed file |

## What gets packed

Every path in `bundles` must exist; the action fails on the first one that
does not. Directories are not searched recursively and only their `.json`
files are packed, without looking inside: keep the directory to attestation
bundles, since a stray SBOM or report would be packed as if it were one. The
action does check that every line of the result is a JSON document and fails
otherwise.

`.jsonl` inputs are merged line by line, which makes it easy to combine
attestations produced elsewhere, such as a provenance file downloaded from
another workflow run, with the bundles of the current job. The `output` file
may itself be one of the inputs.

The action fails when nothing was packed.

## Examples

### Pack the job's attestations and upload them

```yaml
steps:
  - uses: carabiner-dev/actions/bnd/pack@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      bundles: attestations/
      upload-artifact: 'true'
```

### Merge a downloaded jsonl with the job's bundles

```yaml
steps:
  - uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
    with:
      name: source-provenance
      path: /tmp/slsa-source

  - uses: carabiner-dev/actions/bnd/pack@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    with:
      bundles: |
        attestations/
        /tmp/slsa-source/signed_bundle.intoto.jsonl
```

### Verify the packed attestations with AMPEL

```yaml
steps:
  - uses: carabiner-dev/actions/bnd/pack@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    id: pack
    with:
      bundles: attestations/

  - uses: carabiner-dev/actions/ampel/verify@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9
    with:
      subject: sha1:${{ github.sha }}
      collector: jsonl:${{ steps.pack.outputs.attestations }}
      policy: .ampel/policy.yaml
```

### Attach the packed attestations to a release

```yaml
steps:
  - uses: carabiner-dev/actions/bnd/pack@32587e82f960d49b36101e8c45d1956e511965d3 # v1.2.9 # pin to a release commit once tagged
    id: pack
    with:
      bundles: |
        provenance.bundle.json
        sboms/
      output: dist/attestations.jsonl

  - run: gh release upload "${TAG}" "${ATTESTATIONS}"
    env:
      GH_TOKEN: ${{ github.token }}
      TAG: ${{ github.ref_name }}
      ATTESTATIONS: ${{ steps.pack.outputs.attestations }}
```

## See Also

- [`bnd/sign`](../sign) — signs an in-toto statement or predicate; its
  `output` appends to an existing jsonl file, for jobs that build the file
  incrementally instead of packing at the end.
- [`ampel/verify`](../../ampel/verify) — verifies a subject against a policy,
  reading attestations from a `jsonl:` collector among others.
