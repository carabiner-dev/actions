# drop/install

Installs an app from its GitHub release with [drop](https://github.com/carabiner-dev/drop).
drop verifies the artifact against the security policies its publisher
defines, evaluated with AMPEL against the attestations shipped with the
release, before it lands in the runner. No policy, no install.

## Usage

```yaml
- uses: carabiner-dev/actions/drop/install@<commit> # pin to a release commit
  with:
    app: sigstore/cosign
    version: v3.1.3
```

The binary lands in `$HOME/.carabiner/bin`, which is added to the `PATH`, so
later steps can call it by name. drop itself is installed under
`$HOME/.carabiner/tools/drop`, so the app being installed may be drop.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `app` | Yes | - | App to install: `org/repo`, `github.com/org/repo`, or `org/repo#toolname` when the binary is not named after the repository |
| `version` | No | `""` | Release tag to install; the latest stable release when empty |
| `policy-repo` | No | `""` | Alternative policy source: a GitHub repository (URL or slug) or a local checkout path |
| `insecure` | No | `false` | Skip verification and install the artifact as published |
| `type` | No | `""` | Artifact type to install when the release offers several: `binary`, `package` or `archive` |
| `install-dir` | No | `$HOME/.carabiner` | Directory to install into, as a `$HOME`-relative or POSIX-style path; binaries go to its `bin/` subdirectory |
| `drop-version` | No | `""` | drop version to install; defaults to the drop installer's pin |
| `token` | No | `${{ github.token }}` | Token for drop's GitHub API calls, exported as `GITHUB_TOKEN`; anonymous calls are rate limited |

## Where policies come from

drop reads the publisher's policies from the `.github` repository of the
app's organization, under `ampel/policies/release/<repo>/` and
`ampel/policies/release/_/`, and falls back to the community policies in
[policylabs/oss](https://github.com/policylabs/oss). `policy-repo` replaces
that source, for example to verify with policies of your own before the
publisher ships any.

When a project has no policies, or none of them applies to the release, the
step fails with the options drop offers: another policy source, or
`insecure: 'true'` to install without verifying. Prefer asking for community
policies with `drop request org/repo` over going insecure.

## Examples

Install the latest stable release, verified against the publisher's policies:

```yaml
- uses: carabiner-dev/actions/drop/install@<commit>
  with:
    app: carabiner-dev/drop
```

Verify with your own policies while a project has none:

```yaml
- uses: carabiner-dev/actions/drop/install@<commit>
  with:
    app: goreleaser/goreleaser
    version: v2.18.1
    policy-repo: my-org/release-policies
```

Use drop as a plain installer, skipping verification:

```yaml
- uses: carabiner-dev/actions/drop/install@<commit>
  with:
    app: goreleaser/goreleaser
    insecure: 'true'
```

Install a system package instead of the bare binary on Linux runners:

```yaml
- uses: carabiner-dev/actions/drop/install@<commit>
  with:
    app: sigstore/gitsign
    type: package
```
