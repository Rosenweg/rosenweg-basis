// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../anmeldung/karten_sitzung.dart';
import '../anmeldung/kartenleser.dart';
import '../konfig.dart';
import '../plattform.dart';
import '../protokoll.dart';
import '../sitzung.dart';
import 'aktualisierung_leiste.dart';
import 'bausteine.dart';

/// Farben und Texte des Rosenweg-Anmeldeschirms - dieselben wie
/// `AnmeldeOberflaeche` im Modul anmeldeschirm von commons-rosenweg (Android-
/// Apps, Sperrbildschirm der geteilten Telefone), damit er auf allen Geraeten
/// gleich aussieht. Die festen Werte hier sind Blau (Ausschuss/Verwaltung und
/// Standard); je Gruppe der App: [AnmeldeFarben.fuer].
class AnmeldeFarben {
  AnmeldeFarben._();
  static const blau = Color(0xFF1E3A8A);
  static const hellblau = Color(0xFFBFDBFE);
  static const knopf = Color(0xFF2563EB);
  static const knopfDunkel = Color(0xFF1E40AF);
  static const rot = Color(0xFFFCA5A5);
  static const gruen = Color(0xFFBBF7D0);
  static const gelb = Color(0xFFFDE68A);

  /// Farben des Schirms fuer die Gruppe der App; null = blau.
  static AnmeldePalette fuer(RosenwegGruppe? gruppe) => switch (gruppe) {
        RosenwegGruppe.bewohner => AnmeldePalette.rot,
        RosenwegGruppe.technik => AnmeldePalette.gruen,
        RosenwegGruppe.verwaltung || null => AnmeldePalette.blau,
      };
}

/// Farben des Anmeldeschirms je Gruppe (Stefan 27.11.2026): Grund wie der
/// Logo-Grund (werkzeug/logo/baukasten.py `--gruppe`), sonst bleibt alles
/// gleich. Dieselben Werte wie `AnmeldeFarben` in commons-rosenweg (Modul
/// anmeldeschirm). Auf Rot und Gruen erreichen helle Schrift, Meldungen und
/// die weisse Schrift beider Knoepfe mindestens 4.5:1 (WCAG AA); die Knoepfe
/// sind dort dunkler als der Grund und behalten den weissen Rand.
class AnmeldePalette {
  const AnmeldePalette({
    required this.grund,
    required this.hell,
    required this.knopf,
    required this.knopfDunkel,
    required this.rahmen,
    required this.fehler,
    required this.ok,
    required this.warnung,
  });

  final Color grund;

  /// Helle Schrift: Kopf, Hinweise, Fuss, offene Schritte.
  final Color hell;

  /// Hauptknopf ("Mit Rosenweg-Konto anmelden").
  final Color knopf;

  /// Zweitknopf ("QR-Code scannen", "Mit dem Handy anmelden", "Abbrechen").
  final Color knopfDunkel;

  /// Rand des Felds "Mit dem Handy anmelden".
  final Color rahmen;
  final Color fehler;
  final Color ok;
  final Color warnung;

  /// Ausschuss/Verwaltung und Standard: die bisherigen Farben.
  static const blau = AnmeldePalette(
    grund: AnmeldeFarben.blau,
    hell: AnmeldeFarben.hellblau,
    knopf: AnmeldeFarben.knopf,
    knopfDunkel: AnmeldeFarben.knopfDunkel,
    rahmen: AnmeldeFarben.knopf,
    fehler: AnmeldeFarben.rot,
    ok: AnmeldeFarben.gruen,
    warnung: AnmeldeFarben.gelb,
  );

  /// Bewohner.
  static const rot = AnmeldePalette(
    grund: Color(0xFFD62828),
    hell: Color(0xFFFFF1F1),
    knopf: Color(0xFFA51D1D),
    knopfDunkel: Color(0xFF7F1616),
    rahmen: Color(0xFFFFF1F1),
    fehler: Color(0xFFFFF7CC),
    ok: Color(0xFFEBFFF1),
    warnung: Color(0xFFFFF7CC),
  );

  /// Technik.
  static const gruen = AnmeldePalette(
    grund: Color(0xFF2E6B4F),
    hell: Color(0xFFD7F2E3),
    knopf: Color(0xFF1F5A3F),
    knopfDunkel: Color(0xFF173F2D),
    rahmen: Color(0xFFD7F2E3),
    fehler: Color(0xFFFFE1E1),
    ok: Color(0xFFBBF7D0),
    warnung: Color(0xFFFDE68A),
  );
}

