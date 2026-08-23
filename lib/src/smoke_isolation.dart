import 'dart:io';

/// Returns `null` only when [environment] can be proven to be the exact
/// private filesystem contract created by `scripts/smoke-shot.sh`.
///
/// Every inspected path already exists when the harness starts the app. That
/// lets [resolveSymbolicLinks] reject both lexical escapes and symlink escapes
/// instead of trusting a string prefix.
Future<String?> validateSmokeIsolation(Map<String, String> environment) async {
  if (environment['BURLMD_SMOKE_ISOLATED'] != '1') {
    return 'the harness isolation marker is missing';
  }

  final root = environment['BURLMD_SMOKE_ROOT'];
  final nonce = environment['BURLMD_SMOKE_NONCE'];
  if (root == null ||
      nonce == null ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(nonce)) {
    return 'the harness root or nonce is missing or invalid';
  }

  final rootPath = await _canonicalDirectory(root);
  final tempPath = await _canonicalDirectory('/tmp');
  if (rootPath == null ||
      tempPath == null ||
      !_isHarnessRoot(rootPath, tempPath)) {
    return 'the harness root is not a private smoke state directory';
  }

  final expected = <String, String>{
    'HOME': '$rootPath/home',
    'XDG_DATA_HOME': '$rootPath/data',
    'BURLMD_DB_PATH': '$rootPath/data/burlmd/index.sqlite3',
    'BURLMD_SMOKE_WORKSPACE': '$rootPath/data/burlmd/workspace',
    'BURLMD_SMOKE_NONCE_FILE': '$rootPath/.burlmd-smoke-nonce',
    // The harness creates this empty marker before launch. Scenarios replace
    // its contents only after their readiness condition is true. Keeping the
    // path fixed beneath the capability root prevents a direct launch from
    // choosing an arbitrary file that a staging hook can overwrite.
    'BURLMD_SMOKE_READY_FILE': '$rootPath/.burlmd-smoke-ready',
  };
  for (final entry in expected.entries) {
    final supplied = environment[entry.key];
    final canonical = await _canonicalPath(supplied);
    if (canonical == null || canonical != entry.value) {
      return '${entry.key} does not resolve inside the private smoke state';
    }
  }

  // Unlike the other contract paths, the readiness marker is written by a
  // staged widget after this validation returns. Require its immediate parent
  // to be the canonical root too: exact target equality rejects a symlinked
  // marker and this check makes the root-bound placement explicit.
  final readinessFile = environment['BURLMD_SMOKE_READY_FILE'];
  final readinessParent = readinessFile == null
      ? null
      : await _canonicalDirectory(File(readinessFile).parent.path);
  if (readinessParent != rootPath) {
    return 'BURLMD_SMOKE_READY_FILE is not directly inside the private smoke state';
  }

  // The Workspace is the Core's default for the supplied XDG_DATA_HOME. This
  // exact equality rules out a caller pointing the staging hook at a real
  // default Workspace, even when HOME/XDG themselves look isolated.
  final workspace = expected['BURLMD_SMOKE_WORKSPACE']!;
  final dataHome = expected['XDG_DATA_HOME']!;
  if (workspace != '$dataHome/burlmd/workspace') {
    return 'the smoke Workspace is not the isolated default Workspace';
  }

  try {
    final storedNonce = await File(
      expected['BURLMD_SMOKE_NONCE_FILE']!,
    ).readAsString();
    if (storedNonce != '$nonce\n') {
      return 'the harness nonce does not match its private capability file';
    }
  } on FileSystemException {
    return 'the harness nonce capability file cannot be read';
  }

  return null;
}

bool _isHarnessRoot(String root, String temp) {
  final prefix = '$temp${Platform.pathSeparator}burlmd-smoke-state.';
  if (!root.startsWith(prefix)) return false;
  return Directory(root).parent.path == temp;
}

Future<String?> _canonicalDirectory(String? path) async {
  if (path == null || path.isEmpty) return null;
  try {
    return await Directory(path).resolveSymbolicLinks();
  } on FileSystemException {
    return null;
  }
}

Future<String?> _canonicalPath(String? path) async {
  if (path == null || path.isEmpty) return null;
  try {
    // FileSystemEntity exposes resolution as an instance method. The kernel
    // resolves the path independent of whether the terminal entity is a file
    // or a directory, so File is sufficient for all contract entries here.
    return await File(path).resolveSymbolicLinks();
  } on FileSystemException {
    return null;
  }
}
