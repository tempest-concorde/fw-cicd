# fw-cicd - Flight Wall CI/CD Shared Workflows

Reusable GitHub Actions workflows and composite actions for the Flight Wall project.

## Purpose

This repository provides DRY (Don't Repeat Yourself) CI/CD components consumed by all `fw-*` repositories, ensuring consistent build, test, sign, and release processes across the entire project.

## Contents

### Reusable Workflows

Located in `.github/workflows/`:

- **build-container.yml** - Docker Buildx per-architecture build with Trivy scanning and GHCR push
- **build-bootc.yml** - UBI9 + buildah bootc image build with parameterized smoke tests (ARM64)
- **cosign-sign-verify.yml** - Key-based or keyless cosign signing with verification
- **commitlint.yml** - PR title validation via commitlint
- **merge-manifest.yml** - Multi-arch manifest creation and cosign signing (key-based or keyless)
- **sbom-attest.yml** - SBOM generation (CycloneDX) and cosign attestation (key-based or keyless)
- **semantic-release.yml** - Conventional commits → semantic versioning (global or local config)

### Composite Actions

Located in `actions/`:

- **cosign-sign** - Cosign image signing (key-based or keyless OIDC)
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

  sbom:
    needs: merge-manifest
    uses: tempest-concorde/fw-cicd/.github/workflows/sbom-attest.yml@main
    with:
      registry: ghcr.io
      image_name: tempest-concorde/fw-app
      image_digest: ${{ needs.merge-manifest.outputs.digest }}
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  # SLSA provenance must be called directly - it's a reusable workflow that cannot be wrapped
  provenance:
    needs: merge-manifest
    permissions:
      actions: read
      id-token: write
      packages: write
    uses: slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@v2.1.0
    with:
      image: ghcr.io/tempest-concorde/fw-app
      digest: ${{ needs.merge-manifest.outputs.digest }}
      registry-username: ${{ github.actor }}
    secrets:
      registry-password: ${{ secrets.GITHUB_TOKEN }}
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
