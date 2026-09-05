---
verification_commands:
  - name: probe
    label: canonical BURL verification for BURL-K009
    command: "./scripts/attest-github-app-token-expiration.sh --client-id \"$BURLMD_GITHUB_APP_CLIENT_ID\" --output .constitution/evidence/BURL-K009/github-app-token-expiration-attestation.json && ./scripts/verify-github-app-registration.sh --manifest config/github-app.release.toml --installation-url \"$BURLMD_GITHUB_APP_INSTALLATION_URL\" --expected-client-id \"$BURLMD_GITHUB_APP_CLIENT_ID\" --require-device-flow --require-private-repository-permissions --forbid-permission workflows --token-expiration-attestation .constitution/evidence/BURL-K009/github-app-token-expiration-attestation.json --max-attestation-age-hours 24 --output .constitution/evidence/BURL-K009/github-app-registration.json && git diff --check"
    exists: false
    owner: BURL-K009
  - name: probe
    label: canonical BURL verification for BURL-O014
    command: "./scripts/attest-github-app-token-expiration.sh --client-id \"$BURLMD_GITHUB_APP_CLIENT_ID\" --output .constitution/evidence/BURL-O014/github-app-token-expiration-attestation.json && ./scripts/verify-github-app-registration.sh --manifest config/github-app.release.toml --installation-url \"$BURLMD_GITHUB_APP_INSTALLATION_URL\" --expected-client-id \"$BURLMD_GITHUB_APP_CLIENT_ID\" --require-device-flow --require-private-repository-permissions --forbid-permission workflows --token-expiration-attestation .constitution/evidence/BURL-O014/github-app-token-expiration-attestation.json --max-attestation-age-hours 24 --output .constitution/evidence/BURL-O014/github-app-registration.json && git diff --check"
    exists: false
    owner: BURL-O014
  - name: test
    label: quoted by BURL-E001
    command: "./scripts/smoke-shot.sh harness-selftest && test -s .qa/harness-selftest.png"
    exists: true
  - name: other
    label: canonical BURL verification for BURL-B004
    command: cargo build --manifest-path rust/Cargo.toml
    exists: true
  - name: test
    label: canonical BURL verification for BURL-B007
    command: "cargo build --manifest-path rust/Cargo.toml && flutter test"
    exists: true
  - name: format
    label: quoted by BURL-M003
    command: "cargo fmt --manifest-path rust/Cargo.toml -- --check && cargo clippy --workspace --all-targets --all-features --manifest-path rust/Cargo.toml -- -D warnings && cargo test --manifest-path rust/Cargo.toml && dart format --output=none --set-exit-if-changed lib test test_driver integration_test && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ! rg -n '\\[DEBUG-' lib rust test scripts && actionlint && ./scripts/assert-ci-matrix.sh --workflow .github/workflows/ci.yml --require-runner ubuntu-24.04 --require-runner macos-26 --require-runner macos-15 --require-role-schema .constitution/tech-spec/contracts/ci-role-evidence.schema.json --require-aggregate-schema .constitution/tech-spec/contracts/ci-evidence.schema.json && ./scripts/assert-managed-evidence-isolation.sh --contract .constitution/tech-spec/contracts/provisional-spikes.toml --sandbox bubblewrap --expected-version 0.11.2 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: canonical BURL verification for BURL-A002
    command: "cargo test --color=always --package rust --lib --manifest-path rust/Cargo.toml"
    exists: true
  - name: test
    label: quoted by BURL-F002
    command: "cargo test --lib --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test test/components/editor_test.dart test/components/selection_test.dart test/components/lifecycle_actions_test.dart test/components/block_editing_test.dart && BURLMD_SMOKE_F002=1 ./scripts/smoke-shot.sh f002-live-preview && dart analyze && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-F003
    command: "cargo test --lib --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test test/components/selection_test.dart test/components/editor_test.dart && BURLMD_SMOKE_F003=1 ./scripts/smoke-shot.sh f003-selection && dart analyze && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-F006
    command: "cargo test --lib --manifest-path rust/Cargo.toml link_completion_limit_is_ten -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml link_completion_limit_is_ten && cargo test --lib --manifest-path rust/Cargo.toml prospective_ghost_completion -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml prospective_ghost_completion && cargo test --lib --manifest-path rust/Cargo.toml resolve_link_target -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml resolve_link_target && cargo test --lib --manifest-path rust/Cargo.toml create_link_target -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml create_link_target && flutter_rust_bridge_codegen generate && flutter gen-l10n && flutter test test/components/link_completion_test.dart test/components/editor_test.dart && BURLMD_SMOKE_F006=1 ./scripts/smoke-shot.sh f006-link-completion && dart analyze && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-F007
    command: "cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_reports_phantom -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_reports_phantom && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_rejects_utf16_surrogate -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_rejects_utf16_surrogate && cargo test --lib --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test test/components/selection_editing_test.dart test/components/text_input_client_test.dart test/components/selection_test.dart && BURLMD_SMOKE_F007=1 ./scripts/smoke-shot.sh f007-range-editing && dart analyze && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-N006
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && ./scripts/verify-second-device-join.sh --private-remote \"$BURLMD_TEST_PRIVATE_REMOTE_URL\" --object-endpoint \"$BURLMD_TEST_S3_ENDPOINT\" --output target/runbooks/clone-k005.json && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: "quoted by BURL-H006, BURL-J001, BURL-J002, BURL-J003, BURL-J004, BURL-J005, BURL-N007, BURL-L004, BURL-L008"
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && dart analyze && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-H004
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh adapt-h004 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-I009
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh adopt-i009 && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-N005
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh asset-i010 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-L007
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh asset-l007 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-K001
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh auth-k001 && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: canonical BURL verification for BURL-P004
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh decide-h011 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-L011
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh delete-l011 && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-N003
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh detach-i012 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-G008
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh edit-g008 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: canonical BURL verification for BURL-P003
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh ext-h010 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-G009
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh find-g009 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-O016
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh health-m004 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-G010
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh hist-g010 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-I003
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh image-i003 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-L006
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh life-l006 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-O002
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh log-m002 && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-N002
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh migrate-i011 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-I004
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh object-i004 && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-H007
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh preflight-h007 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-I006
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh recover-i006 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: canonical BURL verification for BURL-P001
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh repair-h008 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-K003
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh repo-k003 && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-I008
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh rotate-i008 && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: bench
    label: quoted by BURL-L003
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh sched-l003 && cargo run --release --manifest-path rust/Cargo.toml --bin sync-freshness-meter -- --private-remote \"$BURLMD_TEST_PRIVATE_REMOTE_URL\" --local-versions 100 --incoming-versions 100 --offline-cycles 10 --offline-duration-seconds 3600 --output target/sync-meters/sched-l003.json && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-G003
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh state-g003 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-N010
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh state-l009 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-N001
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh sug-l005 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-K002
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh token-k002 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-I005
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh transfer-i005 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-N004
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh unlink-i013 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-O010
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh update-m010 && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-K004
    command: "cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test integration_test/connect_consolidation_flow_test.dart -d linux && dart analyze && git diff --check"
    exists: false
    owner: BURL-M003
  - name: probe
    label: canonical managed verification for BURL-P002
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-P002 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/evidence/BURL-P002/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-P002
  - name: test
    label: "quoted by BURL-I002, BURL-L002"
    command: "cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && ./scripts/check-generated-bindings.sh && git diff --check"
    exists: false
    owner: BURL-M003
  - name: test
    label: "quoted by BURL-H003, BURL-H005, BURL-I007, BURL-L010"
    command: "cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && git diff --check"
    exists: true
  - name: probe
    label: canonical managed verification for BURL-O004
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-O004 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/evidence/BURL-O004/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-O004
  - name: test
    label: canonical BURL verification for BURL-N009
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/run-private-github-canary.sh --private-remote \"$BURLMD_TEST_PRIVATE_REMOTE_URL\" --object-endpoint \"$BURLMD_TEST_S3_ENDPOINT\" --cleanup always --output .constitution/evidence/BURL-N009/canary-n009.json && ./scripts/verify-device-authorization-runbook.sh --require-human-approval --output .constitution/evidence/BURL-N009/device-auth-n009.json && git diff --check"
    exists: false
    owner: BURL-N009
  - name: test
    label: quoted by BURL-G005
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh close-g005 && git diff --check"
    exists: true
  - name: test
    label: quoted by BURL-J007
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh consui-j007 && git diff --check"
    exists: true
  - name: test
    label: quoted by BURL-N011
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh integ-l012 && git diff --check"
    exists: true
  - name: test
    label: quoted by BURL-O005
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh migrate-m005 && git diff --check"
    exists: true
  - name: test
    label: quoted by BURL-G006
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh open-g006 && git diff --check"
    exists: true
  - name: test
    label: quoted by BURL-J006
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh port-j006 && git diff --check"
    exists: true
  - name: test
    label: quoted by BURL-N008
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh remote-k007 && git diff --check"
    exists: true
  - name: test
    label: canonical BURL verification for BURL-P005
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && ./scripts/smoke-shot.sh rescan-h012 && git diff --check"
    exists: true
  - name: probe
    label: canonical managed verification for BURL-G011
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-G011 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/evidence/BURL-G011/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-G011
  - name: test
    label: quoted by BURL-G011 post-matrix common functional check
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && git diff --check"
    exists: false
    owner: BURL-G011
  - name: test
    label: quoted by BURL-G004
    command: "cargo test --manifest-path rust/Cargo.toml && flutter test && dart analyze && BURLMD_SMOKE_TABS_G004=1 ./scripts/smoke-shot.sh tabs-g004 && git diff --check"
    exists: true
  - name: test
    label: quoted by BURL-M015
    command: "cargo test --manifest-path rust/Cargo.toml a_structural_draft_failure_after_tier_two_publication_returns_authoritative_success && ./scripts/repeat-test.sh --count 100 -- cargo test --manifest-path rust/Cargo.toml a_structural_draft_failure_after_tier_two_publication_returns_authoritative_success && git diff --check"
    exists: false
    owner: BURL-M015
  - name: test
    label: quoted by BURL-D008
    command: "cargo test --manifest-path rust/Cargo.toml api::ffi_api -- --list | grep -q ': test' && cargo test --manifest-path rust/Cargo.toml api::ffi_api && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings && dart analyze"
    exists: true
  - name: test
    label: quoted by BURL-D005
    command: "cargo test --manifest-path rust/Cargo.toml index:: -- --list | grep -q ': test' && cargo test --manifest-path rust/Cargo.toml index:: && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings"
    exists: true
  - name: test
    label: quoted by BURL-D009
    command: "cargo test --manifest-path rust/Cargo.toml index::query -- --list | grep -q ': test' && cargo test --manifest-path rust/Cargo.toml index::query && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings && dart analyze"
    exists: true
  - name: test
    label: quoted by BURL-D003
    command: "cargo test --manifest-path rust/Cargo.toml markdown:: -- --list | grep -q ': test' && cargo test --manifest-path rust/Cargo.toml markdown:: && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings"
    exists: true
  - name: test
    label: quoted by BURL-D002
    command: "cargo test --manifest-path rust/Cargo.toml okf:: -- --list | grep -q ': test' && cargo test --manifest-path rust/Cargo.toml okf:: && cargo test --manifest-path rust/Cargo.toml -- --skip keyring && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings"
    exists: true
  - name: test
    label: quoted by BURL-D004
    command: "cargo test --manifest-path rust/Cargo.toml workspace::bootstrap -- --list | grep -q ': test' && cargo test --manifest-path rust/Cargo.toml workspace::bootstrap && cargo test --manifest-path rust/Cargo.toml -- --skip keyring && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings"
    exists: true
  - name: test
    label: quoted by BURL-D006
    command: "cargo test --manifest-path rust/Cargo.toml workspace::lifecycle -- --list | grep -q ': test' && cargo test --manifest-path rust/Cargo.toml workspace::lifecycle && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings && dart analyze"
    exists: true
  - name: test
    label: quoted by BURL-D007
    command: "cargo test --manifest-path rust/Cargo.toml workspace::persist -- --list | grep -q ': test' && cargo test --manifest-path rust/Cargo.toml workspace::persist && cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings"
    exists: true
  - name: test
    label: "canonical BURL verification for BURL-B002, BURL-B003"
    command: "cargo test --manifest-path rust/Cargo.toml db::"
    exists: true
  - name: test
    label: canonical BURL verification for BURL-B001
    command: "cargo test --manifest-path rust/Cargo.toml security::"
    exists: true
  - name: other
    label: quoted by BURL-B005
    command: flutter analyze
    exists: true
  - name: build
    label: quoted by BURL-O008
    command: "flutter build macos --release && git diff --check"
    exists: true
  - name: other
    label: "canonical BURL verification for BURL-A001: manual macOS launch acceptance"
    command: "flutter_rust_bridge_codegen generate && cargo build --release --manifest-path rust/Cargo.toml && flutter run -d macos"
    exists: true
  - name: test
    label: quoted by BURL-B006
    command: flutter test
    exists: true
  - name: test
    label: quoted by BURL-E002
    command: "flutter test && ./scripts/smoke-shot.sh e002-workspace-opens"
    exists: true
  - name: test
    label: quoted by BURL-E008
    command: "flutter test && ./scripts/smoke-shot.sh shel-e008"
    exists: true
  - name: test
    label: quoted by BURL-G007
    command: "flutter test && dart analyze && ./scripts/smoke-shot.sh nav-g007 && git diff --check"
    exists: true
  - name: test
    label: quoted by BURL-G002
    command: "flutter test && dart analyze && ./scripts/smoke-shot.sh pref-g002 && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-G001
    command: "flutter test && dart analyze && ./scripts/visual-regression.sh shell-g001 --baseline test/goldens/shell-g001-linux.png --max-different-pixels 0 && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-G001
  - name: test
    label: quoted by BURL-F004
    command: "flutter test test/components/block_editing_test.dart && BURLMD_SMOKE_F004=1 ./scripts/smoke-shot.sh f004-block-editing"
    exists: true
  - name: test
    label: quoted by BURL-E007
    command: "flutter test test/components/draft_recovery_test.dart && ./scripts/smoke-shot.sh e007-draft-recovery"
    exists: true
  - name: test
    label: quoted by BURL-E004
    command: "flutter test test/components/editor_test.dart && ./scripts/smoke-shot.sh e004-editor-mounted"
    exists: true
  - name: test
    label: quoted by BURL-F005
    command: "flutter test test/components/emphasis_shortcuts_test.dart && BURLMD_SMOKE_F005=1 ./scripts/smoke-shot.sh f005-emphasis && dart analyze && git diff --check && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-E005
    command: "flutter test test/components/lifecycle_actions_test.dart && ./scripts/smoke-shot.sh e005-lifecycle"
    exists: true
  - name: test
    label: quoted by BURL-E006
    command: "flutter test test/components/search_panel_test.dart && ./scripts/smoke-shot.sh e006-search"
    exists: true
  - name: test
    label: quoted by BURL-E003
    command: "flutter test test/components/workspace_tree_test.dart && ./scripts/smoke-shot.sh e003-tree"
    exists: true
  - name: other
    label: canonical BURL verification for BURL-A003
    command: "flutter_rust_bridge_codegen generate && cargo build --manifest-path rust/Cargo.toml"
    exists: true
  - name: other
    label: "quoted by BURL-C001, BURL-C002, BURL-C003, BURL-O006, BURL-O009, BURL-O011, BURL-O012, BURL-O013"
    command: git diff --check
    exists: true
  - name: build
    label: quoted by BURL-O007
    command: "nix flake check && nix build .#packages.x86_64-linux.default && git diff --check"
    exists: true
  - name: test
    label: quoted by BURL-D001
    command: "test -s .constitution/spikes/SPK-BURL-D001.md && ! grep -q 'Status: placeholder' .constitution/spikes/SPK-BURL-D001.md && ! grep -q 'To be filled' .constitution/spikes/SPK-BURL-D001.md && git diff --quiet HEAD~1 HEAD -- rust/src"
    exists: false
    owner: BURL-M003
  - name: test
    label: quoted by BURL-F001
    command: "test -s .constitution/spikes/SPK-BURL-F001.md && ! grep -q 'Status: placeholder' .constitution/spikes/SPK-BURL-F001.md && ! grep -q 'To be filled' .constitution/spikes/SPK-BURL-F001.md && git diff --quiet a960e34afb59e46ead601375bbfd6424eb4193ec^ a960e34afb59e46ead601375bbfd6424eb4193ec -- lib rust/src && git diff --check HEAD^ HEAD && flutter test test/components/editor_test.dart test/components/selection_test.dart && dart analyze && ! rg -n '\\[DEBUG-' lib rust test scripts"
    exists: false
    owner: BURL-M003
  - name: probe
    label: quoted by BURL-H001
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-H001 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/prototypes/ast/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-M003
  - name: probe
    label: quoted by BURL-H002
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-H002 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/prototypes/path/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-M003
  - name: probe
    label: quoted by BURL-I001
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-I001 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/prototypes/assets/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-M003
  - name: probe
    label: quoted by BURL-L001
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-L001 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/prototypes/git-analysis/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-M003
  - name: probe
    label: canonical managed verification for BURL-O001
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-O001 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/prototypes/packaging/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-M003
  - name: other
    label: canonical BURL verification for BURL-O006
    command: "Run the accepted production AppImage build and installed probes derived from `SPK-BURL-O001`, then `git diff --check`."
    exists: false
    owner: BURL-O006
  - name: other
    label: quoted by BURL-O009
    command: "Run the accepted release construction and artifact verification commands from final TechSpec, then `git diff --check`."
    exists: false
    owner: BURL-O009
  - name: other
    label: canonical BURL verification for BURL-O011
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-O011 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/evidence/BURL-O011/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-O011
  - name: other
    label: canonical BURL verification for BURL-O012
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-O012 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/evidence/BURL-O012/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-O012
  - name: other
    label: canonical BURL verification for BURL-O013
    command: "TRUST_ANCHOR_WORKTREE/scripts/managed-evidence.sh run --ticket BURL-O013 --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output EVIDENCE_WORKTREE/.constitution/evidence/BURL-O013/managed-evidence.json && git -C EVIDENCE_WORKTREE diff --check"
    exists: false
    owner: BURL-O013
