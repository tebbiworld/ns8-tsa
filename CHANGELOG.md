# Changelog

## 1.1.0 — 2026-09-19

Alignment with the NethServer module conventions (NethServer/agents skills).

### Security

- **The signing key password is no longer exposed.** It was stored in `state/environment` (mirrored by NS8 to Redis in plain text) and passed to the server as a command line argument, which made it visible in the process list of the node. It now lives in `state/passwords.env` (mode 0600) and reaches the server through a private configuration file (`--config`, mode 0400, owned by the server user). Existing installations are migrated on update; key and certificates do not change.

### Changed

- **Module backup now contains the keys.** New `etc/state-include.conf`: the backup holds the signing key and certificate chain, the archived certificate generations and the secrets file. Before, only the module environment was saved, so a restored authority would have started with a new key.
- **Working restore.** New `restore-module` steps bring the original key back into service and re-apply the settings.
- `update-module` only restarts a running instance.

### Fixed

- Certificate permissions are set through the user namespace. Once the files belonged to the server user, a direct `chmod` by the module user failed, which broke `configure-module` after a restore.

### Added

- Robot Framework tests (install, update from the previous release, backup and restore, each with a real signed and verified timestamp) run on real NS8 nodes through `stephdl/ns8-ci-actions`.

## 1.0.2 — 2026-09-14

### Fixed

- `update-module` now restarts the service, so a new upstream image (automatic releases) or a changed unit takes effect right after the update instead of at the next reboot.

## 1.0.1 — 2026-09-14

- sigstore timestamp-server v2.1.2 → v2.1.3 (automatic upstream update).

