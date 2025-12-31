# WiFi Config Switcher Changelog

## v3.5.0
- **Feature:** Added full support for `meta-hybrid_mount` for KernelSU.
- **Refactor (Magic Mount):** Optimized for `meta-magic_mount` compatibility while supporting hybrid architectures.
- **Aggressive Cleanup:** Live switching now detects and unmounts any existing mounts (including those from meta-magic_mount) before re-applying to prevent stacking.
- **Path Independence:** Improved path discovery to handle non-standard module locations used by hybrid mounting systems.

## v3.4.4
- **Refactor (Magic Mount):** Optimized for `meta-magic_mount` compatibility, moving towards traditional file-mirroring logic for KernelSU.
- **Path Independence:** Scripts now dynamically determine the module directory at runtime (`readlink -f "$0"`), ensuring compatibility with custom mount points.
- **Aggressive Cleanup:** Live switching now detects and unmounts any existing mounts (including those from meta-magic_mount) before re-applying to prevent stacking.
- **SUSFS Awareness:** Added detection and safe handling for SUSFS environments.

## v3.4.3
# warning ⚠️ 
- **NotFixed:**New custom configuration (Could not load existing settings due to isolation) This is not fixed yet. Don't expect soon!
- **WebUI:** Improved resilience by re-checking the fallback file immediately after executing the backend script.
- **Boot:** Optimized `post-fs-data.sh` execution order to ensure the fallback file is correctly created on first boot/install.
...