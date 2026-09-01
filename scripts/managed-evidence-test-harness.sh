#!/usr/bin/env bash
# Non-authoritative fixture harness. It has no network, credential, report
# path, schema-emission, or launcher-substitution surface.
set -euo pipefail

workspace= contracts=
while (($#)); do
  case "$1" in
    --workspace) workspace=$2; shift 2;;
    --contracts) contracts=$2; shift 2;;
    *) printf 'usage: %s --workspace DIR --contracts DIR\n' "$0" >&2; exit 2;;
  esac
done
[[ -n $workspace && -n $contracts && -d $workspace && -d $contracts ]] || exit 2
workspace=$(realpath "$workspace")
[[ $workspace == /tmp/* ]] || { printf 'harness workspace must be temporary\n' >&2; exit 2; }
for contract in ci-evidence.schema.json ci-role-evidence.schema.json provisional-spikes.toml; do
  [[ -f $contracts/$contract && ! -L $contracts/$contract ]] || exit 1
done
# This format intentionally cannot validate as the production aggregate: it
# has no expected identity, role evidence, or accepted status.
jq -cn --arg contracts "$contracts" '{kind:"managed-evidence-test-observation",status:"observed",contracts:$contracts}' >"$workspace/observation.json"
