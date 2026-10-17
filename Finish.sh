#!/usr/bin/env bash
set -euo pipefail

source "Config.env"

# ==============================================================================
# X. In new terminal
# ==============================================================================

systemd-analyze
systemd-analyze critical-chain
systemd-analyze blame | head -n 25 || true
