#!/usr/bin/env bash
# CI obtains its helper closure from the exact devenv input recorded in
# devenv.lock; workflows never select a runner-provided Flutter/Dart toolchain.
set -euo pipefail
readonly devenv_rev=b1df4c7e27423c6c7d4737e78bce2fd84c4c0962
exec nix run "github:cachix/devenv/$devenv_rev" -- shell -- "$@"
