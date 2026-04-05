# ampel-bootstrap

This action is the trust anchor for all Carabiner tool installers. It downloads
a **pinned** version of the ampel binary and verifies its integrity against
hardcoded SHA-256 hashes before making it available for use.

Other installer actions (ampel, bnd, beaker, revex) use the bootstrap binary to
verify their downloads against SLSA provenance attestations. The trust chain is:

```
caller pins action @SHA  ─>  hardcoded ampel SHA-256  ─>  bootstrap ampel verifies target via SLSA provenance
```

## Rotating the bootstrap version

When a new ampel version is released and you want to update the trust anchor,
run the included helper script:

```bash
./install/ampel-bootstrap/rotate.sh
```

The script will:

1. Fetch the latest ampel release tag from GitHub.
2. Download all platform binaries to a temp directory.
3. Compute their SHA-256 hashes.
4. Patch `action.yml` in place with the new version and hashes.
5. Print a summary of the changes for review.

You can also pin a specific version:

```bash
./install/ampel-bootstrap/rotate.sh v1.2.0
```

After running the script, review the diff, commit, and open a PR. Once merged,
update all `@main` references in the other install actions to point to the new
commit SHA.

## Why hardcoded hashes?

ampel is the tool that verifies binary integrity, but it can't verify itself
before it exists on the runner. The hardcoded SHA-256 hashes break this
chicken-and-egg problem. The hashes are trusted because the action is pinned by
commit SHA — anyone referencing `carabiner-dev/actions/install/ampel-bootstrap@<sha>`
is explicitly trusting the hashes at that commit.
