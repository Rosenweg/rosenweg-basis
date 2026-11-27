// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../konfig.dart';

/// Farben der Rosenweg-Apps. Rot und Dunkelrot aus dem Logo (A2), der
/// Grundton fuer Material 3 aus rosenweg-vm.
class RosenwegFarben {
  RosenwegFarben._();

  /// Hintergrund des Logos.
  static const rot = Color(0xFFD32F2F);

  /// Bildschirm im alten Monitor-Logo; dunkle Flaechen.
  static const dunkelrot = Color(0xFF7F1D1D);

  /// Grundton, aus dem Material 3 alle Farben ableitet (rosenweg-vm).
  static const grundton = Color(0xFF8B1E3F);

  /// Gut/gespeichert, Warnung — fuer Meldungen, gleich in hell und dunkel lesbar.
  static const gut = Color(0xFF2E7D32);
  static const warnung = Color(0xFFB26A00);

  /// Gruppenfarben (wie der Logo-Grund, baukasten.py GRUPPEN).
  static const bewohner = Color(0xFFD62828);
  static const verwaltung = Color(0xFF1E3A8A);
  static const technik = Color(0xFF2E6B4F);

  /// Farbe der Gruppe; null = der bisherige Grundton.
  static Color fuer(RosenwegGruppe? gruppe) => switch (gruppe) {
        RosenwegGruppe.bewohner => bewohner,
        RosenwegGruppe.verwaltung => verwaltung,
        RosenwegGruppe.technik => technik,
        null => grundton,
      };
}

/// Thema fuer alle Rosenweg-Apps: Material 3, grosse Bedienelemente,
/// Eingabefelder mit Rahmen (wie die Formulare im Portal). Grundton ist die
/// Gruppenfarbe ([GruppenFarbe], Stefan 28.11.2026); `fidelity` haelt die
/// Akzente nahe an Rot, Blau und Gruen statt sie zu entsaettigen.
ThemeData rosenwegThema(Brightness helligkeit, [RosenwegGruppe? gruppe]) {
  final farben = ColorScheme.fromSeed(
    seedColor: RosenwegFarben.fuer(gruppe),
    brightness: helligkeit,
    dynamicSchemeVariant: gruppe == null ? DynamicSchemeVariant.tonalSpot : DynamicSchemeVariant.fidelity,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: farben,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
    cardTheme: const CardThemeData(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    // Dialoge am Desktop nicht ueber die ganze Fensterbreite.
    dialogTheme: const DialogThemeData(constraints: BoxConstraints(minWidth: 280, maxWidth: 560)),
  );
}