layout:
  - path: ".agents"
    purpose: Agent skill definitions (Dart/Flutter workflows)
  - path: ".constitution"
    purpose: AI Project Development Framework artifacts
  - path: ".envrc"
    purpose: "direnv entrypoint; activates the devenv shell"
  - path: ".gitignore"
    purpose: migrated from the layout tree
  - path: README.md
    purpose: "Onboarding: how to enter the environment"
  - path: devenv.nix
    purpose: "Developer environment: toolchains, native deps, git hooks"
  - path: devenv.yaml
    purpose: "devenv inputs (nixpkgs, rust-overlay, git-hooks)"
  - path: devenv.lock
    purpose: "Pinned input revisions; the reproducibility boundary"
  - path: rust-toolchain.toml
    purpose: "Rust version pin, read by devenv and by rustup"
  - path: linux
    purpose: Flutter Linux build files (in-scope target)
  - path: macos
    purpose: Flutter macOS build files (in-scope target)
  - path: lib
    purpose: Dart/Flutter UI source code
  - path: lib/main.dart
    purpose: migrated from the layout tree
  - path: lib/src
    purpose: migrated from the layout tree
  - path: lib/src/components
    purpose: Reusable UI blocks
  - path: lib/src/design
    purpose: "Presentation composition, theme, and motion"
  - path: lib/src/providers
    purpose: Riverpod state definitions
  - path: lib/src/rust
    purpose: Auto-generated FRB Dart bindings
  - path: lib/src/screens
    purpose: "Full-screen routes (workspace.dart, login.dart —"
  - path: scripts
    purpose: Repository-owned validation entry points
  - path: scripts/smoke-shot.sh
    purpose: Manual QA gate for every UI ticket (BURL-E001)
  - path: scripts/visual-regression.sh
    purpose: Exact visual gate introduced by BURL-G001
    exists: false
  - path: scripts/managed-evidence.sh
    purpose: Managed evidence client implemented by BURL-M003
    exists: false
  - path: test
    purpose: Dart widget tests
  - path: rust
    purpose: Rust Core Engine source code
  - path: rust/src/frb_generated.rs
    purpose: "Auto-generated FRB Rust bridge; changes with Dart bindings"
  - path: rust/Cargo.toml
    purpose: migrated from the layout tree
  - path: rust/tests
    purpose: Rust integration tests
    exists: false
  - path: rust/src
    purpose: migrated from the layout tree
  - path: rust/src/api
    purpose: "FFI interface exposed to Dart (thin #[frb] wrappers)"
  - path: rust/src/api/auth.rs
    purpose: "OAuth flow, token storage, session state"
  - path: rust/src/api/ffi_api.rs
    purpose: The contract surface
  - path: rust/src/api/simple.rs
    purpose: FRB template init hook (outside the contract)
  - path: rust/src/db
    purpose: rusqlite database management
  - path: rust/src/assets
    purpose: "Planned: Local Asset Store identity, manifest,"
    exists: false
  - path: rust/src/diagnostics
    purpose: "Planned: rotating structured log and export"
    exists: false
  - path: rust/src/draft.rs
    purpose: "Active-draft-state domain: NoteState/NoteMetadata,"
  - path: rust/src/error.rs
    purpose: "Shared AppError, so db/security don't depend on api"
  - path: rust/src/git
    purpose: gix integration
  - path: rust/src/index
    purpose: "Bundle -> SQLite indexer: notes, notes_fts,"
  - path: rust/src/markdown
    purpose: "AST parsing logic; owns the span map (ADR-007)"
  - path: rust/src/okf
    purpose: "OKF v0.2 bundle domain: frontmatter (read and"
  - path: rust/src/export
    purpose: "Planned: stable-revision copy/archive Export"
    exists: false
  - path: rust/src/object_store
    purpose: "Planned: S3-compatible transfer and validation"
    exists: false
  - path: rust/src/provider
    purpose: "Planned: private GitHub App/provider integration"
    exists: false
  - path: rust/src/security
    purpose: OS Keychain root-key integration
  - path: rust/src/sync
    purpose: Debounced background sync scheduler
  - path: rust/src/update
    purpose: "Planned: compatible release-metadata checks"
    exists: false
  - path: rust/src/workspace
    purpose: "bootstrap (init/open, Git repo adoption),"
  - path: rust/src/test_support.rs
    purpose: "#[cfg(test)]-only fixtures shared across unit test modules"
  - path: pubspec.yaml
    purpose: Dart dependencies
  - path: ".github/workflows"
    purpose: "Planned: PR, canary, benchmark, and release gates"
    exists: false
  - path: flake.nix
    purpose: "Planned: release-tagged Nix package entrypoint"
    exists: false
  - path: flake.lock
    purpose: "Planned: release Flake reproducibility boundary"
    exists: false
  - path: nix
    purpose: "Planned: release package modules and checks"
    exists: false
  - path: flutter_rust_bridge.yaml
    purpose: FRB configuration
