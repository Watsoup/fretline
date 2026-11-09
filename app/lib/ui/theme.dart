import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF14161B);
  static const panel = Color(0xFF1D2027);
  static const line = Color(0xFF2C313B);
  static const text = Color(0xFFE8EAEE);
  static const dim = Color(0xFF8B93A1);
  static const accent = Color(0xFFF5A524);
  static const down = Color(0xFF4EA8FF);
  static const up = Color(0xFFFF7AB6);
  static const ok = Color(0xFF3CCF8E);
  static const bad = Color(0xFFFF5D5D);
  static const nowLine = Color(0xFFF5A524);

  /// One colour per string (1 = high e ... 6 = low E), Rocksmith-ish.
  static const strings = [
    Color(0xFFB57BFF), // 1 e
    Color(0xFF3CCF8E), // 2 B
    Color(0xFFFF9F43), // 3 G
    Color(0xFF4EA8FF), // 4 D
    Color(0xFFF5D624), // 5 A
    Color(0xFFFF5D5D), // 6 E
  ];
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: base.colorScheme.copyWith(primary: C.accent, secondary: C.accent, surface: C.panel),
    cardColor: C.panel,
    dividerColor: C.line,
    sliderTheme: const SliderThemeData(activeTrackColor: C.accent, thumbColor: C.accent),
    appBarTheme: const AppBarTheme(backgroundColor: C.bg, elevation: 0),
  );
}
