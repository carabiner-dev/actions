# unpack/sbom

A reusable GitHub Action that generates SBOMs (Software Bill of Materials)
for codebases discovered by [unpack](https://github.com/carabiner-dev/unpack).

The action scans the repository for codebases using `unpack ls`, then runs
`unpack extract` for each one to produce an SBOM in either SPDX or CycloneDX
format.

## Usage

```yaml
- uses: carabiner-dev/actions/unpack/sbom@main
```

That's it. With no inputs, the action will:

1. Install `unpack` into the runner
2. Discover all codebases in the repository
3. Generate an SPDX SBOM for each one
4. Write them to the current directory

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `codebases` | No | `""` | Newline-separated list of codebase IDs to generate SBOMs for (e.g. `golang:.`, `npm:frontend`). When empty, generates for all discovered codebases. |
| `ecosystems` | No | `""` | Newline-separated list of ecosystems to include (e.g. `golang`, `npm`, `rust`). When empty, all ecosystems are included. |
| `ignore` | No | `""` | Newline-separated list of path patterns to pass to `unpack ls --ignore` when discovering codebases. |
| `files` | No | `false` | Include file information in the generated SBOMs. |
| `format` | No | `spdx` | SBOM format: `spdx` or `cyclonedx` (also accepts `cdx`). |
| `output-path` | No | `""` | Directory where generated SBOMs will be written. When empty, a temporary directory is created automatically. |
| `push-to-release` | No | `""` | When set, upload the generated SBOMs to the GitHub release matching this tag (e.g. `v1.2.3`). Requires `GH_TOKEN` to be set in the environment. |

## Permissions

When using `push-to-release`, the token set in `GH_TOKEN` must have `contents: write`
permission to upload assets to the GitHub release.

If you want to sign the generated SBOMs, the workflow also needs `id-token: write`
permission to request an OIDC token for signing.

## Outputs

| Output | Description |
| --- | --- |
| `files` | Newline-separated list of generated SBOM file paths |

## Filename Convention

Generated SBOM filenames follow the pattern:

```
{github-org}-{repo-name}-{codebase-id}.spdx.json
```

Where colons and slashes in the codebase ID are replaced with dashes.

**Examples** (for the `carabiner-dev/unpack` repository):

| Codebase ID | Filename |
| --- | --- |
| `golang:source/golang/testdata/with-replace` | `carabiner-dev-unpack-golang-source-golang-testdata-with-replace.spdx.json` |
| `golang:.` (multiple top-level) | `carabiner-dev-unpack-golang.spdx.json` |
| `golang:.` (only top-level codebase) | `carabiner-dev-unpack.spdx.json` |

When the CycloneDX format is used, the extension is `.cdx.json` instead of `.spdx.json`.

## Examples

### Generate SBOMs for all codebases

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: carabiner-dev/actions/unpack/sbom@main
```

### Generate only for Go and npm ecosystems

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: carabiner-dev/actions/unpack/sbom@main
    with:
      ecosystems: |
        golang
        npm
```

### Generate for specific codebases

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.
  - uses: carabiner-dev/actions/unpack/sbom@main
    with:
      codebases: |
        golang:.
        npm:frontend
```

### CycloneDX format with file information

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.
  - uses: carabiner-dev/actions/unpack/sbom@main
    with:
      format: cyclonedx
      files: 'true'
      output-path: sboms/
```

### Ignore vendor directories

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.
  - uses: carabiner-dev/actions/unpack/sbom@main
    with:
      ignore: |
        vendor
        third_party
```

### Upload SBOMs to a GitHub release

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.

  - uses: carabiner-dev/actions/unpack/sbom@main
    with:
      output-path: /tmp
      push-to-release: ${{ steps.tag.outputs.tag_name }}
    env:
      GH_TOKEN: ${{ github.token }}
```

### Upload SBOMs as artifacts

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.

  - uses: carabiner-dev/actions/unpack/sbom@main
    id: sbom
    with:
      output-path: sboms/

  - uses: actions/upload-artifact@v4
    with:
      name: sboms
      path: sboms/
```
