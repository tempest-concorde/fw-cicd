# fw-cicd - Flight Wall CI/CD Shared Workflows

Reusable GitHub Actions workflows and composite actions for the Flight Wall project.

## Purpose

This repository provides DRY (Don't Repeat Yourself) CI/CD components consumed by all `fw-*` repositories, ensuring consistent build, test, sign, and release processes across the entire project.

## Contents

### Reusable Workflows

Located in `.github/workflows/`:

- **build-container.yml** - Per-architecture container build with Trivy scanning and GHCR push
- **merge-manifest.yml** - Multi-arch manifest creation and cosign signing
- **slsa-provenance.yml** - SBOM generation (CycloneDX) and SLSA build provenance attestation
- **semantic-release.yml** - Conventional commits → semantic versioning

### Composite Actions

Located in `actions/`:

- **cosign-sign** - Cosign image signing with keyless OIDC
- **trivy-scan** - Container vulnerability scanning with SARIF upload to GitHub Security

## Usage

### In downstream repositories (fw-os, fw-app, etc.)

#### Example: Build and release workflow

```yaml
name: Release Container

on:
  push:
    tags:
      - 'v*'

jobs:
  build-amd64:
    uses: tempest-concorde/fw-cicd/.github/workflows/build-container.yml@main
    with:
      registry: ghcr.io
      image_name: tempest-concorde/fw-app
      platform: linux/amd64
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  build-arm64:
    uses: tempest-concorde/fw-cicd/.github/workflows/build-container.yml@main
    with:
      registry: ghcr.io
      image_name: tempest-concorde/fw-app
      platform: linux/arm64
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  merge-manifest:
    needs: [build-amd64, build-arm64]
    uses: tempest-concorde/fw-cicd/.github/workflows/merge-manifest.yml@main
    with:
      registry: ghcr.io
      image_name: tempest-concorde/fw-app
      tag: ${{ github.ref_name }}
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  provenance:
    needs: merge-manifest
    uses: tempest-concorde/fw-cicd/.github/workflows/slsa-provenance.yml@main
    with:
      image_digest: ${{ needs.merge-manifest.outputs.digest }}
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

#### Example: Semantic release

```yaml
name: Create Release

on:
  push:
    branches:
      - main

jobs:
  release:
    uses: tempest-concorde/fw-cicd/.github/workflows/semantic-release.yml@main
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## SLSA Level 2-3 Compliance

These workflows implement the following SLSA (Supply-chain Levels for Software Artifacts) requirements:

| Requirement | Implementation |
|------------|----------------|
| Source provenance | GitHub OIDC identity, SHA-pinned actions |
| Build provenance | SLSA GitHub Generator attestation |
| Signing | cosign with GitHub OIDC (keyless) |
| SBOM | syft/anchore CycloneDX generation + attestation |
| Vulnerability scanning | Trivy (fail on CRITICAL/HIGH) |
| Hermetic builds | Isolated GitHub-hosted runners |
| Reproducibility | Base image pinned by digest |

## Development

All GitHub Actions used in these workflows are pinned to full SHA commits (not tags) for supply chain security.

To update action versions:
1. Update the SHA in the workflow file
2. Update the comment with the version tag for human readability
3. Test in a downstream repo before merging

## License

Apache License 2.0 - see [LICENSE](LICENSE)
