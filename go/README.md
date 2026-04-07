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
  uses: carabiner-dev/actions/go/versions@main

- name: Set up Go
  uses: actions/setup-go@v5
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
- uses: carabiner-dev/actions/go/check-latest@main
```

With a custom go.mod path:

```yaml
- uses: carabiner-dev/actions/go/check-latest@main
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
- uses: carabiner-dev/actions/go/check-previous@main
```

On failure, the action produces an error like:

```
go.mod is using Go 1.24.5 but the previous supported release is Go 1.25.8.
Please update go.mod to Go 1.25.8.
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
      - uses: actions/checkout@v4
      - id: go-versions
        uses: carabiner-dev/actions/go/versions@main
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
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: ${{ matrix.go-version }}
      - run: go test ./...
```
