#!/usr/bin/env bash
# Execute each workflow's inline installer check against disposable Nix profiles.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/burlmd-ci-nix-interface.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
readonly system_path=$PATH
readonly bash_bin=$(command -v bash)

fail() {
  echo "$1" >&2
  exit 1
}

workflow_step_body() {
  local workflow=$1 step_name=$2 occurrence=${3:-1}
  awk -v step_name="$step_name" -v occurrence="$occurrence" '
    $0 == "      - name: " step_name { seen++; in_step = seen == occurrence; next }
    in_step && $0 == "        run: |" { in_run = 1; next }
    in_run && /^      - / { exit }
    in_run {
      sub(/^          /, "")
      print
    }
  ' "$workflow"
}

write_tool() {
  local path=$1 name=$2 output=$3
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'printf '\''%%s\\n'\'' "$*" > "${CALL_LOG:?}/%s"\n' "$name"
    printf 'printf '\''%%s\\n'\'' %q\n' "$output"
  } > "$path"
  chmod +x "$path"
}

write_path_resolver() {
  local path=$1
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' '[[ $1 == -c ]]'
    printf '%s\n' 'printf '\''%s\\n'\'' "$*" > "${CALL_LOG:?}/python3"'
    printf '%s\n' 'target=${!#}'
    printf '%s\n' 'realpath "$target"'
  } > "$path"
  chmod +x "$path"
}

make_profile() {
  local profile=$1 nix_output=$2 nix_store_output=$3 layout=${4:-shared}
  local package="$profile-package"
  local alternate_package="$profile-alternate-package"
  mkdir -p "$profile/bin" "$package/bin" "$alternate_package/bin" "$profile/calls"
  write_tool "$package/bin/nix" nix "$nix_output"
  write_tool "$package/bin/nix-store" nix-store "$nix_store_output"
  write_tool "$alternate_package/bin/nix-store" nix-store "$nix_store_output"
  write_path_resolver "$profile/bin/python3"
  ln -s "$package/bin/nix" "$profile/bin/nix"
  case $layout in
    shared) ln -s "$package/bin/nix-store" "$profile/bin/nix-store";;
    split) ln -s "$alternate_package/bin/nix-store" "$profile/bin/nix-store";;
    external-store) :;;
    *) fail "unknown Nix profile layout: $layout";;
  esac
}

run_post_install_check() {
  local body=$1 profile=$2 extra_path=${3:-}
  local rewritten=${body//nix_profile=\/nix\/var\/nix\/profiles\/default/nix_profile=$profile}
  CALL_LOG="$profile/calls" PATH="$profile/bin${extra_path:+:$extra_path}:$system_path" \
    "$bash_bin" -euo pipefail -c "$rewritten"
}

assert_post_install_rejected() {
  local label=$1 body=$2 profile=$3 extra_path=${4:-}
  if run_post_install_check "$body" "$profile" "$extra_path" >/dev/null 2>&1; then
    fail "installer interface accepted mutation: $label"
  fi
}

assert_preinstalled_rejected() {
  local body=$1 profile=$2
  if CALL_LOG="$profile/calls" PATH="$profile/bin:$system_path" "$bash_bin" -euo pipefail -c "$body" >/dev/null 2>&1; then
    fail "preinstalled Nix check accepted a Nix executable"
  fi
}

workflows=(
  "$root/.github/workflows/ci.yml"
  "$root/.github/workflows/ci-role-linux-x86-64.yml"
  "$root/.github/workflows/ci-role-macos-26-arm64.yml"
  "$root/.github/workflows/ci-role-macos-15-arm64.yml"
)

for workflow in "${workflows[@]}"; do
  site_count=$(rg -Fc '      - name: Verify action-installed Nix interface' "$workflow")
  [[ $site_count -gt 0 ]] || fail "$workflow is missing an executable Nix installer interface check"
  for ((site_index = 1; site_index <= site_count; site_index++)); do
    preinstall_body=$(workflow_step_body "$workflow" 'Reject preinstalled Nix' "$site_index")
    post_install_body=$(workflow_step_body "$workflow" 'Verify action-installed Nix interface' "$site_index")
    [[ -n $preinstall_body && -n $post_install_body ]] || {
      fail "$workflow is missing Nix installer interface site $site_index"
    }

    profile="$tmp/$(basename "$workflow")-$site_index-positive"
    make_profile "$profile" 'nix (Nix) 2.35.2' 'nix-store (Nix) 2.35.2'
    run_post_install_check "$post_install_body" "$profile"
    [[ $(<"$profile/calls/nix") == '--version' ]] || fail "$workflow does not invoke nix --version"
    [[ $(<"$profile/calls/nix-store") == '--version' ]] || fail "$workflow does not invoke nix-store --version"
    assert_preinstalled_rejected "$preinstall_body" "$profile"

    wrong_nix_profile="$tmp/$(basename "$workflow")-$site_index-wrong-nix"
    make_profile "$wrong_nix_profile" 'nix (Nix) 2.35.1' 'nix-store (Nix) 2.35.2'
    assert_post_install_rejected changed-nix-version "$post_install_body" "$wrong_nix_profile"

    missing_nix_profile="$tmp/$(basename "$workflow")-$site_index-missing-nix"
    make_profile "$missing_nix_profile" '' 'nix-store (Nix) 2.35.2'
    assert_post_install_rejected missing-nix-version "$post_install_body" "$missing_nix_profile"

    wrong_store_profile="$tmp/$(basename "$workflow")-$site_index-wrong-store"
    make_profile "$wrong_store_profile" 'nix (Nix) 2.35.2' 'nix-store (Nix) 2.35.1'
    assert_post_install_rejected changed-nix-store-version "$post_install_body" "$wrong_store_profile"

    split_profile="$tmp/$(basename "$workflow")-$site_index-split-profile"
    make_profile "$split_profile" 'nix (Nix) 2.35.2' 'nix-store (Nix) 2.35.2' split
    assert_post_install_rejected split-resolved-profile "$post_install_body" "$split_profile"

    external_store_profile="$tmp/$(basename "$workflow")-$site_index-external-store-profile"
    make_profile "$external_store_profile" 'nix (Nix) 2.35.2' 'nix-store (Nix) 2.35.2' external-store
    mkdir -p "$external_store_profile-external/bin"
    write_tool "$external_store_profile-external/bin/nix-store" nix-store 'nix-store (Nix) 2.35.2'
    assert_post_install_rejected external-nix-store-profile "$post_install_body" "$external_store_profile" "$external_store_profile-external/bin"
  done
done
