use flutter_rust_bridge::frb;

/// Shared domain error, defined outside `api` so `db` and `security` do not
/// have to depend upward on the FFI-facing module to report failures —
/// `containers.md` declares the Local Repository and Secure Storage
/// containers as depending on nothing above them (or only the host OS), and
/// importing `AppError` from `api::ffi_api` would invert that.
#[frb]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AppError {
    DiskFull,
    AuthExpired,
    /// The on-disk file changed underneath an active draft. Carries the
    /// current `base_revision` so the caller can reload rather than guess.
    RevisionMismatch(String),
    GitConflict,
    /// The target path is already occupied, or is a reserved OKF filename
    /// (`index.md` / `log.md`, see ADR-004 decision 6).
    PathUnavailable(String),
    NotFound(String),
    DatabaseError(String),
    CryptoError(String),
    NetworkError(String),
    /// The `state` returned on the OAuth redirect did not match the value
    /// minted for the `flow_id`, or the `flow_id` is unknown or already
    /// consumed. Distinct from `OAuthError` because it is a CSRF signal, not
    /// a provider failure, and no token request is made when it is raised.
    OAuthStateMismatch,
    OAuthError(String),
    IoError(String),
    ParseError(String),
}
