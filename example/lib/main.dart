// SPDX-License-Identifier: GPL-3.0-or-later
// Beispiel-App fuer rosenweg_basis: jede Seite zeigt einen Baustein so, wie
// eine echte App ihn benutzt. Laeuft ohne Anmeldung mit Vorfuehrdaten
// (attrappe.dart) auf Linux, macOS, Windows, Android und iOS.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import 'attrappe.dart';

const beispielApp = RosenwegApp(
  kennung: 'ch.rosenweg4303.basis.beispiel',
  name: 'Rosenweg Bausteine',
  ordner: 'rosenweg-basis-beispiel',
  beschreibung: 'Alle Bausteine der Rosenweg-Basis zum Ausprobieren.',
  quelle: 'https://github.com/Rosenweg/rosenweg-basis',
);

void main() {
  final v = Vorfuehrung();
  final s = RosenwegSitzung(beispielApp, transport: VorfuehrTransport(v));
  s.dateien = vorfuehrDateien(v);
  s.rechte = RosenwegRechte(
    laden: () => s.api.objekt('/api/auth/me'),
    // "Bestaetigen" ohne Browser: im Beispiel einfach hochstufen
    bestaetigen: () async {
      v.stufe = 'konto-frisch';
      return true;
    },
  );
  rosenwegStarten(beispielApp, (sitzung) => BeispielApp(sitzung: sitzung, v: v), sitzung: s);
}

class BeispielApp extends StatelessWidget {
  const BeispielApp({super.key, required this.sitzung, required this.v});
  final RosenwegSitzung sitzung;
  final Vorfuehrung v;

  @override
  Widget build(BuildContext context) => RosenwegGeruest(
        titel: const Text('Rosenweg Bausteine'),
        logo: RosenwegLogo(beispielApp, groesse: 40),
        maxBreite: null,
        // Fuer Bildschirmfotos: BEISPIEL_ZIEL=1 oeffnet gleich die Liste usw.
        anfangsZiel: int.tryParse(Platform.environment['BEISPIEL_ZIEL'] ?? '') ?? 0,
        ziele: [
          GeruestZiel(titel: 'Rechte', symbol: Icons.lock_outline, seite: (_) => RechteBeispiel(sitzung: sitzung, v: v)),
          GeruestZiel(titel: 'Liste', symbol: Icons.list_alt, seite: (_) => ListenBeispiel(sitzung: sitzung)),
          GeruestZiel(titel: 'Formular', symbol: Icons.edit_note, seite: (_) => FormularBeispiel(sitzung: sitzung)),
          GeruestZiel(titel: 'Scannen', symbol: Icons.qr_code_scanner, seite: (_) => const ScannerBeispiel()),
          GeruestZiel(titel: 'Dateien', symbol: Icons.upload_file, seite: (_) => DateienBeispiel(sitzung: sitzung, v: v)),
          GeruestZiel(titel: 'PDF', symbol: Icons.picture_as_pdf_outlined, seite: (_) => PdfAnsicht(laden: () => sitzung.dateien.herunterladen('/api/beispiel.pdf'))),
          GeruestZiel(titel: 'Diagramm', symbol: Icons.show_chart, seite: (_) => const DiagrammBeispiel()),
        ],
      );
}

// ---------------------------------------------------------------- Rechte

class RechteBeispiel extends StatefulWidget {
  const RechteBeispiel({super.key, required this.sitzung, required this.v});
  final RosenwegSitzung sitzung;
  final Vorfuehrung v;
  @override
  State<RechteBeispiel> createState() => _RechteBeispielState();
}