commit_convention: Conventional Commits
---
# Project Structure & Guidelines

## Provisional research boundary

TechSpec v2.0.1-provisional (translated from reviewed v1.8.7-provisional) permits research code only under `.constitution/prototypes/`. The existing Epic G M0 production exceptions remain unchanged. `BURL-M015` and `BURL-M003` may write production code only for their reproducibility and validation bootstrap. Every other production ticket remains blocked by its own decision evidence and a matching Stage 3 and Stage 4 adaptation. Except for these contract-scoped exceptions, production directories (`lib/`, `rust/`, `linux/`, and `macos/`) are read-only inputs to this research wave.

The five exact prototype roots and verification commands are machine-readable in `contracts/provisional-spikes.toml`. Its allowlist is exhaustive: each Spike may write only its named prototype root and report path. Every unlisted repository path is read-only. Framework bookkeeping may update the owning active Task after the Spike process exits, but that isn't part of the Spike's write authority.

Each harness writes one `results.json` that validates against `contracts/spike-result.schema.json`, records each platform run and exact tool and dependency versions, names its corpus, reports every required measurement, and makes one evidence-backed recommendation. Every gate and measurement names its candidate or the reserved `cross-cutting` value. Every run includes `host.profile` and records `claimedEvidenceClasses`, but that claim is not self-authorizing. The trusted collector maps the run to its authenticated role bundle, rejects a profile runner label that differs from the exact runner label for that role, and then requires ordered equality with that role's expected-identity evidence profile. The harness must also read its own TOML entry and fail unless its result contains exactly the declared candidate names and required gate names, every candidate has attributed outcomes, run IDs are unique, and every required run role is present; JSON Schema alone can't enforce those cross-file constraints. The mandatory result validator semantically parses every timestamp as RFC 3339 and rejects impossible calendar dates rather than trusting the schema's shape pattern. It also resolves each recorded 40- or 64-hex Git revision in the captured checkout and requires it to equal that run's captured revision.

Command execution records exit status and separate standard-output and standard-error artifacts. Before aggregation, the harness verifies that every referenced evidence and artifact path is inside the Spike's write allowlist, exists, matches its byte count and SHA-256 digest, and isn't replaced by a later command. Raw fixtures and measurements stay beside the result. A conclusion without reproducible evidence does not settle an open decision.

Research Tasks stop on a failed safety or fidelity gate. A performance miss is evidence, not permission to weaken the PRD: the result records it and final Product Requirements or Technical Implementation evolution decides the response. A production ticket starts only after its own decision evidence settles its physical contract and Stage 4 adapts that ticket. Unrelated unresolved Spikes don't form a global stop.

## Generated-binding bootstrap checker

The merged base for `BURL-M003` doesn't contain `scripts/check-generated-bindings.sh`. Before any validation gate invokes that path, `BURL-M003` must implement the checker under its existing `scripts/**` scope. The implementation must not import or cherry-pick the coordinating Epic G branch.

The checker must perform these steps in order:

1. Capture a path-sorted SHA-256 manifest and a byte-for-byte backup of `rust/src/frb_generated.rs` and every regular file under `lib/src/rust/**`.
2. Run `flutter_rust_bridge_codegen generate` with the provisional `2.12.0` generator.
3. Capture a second path-sorted SHA-256 manifest. Compare both file sets and every file byte-for-byte. Fail if generation exits nonzero or adds, removes, or changes a generated file.
4. On success, failure, or interruption, restore both generated surfaces exactly to their precheck state. Remove generated files that weren't present before the check, restore files that generation changed or removed, and preserve preexisting modifications.
5. Before exit, verify that both generated surfaces match the precheck manifest. Exit nonzero if restoration or verification fails.

The stale-binding diagnostic names both generated surfaces and instructs the developer to regenerate and review the changes. The checker leaves the precheck working tree unchanged, including when it detects stale bindings.

## Managed validation evidence protocol

`BURL-M003` establishes the managed-validation trust anchor. Its implementation milestone receives local validation, independent milestone review, and pull-request review on `chore/epic-m-ci-foundation`. Rebase-merging that pull request makes the resulting `master` tip the immutable `TRUST_ANCHOR_SHA`. The implementation isn't complete at that merge.

From a clean detached checkout at `TRUST_ANCHOR_SHA`, run the merged pipeline against that same SHA. Put the accepted `.constitution/evidence/BURL-M003/managed-evidence.json`, `.constitution/evidence/BURL-M003/completion.md`, and digest-bearing `.constitution/evidence/BURL-M003/manifest.yaml` on `docs/epic-m-ci-evidence`. The manifest records the exact byte counts and SHA-256 digests of the other two files. That dedicated evidence pull request must contain no other change. `BURL-M003` satisfies no dependency until the evidence pull request receives review and merges. Any later change to a trusted workflow, launcher, evidence schema, or raw CI contract repeats this implementation-review, anchor, validation, and evidence-review sequence.

Normal tickets never run a launcher or workflow from the tested source. Run `./scripts/managed-evidence.sh` from a clean detached checkout of the immutable anchor. The client resolves `refs/heads/master` as `WORKFLOW_SIGNER_SHA`. Before dispatch and during collection, it verifies that every trusted control file at that SHA is byte-for-byte and mode-for-mode identical to `TRUST_ANCHOR_SHA`. It rejects a changed launcher, workflow, evidence schema, or raw CI contract.

The client also resolves `SOURCE_REF`, `TESTED_SOURCE_SHA`, and `BASE_SHA` from `origin`. It requires `BASE_SHA` to be an ancestor of `TESTED_SOURCE_SHA`. The exact Git diff from base to tested source can change only paths in the selected Spike's `write_allowlist`. The check covers additions, deletions, renames, copies, mode changes, symlinks, and submodules. The client repeats this allowlist check during collection. A candidate can't define expected identity or change validation controls.

The one repository-owned entry point is `./scripts/managed-evidence.sh`. `BURL-M003` implements it as a narrow client, not as a general workflow framework. It uses GitHub REST API version `2026-03-10` and the fixed `.github/workflows/ci.yml` file. `GH_TOKEN` must never appear in an argument, log, report, or artifact. The command has exactly two forms:

- `./scripts/managed-evidence.sh run --ticket TICKET_ID --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --output REPORT_JSON` verifies the anchor and source guards. For a managed Spike, it also builds and identifies the locked coordinator before reading `GH_TOKEN`. It then creates canonical expected identity with a fresh run identity of `managed:` plus 32 lowercase hexadecimal digits. The launcher derives the artifact nonce as those exact 32 digits and dispatches the caller on `master`. It requires the dispatch response's exact workflow run ID, waits up to 7,200 seconds for attempt 1, and collects that run. It accepts `BURL-M003` only for the post-merge self-validation where the anchor, signer, tested source, and `master` tip are equal. Other tickets require the merged CI completion record. The observer invocation is `--ticket BURL-P002` with output `.constitution/evidence/BURL-P002/managed-evidence.json`.
- `./scripts/managed-evidence.sh collect --ticket TICKET_ID --trust-anchor-sha TRUST_ANCHOR_SHA --source-ref SOURCE_REF --tested-source-sha TESTED_SOURCE_SHA --base-sha BASE_SHA --run-identity RUN_IDENTITY --run-id RUN_ID --attempt RUN_ATTEMPT --output REPORT_JSON` resumes one dispatched run. It reconstructs the exact expected identity and verifies the returned run, attempt, event, signer, tested-source input, expected-identity bytes, and both guards before it accepts evidence.

`TRUST_ANCHOR_WORKTREE` is the clean detached checkout whose `HEAD` equals `TRUST_ANCHOR_SHA`. `EVIDENCE_WORKTREE` is the separate checkout that will receive the declared evidence-only commit. `SOURCE_REF` is the full pushed `refs/heads/...` reference. `TESTED_SOURCE_SHA`, `BASE_SHA`, and `TRUST_ANCHOR_SHA` are full 40-hex commit SHAs. `BASE_SHA` is the reviewed ticket base: the merged tranche base for the first milestone or the reviewed preceding milestone in the same tranche. `RUN_IDENTITY` is the `managed:` prefix plus the launcher's 32-hex nonce. `ARTIFACT_NONCE` is exactly that lowercase hexadecimal suffix, never an independent input. Semantic validation requires `RUN_IDENTITY` to equal `managed:` plus `ARTIFACT_NONCE`. `RUN_ID` and `RUN_ATTEMPT` identify the dispatched workflow attempt. `REPORT_JSON` is an absolute path under `EVIDENCE_WORKTREE` that matches a declared evidence path. `OUTPUT_DIR` is its parent directory. The launcher rejects output inside the anchor checkout or outside the declared evidence worktree.

GitHub requires a `workflow_dispatch` workflow to exist on the default branch. The REST endpoint accepts a branch or tag as `ref`, not a commit SHA. Therefore the launcher dispatches `master` and verifies its exact signer SHA against the anchor before and after the run. The API version returns `200 OK` with the workflow run ID and URLs. The launcher never discovers a run by recency or branch order.

