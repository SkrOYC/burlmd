import 'package:burlmd/src/rust/frb_generated.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injects the initialized Rust FFI API surface into the widget tree.
/// `RustLib.init()` must already have completed (awaited in `main()`)
/// before any widget first reads this provider.
final rustApiProvider = Provider<RustLibApi>(
  // ignore: invalid_use_of_internal_member
  (ref) => RustLib.instance.api,
);
