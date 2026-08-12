# unpack/sbom/image

A reusable GitHub Action that generates SBOMs (Software Bill of Materials) of
container images using [unpack](https://github.com/carabiner-dev/unpack).

The action runs `unpack image` for each reference it is given: the image is
pulled, its layers are squashed into the filesystem a running container would
see, and the operating system packages installed in it (apk, dpkg and rpm
databases, including distroless images) are extracted into an SPDX or CycloneDX
SBOM. Multi-arch references produce a single SBOM with the index at the top and
one node per platform image, each carrying its own packages.

The SBOMs can optionally be wrapped in in-toto attestations and signed into
sigstore bundles using the workflow's own identity, which is what makes the
action useful right after an image build step in CI.

> [!IMPORTANT]
> This action requires a release of unpack that ships the `unpack image`
> command. Use the `unpack-version` input to select it until the version
> pinned by [`install/unpack`](../../../install/unpack) catches up.

## Usage

```yaml
- uses: carabiner-dev/actions/unpack/sbom/image@36a39ef667efe7112df8b1a534a4e37f35fad6fd # v1.2.6
  with:
    images: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
```

With no other inputs, the action will:

1. Install `unpack` into the runner
2. Pull each image and extract its installed packages
3. Write one SPDX SBOM per image to a temporary directory
4. Expose the generated paths through the `files` output

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `images` | Yes | - | Newline-separated list of OCI references to generate SBOMs for (e.g. `alpine:3.21`, `ghcr.io/org/app@sha256:...`). |
| `files` | No | `false` | Include the package file lists in the generated SBOMs. |
| `format` | No | `spdx` | SBOM format: `spdx` or `cyclonedx` (also accepts `cdx`). |
| `attest` | No | `false` | Wrap the generated SBOMs in in-toto attestations. |
| `sign` | No | `false` | Sign the attestations into sigstore bundles (implies `attest`). |
| `output-path` | No | `""` | Directory where the generated SBOMs will be written. When empty, a temporary directory is created automatically. |
| `push-to-release` | No | `""` | When set, upload the generated SBOMs to the GitHub release matching this tag (e.g. `v1.2.3`). Requires `GH_TOKEN` to be set in the environment. |
| `unpack-version` | No | `""` | Version of unpack to install. Must be a release that ships the `unpack image` command. When empty, the version pinned by `install/unpack` is used. |

## Outputs

| Output | Description |
| --- | --- |
| `files` | Newline-separated list of generated SBOM file paths |

## Permissions

Signing uses the job's workload identity, so `sign: 'true'` requires the job to
grant `id-token: write`. The action fails early with a clear error when the
permission is missing.

When using `push-to-release`, the token set in `GH_TOKEN` must have
`contents: write` permission to upload assets to the GitHub release.

## Private registries

`unpack` resolves registry credentials through the standard Docker keychain, so
pulling from a private registry only requires logging in before this action
runs, for example with `docker/login-action`. Public images need no
authentication.

## Filename Convention

One file is written per image reference. The reference is sanitized into the
filename by replacing every character outside `[A-Za-z0-9._-]` with a dash and
collapsing repeated dashes:

```
{sanitized-image-reference}.spdx.json
```

The extension reflects what was requested:

| Inputs | Extension |
| --- | --- |
| default | `.spdx.json` |
| `attest: 'true'` | `.spdx.intoto.json` |
| `sign: 'true'` | `.spdx.bundle.json` |

When the CycloneDX format is used, `spdx` is replaced with `cdx` in all of the
above.

**Examples:**

| Image reference | Filename |
| --- | --- |
| `alpine:3.21` | `alpine-3.21.spdx.json` |
| `ghcr.io/carabiner-dev/unpack:v0.2.1` | `ghcr.io-carabiner-dev-unpack-v0.2.1.spdx.json` |
| `ghcr.io/org/app@sha256:abc123` | `ghcr.io-org-app-sha256-abc123.spdx.json` |

References that sanitize to the same name overwrite each other; the action
warns when it replaces a file that already exists.

## Examples

### Generate an SBOM of a public image

```yaml
steps:
  - uses: carabiner-dev/actions/unpack/sbom/image@36a39ef667efe7112df8b1a534a4e37f35fad6fd # v1.2.6
    with:
      images: alpine:3.21
```

### Generate SBOMs of several images at once

```yaml
steps:
  - uses: carabiner-dev/actions/unpack/sbom/image@36a39ef667efe7112df8b1a534a4e37f35fad6fd # v1.2.6
    with:
      images: |
        ghcr.io/${{ github.repository }}:${{ github.ref_name }}
        ghcr.io/${{ github.repository }}-debug:${{ github.ref_name }}
      output-path: sboms/
```

### CycloneDX format with package file lists

```yaml
steps:
  - uses: carabiner-dev/actions/unpack/sbom/image@36a39ef667efe7112df8b1a534a4e37f35fad6fd # v1.2.6
    with:
      images: alpine:3.21
      format: cyclonedx
      files: 'true'
```

### Attest the SBOM of a freshly built image

```yaml
steps:
  - id: build
    run: |
      docker build -t ghcr.io/${{ github.repository }}:${{ github.sha }} .
      docker push ghcr.io/${{ github.repository }}:${{ github.sha }}

  - uses: carabiner-dev/actions/unpack/sbom/image@36a39ef667efe7112df8b1a534a4e37f35fad6fd # v1.2.6
    with:
      images: ghcr.io/${{ github.repository }}:${{ github.sha }}
      attest: 'true'
      output-path: sboms/
```

### Sign the attestation with the workflow identity

```yaml
jobs:
  sbom:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # required to sign with the job's identity
      contents: read
    steps:
      - uses: carabiner-dev/actions/unpack/sbom/image@36a39ef667efe7112df8b1a534a4e37f35fad6fd # v1.2.6
        with:
          images: ghcr.io/${{ github.repository }}:${{ github.sha }}
          sign: 'true'
          output-path: sboms/
```

### Pull from a private registry

```yaml
steps:
  - uses: docker/login-action@5e57cd118135c172c3672efd75eb46360885c0ef # v3.6.0
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}

  - uses: carabiner-dev/actions/unpack/sbom/image@36a39ef667efe7112df8b1a534a4e37f35fad6fd # v1.2.6
    with:
      images: ghcr.io/${{ github.repository }}:${{ github.sha }}
```

### Upload the SBOMs to a GitHub release

```yaml
steps:
  - uses: carabiner-dev/actions/unpack/sbom/image@36a39ef667efe7112df8b1a534a4e37f35fad6fd # v1.2.6
    with:
      images: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
      output-path: /tmp
      push-to-release: ${{ github.ref_name }}
    env:
      GH_TOKEN: ${{ github.token }}
```

### Upload the SBOMs as artifacts

```yaml
steps:
  - uses: carabiner-dev/actions/unpack/sbom/image@36a39ef667efe7112df8b1a534a4e37f35fad6fd # v1.2.6
    id: sbom
    with:
      images: ghcr.io/${{ github.repository }}:${{ github.sha }}
      output-path: sboms/

  - uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
    with:
      name: image-sboms
      path: sboms/
```

## See Also

- [`unpack/sbom/source`](../source) — SBOMs of the codebases in the repository
  source, discovered by `unpack ls`.