Before dispatch, the launcher creates canonical `expected-identity.json` bytes. The identity separates `trustAnchorSha`, `workflowSignerSha`, `testedSourceSha`, `baseSha`, `runIdentity`, and its bijectively derived `artifactNonce`. It binds the exact source write allowlist and the selected ticket's complete `requiredEvidenceClasses` mapping. The launcher passes the base64 bytes and their SHA-256 digest as dispatch inputs and retains its local bytes. The trusted caller's static `expected` job decodes and validates those bytes, uploads the expected-identity artifact, and exports its artifact ID and bare action digest. Each role-calling job needs `expected` and passes those outputs as trusted reusable-workflow inputs. The workflow doesn't reconstruct candidate-supplied identity.

The trusted caller and its three static local reusable workflows run from `WORKFLOW_SIGNER_SHA` on `master`. Each role checks out `TESTED_SOURCE_SHA` into a separate data directory with `persist-credentials: false`. It removes checkout authentication before candidate execution. It never loads a workflow, action, launcher, or configuration from the tested checkout. Artifact names use only fixed lowercase prefixes, the fixed role, and `ARTIFACT_NONCE`: expected, candidate, sealed, and sealing-receipt artifacts each have one declared template. This alphabet excludes the pinned upload action's forbidden characters. Collection rejects a run/nonce mismatch, a forbidden character, or any missing, duplicate, extra, or substituted reserved name.

The client writes one aggregate conforming to `contracts/ci-evidence.schema.json` at `REPORT_JSON`, replacing that file atomically. For a managed Spike, it also writes the declared `results.json`. Standard output contains `status`, `runIdentity`, `workflowRunId`, `runAttempt`, `trustAnchorSha`, `workflowSignerSha`, `testedSourceSha`, `result`, and `report`. `result` is null for `BURL-M003`. Diagnostics go to standard error.

Exit status `0` means the report is `accepted` and the managed-Spike result is valid. Exit status `1` means the report is schema-valid but `rejected`. Exit status `2` means arguments, the trust-anchor checkout, dispatch, permissions, interruption, or output failure prevented a schema-valid report. After the service returns a run ID, service, timeout, bundle, guard, staging, coordinator, and result failures produce a rejected report and exit `1`. `run` needs Actions write permission for dispatch plus read permissions for collection. `collect` needs Actions, attestations, and contents read permission.

Managed-Spike collection uses two execution phases. The clean trust-anchor client controls both phases; candidate branches can't replace the client or its coordinator-step contract.

Before acquiring or using GitHub authentication, the preparation phase performs these steps:

1. Resolve the ticket's exact coordinator manifest, lockfile, source tree, build command, and binary path from `contracts/provisional-spikes.toml` at the trusted contract hash.
2. Start with `env -i`, owned empty `HOME`, XDG, Cargo, GitHub CLI, and Git configuration directories, and no inherited file descriptor above standard error.
3. Fetch only locked Cargo dependencies without GitHub, Git, SSH-agent, package-registry, or cloud credentials. This dependency-fetch step doesn't run a build script.
4. Run the declared `cargo build --locked --offline --release` command inside Bubblewrap `0.11.2` with network disabled, source and dependency inputs read-only, and only the build target writable. Candidate build scripts therefore receive no credential, user configuration, repository metadata outside the declared source, or network.
5. Require one regular, non-symlink executable at the declared path. Record its SHA-256 digest with the source-tree, lockfile, toolchain-closure, contract, and build-command digests. Resolve the minimal Nix runtime closure required by this executable plus the pinned shell and core utilities; reject any closure containing Git, the GitHub CLI, SSH, cloud CLIs, or network clients.

Only after preparation succeeds may the authenticated phase obtain `GH_TOKEN` and the workflow identity descriptors. This phase may query the versioned APIs, download artifacts and attestations, verify identity and hashes, and stage verified bytes. It must not invoke Cargo, a build script, a coordinator executable, a candidate shell command, or another executable from the tested source. The trusted client validates the prepared coordinator identity again after staging.

Before coordinator execution, the client closes authentication clients, unsets `GH_TOKEN`, `GITHUB_TOKEN`, Actions OIDC variables, `SSH_AUTH_SOCK`, `GIT_ASKPASS`, package-registry tokens, and common cloud credential variables, and discards every temporary authentication file. The trusted launcher enumerates its open descriptors and closes every descriptor above standard error that isn't in its empty execution allowlist. It verifies closure before it executes Bubblewrap. Bubblewrap supplies namespace, network, and filesystem isolation only. Failure to close a descriptor or establish any namespace or mount rejects the aggregate.

The coordinator sandbox mounts the validated executable and its minimal runtime closure read-only at `/coordinator`, verified role inputs read-only at `/inputs`, and the trusted contract plus schemas read-only at `/contract`. Only `/output` is writable. The sandbox has an owned empty `/home/coordinator`, empty XDG and GitHub CLI configuration directories, and a temporary directory. It doesn't mount the repository, `.git`, the host home, credential stores, sockets, or host configuration. `PATH` contains only the pinned shell and core utilities. Locale is `C.UTF-8`. Git prompts and system, global, and command-supplied credential helpers are disabled even though Git isn't in the execution closure. The only task variables are `COORDINATOR_BIN=/coordinator/bin`, `INPUT_ROOT=/inputs`, `OUTPUT_ROOT=/output`, and `CONTRACT_ROOT=/contract`.

Credential-isolation fixtures inject unique canaries into GitHub, Git, SSH-agent, package-registry, and cloud environment variables and standard configuration paths. The parent also opens a non-`CLOEXEC` descriptor on unique canary bytes. A probe coordinator dumps its environment, checks standard paths, attempts to locate the GitHub CLI and Git, enumerates inherited descriptors, and attempts a network connection. No canary, credential path, client, extra descriptor, or network route may be visible. The same sandbox must run a representative coordinator successfully and produce a valid result from read-only inputs. The aggregate records the executable and closure identities plus every isolation check.

Each role workflow has two static jobs on separate fresh hosted environments. The `candidate` job receives only `contents: read`; all unspecified permissions, including `id-token`, `attestations`, and `actions`, are `none`. A trusted launcher runs every tested-source build, test, probe, and packaging command with owned empty user and configuration directories, closed inherited descriptors, and an explicit environment that omits GitHub tokens, Actions artifact runtime tokens and URLs, OIDC request variables, SSH-agent and askpass state, package-registry tokens, cloud credentials, and Git credential configuration. Candidate commands receive no artifact-runtime authority. After candidate commands finish, the trusted workflow wrapper receives the job-scoped artifact runtime authority needed to upload the untrusted bundle. It records only the role's assigned ticket evidence classes. Canary fixtures prove a representative candidate command can't observe those capabilities and still succeeds.

Candidate output is untrusted. On Linux, the trusted launcher starts candidate commands with `env -i` in a Bubblewrap `0.11.2` private PID namespace. It must prove that a double-fork probe does not survive the teardown lock before upload. Any failed command, required Linux teardown, bundle creation, or upload fails the candidate job. On hosted macOS, the launcher terminates and reaps known test processes and records cleanup failure. That bounded cleanup does not claim zero survivors or lifecycle containment for arbitrary candidate code. The candidate job then creates `ci-role-evidence.json` and the complete deterministic `ci-role-evidence.tar.zst` as untrusted output. After candidate commands finish, the trusted workflow wrapper invokes the pinned upload action with `overwrite: false` and `if-no-files-found: error` for the exact unique candidate artifact name. The wrapper necessarily receives job-scoped artifact runtime authority for that upload. A surviving hosted-macOS process can corrupt this untrusted output or cause an upload denial. It cannot gain seal-only OIDC or attestation authority, and it cannot enter the fresh sealing environment. The wrapper exports the action's artifact ID and bare lowercase 64-hex `artifact-digest` as trusted job outputs.

The `seal` job has `needs: candidate` without an `always()` override and starts on a fresh hosted environment with no shared process namespace, workspace, or writable filesystem. Only the immutable untrusted candidate artifact crosses the boundary. The fresh environment protects seal authority; it doesn't prove lifecycle containment for arbitrary hosted-macOS candidate code. The sealing job downloads the exact unique name and uses only immutable trust-anchor validators to check expected identity, candidate job and hosted label, manifest shape, every internal hash, artifact ID and name, normalized REST digest, safe archive shape, the trusted upload outputs, and the completed candidate job record. It rejects an unexpected member, changed bundle, duplicate reserved name, pre-upload collision, failed candidate, wrong label, or self-hosted label. It never executes candidate bytes.

Only `seal` receives `actions: read`, `contents: read`, `id-token: write`, and `attestations: write`. It creates deterministic `ci-sealed-role-evidence.tar.zst` containing only the unchanged candidate `ci-role-evidence.tar.zst`. It attests and uploads that sealed bundle exactly once under the unique sealed artifact name with `overwrite: false` and `if-no-files-found: error`.

After the upload, `seal` queries the sealed artifact REST object. It requires the REST `digest` to equal `sha256:` plus the pinned action's bare `artifact-digest` output. It then writes `ci-seal-receipt.json` against `contracts/ci-role-evidence.schema.json#/$defs/sealingReceipt`. The receipt records only immutable facts available during the job: run and attempt, `job.check_run_id`, workflow and source identities, role and artifact nonce, the `github-hosted` environment claim, expected, candidate, and sealed artifact identity and digest pairs, and inner and sealed bundle hashes. The receipt has no job status, conclusion, or completion timestamp. The job attests the receipt and uploads it under `managed-evidence-seal-receipt-{role}-{artifactNonce}`. Because the receipt is separate from the sealed bundle that it hashes, neither digest is self-referential.

Candidate-controlled bytes that reserve a sealed or receipt name, corrupt the expected upload inventory, or fail a bundle check cause a fail-closed rejection. Candidate commands lack artifact runtime credentials. After those commands finish, the trusted candidate wrapper receives job-scoped artifact runtime authority to upload the untrusted bundle. Only the fresh sealing environment receives OIDC and attestation authority. The fresh environment keeps candidate bytes away from those capabilities. It doesn't make candidate output trusted or claim universal macOS process containment. Bubblewrap remains the Linux candidate-containment and post-download coordinator boundary.

Release identity is `candidate:` followed by the 40-hex tested source SHA. Build identity is the SHA-256 of an exact input manifest containing the trust anchor, workflow signer, tested source, source diff, base SHA, repository tree, lockfiles, toolchain pins, action pins, and build configuration. Corpus identity is the SHA-256 of the generated corpus manifest. Run identity is `managed:` plus the launcher's lowercase 32-hex nonce. Artifact nonce is exactly the same 32-hex suffix; the service run ID and attempt remain separate origin fields. Required roles are exactly `linux-x86_64`, `macos-26-arm64`, and `macos-15-arm64`. Expected identity assigns one signer and one exact evidence-class array to each role:

- `linux-x86_64`: `.github/workflows/ci-role-linux-x86-64.yml`
- `macos-26-arm64`: `.github/workflows/ci-role-macos-26-arm64.yml`
- `macos-15-arm64`: `.github/workflows/ci-role-macos-15-arm64.yml`

The raw contract defines the following required evidence profiles. Environment capabilities outside the selected row aren't requirements for that run:

| Ticket | `linux-x86_64` | `macos-26-arm64` | `macos-15-arm64` |
| :--- | :--- | :--- | :--- |
| `BURL-M003` | Common functional, managed-evidence protocol, security, isolation, generated-binding check, static analysis, desktop integration | Common functional, managed-evidence protocol, security, static analysis, desktop integration | Common functional, managed-evidence protocol, security, static analysis, desktop integration |
| `BURL-H001` | Common functional, performance, AST measurement | Common functional, performance, AST measurement | Common functional |
| `BURL-H002` | Common functional, filesystem compatibility | Common functional, filesystem compatibility | Common functional |
| `BURL-I001` | Common functional, performance, asset measurement | Common functional, performance, asset measurement | Common functional |
| `BURL-L001` | Common functional, filesystem compatibility, Git protocol | Common functional, filesystem compatibility, Git protocol | Common functional |
| `BURL-O001` | Packaging runtime | Packaging runtime, repeatable construction | Packaging runtime compatibility |
| `BURL-G011` | Common functional, Linux platform regression | Common functional, authoritative macOS visual | Common functional |
| `BURL-P002` | Common functional, performance | Common functional, performance | Common functional |
| `BURL-O004` | Common functional, performance | Common functional, performance | Common functional |

Each signer is a reusable workflow with exactly two role jobs, `candidate` and `seal`, on the same fixed hosted label. `seal` needs the successful `candidate` job and runs on a fresh environment. The trusted caller uses the static same-repository form `./.github/workflows/WORKFLOW_FILE`; expressions and ref suffixes are forbidden in `jobs.<job_id>.uses`. GitHub resolves each local workflow from `WORKFLOW_SIGNER_SHA`, which is the dispatched `master` commit. The expected identity records `job_workflow_ref` on `refs/heads/master` and `job_workflow_sha`. Aggregation requires the static role path and requires `job_workflow_sha` to equal `workflowSignerSha`. It separately requires the complete tested checkout and role manifest to name `testedSourceSha`; those SHAs don't need to match. The trust-surface comparison binds the signer commit to `trustAnchorSha`.

Candidate commands write only their declared results, logs, raw measurements, and handoffs. The candidate job records each relative path, byte count, and SHA-256 digest in `internalArtifacts`. It writes `ci-role-evidence.json` against `contracts/ci-role-evidence.schema.json` and creates one deterministic `ci-role-evidence.tar.zst` containing that manifest and every named file. These bytes remain untrusted until the fresh sealing job validates them. The manifest doesn't contain the bundle digest, artifact ID, upload digest, attestation, or another value assigned after bundling or upload, which prevents a digest cycle.

The sealing receipt can't prove that its own job completed successfully. The authenticated client waits for the workflow attempt to reach a terminal state. For each receipt, the client finds exactly one job API object whose `check_run_url` names `sealingCheckRunId`. It then requires the matching run and attempt, `status=completed`, `conclusion=success`, the static `seal` job position, the fixed hosted label without `self-hosted`, and signed `runner_environment=github-hosted` provenance. Only after these checks does the client construct aggregate `origin.sealingJob`. An in-progress, failed, missing, duplicate, or mismatched seal produces a typed rejected report and no accepted origin.

The client enumerates the exact run's artifacts. For every expected, candidate, and sealed artifact, the pinned upload action output is bare lowercase 64-hex. The REST `digest` and aggregate `artifactDigest` use `sha256:<hex>`. Before the client records an artifact, it requires the REST value to equal `sha256:` plus `uploadActionDigest`; a prefix, case, or byte mismatch produces `artifact-digest-mismatch`. The client verifies the receipt and sealed-bundle attestations, then safely unpacks the sealed bundle's sole `ci-role-evidence.tar.zst` member. It compares every receipt field with the completed run APIs, expected identity, and bundle digests. It safely unpacks the inner bundle, validates the manifest, and verifies every `internalArtifacts` entry before using a result. A missing, extra, duplicate, escaped, size-mismatched, or digest-mismatched outer or inner member rejects the role bundle.

For a managed Spike, every `internalArtifacts.name` is relative to that Spike's prototype root. After verification, the CLI atomically replaces `OUTPUT_DIR/managed-evidence-coordinator` and stages only manifest-named bytes under `roles/ROLE_ID/`, preserving each relative name. The fixed role directories are `linux-x86_64`, `macos-26-arm64`, and `macos-15-arm64`. The CLI rejects absolute paths, traversal, links, name collisions, files outside the ticket allowlist, and any staged byte that differs from its verified manifest entry.

After authentication is gone, the trusted sandbox launcher runs the ticket's ordered `coordinator_steps` from `contracts/provisional-spikes.toml`. Those steps invoke only the prepared `COORDINATOR_BIN` and pinned core utilities against `/inputs`, `/contract`, and `/output`. They don't invoke Cargo, a build script, Git, a network transfer, a manual handoff source, an environment-selected path, or an unstaged role output. `scripts/assert-managed-evidence-isolation.sh` is the required contract fixture: it verifies the pinned Bubblewrap version and namespace probe, preparation-before-auth ordering, coordinator identity recheck, token and configuration canary exclusion, descriptor closure, read-only inputs, output-only writes, forbidden-tool absence, and a failed network probe while a representative coordinator result succeeds. After the client copies the validated machine result, it removes the owned coordinator root. The packaging workflow applies the same bundle verification and staging rules to the macOS 26 construction bundle before the macOS 15 role imports and probes that archive.

The signed provenance must bind the sealing job's exact static reusable-workflow path, `workflowSignerSha`, `refs/heads/master`, invocation run and attempt, and `runner_environment` claim. That claim must equal `github-hosted`; a self-hosted sealing job is rejected even if it supplies the expected custom labels. The receipt's `sealingCheckRunId` comes from the documented `job.check_run_id` context and identifies the post-completion API object without predicting its result. The aggregate retains separate candidate and sealing job observations and artifact facts. The unique run-derived artifact names, trusted upload outputs, `needs` edge, check-run locator, and signed sealing provenance form the correlation; the client never accepts a manifest-supplied job identity or an in-job completion claim.

Aggregation runs only from the clean trust-anchor checkout with authenticated read access. It compares each manifest with the independently supplied expected identity and writes `contracts/ci-evidence.schema.json`. Acceptance requires true trust-anchor, trusted-surface, and source-allowlist checks. For each of the five managed Spikes, the coordinator steps write `coordinator_result` inside the fixed coordinator root. The CLI validates that file against `contracts/spike-result.schema.json` and enforces the declared Spike ID, candidates, gates, runs, and role separation. It then atomically copies the validated bytes to `managed_results`. A missing or invalid result produces a rejected report with `aggregation-error` and exit status `1`.

An `accepted` result contains all required enriched roles, post-completion successful job observations, successful aggregation checks, and no rejection reasons. A `rejected` result can contain partial or no role evidence and must contain one or more typed rejection reasons. Its reason can record a queued, in-progress, failed, or missing sealing observation without constructing an accepted `origin.sealingJob`. Therefore incomplete, failed, mismatched, stale, corrupt, unauthenticated, or unaggregated evidence produces a durable fail-closed result instead of becoming schema-invalid.

The CLI writes `results.json` and `REPORT_JSON` atomically and reports both paths in its standard-output summary. The executor writes the human Spike report as an interpretation of the accepted `results.json`; the CLI doesn't author that report. Milestone evidence commits the authoritative `results.json`, accepted `REPORT_JSON`, and human Spike report together.

The local `run` client uses a token with Actions write permission only to dispatch and Actions, attestations, and contents read permission to collect. GitHub requires both a calling reusable-workflow job and the called workflow to permit attestation and OIDC access, and nested permissions can't be elevated. The trusted caller therefore grants the union `actions: read`, `contents: read`, `id-token: write`, and `attestations: write`. Each role's candidate job narrows that union to only `contents: read`; unspecified permissions are `none`. Candidate commands receive no token or artifact runtime credential. After they finish, the trusted wrapper receives job-scoped artifact runtime authority to upload the untrusted bundle. Its sealing job grants the same union as the caller and alone receives OIDC and attestation authority. Collection uses only `contents: read`, `actions: read`, and `attestations: read`. No workflow grants release, package, or repository-content write authority. A surviving hosted-macOS process can corrupt untrusted output or cause upload denial, but can't gain seal authority or enter the fresh sealing environment.

GitHub artifact attestations for private or internal repositories require GitHub Enterprise Cloud. Repository plan eligibility isn't guaranteed by this specification. If the candidate repository can't create and verify the attestation, `BURL-M003` must return a rejected aggregate with `attestation-unavailable`. It must not substitute a hash-only protocol.

Aggregation verifies each bundle and compares its captured identities with the independently supplied expected identity. For each role, `evidenceClasses` and the `gates` key set must equal `requiredEvidenceClasses` exactly, and every gate must be true. A missing assigned class, an unassigned extra class, or a class that the role can't produce rejects the aggregate. Every role also records a non-empty observed `environment.filesystem` string from its system API. Sealing and aggregation revalidate that exact manifest value after every archive boundary, reject omission, an empty value, or a changed value as filesystem-evidence mismatch, and never infer a filesystem type from the hosted label. For a managed Spike, the later evidence commit contains exactly the accepted `REPORT_JSON`, authoritative `results.json`, and executor-authored human report declared by the raw contract. For bootstrap, `docs/epic-m-ci-evidence` contains only `.constitution/evidence/BURL-M003/managed-evidence.json`, `.constitution/evidence/BURL-M003/completion.md`, and `.constitution/evidence/BURL-M003/manifest.yaml`. The workflow never pushes repository content. Milestone review starts only from accepted evidence. A draft pull request alone is not evidence.

The hosted OS labels are mutable image channels. Every result records `ImageOS` and `ImageVersion`, and performance or visual aggregation refuses mixed image versions. GitHub doesn't guarantee physical host identity, CPU scheduling, storage throughput, or absence of neighboring load. Repeated samples and captured resource facts bound the claim; they don't turn a hosted label into physical-workstation proof.

The following table shows which environments can serve later evidence consumers. A ticket requires a capability only when its `requiredEvidenceClasses` profile names that class:

| Consumer | `ubuntu-24.04` | `macos-26` | `macos-15` |
| :--- | :--- | :--- | :--- |
| Common functional matrix | Required | Required | Required; compatibility only |
| AST and FFI projection measurements | Performance reference | Performance reference | Not accepted |
| Asset decode and memory measurements | Performance reference | Performance reference | Not accepted |
| Workspace-observer latency | Performance reference | Performance reference | Functional behavior only |
| Nightly PRD meters | Performance reference | Performance reference | Not accepted |
| Packaging and installed-app proof | x86-64 Linux artifact | Apple Silicon macOS 26 artifact | Same Apple Silicon artifact on macOS 15 |
| Platform and product visual regression | Required non-authoritative exact Linux platform regression | Sole authoritative product visual baseline | Not accepted |

Linux platform-regression capture extends the committed private headless Sway and Wayland implementation. It owns compositor, display, input, process, state directory, and application PID. `BURL-M003` establishes that isolated environment and runs functional desktop integration, but its bootstrap profile doesn't claim platform-regression evidence. A later shell or release gate that names `linux-platform-regression` must reconcile the current `1878x989` capture to the PRD's verified 1920x1080 at 60 Hz logical viewport. The zero-pixel result is required implementation-regression evidence, not authoritative product visual evidence. It must not fall back to the Writer's desktop or substitute for macOS 26.

macOS 26 visual capture runs the actual Apple Silicon hosted desktop application. It produces the sole authoritative product visual baseline set and verifies the 1920x1080 logical application viewport before capture. The installed Flutter 3.44.3 source provides `FlutterDriver.screenshot`, but it doesn't guarantee the host window geometry. `BURL-M003` runs functional desktop integration on this environment without claiming authoritative visual evidence. A later shell or release gate that names `macos-authoritative-visual` must prove geometry before capture. Widget-test or Linux platform-regression output can't substitute. macOS 15 never creates or updates visual baselines.

All workflow actions use the full commit SHAs in `stack.yaml`. The workflow uses the repository's Nix, Rust, Cargo, and Pub locks rather than hosted preinstalled tool versions. It captures any unavoidable host utility version. The OS-major labels and image versions remain evidence inputs, not lockfile replacements.

## Commits
This repository uses [Conventional Commits](https://www.conventionalcommits.org/):
`type(scope): summary`, with types `feat`, `fix`, `docs`, `chore`, `refactor`, and
`test`; scope names the area (`docs(prd)`, `fix(editor)`). The history has followed
this shape since Epic A; it is documented here so review can hold work to it rather
than infer it.

## Monorepo Layout (Standard FRB Template)
The repository follows the default `flutter_rust_bridge` template structure to minimize custom build script overhead.

```text
/
├── .agents/                 # Agent skill definitions (Dart/Flutter workflows)
├── .constitution/           # AI Project Development Framework artifacts
├── .envrc                   # direnv entrypoint; activates the devenv shell
├── .gitignore
├── README.md                # Onboarding: how to enter the environment
├── devenv.nix               # Developer environment: toolchains, native deps, git hooks
├── devenv.yaml              # devenv inputs (nixpkgs, rust-overlay, git-hooks)
├── devenv.lock              # Pinned input revisions; the reproducibility boundary
├── rust-toolchain.toml      # Rust version pin, read by devenv and by rustup
├── linux/                   # Flutter Linux build files (in-scope target)
├── macos/                   # Flutter macOS build files (in-scope target)
├── lib/                     # Dart/Flutter UI source code
│   ├── main.dart
│   ├── src/
│   │   ├── components/      # Reusable UI blocks
│   │   ├── design/          # Presentation composition, theme, and motion
│   │   ├── providers/       # Riverpod state definitions
│   │   ├── rust/            # Auto-generated FRB Dart bindings
│   │   └── screens/         # Full-screen routes (workspace.dart, login.dart —
│   │                        #   login retained for the deferred connect flow,
│   │                        #   no longer a startup gate since BURL-E002)
├── scripts/                 # Repository-owned validation entry points
│   ├── smoke-shot.sh        # Manual QA gate for every UI ticket (BURL-E001)
│   ├── visual-regression.sh # Exact visual gate introduced by BURL-G001
│   └── managed-evidence.sh  # Managed evidence client implemented by BURL-M003
├── test/                    # Dart widget tests
├── rust/                    # Rust Core Engine source code
│   └── src/frb_generated.rs # Auto-generated FRB Rust bridge; changes with Dart bindings
│   ├── Cargo.toml
│   ├── tests/               # Rust integration tests
│   ├── src/
│   │   ├── api/             # FFI interface exposed to Dart (thin #[frb] wrappers)
│   │   │   ├── auth.rs      # OAuth flow, token storage, session state
│   │   │   ├── ffi_api.rs   # The contract surface
│   │   │   └── simple.rs    # FRB template init hook (outside the contract)
│   │   ├── db/              # rusqlite database management
│   │   ├── assets/          # Planned: Local Asset Store identity, manifest,
│   │   │                      hydration, verification, and retention
│   │   ├── diagnostics/     # Planned: rotating structured log and export
│   │   ├── draft.rs         # Active-draft-state domain: NoteState/NoteMetadata,
│   │   │                      the open-note cache, block_path-addressed edits
│   │   ├── error.rs         # Shared AppError, so db/security don't depend on api
│   │   ├── git/             # gix integration
│   │   ├── index/           # Bundle -> SQLite indexer: notes, notes_fts,
│   │   │                      fts_mapping, links, directories. `scan` (full
│   │   │                      walk, owns reindex_workspace), `incremental`
│   │   │                      (single-Note reindex, content_hash
│   │   │                      short-circuit), `query` (read paths: search,
│   │   │                      backlinks, tree, title prefix).
│   │   ├── markdown/        # AST parsing logic; owns the span map (ADR-007).
│   │   │                      `parser`/`ast` (parse to Block tree), `spans`
│   │   │                      (span map + its invariants), `splice`
│   │   │                      (span-preserving source edits)
│   │   ├── okf/             # OKF v0.2 bundle domain: `frontmatter` (read and
│   │   │                      validate), `concept_id` (concept-id <-> path,
│   │   │                      reserved-filename rules), `links` (target
│   │   │                      resolution and serialization)
│   │   ├── export/          # Planned: stable-revision copy/archive Export
│   │   ├── object_store/    # Planned: S3-compatible transfer and validation
│   │   ├── provider/        # Planned: private GitHub App/provider integration
│   │   ├── security/        # OS Keychain root-key integration
│   │   ├── sync/            # Debounced background sync scheduler
│   │   ├── update/          # Planned: compatible release-metadata checks
│   │   ├── workspace/       # `bootstrap` (init/open, Git repo adoption),
│   │   │                      `lifecycle` (note & directory create/rename/
│   │   │                      move/delete, atomic write), `links_rewrite`
│   │   │                      (inbound-Link source rewriting on rename),
│   │   │                      `persist` (the ADR-008 tiers and their locks)
│   │   └── test_support.rs  # #[cfg(test)]-only fixtures shared across unit test modules
├── pubspec.yaml             # Dart dependencies
├── .github/workflows/       # Planned: PR, canary, benchmark, and release gates
├── flake.nix                # Planned: release-tagged Nix package entrypoint
├── flake.lock               # Planned: release Flake reproducibility boundary
├── nix/                     # Planned: release package modules and checks
└── flutter_rust_bridge.yaml # FRB configuration
```

The directories marked **Planned** are the physical homes for the forward boundaries already accepted by Architecture v2.0.1. They remain absent until their owning implementation ticket begins. A Spike never creates them. Final Stage 3 may refine files inside a planned directory after evidence, but moving responsibility to a different boundary requires Architecture review and a Tasks adaptation.

`android/` and `ios/` are absent by design: mobile targets are deferred per
`tasks/critical-path.md`, and no mobile toolchain is provisioned. `ANDROID_HOME`
is pointed at an in-repo path that deliberately holds no SDK, so Flutter cannot silently
adopt an SDK from the contributor's home directory; see `stack.yaml`.

## Toolchain
All commands below assume the `devenv` shell (`devenv shell`, or automatic via
`direnv`). Toolchain versions are pinned there and in `rust-toolchain.toml`; see
`stack.yaml` for the compatibility policy.

## Coding Standards
1. **Rust:**
   - Must pass `cargo clippy -- -D warnings`.
   - Must be formatted with `cargo fmt`.
   - Avoid async/await unless absolutely necessary (e.g., long-running sync operations on a dedicated thread). Local index queries remain synchronous for maximum performance, except where `tech-spec/contracts/ffi_api.rs` itself declares a function `async` (e.g. `search_notes`) — the contract's FFI-boundary signature takes precedence over this preference; the function's own body should still execute synchronously to completion rather than actually yielding to an executor.
   - In the delivered v1.6.x model, source spans are Core-side state keyed by `block_path` and aren't fields of the reduced `AstNode` render projection. Forward work must instead keep source ranges inside the canonical Core document/AST state required by ADR-013; a Flutter render projection still receives only the coordinates its interaction contract needs. Final Stage 3 settles the exact range and projection types after SPK-BURL-H001. No UI code may treat a byte offset into Core-owned source as independent authority.
   - No code path may rewrite bytes outside the span of an edited Block. This is the Edit Fidelity constraint in `prd/constraints.yaml` and it is the reason no AST-to-Markdown serializer exists for the save path; adding one for that path reintroduces exactly the failure the constraint forbids.
2. **Dart:**
   - Must pass `dart analyze`.
   - Must be formatted with `dart format`.
   - UI widgets must be completely stateless regarding note content. All active note state is pulled from Riverpod providers connected to the FRB. Ephemeral selection coordinates (`block_path` plus Flutter UTF-16 rendered offset) are UI state, not note content, and are exempt — this is what allows cross-Block selection under ADR-006 without amending `architecture/containers.md`.
   - **`lib/src/design/` is presentation-only composition.** It owns shell
     composition, theme tokens/construction, and motion. It may depend on
     components, providers, and generated types, but must not define provider
     state or call Core/FRB directly; provider modules own state and Core
     access remains behind their existing seams.
   - The rendered and raw presentations of a Block must be typographically identical. Only the text differs (`**bold**` versus bold); font, size, weight, line height, and padding must not, or the Block visibly jumps when it takes focus.
   - **Every error returned across the FFI boundary must reach a user-visible surface.** No call site may swallow a Core error. This rule exists because the editor shipped through Epic B with no error path at all — failures crossed the boundary and were discarded, a gap Epic B's review recorded but could not reach until the editor was mounted (`BURL-E004`, which landed the shell's error surface).
   - **Shell surfaces coordinate through provider seams, not widget ownership.** Note selection flows through the shared selection seam (`selectedNoteIdProvider`) so the tree, editor and lifecycle actions stay coherent without referencing each other; the Directory tree renders from the Core's single whole-tree payload (one call, children nested) and holds only expansion state as ephemeral UI state. Note switching must close the outgoing Note through the Core before opening the next, so its session reaches the commit tier (`BURL-E004`).
   - **Close a Note.** An FFI error refuses the close and keeps the outgoing
     session writable. `CloseNoteResult.warning` means Core retired the session
     after a safe write. The UI removes the retired tab and shows a dismissible
     status. It continues only one Note-to-Note replacement when no batch,
     Workspace switch, or orderly shutdown encloses the close. A batch stops
     with every unprocessed tab preserved, and an enclosing switch or shutdown
     is canceled. The UI must not restore a writable snapshot for a retired
     session. After an incoming open fails with its ID still selected, another
     explicit selection of that Note must issue the open request again.
   - **Settle lifecycle results before warnings.** `LifecycleResult.warning`
     is not an FFI error. When it is populated, Presentation must adopt the
     returned state, apply `LifecycleEffects`, and clear each removed editor
     before it shows one localized dismissible status selected by the typed
     warning stage. It must not parse `detail` or restore the previous editor.
     An `AppError` remains a true refusal, so only that path retains the prior
     Core-valid session. A `Settlement` warning can report an advisory
     post-publication state refresh (such as Link-existence badges); its
     destination state and IDs remain authoritative and writable.
   - **Link-completion grammar is fixed.** A completion is eligible only when a collapsed caret has a last unmatched `[[` on the same line before it; its query is the intervening text. The UI snapshots that exact trigger range and source value, requests no more than 10 Core candidates, and rejects/dismisses the list if a newline, `]]`, focus/selection change, or edit invalidates the snapshot. Core supplies either an existing candidate or a distinguishable prospective ghost when the query is a valid future target. Acceptance replaces the snapshot range with the Core-supplied `LinkCompletion.insert_text`; no Dart code may construct or repair a destination. Follow always re-resolves first, then calls `create_link_target(target_id)` only for a still-missing target.
   - **A cross-Block selection uses one direct `TextInputClient` proxy, not a hidden `TextField`.** Its initial/current proxy value is `TextEditingValue.empty`; after `TextInput.attach`, it calls `setEditingState` with that value before `show`. It owns exactly one `TextInputConnection`, resets the empty platform value after a Core result, and closes before promotion or disposal. `updateEditingValue` handles only ordinary committed text/IME; an `Actions`/`Shortcuts` layer compatible with Flutter 3.44.3 `DefaultTextEditingShortcuts` explicitly handles Delete/Backspace and clipboard copy/cut/paste intents. While `TextEditingValue.composing` is valid and non-collapsed it neither mutates Core nor replaces the platform value. `RangeEditResult` is a present atomic operation, compatible with later undo but not an implementation of deferred CAP-EDIT-08 (ADR-012).
