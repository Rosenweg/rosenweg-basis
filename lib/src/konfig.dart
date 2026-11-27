// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/widgets.dart';

/// Feste Angaben des Hauses. Nichts davon ist geheim.
///
/// Bewusst im Code und nicht in einer Einstellungsseite: die Apps sollen auf
/// einem fremden Laptop ohne jede Einrichtung funktionieren. Ein Haus, eine
/// Anmeldung. (Aus rosenweg-vm lib/konfig.dart.)
class RosenwegKonfig {
  const RosenwegKonfig({
    this.authentik = 'https://authentik.rosenweg4303.ch/application/o',
    this.clientId = 'rosenweg-apps',
    this.scopes = 'openid email profile offline_access',
    this.api = 'https://rosenweg4303.ch',
    this.hausDnsName = 'location.rosenweg4303.ch',
    this.hausDnsWert = 'Rosenweg GBT',
    this.hausDnsZeit = const Duration(milliseconds: 1500),
    this.anmeldungHoechstensAlt = const Duration(days: 30),
    this.kerberosQuelle = 'ad-kerberos',
    this.kerberosDienst = 'HTTP/authentik.rosenweg4303.ch@AD.ROSENWEG4303.CH',
  });

  /// Authentik, Anwendung "rosenweg-apps": oeffentlicher Client mit PKCE,
  /// derselbe wie in commons-rosenweg (RosenwegAnmeldung), Rosenweg Telefon
  /// und rosenweg-vm.
  final String authentik;
  final String clientId;

  /// offline_access: ohne Refresh-Token muesste die Person bei jedem Start
  /// durch den Browser.
  final String scopes;

  /// Haupt-API (Website-Backend, api/server.js).
  final String api;

  /// Erkennung "im Haus": TXT-Eintrag im INTERNEN DNS (UniFi-Gateway),
  /// oeffentlich nicht vorhanden. Exakter Vergleich. Nur ein Hinweis, keine
  /// Sicherheit.
  final String hausDnsName;
  final String hausDnsWert;
  final Duration hausDnsZeit;

  /// Entscheid Stefan (rosenweg-vm): still anmelden, solange die letzte
  /// Anmeldung im Browser hoechstens 30 Tage her ist; danach wieder durch den
  /// Browser. Gezaehlt ab der Browser-Anmeldung, nicht ab dem letzten Erneuern.
  final Duration anmeldungHoechstensAlt;

  /// Stille Anmeldung mit dem Kerberos-Ticket der Sitzung (Linux-Stationen
  /// mit Domaenenanmeldung, Windows-Rechner der Domaene): Slug der
  /// Kerberos-Quelle in Authentik. null = aus.
  final String? kerberosQuelle;

  /// Principal von Authentik fuer SPNEGO (SPN der Kerberos-Quelle,
  /// `HTTP@authentik.rosenweg4303.ch` in Authentik), mit Realm, damit kein
  /// DNS-Umweg den Namen verbiegt.
  final String kerberosDienst;

  static const standard = RosenwegKonfig();
}

/// Zielgruppe einer App = Farbe ihres Logo-Grundes (werkzeug/logo/baukasten.py
/// `--gruppe`, Spalte 4 von werkzeug/logo/flutter-apps.txt) und ihres
/// Anmeldeschirms. Entscheid Stefan 27.11.2026.
enum RosenwegGruppe {
  /// Rosenweg-Rot #D62828: alle Bewohner.
  bewohner,

  /// Rosenweg-Blau #1E3A8A: Ausschuss, Hausverwaltung (bisher fuer alle).
  verwaltung,

  /// Dunkelgruen #2E6B4F: Technik, Admin.
  technik;

  /// Aus dem Namen (`bewohner`, `verwaltung`, `technik`); sonst null.
  static RosenwegGruppe? ausName(String? name) {
    final n = name?.trim().toLowerCase();
    for (final g in values) {
      if (g.name == n) return g;
    }
    return null;
  }
}

/// Was eine einzelne App von sich sagt. Eine Zeile pro App, der Rest kommt
/// aus der Basis.
class RosenwegApp {
  const RosenwegApp({
    required this.kennung,
    required this.name,
    required this.ordner,
    required this.beschreibung,
    this.quelle,
    this.logo,
    this.konfig = RosenwegKonfig.standard,
    this.ohneBrowser = true,
    this.gruppe,
  });

  /// applicationId (Android) = APPLICATION_ID (GTK) = Schema des Ruecksprungs
  /// auf Telefonen (`<kennung>:/anmeldung`), z. B. `ch.rosenweg4303.profil`.
  final String kennung;

  /// Anzeigename, z. B. "Rosenweg Profil".
  final String name;

  /// Kurzer technischer Name: Linux-Paket, Ordner der Logdatei, Eintrag im
  /// Schluesselbund, z. B. `rosenweg-profil`.
  final String ordner;

  /// Ein Satz fuer den Anmeldeschirm und "Ueber".
  final String beschreibung;

  /// Quelltext (GPL verlangt, ihn anzubieten), z. B.
  /// https://github.com/Rosenweg/rosenweg-profil
  final String? quelle;

  /// Logo der App (Baukasten, `assets/logo/<ordner>-512.png`). Ohne: der Turm.
  final ImageProvider? logo;

  final RosenwegKonfig konfig;

  /// Anmeldung auch ohne Browser anbieten: Rosenweg-Karte, Anmelde-QR,
  /// "Mit dem Handy anmelden" (eigene Sitzung je App, `rw_app_...`-Zugang
  /// der Haupt-API). false fuer Apps, deren Dienste ein Authentik-Token
  /// verlangen (Rosenweg VM: das vm-gateway prueft `userinfo`) - dann zeigt
  /// der Anmeldeschirm nur das Rosenweg-Konto.
  final bool ohneBrowser;

  /// Zielgruppe wie das Logo (`--gruppe`): Farbe des Anmeldeschirms, auch des
  /// nativen auf Android (commons-rosenweg ab cloud 0.13.6). null = blau wie
  /// bisher.
  final RosenwegGruppe? gruppe;

  /// Ruecksprung auf Telefonen; in Authentik bei rosenweg-apps als "strikt"
  /// eingetragen (docs/authentik.md).
  String get telefonRuecksprung => '$kennung:/anmeldung';

  ImageProvider get logoOderTurm =>
      logo ?? const AssetImage('assets/logo/rosenweg-512.png', package: 'rosenweg_basis');
}
