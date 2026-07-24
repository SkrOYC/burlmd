//! Test-only helpers shared by `git::operations`'s and `sync::scheduler`'s
//! unit test modules. Both drive the real `git` CLI against throwaway
//! `tempdir()` repositories to build test fixtures (a working copy and/or a
//! bare "remote"), and used to each define an identical local copy of these
//! two functions. Centralized here instead, so there is exactly one
//! implementation to keep in sync.
#![cfg(test)]

use std::path::Path;
use std::process::Command as StdCommand;

/// Runs `git <args>` in `dir` with a fixed author/committer identity, so
/// tests never depend on (or fail because of) the invoking machine's global
/// git config. Panics via `assert!` on any non-zero exit status.
pub(crate) fn git(dir: &Path, args: &[&str]) {
    let status = StdCommand::new("git")
        .args(args)
        .current_dir(dir)
        .env("GIT_AUTHOR_NAME", "Test")
        .env("GIT_AUTHOR_EMAIL", "test@example.com")
        .env("GIT_COMMITTER_NAME", "Test")
        .env("GIT_COMMITTER_EMAIL", "test@example.com")
        .status()
        .expect("git CLI available in devenv shell");
    assert!(status.success(), "git {:?} failed in {:?}", args, dir);
}

/// Creates a bare repository at `dir` (creating `dir` itself first). Used as
/// the "remote" in tests that exercise `push`/`pull` against a local bare
/// repo instead of a real network remote.
pub(crate) fn init_bare(dir: &Path) {
    std::fs::create_dir_all(dir).unwrap();
    git(dir, &["init", "--bare", "--initial-branch=main", "-q"]);
}

/// Initializes a non-bare repository at `dir` (which must already exist) with a fixed
/// `user.name`/`user.email` committer identity, ready for `git::operations::commit_all` to
/// commit into. Was previously duplicated verbatim across `git::operations`'s and
/// `sync::scheduler`'s test modules; centralized here for the same reason as `git`/`init_bare`.
pub(crate) fn init_repo(dir: &Path) {
    git(dir, &["init", "--initial-branch=main", "-q"]);
    git(dir, &["config", "user.name", "Test"]);
    git(dir, &["config", "user.email", "test@example.com"]);
}
