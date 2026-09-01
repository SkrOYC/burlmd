#!/usr/bin/env bash
# Evaluation-only coverage for every hosted role system. This catches a Linux
# package leaking into macOS before a hosted runner spends minutes provisioning.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
for system in x86_64-linux aarch64-darwin x86_64-darwin; do
  (cd "$root" && ./scripts/ci-devenv.sh devenv eval --system "$system" packages >/dev/null)
done