/// Wo der Anmelde-QR fuer Apps steht.
const _qrSeite = 'rosenweg4303.ch/smartphones';

/// Der Rosenweg-Anmeldeschirm in Flutter (Stefan 27.11.2026: "auch in den
/// Flutter-Apps den Anmeldeschirm umsetzen, aber angepasst").
///
/// Grund in der Gruppenfarbe der App ([RosenwegApp.gruppe], sonst blau), Rosenweg-Siegel, oben "`<App>` · zum Benutzen anmelden", unten "Die
/// Anmeldung gilt nur fuer `<App>`." - wie auf Android. Die drei Wege je
/// Plattform:
///
/// | | Karte | Rosenweg-Konto | QR-Code |
/// |---|---|---|---|
/// | Android | nativer Schirm aus commons-rosenweg (hier nur "Anmelden") |||
/// | iOS | Knopf, Core NFC | Browserfenster in der App | iPhone scannt den Portal-QR |
/// | Desktop | USB-Leser (PC/SC), nur wenn einer steckt | Browser | Desktop ZEIGT einen QR, das Handy bestaetigt |
///
/// An Stationen und Domaenen-PCs erscheint der Schirm gar nicht: die Sitzung
/// meldet vorher still per Kerberos an ([RosenwegSitzung.starten]).
class RosenwegAnmeldeSchirm extends StatefulWidget {
  const RosenwegAnmeldeSchirm({super.key, required this.sitzung, this.leser, this.qrScannerDa});
  final RosenwegSitzung sitzung;

  /// Fuer Tests; sonst [Kartenleser.fuerPlattform].
  final Kartenleser? leser;

  /// Fuer Tests; sonst fragt iOS VisionKit.
  final bool? qrScannerDa;

  @override
  State<RosenwegAnmeldeSchirm> createState() => _AnmeldeSchirmZustand();
}

/// Frueherer Name.
typedef AnmeldeSchirm = RosenwegAnmeldeSchirm;

enum _Stand { laeuft, ok, fehler }

class _Schritt {
  _Schritt(this.titel);
  final String titel;
  _Stand? stand;
  String? erklaerung;
}

class _AnmeldeSchirmZustand extends State<RosenwegAnmeldeSchirm> {
  RosenwegSitzung get s => widget.sitzung;
  KartenSitzung? get karte => s.karte;
  String get appName => s.app.name;
  bool get ios => RosenwegPlattform.istIos;
  bool get desktop => RosenwegPlattform.istDesktop;

  /// Farben nach der Gruppe der App (wie ihr Logo).
  AnmeldePalette get f => AnmeldeFarben.fuer(s.app.gruppe);

  Kartenleser? _leser;
  bool _leserDa = false;
  bool _qrDa = false;
  Timer? _leserTakt;
  StreamSubscription<String>? _karten;

  /// Ablauf (Karte/QR/Handy wird geprueft): Schritte statt Knoepfe.
  List<_Schritt>? _schritte;
  bool _prueft = false;
  String? _meldung;

  // "Mit dem Handy anmelden" (Desktop)
  HandyCode? _code;
  bool _codeHolt = false;
  Timer? _codeTakt;
  int _neueCodes = 0;
  String? _codeText;

  @override
  void initState() {
    super.initState();
    if (karte == null) return; // Android oder App nur mit Konto
    _leser = widget.leser ?? Kartenleser.fuerPlattform();
    _leserPruefen();
    if (_leser != null && !_leser!.aufKnopfdruck) {
      // Desktop: steckt jemand einen Leser ein, erscheint die Karte
      _leserTakt = Timer.periodic(const Duration(seconds: 3), (_) => _leserPruefen());
    }
    if (ios) {
      if (widget.qrScannerDa != null) {
        _qrDa = widget.qrScannerDa!;
      } else {
        RosenwegPlattform.iosQrDa().then((d) => mounted ? setState(() => _qrDa = d) : null);
      }
    } else {
      _qrDa = widget.qrScannerDa ?? desktop;
    }
  }

  @override
  void dispose() {
    _leserTakt?.cancel();
    _karten?.cancel();
    _codeTakt?.cancel();
    super.dispose();
  }

