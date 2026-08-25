import 'dart:convert';

import 'package:burlmd/src/components/visual_parity_fixture.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';

/// Normal-app capture target used by the external Linux compositor worker.
/// This deliberately avoids testWidgets/integration_test bindings.
void main() {
  final controller = FixtureCaptureController();
  enableFlutterDriverExtension(
    handler: (message) async {
      final decoded = message == null
          ? <String, Object?>{}
          : jsonDecode(message);
      final request = decoded is Map
          ? decoded.cast<String, Object?>()
          : <String, Object?>{};
      final command = request['command'] as String? ?? 'settle';
      final arguments = request['arguments'] is Map
          ? (request['arguments'] as Map).cast<String, Object?>()
          : const <String, Object?>{};
      try {
        return jsonEncode(await controller.execute(command, arguments));
      } on StateError catch (error) {
        return jsonEncode(<String, Object?>{
          'error': error.toString(),
          'settled': false,
        });
      }
    },
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FixtureReferenceShell(captureController: controller),
    ),
  );
}
