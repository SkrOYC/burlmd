#!/usr/bin/env bash
# Evaluation-only coverage for every hosted role system. This catches a Linux
# package or Mesa driver environment value leaking into macOS before a hosted
# runner spends minutes provisioning.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
(cd "$root" && ./scripts/ci-devenv.sh devenv eval --system x86_64-linux packages >/dev/null)
for system in aarch64-darwin x86_64-darwin; do
  (cd "$root" && ./scripts/ci-devenv.sh devenv eval --system "$system" packages >/dev/null)
  environment=$(cd "$root" && ./scripts/ci-devenv.sh devenv eval --system "$system" \
    env.BURLMD_MESA_DRI_PATH env.BURLMD_MESA_EGL_VENDOR_PATH)
  [[ $environment != *'/nix/store/'* ]] || {
    echo "Darwin environment leaked Linux Mesa paths for $system" >&2
    exit 1
  }
done