  Future<void> _leserPruefen() async {
    final l = _leser;
    if (l == null) return;
    final da = await l.verfuegbar();
    if (!mounted) return;
    if (da != _leserDa) setState(() => _leserDa = da);
    if (da && !l.aufKnopfdruck) {
      _karten ??= l.lauschen().listen(_karte);
    } else if (!da) {
      await _karten?.cancel();
      _karten = null;
    }
  }

  // ── Karte ──

  Future<void> _iosKarteLesen() async {
    final uid = await _leser?.einmalLesen();
    if (uid != null) _karte(uid);
  }

  void _karte(String uid) {
    if (_prueft || s.phase == Phase.anmelden || !mounted) return;
    _ablauf(['Rosenweg-Karte prüfen', 'Anmeldung für $appName'], 'Karte erkannt', () => karte!.mitKarte(uid));
  }

  // ── QR (iOS scannt) ──

  Future<void> _qrScannen() async {
    setState(() => _meldung = null);
    final inhalt = await RosenwegPlattform.iosQrScannen();
    if (inhalt == null || !mounted) return;
    final t = inhalt.trim();
    if (!t.startsWith(KartenSitzung.qrPraefix)) {
      setState(() => _meldung = t.startsWith(KartenSitzung.qrPraefixTelefon)
          ? 'Das ist der QR für geteilte Telefone. Wähle auf $_qrSeite „App auf eigenem Handy“.'
          : 'Das ist kein Rosenweg-Anmelde-QR. Öffne $_qrSeite und wähle „App auf eigenem Handy“.');
      return;
    }
    _ablauf(['QR-Code prüfen', 'Anmeldung für $appName'], 'QR-Code erkannt', () => karte!.mitQr(t));
  }

  // ── Mit dem Handy anmelden (Desktop zeigt QR) ──

  Future<void> _handyStarten() async {
    _neueCodes = 0;
    await _codeHolen();
  }

