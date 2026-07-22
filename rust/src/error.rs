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
    GitConflict,
    DatabaseError(String),
    CryptoError(String),
    NetworkError(String),
    OAuthError(String),
    IoError(String),
    ParseError(String),
}