3. **Nix:**
   - Every `*.nix` file must be formatted with `nixfmt` (RFC style). Today that is only `devenv.nix`.
4. **Testing:**
   - Rust: Unit tests for AST parsing, SQLite migrations, and Git merge logic.
   - Dart: Widget tests for editor rendering (verifying AST nodes render correctly).
   - **Round-trip property tests are mandatory for the splice path.** For any Note and any Block, splicing that Block's own unmodified source back over its span must produce a byte-identical file. This is the executable form of the Edit Fidelity constraint and is cheap to state as a property over a corpus of fixture Notes, including ones with frontmatter keys the application does not manage.
   - **Every ticket touching UI must launch the real application in its Verification Command.** Not `flutter test` alone. The gap this closes is documented under "Running the real app" below: through Epic B, no ticket's gate ever started the app, and a real regression shipped that six passing widget tests could not see.

5. **Accessibility (standing standard, adopted before Epic E paints widgets):**
   - Keyboard completeness is a hard review bar: every capability reachable by pointer is reachable by keyboard, and focus order follows visual order.
   - Every user-visible widget carries Flutter `Semantics` labels as it is written — not retrofitted. Screen-reader certification is deferred scope (`prd/out-of-scope/screen-reader-certification.md`); semantic structure is not.
6. **Internationalization readiness (standing standard, same timing):**
   - User-facing strings externalize through Flutter `gen-l10n` from the first screen onward; no new hardcoded UI text lands once Epic E begins.
   - No translation effort is scheduled; this standard exists because retrofitting string extraction across painted screens is a sweep nobody enjoys.
   - The repository configures `flutter: generate: true` and `l10n.yaml`, with `lib/l10n/app_en.arb` as the template ARB file. The configuration sets `arb-dir: lib/l10n`, `output-dir: lib/l10n/generated`, and `output-localization-file: app_localizations.dart`; code imports `package:burlmd/l10n/generated/app_localizations.dart`. The committed `lib/l10n/generated/**` files are repository-owned generated Dart. When you change an ARB file or `l10n.yaml`, run `flutter gen-l10n`, commit the regenerated output, and don't edit generated Dart by hand. The BURL-F006 verification command runs `flutter gen-l10n` before tests and `git diff --check`, which verifies that generation leaves no uncommitted output.

## Persistence lock rules

Before restoring a current-version Workspace session snapshot, Core performs semantic validation after JSON Schema validation. `workspace_id` must equal the active Workspace identity. Every Note and Directory identity must be nonempty, unique in its array, and valid under Core's applicable identity rules. `active_note_id` must be null or one of the `open_note_ids` values. Core rejects duplicate identities and every cross-field violation.

For any malformed current-version snapshot, Core quarantines and preserves the original bytes and returns an empty writable session for the active Workspace. It never restores malformed state. The normal current-version snapshot path remains writable after quarantine, without changing the preserved bytes. Unsupported later-version snapshots keep the separate isolation behavior defined by `workspace-session-snapshot.schema.json`.

`rust/src/workspace/persist.rs` uses this acquisition order: lifecycle, tier 2 write, tier 1, state, then connection. A caller can take a suffix of this order, but it must not acquire these locks in reverse order.

- The per-Note tier 1 lock serializes a source mutation through its draft write and serializes lifecycle state installation with that mutation.
- A source mutation obtains a Workspace edit lease before open-session lookup and retains it through its draft write. Lifecycle closes admission and drains those leases before snapshotting Notes; later source mutations refuse unchanged and retry after the lifecycle call. Admission state is not a lock and must not make a keystroke wait behind filesystem or Git work.
- The FFI owns one counted lease. A direct internal session mutator borrows an existing same-thread lease rather than attempting a second admission; lifecycle must install its reopen guard immediately after closing admission, before any fallible wait.
- The state lock protects the in-memory snapshot and must not span database or filesystem I/O.
- No closure passed to `with_connection` may perform file I/O.
- No lock that a keystroke can contend for may span an `fsync`.
- Tier 2 writes must use the per-Note tier 2 write lock for the full OCC check, file write, and revision re-record sequence.

## Terminology introduced at this layer

`prd/glossary.yaml` owns the product vocabulary and deliberately holds no implementation terms. Four terms this specification introduces are load-bearing across the contract, the ADRs and every Epic D ticket, and are defined here because they belong to the physical layer:

| Term | Definition |
| :--- | :--- |
| Concept id | A Note's identity under OKF §2: its bundle-relative path with `.md` removed. Unique within a bundle, **not** globally, which is why ADR-005 decision 7 makes exactly one Workspace active. Stored as `notes.id`. |
| Working source | The single in-memory buffer holding an open Note's full current text — byte-identical to what `drafts.raw_markdown` persists for it. It is what `update_block` substitutes into and what the tier 2 write copies verbatim. |
| Span map | The Core-side map from `block_path` to a byte range in the working source. Never crosses the FFI boundary and never appears on the AST (ADR-007 decision 3). |
| Block path | An index path into a Note's AST, addressing one Block. **Not stable across any reparsing call** — a splice can change a Block's node shape — so callers re-derive it from the returned state rather than retaining it. |

The distinction most worth stating: the **working source** is not the draft row. They hold the same bytes, but the buffer is the live editing state and the row is its crash-durable copy, and tier 2 clears the row while the buffer persists until the Note closes. Conflating them makes "a draft row exists" mean "a Note is open", which is false in both directions.

## Editor-depth verification commands

The active editor-depth tickets quote these commands exactly. `BURLMD_SMOKE_F005`, `BURLMD_SMOKE_F006`, and `BURLMD_SMOKE_F007` are required readiness inputs: the smoke harness must reject a generic Workspace window and capture only after the named staged interaction is ready.

- `flutter test test/components/emphasis_shortcuts_test.dart && BURLMD_SMOKE_F005=1 ./scripts/smoke-shot.sh f005-emphasis && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- `cargo test --lib --manifest-path rust/Cargo.toml link_completion_limit_is_ten -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml link_completion_limit_is_ten && cargo test --lib --manifest-path rust/Cargo.toml prospective_ghost_completion -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml prospective_ghost_completion && cargo test --lib --manifest-path rust/Cargo.toml resolve_link_target -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml resolve_link_target && cargo test --lib --manifest-path rust/Cargo.toml create_link_target -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml create_link_target && flutter_rust_bridge_codegen generate && flutter gen-l10n && flutter test test/components/link_completion_test.dart test/components/editor_test.dart && BURLMD_SMOKE_F006=1 ./scripts/smoke-shot.sh f006-link-completion && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- `cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_reports_phantom -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_reports_phantom && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_rejects_utf16_surrogate -- --list | rg -q ': test' && cargo test --lib --manifest-path rust/Cargo.toml range_edit_result_rejects_utf16_surrogate && cargo test --lib --manifest-path rust/Cargo.toml && flutter_rust_bridge_codegen generate && flutter test test/components/selection_editing_test.dart test/components/text_input_client_test.dart test/components/selection_test.dart && BURLMD_SMOKE_F007=1 ./scripts/smoke-shot.sh f007-range-editing && dart analyze && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`

## Forward implementation verification commands

Stage 4 tickets quote one of these gates and replace `<ticket-id>` with their lowercase ticket identifier. Ticket-specific tests and hardware-in-the-loop procedures supplement the gate; they don't remove it.

- **Core-only:** `cargo test --manifest-path rust/Cargo.toml && cargo clippy --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings && git diff --check`
- **Core/FFI/UI:** `cargo test --manifest-path rust/Cargo.toml && ./scripts/check-generated-bindings.sh && flutter test && dart analyze && ./scripts/smoke-shot.sh <ticket-id> && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Flutter-only:** `flutter test && dart analyze && ./scripts/smoke-shot.sh <ticket-id> && git diff --check && ! rg -n '\[DEBUG-' lib rust test scripts`
- **Release Flake:** `nix flake check && nix build .#packages.x86_64-linux.default && git diff --check`
- **macOS release build:** `flutter build macos --release && git diff --check`

Spike-dependent implementation tickets may quote the stable portion of these commands while the TechSpec is provisional. They must stop before implementation until final Stage 3 replaces every candidate-specific command and Stage 4 adapts the ticket.