  Future<void> _codeHolen() async {
    if (_codeHolt) return;
    setState(() {
      _codeHolt = true;
      _codeText = null;
      _meldung = null;
    });
    try {
      final c = await karte!.handyCodeHolen();
      if (!mounted) return;
      setState(() => _code = c);
      _codeTakt?.cancel();
      _codeTakt = Timer.periodic(const Duration(seconds: 1), (_) => _codeTick());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _code = null;
        _codeText = e is KartenFehler && e.status == 404
            ? 'Der Server kennt diese Anmeldung noch nicht.'
            : fehlerTextKurz(e);
      });
    } finally {
      if (mounted) setState(() => _codeHolt = false);
    }
  }

  int _sekunde = 0;
  bool _fragt = false;

  Future<void> _codeTick() async {
    final c = _code;
    if (c == null || !mounted) return;
    setState(() {}); // Frist neu zeichnen
    if (DateTime.now().isAfter(c.bis)) return _abgelaufen();
    if (++_sekunde % c.intervall.inSeconds.clamp(1, 30) != 0 || _fragt) return;
    _fragt = true;
    try {
      final stand = await karte!.handyCodeAbholen(c);
      if (!mounted || _code != c) return;
      switch (stand) {
        case HandyStand.wartet:
          break;
        case HandyStand.angemeldet:
          _codeTakt?.cancel();
          setState(() {
            _code = null;
            _schritte = [_Schritt('Auf dem Handy bestätigt')..stand = _Stand.ok, _Schritt('Anmeldung für $appName')];
            _prueft = true;
          });
          _fertig();
        case HandyStand.abgelehnt:
          _codeTakt?.cancel();
          setState(() {
            _code = null;
            _codeText = 'Auf dem Handy abgelehnt.';
          });
        case HandyStand.abgelaufen:
          await _abgelaufen();
      }
    } catch (e) {
      Protokoll.schreiben('Handy-Anmeldung: Abholen', e);
    } finally {
      _fragt = false;
    }
  }

  /// Hoechstens dreimal von selbst einen neuen Code; dann nur noch auf Knopfdruck.
  Future<void> _abgelaufen() async {
    _codeTakt?.cancel();
    if (++_neueCodes <= 3) return _codeHolen();
    setState(() {
      _code = null;
      _codeText = 'Der Code ist abgelaufen.';
    });
  }

  void _handyBeenden() {
    _codeTakt?.cancel();
    setState(() {
      _code = null;
      _codeText = null;
    });
  }

  bool get _handyOffen => _code != null || _codeHolt || _codeText != null;

  // ── Ablauf ──

  Future<void> _ablauf(List<String> titel, String erkannt, Future<void> Function() anmelden) async {
    _handyBeenden();
    setState(() {
      _prueft = true;
      _meldung = null;
      _schritte = [for (final t in titel) _Schritt(t)];
      _schritte![0]
        ..stand = _Stand.laeuft
        ..erklaerung = erkannt;
    });
    try {
      await anmelden();
      if (!mounted) return;
      setState(() => _schritte![0]
        ..stand = _Stand.ok
        ..erklaerung = null);
      _fertig();
    } catch (e) {
      if (!mounted) return;
      setState(() => _schritte![0]
        ..stand = _Stand.fehler
        ..erklaerung = '${fehlerTextKurz(e)} – bitte nochmals versuchen.');
      // Wie der Sperrbildschirm: nach 8 s zurueck
      await Future<void>.delayed(const Duration(seconds: 8));
      if (mounted) {
        setState(() {
          _schritte = null;
          _prueft = false;
        });
      }
    }
  }

  void _fertig() {
    final k = karte;
    setState(() => _schritte![1]
      ..stand = _Stand.ok
      ..erklaerung = (k?.name ?? '').isEmpty ? null : 'angemeldet als ${k!.name}');
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (mounted) s.ohneBrowserAngemeldet();
    });
  }

  // ── Oberflaeche ──

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: Colors.white),
      ),
      child: ColoredBox(
        color: f.grund,
        child: SafeArea(
          child: LayoutBuilder(builder: (context, platz) {
            final breit = platz.maxWidth >= 820 && _handyOffen;
            final haupt = _haupt(context, breit, platz);
            if (!breit) return haupt;
            return Row(children: [
              Expanded(child: haupt),
              SizedBox(width: 400, child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: _handyFeld()))),
              const SizedBox(width: 24),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _haupt(BuildContext context, bool breit, BoxConstraints platz) {
    final schritte = _schritte;
    final logo = schritte != null ? 110.0 : (platz.maxHeight < 640 ? 150.0 : (desktop ? 200.0 : 230.0));
    final teile = <Widget>[
      _text(schritte != null ? 'Anmelden' : '$appName · zum Benutzen anmelden',
          groesse: schritte != null ? 26 : 15, farbe: schritte != null ? Colors.white : f.hell),
      const SizedBox(height: 18),
      if (_handyOffen && !breit) _handyFeld() else _siegel(logo),
      if (schritte != null) ...[
        const SizedBox(height: 16),
        for (final z in schritte) _schrittZeile(z),
      ] else
        ..._wege(context, zeigeKarte: !(_handyOffen && !breit)),
      const SizedBox(height: 16),
      _text('Die Anmeldung gilt nur für $appName.', groesse: 12, farbe: f.hell),
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: teile),
        ),
      ),
    );
  }

  List<Widget> _wege(BuildContext context, {required bool zeigeKarte}) {
    final android = s.android != null;
    final browserOffen = s.phase == Phase.anmelden;
    if (browserOffen) {
      return [
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        if (!android) ...[
          _text('Die Anmeldeseite ist im Browser offen.\nNach der Anmeldung geht es hier weiter.', groesse: 15),
          const SizedBox(height: 16),
          _knopf('Abbrechen', f.knopfDunkel, s.abbrechen, hoehe: 44),
        ],
      ];
    }
    if (android) {
      // Der native Schirm (commons-rosenweg) liegt darueber; hierher kommt nur, wer ihn verlassen hat
      return [
        const SizedBox(height: 24),
        _knopf('Anmelden', f.knopf, s.anmelden),
      ];
    }
    final k = karte;
    final leser = _leser;
    final mitKarte = k != null && leser != null && _leserDa;
    final mitQr = k != null && _qrDa;
    final hinweis = <String>[
      if (mitKarte && ios) 'Tippe „Rosenweg-Karte lesen“ und halte die Karte oben an die Rückseite des iPhones.',
      if (mitQr && ios) '„QR-Code scannen“: Anmelde-QR von $_qrSeite auf einem anderen Gerät.',
      if (mitQr && desktop && !_handyOffen) '„Mit dem Handy anmelden“: QR-Code mit dem Handy scannen und im Portal bestätigen.',
    ];
    return [
      if (zeigeKarte && mitKarte && !ios) ...[
        const SizedBox(height: 20),
        _text('Rosenweg-Karte\nauf den Kartenleser legen', groesse: 20, fett: true),
      ],
      if (hinweis.isNotEmpty) ...[
        const SizedBox(height: 14),
        _text(mitKarte && !ios ? 'Oder: ${hinweis.join('\n')}' : hinweis.join('\n'), groesse: 14, farbe: f.hell),
      ],
      if (_meldung != null) ...[
        const SizedBox(height: 12),
        _text(_meldung!, groesse: 15, farbe: f.fehler),
      ],
      const SizedBox(height: 24),
      if (mitKarte && ios) ...[
        _knopf('Rosenweg-Karte lesen', f.knopfDunkel, _iosKarteLesen, hoehe: 48),
        const SizedBox(height: 10),
      ],
      _knopf('Mit Rosenweg-Konto anmelden', f.knopf, s.anmelden),
      if (mitQr) ...[
        const SizedBox(height: 10),
        if (ios)
          _knopf('QR-Code scannen', f.knopfDunkel, _qrScannen, hoehe: 48)
        else
          _knopf(_handyOffen ? 'QR-Code schliessen' : 'Mit dem Handy anmelden', f.knopfDunkel,
              _handyOffen ? _handyBeenden : _handyStarten,
              hoehe: 48),
      ],
    ];
  }

  /// Desktop: QR zum Scannen mit dem Handy, Code, Frist.
  Widget _handyFeld() {
    final c = _code;
    final teile = <Widget>[];
    if (c != null) {
      final rest = c.bis.difference(DateTime.now());
      final m = rest.inMinutes, sek = rest.inSeconds % 60;
      teile.addAll([
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: QrImageView(data: c.adresse, size: 220, padding: EdgeInsets.zero, semanticsLabel: 'Anmelde-QR für das Handy'),
          ),
        ),
        const SizedBox(height: 10),
        SelectableText(c.benutzerCode,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 3)),
        const SizedBox(height: 10),
        _text('Scanne den Code mit der Kamera deines Handys.\nIm Portal „Anmelden“ bestätigen – fertig.',
            groesse: 14, farbe: f.hell),
        const SizedBox(height: 6),
        _text(rest.isNegative ? 'wird erneuert …' : 'gültig noch $m:${sek.toString().padLeft(2, '0')}',
            groesse: 12, farbe: f.hell),
      ]);
    } else if (_codeHolt) {
      teile.addAll([const SizedBox(height: 40), const Center(child: CircularProgressIndicator()), const SizedBox(height: 40)]);
    } else {
      teile.addAll([
        _text(_codeText ?? '', groesse: 15, farbe: f.fehler),
        const SizedBox(height: 12),
        _knopf('Neuen Code holen', f.knopfDunkel, _handyStarten, hoehe: 44),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: f.knopfDunkel.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: f.rahmen, width: 2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _text('Mit dem Handy anmelden', groesse: 17, fett: true),
        const SizedBox(height: 12),
        ...teile,
      ]),
    );
  }

  Widget _siegel(double groesse) => Center(
        child: Image.asset('assets/anmeldung/rosenweg-siegel.webp',
            package: 'rosenweg_basis', width: groesse, height: groesse, filterQuality: FilterQuality.medium, semanticLabel: 'Rosenweg'),
      );

  Widget _schrittZeile(_Schritt z) {
    final (zeichen, farbe) = switch (z.stand) {
      null => ('○', f.hell),
      _Stand.laeuft => ('⏳', Colors.white),
      _Stand.ok => ('✓', f.ok),
      _Stand.fehler => ('✗', f.fehler),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: Text(
        '$zeichen  ${z.titel}${z.erklaerung == null ? '' : '\n     ${z.erklaerung}'}',
        style: TextStyle(color: farbe, fontSize: 17, fontWeight: z.stand == _Stand.laeuft ? FontWeight.bold : FontWeight.normal),
      ),
    );
  }

  Widget _text(String t, {double groesse = 15, Color farbe = Colors.white, bool fett = false}) => Text(t,
      textAlign: TextAlign.center,
      style: TextStyle(color: farbe, fontSize: groesse, fontWeight: fett ? FontWeight.bold : FontWeight.normal, height: 1.3));

  /// Knopf mit runden Ecken und feinem weissem Rand (wie AnmeldeOberflaeche.knopf).
  Widget _knopf(String text, Color farbe, VoidCallback? tippen, {double hoehe = 52}) => SizedBox(
        height: hoehe,
        child: FilledButton(
          onPressed: tippen,
          style: FilledButton.styleFrom(
            backgroundColor: farbe,
            foregroundColor: Colors.white,
            // Schriftfamilie des Themas (sonst nimmt der Knopf die Standardschrift der Engine)
            textStyle: TextStyle(fontSize: 17, fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Colors.white, width: 1.2)),
          ),
          child: Text(text),
        ),
      );
}

