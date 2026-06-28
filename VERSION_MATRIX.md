# VERSION MATRIX

## Versioning model (current in-repo behavior)

- The Kit currently uses environment defaults in `.env.example`:
  - `NEXUS_IMAGE=nexusiq-nexus:local`
  - `AEON_IQ_IMAGE=nexusiq-aeon:local`
- `docker-compose.yml` pins only infrastructure/runtime images and build contexts:
  - `postgres` uses `pgvector/pgvector:pg16`
  - `aeon` and `nexus-agentd`/`nexus-mcp` are built from `AEON_BUILD_CONTEXT` and `NEXUS_BUILD_CONTEXT`.
- `install.sh` vendors source trees:
  - `NEXUSIQ_VENDOR_NEXUS` (or default clone of `adaptiveliquidity/Nexus`)
  - `NEXUSIQ_VENDOR_AEON` (or default clone of `adaptiveliquidity/AEON-IQ`)
- `install.sh` does pin Nexus checkout by default via:
  - `NEXUSIQ_NEXUS_REF=${NEXUSIQ_NEXUS_REF:-85780b8a1d306d08e8ef333a950bdbe0c3d8e76c}`
- `docker/Dockerfile.nexus` pins base image digests:
  - `rust@sha256:c8a94a78f67ec8c4d474ec7f71e0720f21eb7e584e158daec0874cafa7c30e4d`
  - `debian@sha256:96e378d7e6531ac9a15ad505478fcc2e69f371b10f5cdf87857c4b8188404716`
- There is currently no release tag in this repo, so this row is seeded as the **initial alpha baseline**.

| NexusIQ kit version | Nexus version | AEON-IQ version | Notes |
|---|---|---|---|
| `initial-alpha` | `85780b8a1d306d08e8ef333a950bdbe0c3d8e76c` | `TBD (vendored as ./vendor/aeon-iq via default clone, no commit pin)` | `NEXUS_IMAGE` default `nexusiq-nexus:local`, `AEON_IQ_IMAGE` default `nexusiq-aeon:local`; services: `aeon`, `nexus-agentd`, `nexus-mcp` |

## How to read it

- Read each row as a tested compatibility contract for a concrete Kit release.
- `Nexus version` is the source revision used for the vendored Nexus checkout at install/release time.
- `AEON-IQ version` is the checked-out revision used for `vendor/aeon-iq`.
- `Notes` should include any local image taging used for that release (`NEXUS_IMAGE`, `AEON_IQ_IMAGE`) and any migration or API-model caveats.

## How to update

- Add a new row for every released Kit version at the top of the table.
- Record exact component SHAs used in that release (commit SHA for Nexus and AEON-IQ).
- Include the exact compose/runtime baselines you intentionally changed:
  - pinned image references in `.env`/compose
  - Nexus checkout ref override in `NEXUSIQ_NEXUS_REF`
  - AEON-IQ checkout ref in `NEXUSIQ_VENDOR_AEON` or pinned checkout in `vendor/aeon-iq`
- Keep `README.md` and release notes aligned with the matrix values.
