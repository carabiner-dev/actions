# Go Actions

Reusable GitHub Actions for managing Go versions in your projects. These actions
read your project's `go.mod` and the [Go release API](https://go.dev/dl/?mode=json)
to verify your project is using a supported Go version.

## go/versions

Resolves Go version information from three sources: the project's `go.mod`, the
latest stable Go release, and the previous supported Go release. This action is
used internally by `go/check-latest` and `go/check-previous`.

### Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `go-mod-path` | No | `go.mod` | Path to the go.mod file |
| `minor-cooloff-days` | No | `5` | Days a new minor release (`X.Y.0`) must have been out before `X.Y` is reported as the stable line. `0` disables. |
| `patch-cooloff-days` | No | `1` | Days a patch release (`X.Y.Z`, Z>0) must have been out before it is picked over the previous patch of its line. `0` disables. |

### Cooloff periods

Brand-new Go releases occasionally break builds or tooling. By default the action
holds back new releases for a short cooloff period rather than reporting them the
moment they are published:

- A new **minor** line (e.g. `1.27.0`) is only reported as `GO_VERSION_STABLE`
  once it is at least `minor-cooloff-days` old. Until then the previous line
  stays stable and `GO_VERSION_PREVIOUS` moves one line further back.
- A new **patch** (e.g. `1.26.7`) is only picked once it is at least
  `patch-cooloff-days` old; until then the previous patch of that line (`1.26.6`)
  is reported. `X.Y.0` releases are governed by the minor cooloff only.

Release dates are taken from the `Last-Modified` header of each release's source
tarball on [go.dev/dl](https://go.dev/dl/), so no additional services or
credentials are involved. Set both inputs to `0` to always get the newest
releases.

### Outputs

| Output | Example | Description |
| --- | --- | --- |
| `GO_VERSION_PROJECT` | `1.25.8` | Full Go version from go.mod |
| `GO_MINOR_VERSION_PROJECT` | `1.25` | Minor version from go.mod (no patch) |
| `GO_VERSION_STABLE` | `1.26.1` | Latest stable Go release |
| `GO_MINOR_VERSION_STABLE` | `1.26` | Latest stable minor version (no patch) |
| `GO_VERSION_PREVIOUS` | `1.25.8` | Previous supported Go release |
| `GO_MINOR_VERSION_PREVIOUS` | `1.25` | Previous supported minor version (no patch) |

### Usage

```yaml
- name: Resolve Go versions
  id: go-versions
  uses: carabiner-dev/actions/go/versions@5c3fc97584f8e39921fcfefe319a60f0657294a0 # v1.2.8

- name: Set up Go
  uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
  with:
    go-version: ${{ steps.go-versions.outputs.GO_VERSION_STABLE }}
```

## go/check-latest

Checks that the project's `go.mod` references the latest stable Go release
(including patch version). Fails with an actionable error message if the version
doesn't match.

### Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `go-mod-path` | No | `go.mod` | Path to the go.mod file |

### Usage

```yaml
- uses: carabiner-dev/actions/go/check-latest@5c3fc97584f8e39921fcfefe319a60f0657294a0 # v1.2.8
```

With a custom go.mod path:

```yaml
- uses: carabiner-dev/actions/go/check-latest@5c3fc97584f8e39921fcfefe319a60f0657294a0 # v1.2.8
  with:
    go-mod-path: 'src/go.mod'
```

On failure, the action produces an error like:

```
go.mod is using Go 1.25.3 but the latest stable release is Go 1.26.1.
Please update go.mod to Go 1.26.1.
```

## go/check-previous

Checks that the project's `go.mod` references the previous supported Go release
(including patch version). This is useful for projects that intentionally track
the previous release branch rather than the latest. Fails with an actionable
error message if the version doesn't match.

### Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `go-mod-path` | No | `go.mod` | Path to the go.mod file |

### Usage

```yaml
- uses: carabiner-dev/actions/go/check-previous@5c3fc97584f8e39921fcfefe319a60f0657294a0 # v1.2.8
```

On failure, the action produces an error like:

```
go.mod is using Go 1.24.5 but the previous supported release is Go 1.25.8.
Please update go.mod to Go 1.25.8.
```

## go/modtidy

Runs `go mod tidy` and fails if `go.mod` or `go.sum` would change. Useful as a
CI check to ensure committed module files stay in sync with the source. Assumes
Go is already installed on the runner (e.g. via `actions/setup-go`).

### Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `working-directory` | No | `.` | Directory in which to run `go mod tidy` |

### Usage

```yaml
- uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
  with:
    go-version-file: 'go.mod'

- uses: carabiner-dev/actions/go/modtidy@5c3fc97584f8e39921fcfefe319a60f0657294a0 # v1.2.8
```

With a custom working directory:

```yaml
- uses: carabiner-dev/actions/go/modtidy@5c3fc97584f8e39921fcfefe319a60f0657294a0 # v1.2.8
  with:
    working-directory: 'src'
```

On failure, the action prints the diff and an error like:

```
go.mod or go.sum is not tidy. Run 'go mod tidy' locally and commit the result.
```

## Building a Version Matrix

The `go/versions` action is useful for building CI matrices that test against
both supported Go versions:

```yaml
jobs:
  resolve:
    runs-on: ubuntu-latest
    outputs:
      go-versions: ${{ steps.matrix.outputs.go-versions }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - id: go-versions
        uses: carabiner-dev/actions/go/versions@5c3fc97584f8e39921fcfefe319a60f0657294a0 # v1.2.8
      - id: matrix
        run: |
          echo "go-versions=[\"${{ steps.go-versions.outputs.GO_VERSION_STABLE }}\",\"${{ steps.go-versions.outputs.GO_VERSION_PREVIOUS }}\"]" >> "$GITHUB_OUTPUT"

  test:
    needs: resolve
    strategy:
      matrix:
        go-version: ${{ fromJSON(needs.resolve.outputs.go-versions) }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
        with:
          go-version: ${{ matrix.go-version }}
      - run: go test ./...
```