class _RechteBeispielState extends State<RechteBeispiel> {
  Future<void> _neu() async {
    await widget.sitzung.rechte.laden(neu: true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final r = RechteBereich.von(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Abschnitt(
        titel: 'Vorführung einstellen',
        symbol: Icons.tune,
        erklaerung: 'In einer echten App kommt das aus GET /api/auth/me.',
        kind: Column(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('In der Gruppe Technik (darf alles)'),
            value: v.technik,
            onChanged: (x) {
              v.technik = x;
              _neu();
            },
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'karte', label: Text('Karte')),
              ButtonSegment(value: 'konto', label: Text('Konto')),
              ButtonSegment(value: 'konto-frisch', label: Text('Frisch')),
            ],
            selected: {v.stufe},
            onSelectionChanged: (s) {
              v.stufe = s.first;
              _neu();
            },
          ),
          const SizedBox(height: 8),
          Text(r.stand == null ? 'Rechte werden geladen …' : 'Stand: ${r.stand}'),
        ]),
      ),
      const SizedBox(height: 16),
      Abschnitt(
        titel: 'Knöpfe nur mit Recht',
        symbol: Icons.smart_button,
        kind: Wrap(spacing: 12, runSpacing: 8, children: [
          NurMit(recht: 'reklamationen', kind: FilledButton(onPressed: () {}, child: const Text('Meldungen ansehen'))),
          NurMit(
            recht: 'reklamationen',
            zugriff: Zugriff.schreiben,
            kind: FilledButton(onPressed: () {}, child: const Text('Meldung bearbeiten')),
            sonst: const FilledButton(onPressed: null, child: Text('Bearbeiten (nur Verwaltung)')),
          ),
          NurMit(recht: 'proxmox', kind: FilledButton(onPressed: () {}, child: const Text('Proxmox (nur Technik)'))),
        ]),
      ),
      const SizedBox(height: 16),
      const SizedBox(
        height: 320,
        child: Card(
          child: NurMit(
            recht: 'rechteverwaltung',
            stufe: Anmeldestufe.konto,
            hinweis: true,
            kind: Center(child: Text('Rechteverwaltung: hier wäre die Admin-Seite.')),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Abschnitt(
        titel: 'Heikle Aktion',
        symbol: Icons.key,
        erklaerung: 'Lehnt die API mit „bitte bestätigen“ ab (403 reauth/stufe), fragt mitBestaetigung und versucht es einmal nochmals.',
        kind: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () async {
              final ok = await mitBestaetigung(context, () async {
                if (v.stufe != 'konto-frisch') throw KeineBerechtigung('Bitte bestätigen', {'reauth': true});
                return true;
              });
              if (ok == true && context.mounted) zeigeMeldung(context, 'Passwort geändert (Vorführung).');
            },
            child: const Text('Passwort ändern'),
          ),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Liste

typedef Meldung = ({int id, String titel, String haus, String status, String datum});

Meldung _meldung(Map<String, dynamic> j) =>
    (id: j['id'] as int, titel: j['titel'] as String, haus: j['haus'] as String, status: j['status'] as String, datum: j['datum'] as String);

class ListenBeispiel extends StatefulWidget {
  const ListenBeispiel({super.key, required this.sitzung});
  final RosenwegSitzung sitzung;
  @override
  State<ListenBeispiel> createState() => _ListenBeispielState();
}

class _ListenBeispielState extends State<ListenBeispiel> {
  late final _steuerung = ListenSteuerung<Meldung>(
    lader: apiListe(widget.sitzung.api, '/api/reklamationen',
        schluessel: 'reklamationen',
        wandeln: _meldung,
        parameter: (a) => {
              if (a.filter.contains('offen')) 'status': 'offen',
              if (a.filter.contains('erledigt')) 'status': 'erledigt',
            }),
    limit: 40,
    schluessel: (m) => m.id,
    filter: const [ListenFilter(id: 'offen', titel: 'Offen'), ListenFilter(id: 'erledigt', titel: 'Erledigt')],
  );

  @override
  void dispose() {
    _steuerung.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RosenwegListe<Meldung>(
        steuerung: _steuerung,
        suchHinweis: 'Meldung oder Haus suchen',
        mehrfachauswahl: true,
        spalten: [
          ListenSpalte(id: 'id', titel: 'Nr.', text: (m) => '${m.id}', breite: 64, sortierbar: true),
          ListenSpalte(id: 'titel', titel: 'Meldung', text: (m) => m.titel, flex: 3, sortierbar: true),
          ListenSpalte(id: 'haus', titel: 'Haus', text: (m) => m.haus, flex: 2, sortierbar: true),
          ListenSpalte(id: 'datum', titel: 'Datum', text: (m) => m.datum, flex: 2, sortierbar: true),
          ListenSpalte(
            id: 'status',
            titel: 'Status',
            zelle: (_, m) => Chip(label: Text(m.status), visualDensity: VisualDensity.compact),
            flex: 2,
          ),
        ],
        kachel: (_, m) => ListTile(
          title: Text(m.titel),
          subtitle: Text('${m.haus} · ${m.datum}'),
          trailing: Text(m.status),
        ),
        antippen: (m) => zeigeMeldung(context, 'Meldung ${m.id}: ${m.titel}'),
        auswahlAktionen: (context, a) => [
          IconButton(
            tooltip: 'Erledigt',
            icon: const Icon(Icons.check),
            onPressed: () {
              zeigeMeldung(context, '${a.length} als erledigt markiert (Vorführung).');
              _steuerung.auswahlLeeren();
            },
          ),
        ],
      );
}

// ---------------------------------------------------------------- Formular

class FormularBeispiel extends StatefulWidget {
  const FormularBeispiel({super.key, required this.sitzung});
  final RosenwegSitzung sitzung;
  @override
  State<FormularBeispiel> createState() => _FormularBeispielState();
}

class _FormularBeispielState extends State<FormularBeispiel> {
  final _name = TextEditingController(text: 'Anna Beispiel');
  final _email = TextEditingController(text: 'anna@example.ch');
  int? _betrag = 4250;
  DateTime? _datum;
  TimeOfDay? _zeit;
  String? _art = 'reparatur';
  String? _person;
  var _dringend = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RosenwegInhalt(
        child: RosenwegFormular(
          speichern: () => widget.sitzung.api.put('/api/me', {
            'name': _name.text,
            'email': _email.text,
            'betrag': _betrag,
            'datum': _datum?.toIso8601String(),
            'art': _art,
            'person': _person,
            'dringend': _dringend,
          }),
          weitereKnoepfe: [
            TextButton(
              onPressed: () async {
                if (await loeschenBestaetigen(context, 'Eintrag') && context.mounted) zeigeMeldung(context, 'Gelöscht (Vorführung).');
              },
              child: const Text('Löschen'),
            ),
          ],
          felder: [
            const Hinweis('Tipp: E-Mail auf „…@test“ endend oder Betrag über 1000 zeigt einen Fehler der API am Feld.'),
            TextFeld(name: 'name', titel: 'Name', controller: _name, pflicht: true),
            TextFeld(name: 'email', titel: 'E-Mail', controller: _email, pflicht: true, pruefen: Pruefen.email, tastatur: TextInputType.emailAddress),
            BetragFeld(name: 'betrag', titel: 'Betrag', rappen: _betrag, geaendert: (r) => _betrag = r, hinweis: 'z. B. 42.50'),
            DatumFeld(name: 'datum', titel: 'Datum', wert: _datum, geaendert: (d) => setState(() => _datum = d)),
            ZeitFeld(name: 'zeit', titel: 'Uhrzeit', wert: _zeit, geaendert: (z) => setState(() => _zeit = z)),
            AuswahlFeld<String>(
              name: 'art',
              titel: 'Art',
              wert: _art,
              optionen: const {'reparatur': 'Reparatur', 'reinigung': 'Reinigung', 'anderes': 'Anderes'},
              geaendert: (a) => _art = a,
              pflicht: true,
            ),
            SuchAuswahlFeld<String>(
              name: 'person',
              titel: 'Zuständige Person',
              wert: _person,
              text: (p) => p,
              suchen: (q) async => [
                for (final p in await widget.sitzung.api.liste('/api/personen?q=${Uri.encodeQueryComponent(q)}')) '$p',
              ],
              geaendert: (p) => setState(() => _person = p),
            ),
            SchalterFeld(name: 'dringend', titel: 'Dringend', erklaerung: 'Benachrichtigt sofort die Technik.', wert: _dringend, geaendert: (x) => setState(() => _dringend = x)),
          ],
        ),
      );
}

// ---------------------------------------------------------------- Scannen

class ScannerBeispiel extends StatefulWidget {
  const ScannerBeispiel({super.key});
  @override
  State<ScannerBeispiel> createState() => _ScannerBeispielState();
}

class _ScannerBeispielState extends State<ScannerBeispiel> {
  String? _wert;
  String? _karte;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Abschnitt(
          titel: 'QR-Code oder Strichcode',
          symbol: Icons.qr_code_scanner,
          erklaerung: scannerMitKamera
              ? 'Mit der Kamera; oder eintippen bzw. ein Bild wählen.'
              : 'Auf diesem Computer ohne Kamera: Hand-Scanner (wie eine Tastatur) oder eintippen, oder einen QR-Code aus einem Bild lesen.',
          kind: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              onPressed: () async {
                final w = await codeScannen(context, titel: 'Code scannen', hinweis: 'Den Code in den Rahmen halten.', art: CodeArt.alle);
                if (w != null) setState(() => _wert = w);
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scannen'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final w = await codeAusBildWaehlen(context);
                if (w != null) setState(() => _wert = w);
              },
              icon: const Icon(Icons.image_outlined),
              label: const Text('QR-Code aus Bild lesen'),
            ),
            if (_wert != null) ...[
              const SizedBox(height: 16),
              Hinweis('Gelesen: $_wert', art: HinweisArt.gut),
            ],
          ]),
        ),
        Abschnitt(
          titel: 'Rosenweg-Karte (NFC)',
          symbol: Icons.contactless,
          erklaerung: 'Handy: NFC; iPhone: auf Knopfdruck; Computer: USB-NFC-Leser (PC/SC, z. B. ACR122U).',
          kind: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              onPressed: () async {
                final u = await karteLesen(context, titel: 'Karte lesen', eintippen: true);
                if (u != null) setState(() => _karte = u);
              },
              icon: const Icon(Icons.contactless),
              label: const Text('Karte lesen'),
            ),
            if (_karte != null) ...[
              const SizedBox(height: 16),
              Hinweis('Karte: $_karte', art: HinweisArt.gut),
            ],
          ]),
        ),
      ]);
}

