# Agent guide

Use this guide to locate project requirements and run repository-owned commands.
The linked specifications define scope, implementation rules, and acceptance.

## Read the task authority

For planned work, read the owning ticket and its prerequisites in
[the critical path](.constitution/tasks/critical-path.md) and
[the active epics](.constitution/tasks/epics/). For maintenance outside a ticket,
read the specifications relevant to the requested change. These sources define
the project rules:

- [Constitution metadata](.constitution/constitution.yaml): repository surfaces,
  default branch, and worktree conventions.
- [Product requirements](.constitution/prd/vision.md) and
  [architecture strategy](.constitution/architecture/strategy.md): product scope
  and component responsibilities.
- [Stack](.constitution/tech-spec/stack.yaml) and
  [implementation guidelines](.constitution/tech-spec/guidelines.md): toolchain,
  coding rules, generated artifacts, and verification contracts.
- [Open decisions](.constitution/reports/open-decisions.yaml): unresolved choices
  and their closure requirements.

Check the execution restrictions in the active specifications before running
managed validation. A checked-in script or workflow doesn't authorize its use.
Keep local Linux verification separate from managed evidence and release claims.

## Use the pinned environment

Run commands from the repository root in the pinned environment.
`devenv.nix`, `devenv.lock`, and `rust-toolchain.toml` define the development
tools. Keep dependency lockfiles in place rather than selecting tools from the
host.

In the canonical checkout, `devenv shell` and `.envrc` through direnv provide
the development entry points. Environment entry installs Git hooks. In a linked
worktree, use a verified entry path that doesn't modify shared hooks. Don't
install, repoint, overwrite, or hand-edit shared hooks from a linked worktree.
If a wave needs hook regeneration, obtain explicit user approval during step 0
and regenerate from the intended canonical checkout. Before removing a worktree,
verify that shared hooks don't resolve through it. Don't guess environment-entry
flags or disable commit checks.

For the exact devenv CLI revision used by CI, pass a command to
`scripts/ci-devenv.sh`. For example:

```sh
./scripts/ci-devenv.sh cargo test --manifest-path rust/Cargo.toml
```

This helper reproduces CI's environment entry. It doesn't reproduce a hosted
role, grant managed-execution authority, or produce acceptance evidence alone.
The linked-worktree hook restriction also applies to this helper. Inside an
already loaded local environment, run the command directly.

## Verify the affected behavior

During iteration, select tests for the changed behavior. These examples use
repository-owned test paths and modules:

```sh
cargo test --manifest-path rust/Cargo.toml markdown::
flutter test test/components/editor_test.dart
```

Before completing planned work, run the ticket's exact verification command.
For maintenance outside a ticket, select the documented checks for the affected
behavior. Run applicable formatting and static checks from `devenv.nix`.
The implementation guidelines define the broader Rust, generated-binding,
Flutter, and analyzer gates. Focused tests don't replace required completion
checks.

For changes across Core, bindings, and Flutter, the common functional gate is:

```sh
cargo test --manifest-path rust/Cargo.toml && \
    ./scripts/check-generated-bindings.sh && \
    flutter test && \
    dart analyze && \
    git diff --check
```

Stop on a failed command. UI tickets also require their named real-application
recipe, integration target, scenario, and evidence. Run a recipe only after its
owning task makes it available. Apply reviewed visual-baseline requirements
where the ticket explicitly requires them. Widget tests alone don't satisfy
the real-application gate.

The binding checker temporarily regenerates and restores
`rust/src/frb_generated.rs` and `lib/src/rust/`. Don't edit those surfaces or run
another generator concurrently in the same checkout. When bindings must change,
regenerate them deliberately and review both outputs.

## Own worktrees, processes, and artifacts

Follow the constitution's sibling worktree convention:
`../burlmd-<branch-slug>`, created from merged `master`. Use a separate branch
and worktree for independent implementation work. Preserve unrelated edits.

Keep mutable build outputs local to their checkout. Coordinate Cargo, Flutter,
and generation commands that use the same outputs.

For test services and scratch data, record which invocation owns each process,
socket, and directory. Stop and reap owned processes and remove owned temporary
data after success, failure, or cancellation. Use harness cleanup rather than
removing caller-selected directories or another run's files. Preserve required
evidence and useful build caches; avoid routine full cleans.

The `scripts/visual-regression.sh` and `scripts/smoke-shot.sh` helpers default
to ignored `.qa/` capture output. Their `BURLMD_VISUAL_REGRESSION_DIR` and
`BURLMD_SMOKE_SHOT_DIR` overrides select separate capture directories. Live
recipes use their ticket's evidence destination and manifest requirements.
Check those rules before deleting output or adding screenshots to a commit.

Managed verification constructs its own environment with `env -i`, isolated
homes, and explicit writable paths. Shell variables and optional compiler caches
don't automatically cross that boundary. Change the owning contract and launcher
together when an authorized task requires another environment input.
