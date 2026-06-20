import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('EPD 墨水屏上位机');
    await windowManager.setSize(const Size(960, 680));
    await windowManager.setMinimumSize(const Size(800, 560));
    await windowManager.center();
    await windowManager.show();
  }

  runApp(const EpdFlutterApp());
}
