#!/usr/bin/env bash
# Prototype coordinators are independently reviewed work. Until then, this
# verifies their trusted-launcher boundary without emulating a managed run.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
bash "$root/scripts/test-managed-evidence-client.sh"
bash "$root/scripts/test-managed-evidence-reconciliation.sh"
for ticket in AST-H001 PATH-H002 GIT-L001 ASSET-I001 PKG-M001; do
  rg -Fq "${ticket})" "$root/scripts/managed-evidence.sh"
done
! rg -Fq 'test-collect' "$root/scripts/managed-evidence.sh"
printf 'managed-evidence coordinator boundary tests passed\n'