## Index connection obligations

Every connection opened against the encrypted index must issue `PRAGMA foreign_keys = ON` immediately after the key pragma, and before any statement that touches a table. SQLite defaults it off and does not persist it in the file, so it is a property of the connection rather than of the database.

The ordering is stated that precisely because an earlier revision said *before any other statement*, which is unsatisfiable here: on a SQLCipher connection `rust/src/db/connection.rs` must issue `PRAGMA key` first, then the `SELECT count(*) FROM sqlite_master` unlock probe. An obligation the file it cites cannot meet invites the reader to discount the whole rule. The entire key design in `data-models/schema.sql` depends on it: with the pragma off the `ON UPDATE CASCADE` clauses that make a rename possible do not error, they silently do not fire, and the result is orphaned `links` and `fts_mapping` rows with nothing to signal the loss. Today only `init_schema` reliably runs on the singleton connection, while `open_encrypted_db_with_key` is reachable without it — which is how the tests use it.

`PRAGMA user_version` is the other connection-time concern. `init_schema`
must read it before applying the schema. A fresh index records version 2.
A version 1 index must add and backfill `notes.title_lookup_key` in one
transaction before it records version 2. The lookup key uses NFKC, full default
Unicode case folding, and NFC. It supports Unicode title-prefix matching without
depending on the ASCII-only `LIKE` and `NOCASE` behavior in the bundled
SQLCipher build. An index with a later version remains unchanged.

## Workspace location

The default local Workspace (ADR-005 decision 1) resolves to `$XDG_DATA_HOME/burlmd/workspace`, falling back to `~/.local/share/burlmd/workspace` when `XDG_DATA_HOME` is unset, and to `~/Library/Application Support/burlmd/workspace` on macOS.

This is deliberately *not* a visible directory in the user's home. The bundle is a Git repository the application manages, and CAP-WS-05 already provides the path for pointing burlmd at a Workspace the user placed wherever they prefer. Moving this default later is a user-visible migration, so it is recorded here rather than left to the implementation.

The encrypted index does not live inside the bundle. It is derived state (`data-models/schema.sql`), and placing it in the bundle would put an encrypted binary blob inside a Git repository whose entire premise is human-readable plaintext, producing a large opaque diff on every write. It belongs alongside the Workspace, not within it: it resolves to `$XDG_DATA_HOME/burlmd/index.sqlite3` — a *sibling* of the bundle root inside the shared `burlmd/` parent, not a file within the bundle and not an ancestor of it — with the same fallbacks as the Workspace path above, and `BURLMD_DB_PATH` continuing to override it for tests.

`BURL-D004` moved the code to this path. `rust/src/db/connection.rs` previously resolved `$HOME/.burlmd/index.sqlite3`, a placeholder written in Epic B before any Workspace path existed and never reconciled with one; it now resolves the path above, with a test asserting the legacy location is neither read nor created. Because that ticket also rewrote the index schema, an index file left at the old path by a development build is not migrated and not read — it is stale derived state under a path this specification no longer names, and the bundle it was derived from can rebuild it.

The *mechanical* rules above — `cargo fmt`, `cargo clippy`, `dart format`,
`dart analyze`, `nixfmt` — are enforced as pre-commit hooks installed on entry
to the devenv shell. All of them exclude `.constitution/`, so editing the spec's
FFI contract does not trigger a build gate. The four *language* hooks each guard
on their manifest, but `rust/Cargo.toml` and `pubspec.yaml` both exist as of
Epic A, so all five hooks run on every applicable commit today.

`cargo clippy --workspace --all-targets` on every `.rs` commit is therefore a
live gate now. Against a warm `target/` it costs ~20s (measured at Epic D's
close, on a tree where the dev-profile dependencies were already built). The
multi-minute case is a cold or invalidated `target/` — `bundled-sqlcipher`
compiles the SQLCipher amalgamation from source, and `--all-targets`
additionally builds tests and benches, so a toolchain or feature bump pays for
all of it inside the commit. The standing suggestion is unchanged and still not
acted on: consider moving clippy to the `pre-push` stage, leaving `cargo fmt` on
`pre-commit`.

The coordinating Epic G branch proves the hash-and-regenerate drift check and contains the first private headless visual gate. The merged base doesn't contain the generated-binding checker or accepted managed CI evidence. `BURL-M003` implements the stronger non-mutating checker from the preceding contract and may bootstrap both gates without importing the Epic G branch. Until an evidence commit passes milestone review, the broader testing standard, Rust async-avoidance rule, and Dart widget-statelessness rule remain review obligations.

## Running the real app (manual visual verification)

No ticket's Verification Command through Epic B ever actually launches the
built app (`cargo build`/`cargo test` exercise the Rust half in isolation;
`flutter test` exercises the Dart half against fakes) — so `flutter run`
launching successfully, and the UI actually rendering correctly, had never
once been checked. `flutter run -d linux` in debug mode crashes on startup:
`flutter_rust_bridge`'s generated Dart loader
(`lib/src/rust/frb_generated.dart`, `ioDirectory: 'rust/target/release/'`)
looks for the native library at `rust/target/release/librust.so`, resolved
relative to the process's working directory — a location distinct from the
`bundled-sqlcipher` debug artifact `cargokit` builds into
`build/linux/x64/debug/bundle/lib/librust.so` for the actual app bundle.
Before running the desktop app locally (`flutter run -d linux`, or any manual
visual check), run `cargo build --release` once from `rust/` (and again after
any change to the Rust API surface) so that path exists.

Since `BURL-E001` the procedure below is also a command: `scripts/smoke-shot.sh <name>` builds the release native library and app bundle, launches, waits for actual rendering, captures `.qa/<name>.png`, and exits non-zero if the application fails to start or render. `BURLMD_SMOKE_SHOT_DIR` may direct a deliberately reviewed evidence capture elsewhere; `SPK-BURL-F001` is the sole current exception, with its four generated captures kept under `.constitution/evidence/SPK-BURL-F001/`. Render detection compares raw pixels against a measured desktop noise floor rather than byte-comparing images, because background desktop animation always differs between two captures. Every UI ticket's Verification Command gates on it.

For actually looking at rendered output rather than only asserting widget
properties in `flutter test` — screenshot with `grim`, and, when keystroke
simulation is needed, inject text with `wtype` (both provisioned in
`devenv.nix` for this purpose; Wayland-only, not part of the CI/build path).
This caught a real regression during Epic B's closeout that six passing
`flutter test` cases missed entirely: every test's paragraphs happened to be
single-run, so the bug (a multi-run paragraph silently collapsing to one
uniform, unstyled `TextField` once made editable) was invisible to the suite
until an actual rendered screenshot was inspected.

## Evidence-only acceptance handoff

An accepted managed run is an input to review, not ticket completion. `BURL-G011` and `BURL-P002` each write their managed report to `.constitution/evidence/BURL-G011/managed-evidence.json` and `.constitution/evidence/BURL-P002/managed-evidence.json`. `BURL-O004` additionally writes `.constitution/evidence/BURL-O004/nightly-prd-meters.json`; and the installed-release gates each write only `.constitution/evidence/BURL-O011/managed-evidence.json`, `.constitution/evidence/BURL-O012/managed-evidence.json`, or `.constitution/evidence/BURL-O013/managed-evidence.json`. For each ticket, a later evidence-only pull request may change only that ticket's exact evidence directory, adds the declared managed report and any result artifact, and includes `.constitution/evidence/BURL-<TICKET>/manifest.yaml` with the byte count and SHA-256 digest for every accepted file. Independent review and merge of that manifest-backed pull request are mandatory; neither a successful run nor a draft or unreviewed evidence pull request completes the ticket.

`BURL-O014` consumes the three gate directories only after independently reviewed evidence-only pull requests merge. It validates each manifest, the manifest-bound aggregate report, its accepted identity and exact role profile, and the common immutable `BURL-O009` release identity before it publishes. It never accepts a report from `.constitution/reports/`, an ephemeral handoff, an unmanifested file, or an unreviewed commit.

Canonical acceptance artifacts for `BURL-K009`, `BURL-N009`, and `BURL-O014` likewise live only in `.constitution/evidence/BURL-K009/`, `.constitution/evidence/BURL-N009/`, and `.constitution/evidence/BURL-O014/`. Their reports retain the specified credential-free, permission, device-flow, and freshness checks; a later manifest-backed evidence-only review is still required before acceptance.

## Execution conventions

- Production authorization is contract-scoped. Epic G M0 keeps `BURL-G001`, `BURL-G002`, `BURL-G003`, `BURL-G004`, `BURL-G005`, and `BURL-G007` executable. The bootstrap additionally makes `BURL-M015` and `BURL-M003` executable. Every other production ticket has an implicit STOP until its own decision evidence, any required Product Requirements or Architecture evolution, final Stage 3 contract, and Stage 4 adaptation are merged. An unrelated unresolved Spike doesn't block an otherwise authorized ticket.
- The five `Spike` tickets remain research-only and executable within their exhaustive allowlists after their declared dependencies are satisfied. `BURL-M003` satisfies those dependencies only after both its reviewed implementation pull request and dedicated reviewed evidence pull request merge. Every managed Spike runs the launcher from a clean immutable trust-anchor checkout; the trusted default-branch workflow checks out the separate tested source as data. Before dispatch and during collection, the launcher rejects any change outside the ticket's exact write allowlist or any changed validation control. Within the declared H Spike tranche, the committed, validated, and independently reviewed `BURL-H001` milestone satisfies `BURL-H002`; a draft or unmerged branch never satisfies a cross-tranche or cross-branch dependency.
- A ticket that scopes `rust/src/api/ffi_api.rs` also scopes both generated outputs: `lib/src/rust/**` and `rust/src/frb_generated.rs`. Its verification must regenerate and compare both byte for byte, fail on stale output, and leave the pre-check working tree unchanged. This convention avoids repeating generated files in every FFI ticket without transferring ownership away from the ticket.
- `BURL-M003` is authorized to bootstrap with the provisionally aligned Flutter Rust Bridge generator, Rust crate, and Dart package at `2.12.0`. It must implement the missing non-mutating generated-binding checker before the ordered gate invokes that file. The reviewed implementation merge establishes `TRUST_ANCHOR_SHA`; `.constitution/evidence/BURL-M003/managed-evidence.json`, `completion.md`, and `manifest.yaml` record the accepted self-validation and complete the ticket only after independent review and merge. Any later validation-control change repeats this anchor rotation. Final Stage 3 must revalidate the triple and generated bytes before a downstream production ticket relies on it.

PR #11 remains the delivered redesign foundation and isn’t retroactively assigned to an epic. `BURL-G001` removes the presentation-only Platform chrome that leaked from its prototype.
