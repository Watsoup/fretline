import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/library.dart';
import 'data/progress.dart';
import 'models/notation.dart';
import 'ui/library_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // the highway reads left to right: landscape on tablets
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  final progress = await ProgressStore.open();
  await loadNotation();
  runApp(FretlineApp(store: createLibraryStore(), progress: progress));
}

class FretlineApp extends StatelessWidget {
  final LibraryStore store;
  final ProgressStore progress;
  const FretlineApp({super.key, required this.store, required this.progress});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fretline',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: LibraryScreen(store: store, progress: progress),
    );
  }
}