// ---------------------------------------------------------------- Dateien

class DateienBeispiel extends StatefulWidget {
  const DateienBeispiel({super.key, required this.sitzung, required this.v});
  final RosenwegSitzung sitzung;
  final Vorfuehrung v;
  @override
  State<DateienBeispiel> createState() => _DateienBeispielState();
}

class _DateienBeispielState extends State<DateienBeispiel> {
  Future<void> _hochladen(List<DateiDaten> dateien) async {
    for (final d in dateien) {
      try {
        await mitFortschritt(context, '«${d.name}» wird hochgeladen', (f) => widget.sitzung.dateien.hochladen('/api/upload', d, fortschritt: f));
        if (!mounted) return;
        setState(() {});
        zeigeMeldung(context, '«${d.name}» hochgeladen (${groesseText(d.groesse)}).');
      } catch (e) {
        if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => RosenwegInhalt(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Abschnitt(
            titel: 'Hochladen',
            symbol: Icons.upload_file,
            erklaerung: 'Dateiauswahl des Systems; am Computer auch hineinziehen. Fotos werden vor dem Hochladen verkleinert.',
            kind: DateiAblage(mehrere: true, mitFoto: true, hoechstens: 25 * 1024 * 1024, gewaehlt: _hochladen),
          ),
          const SizedBox(height: 16),
          Abschnitt(
            titel: 'Herunterladen',
            symbol: Icons.download,
            erklaerung: 'Mit dem Token der Anmeldung. Computer: „Speichern unter“; Telefon: Teilen.',
            kind: Wrap(spacing: 12, runSpacing: 8, children: [
              Builder(
                builder: (c) => FilledButton.tonalIcon(
                  onPressed: () async {
                    try {
                      final d = await mitFortschritt(c, 'PDF wird geladen', (f) => widget.sitzung.dateien.herunterladen('/api/beispiel.pdf', fortschritt: f));
                      if (c.mounted) await dateiSpeichern(c, d);
                    } catch (e) {
                      if (c.mounted) zeigeMeldung(c, fehlerText(e), fehler: true);
                    }
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('PDF speichern'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => pdfOeffnen(context, titel: 'Beispiel-PDF', laden: () => widget.sitzung.dateien.herunterladen('/api/beispiel.pdf')),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF öffnen'),
              ),
            ]),
          ),
          if (widget.v.hochgeladen.isNotEmpty) ...[
            const SizedBox(height: 16),
            Abschnitt(
              titel: 'Bisher hochgeladen',
              kind: Column(children: [for (final h in widget.v.hochgeladen) ListTile(dense: true, leading: const Icon(Icons.check), title: Text(h))]),
            ),
          ],
        ]),
      );
}


/// Diagramme und Echtzeit: eine erfundene Temperatur kommt alle 2 s „live“
/// (EchtzeitAttrappe statt Broker), dazu 7 Tage Verlauf mit Zeitraum-Wahl.
class DiagrammBeispiel extends StatefulWidget {
  const DiagrammBeispiel({super.key});
  @override
  State<DiagrammBeispiel> createState() => _DiagrammBeispielState();
}

class _DiagrammBeispielState extends State<DiagrammBeispiel> {
  final _live = EchtzeitAttrappe({'beispiel/temperatur': '4.0'});
  late final StreamSubscription<MqttNachricht> _abo;
  Timer? _uhr;
  final _r = Random(3);
  final _jetzt = DateTime.now();
  late final _punkte = <Messpunkt>[
    for (var m = 7 * 24 * 60; m >= 0; m -= 15)
      Messpunkt(
        _jetzt.subtract(Duration(minutes: m)),
        // eine Luecke vor zwei Tagen (Station kurz aus)
        m > 2 * 24 * 60 && m < 2 * 24 * 60 + 180 ? null : 4 + 3 * sin(m / 60 / 24 * 2 * pi) + _r.nextDouble() * 0.5,
      ),
  ];
  Zeitraum _zeitraum = Zeitraum.kurz[2];
  String _wert = '–';

  @override
  void initState() {
    super.initState();
    _abo = _live.abonnieren('beispiel/#').listen((n) => setState(() => _wert = n.text));
    _uhr = Timer.periodic(const Duration(seconds: 2), (_) => _live.senden('beispiel/temperatur', (4 + _r.nextDouble()).toStringAsFixed(1)));
  }

  @override
  void dispose() {
    _uhr?.cancel();
    _abo.cancel();
    _live.schliessen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reihe = Messreihe(titel: 'Temperatur', einheit: '°C', punkte: _punkte);
    final von = _jetzt.subtract(_zeitraum.dauer);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Abschnitt(
        titel: 'Echtzeit',
        symbol: Icons.sensors,
        erklaerung: 'In einer App: RosenwegMqtt(MqttZugang.ueberApi(sitzung.api)) statt der Attrappe.',
        kind: Row(children: [
          Text('$_wert °C', style: Theme.of(context).textTheme.headlineMedium),
          const Spacer(),
          EchtzeitAnzeige(quelle: _live),
        ]),
      ),
      const SizedBox(height: 12),
      Abschnitt(
        titel: 'Verlauf',
        symbol: Icons.show_chart,
        kind: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: ZeitraumWahl(gewaehlt: _zeitraum, geaendert: (z) => setState(() => _zeitraum = z))),
          const SizedBox(height: 12),
          Verlaufsdiagramm(reihe: reihe.ausschnitt(von, _jetzt), von: von, bis: _jetzt),
          const SizedBox(height: 12),
          Text('Balken, Wertachse ab 0:', style: Theme.of(context).textTheme.labelLarge),
          Verlaufsdiagramm(
            reihe: Messreihe(titel: 'Regen', einheit: 'mm', farbe: diagrammFarben[1], punkte: [
              for (var d = 13; d >= 0; d--) Messpunkt(_jetzt.subtract(Duration(days: d)), (_r.nextDouble() * 8).roundToDouble()),
            ]),
            art: DiagrammArt.balken,
            nullLinie: true,
            hoehe: 180,
          ),
          const SizedBox(height: 12),
          Text('Kleinverlauf für Kacheln:', style: Theme.of(context).textTheme.labelLarge),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 200, child: Kleinverlauf(reihe: reihe.ausschnitt(_jetzt.subtract(const Duration(hours: 24)), _jetzt))),
          ),
        ]),
      ),
    ]);
  }
}