/// Fehlertext ohne Protokoll-Rauschen fuer den Schirm.
String fehlerTextKurz(Object e) => e is KartenFehler ? e.text : fehlerText(e);

// ── Anmeldung in den Einstellungen ────────────────────────────────────────

/// Abschnitt "Anmeldung" fuer Einstellungen: angemeldet als, womit, gilt nur
/// fuer diese App, Abmelden. Zeigt immer den echten Stand der Sitzung.
class AnmeldungKarte extends StatelessWidget {
  const AnmeldungKarte({super.key, required this.sitzung, this.nachAbmelden});
  final RosenwegSitzung sitzung;

  /// z. B. Seite schliessen.
  final VoidCallback? nachAbmelden;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sitzung,
        builder: (context, _) {
          final st = sitzung.stand;
          final t = Theme.of(context).textTheme;
          final f = Theme.of(context).colorScheme;
          final zeilen = <(String, String)>[
            if ((st.name ?? '').isNotEmpty) ('Angemeldet als', st.name!),
            if ((st.email ?? '').isNotEmpty) ('E-Mail', st.email!),
            ('Angemeldet mit', st.art.text),
          ];
          final erklaerung = switch (st.art) {
            AnmeldeArt.geteiltesTelefon =>
              'An- und abmelden geht am Sperrbildschirm des Telefons. Die App nutzt die Person, die dort angemeldet ist.',
            AnmeldeArt.kerberos =>
              'Gilt nur für ${sitzung.app.name}. An diesem Computer meldet dich die App beim nächsten Start wieder von selbst an.',
            AnmeldeArt.karte || AnmeldeArt.qr || AnmeldeArt.handy =>
              'Gilt nur für ${sitzung.app.name} auf diesem Gerät. Alle Geräte siehst und beendest du im Portal unter Profil → App-Anmeldungen.',
            AnmeldeArt.konto => 'Gilt nur für ${sitzung.app.name}. Andere Rosenweg-Apps melden sich selbst an.',
            AnmeldeArt.keine => 'Nicht angemeldet.',
          };
          return Abschnitt(
            titel: 'Anmeldung',
            symbol: Icons.badge_outlined,
            kind: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (k, v) in zeilen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 130, child: Text(k, style: t.bodyMedium?.copyWith(color: f.onSurfaceVariant))),
                    Expanded(child: SelectableText(v, style: t.bodyMedium)),
                  ]),
                ),
              const SizedBox(height: 6),
              Text(erklaerung, style: t.bodySmall?.copyWith(color: f.onSurfaceVariant)),
              if (st.angemeldet && st.art != AnmeldeArt.geteiltesTelefon) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Abmelden'),
                    onPressed: () async {
                      if (!await frage(context, 'Abmelden?',
                          '${sitzung.app.name} meldet sich auf diesem Gerät ab. Andere Rosenweg-Apps bleiben angemeldet.',
                          ja: 'Abmelden')) {
                        return;
                      }
                      nachAbmelden?.call();
                      await sitzung.abmelden();
                    },
                  ),
                ),
              ],
            ]),
          );
        },
      );
}

/// Eigene Seite "Anmeldung" (aus einem Menue). Nach dem Abmelden schliesst
/// sie sich; das Anmeldetor zeigt dann den Anmeldeschirm.
Future<void> zeigeAnmeldung(BuildContext context, RosenwegSitzung sitzung) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (c) => Scaffold(
        appBar: AppBar(title: const Text('Anmeldung')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          AnmeldungKarte(sitzung: sitzung, nachAbmelden: () => Navigator.of(c).pop()),
          const SizedBox(height: 16),
          // "Nach Updates suchen" (Android: Rosenweg Updater, Computer: RosenwegAktualisierung)
          const AktualisierungKarte(),
        ]),
      ),
    ));
