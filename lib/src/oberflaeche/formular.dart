// SPDX-License-Identifier: GPL-3.0-or-later
/// Formulare fuer alle Rosenweg-Apps: Pruefen, Speichern-Zustand, Fehler der
/// API am richtigen Feld, Rueckfrage bei ungespeicherten Aenderungen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../netz/fehler.dart';
import 'bausteine.dart';
import 'rechte_bausteine.dart';

/// Zustand eines [RosenwegFormular]: geaendert, speichert, Fehler.
class FormularSteuerung extends ChangeNotifier {
  bool _geaendert = false;
  bool _speichert = false;
  String? _fehler;
  Map<String, String> _feldFehler = const {};

  /// Es gibt ungespeicherte Aenderungen.
  bool get geaendert => _geaendert;
  bool get speichert => _speichert;

  /// Allgemeiner Fehler (oben im Formular).
  String? get fehler => _fehler;

  /// Fehler der API zu einzelnen Feldern (Name → Satz).
  Map<String, String> get feldFehler => _feldFehler;
  String? feldFehlerVon(String? name) => name == null ? null : _feldFehler[name];

  /// Ein Feld hat sich geaendert (die Felder rufen das selbst).
  void markieren([String? feld]) {
    var neu = !_geaendert;
    _geaendert = true;
    if (feld != null && _feldFehler.containsKey(feld)) {
      _feldFehler = {..._feldFehler}..remove(feld);
      neu = true;
    }
    if (neu) notifyListeners();
  }

  /// Nach dem Laden neuer Werte: nichts geaendert, keine Fehler.
  void zuruecksetzen() {
    _geaendert = false;
    _fehler = null;
    _feldFehler = const {};
    notifyListeners();
  }

  void _setzen({bool? speichert, String? fehler, Map<String, String>? feldFehler, bool? geaendert, bool fehlerLeeren = false}) {
    if (speichert != null) _speichert = speichert;
    if (fehler != null || fehlerLeeren) _fehler = fehler;
    if (feldFehler != null) _feldFehler = feldFehler;
    if (geaendert != null) _geaendert = geaendert;
    notifyListeners();
  }
}

/// Gibt die [FormularSteuerung] an die Felder weiter.
class _FormularBereich extends InheritedNotifier<FormularSteuerung> {
  const _FormularBereich({required FormularSteuerung steuerung, required super.child}) : super(notifier: steuerung);
}

FormularSteuerung? _steuerungVon(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_FormularBereich>()?.notifier;

/// Die [FormularSteuerung] des umgebenden [RosenwegFormular] (null = keins);
/// fuer eigene Felder ausserhalb dieser Datei (z. B. [FotoFeld]).
FormularSteuerung? formularSteuerungVon(BuildContext context) => _steuerungVon(context);

/// Formular mit Knopf "Speichern".
///
/// ```dart
/// RosenwegFormular(
///   speichern: () => api.put('/api/me', {'name': name.text}),
///   felder: [TextFeld(name: 'name', titel: 'Name', controller: name, pflicht: true)],
/// )
/// ```
///
/// * Prueft alle Felder vor dem Speichern; Fehler stehen am Feld.
/// * Waehrend des Speicherns: Knopf mit Kreisel, nicht doppelt druecken.
/// * Lehnt die API ab: `felder`/`feld` der Antwort am jeweiligen Feld
///   ([ApiFehler.feldFehler]), sonst der Satz oben im Formular.
/// * Ungespeicherte Aenderungen: Zurueck fragt "Änderungen verwerfen?".
/// * Desktop: Strg+S bzw. Cmd+S speichert.
class RosenwegFormular extends StatefulWidget {
  const RosenwegFormular({
    super.key,
    required this.felder,
    required this.speichern,
    this.steuerung,
    this.speichernText = 'Speichern',
    this.gespeichertText = 'Gespeichert.',
    this.gespeichert,
    this.weitereKnoepfe = const [],
    this.fragenBeimVerlassen = true,
    this.scrollen = true,
    this.abstand = 16,
  });

  final List<Widget> felder;

  /// Speichert; wirft bei Fehlern (wie [RosenwegApi]).
  final Future<void> Function() speichern;
  final FormularSteuerung? steuerung;
  final String speichernText;

  /// Meldung nach dem Speichern (null = keine).
  final String? gespeichertText;

  /// Nach erfolgreichem Speichern (z. B. Seite schliessen).
  final VoidCallback? gespeichert;

  /// Neben "Speichern" (z. B. "Löschen").
  final List<Widget> weitereKnoepfe;
  final bool fragenBeimVerlassen;

  /// false: kein eigener ListView (Formular steht in einer scrollenden Seite).
  final bool scrollen;
  final double abstand;

  @override
  State<RosenwegFormular> createState() => _RosenwegFormularState();
}

class _RosenwegFormularState extends State<RosenwegFormular> {
  final _form = GlobalKey<FormState>();
  late FormularSteuerung _s = widget.steuerung ?? FormularSteuerung();

  @override
  void didUpdateWidget(RosenwegFormular alt) {
    super.didUpdateWidget(alt);
    if (widget.steuerung != null && widget.steuerung != _s) _s = widget.steuerung!;
  }

  @override
  void dispose() {
    if (widget.steuerung == null) _s.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    if (_s.speichert) return;
    FocusScope.of(context).unfocus();
    _s._setzen(fehlerLeeren: true, feldFehler: const {});
    if (!(_form.currentState?.validate() ?? true)) {
      zeigeMeldung(context, 'Bitte die markierten Felder prüfen.', fehler: true);
      return;
    }
    _form.currentState?.save();
    _s._setzen(speichert: true);
    try {
      await widget.speichern();
      if (!mounted) return;
      _s._setzen(speichert: false, geaendert: false);
      if (widget.gespeichertText != null) zeigeMeldung(context, widget.gespeichertText!);
      widget.gespeichert?.call();
    } catch (e) {
      if (!mounted) return;
      if (e is BestaetigungPerEmail) {
        // nichts gespeichert: wartet auf die Bestaetigung per Mail
        _s._setzen(speichert: false, fehler: e.text);
        await zeigeEmailBestaetigung(context, e);
        return;
      }
      final felder = e is ApiFehler ? e.feldFehler : const <String, String>{};
      _s._setzen(
        speichert: false,
        feldFehler: felder,
        // Nur Feldfehler? Dann oben ein kurzer Satz, sonst der ganze Text
        fehler: felder.isNotEmpty && e is ApiFehler && felder.values.contains(e.text)
            ? 'Bitte die markierten Felder prüfen.'
            : fehlerText(e),
      );
    }
  }

  Future<void> _verlassen(bool weg, Object? ergebnis) async {
    if (weg) return;
    // Gerade gespeichert (z. B. `gespeichert: () => Navigator.pop(...)`):
    // canPop ist erst nach dem naechsten Bau wieder true – dann ohne Frage zu.
    // (Sofort nochmals pop wuerde hier wieder landen.)
    if (!(widget.fragenBeimVerlassen && _s.geaendert)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(ergebnis);
      });
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    final ja = await frage(context, 'Änderungen verwerfen?', 'Du hast Änderungen, die noch nicht gespeichert sind.',
        ja: 'Verwerfen', gefaehrlich: true);
    if (ja && mounted) {
      _s._setzen(geaendert: false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => _FormularBereich(
        steuerung: _s,
        child: ListenableBuilder(
          listenable: _s,
          builder: (context, _) {
            final knoepfe = Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end, children: [
              ...widget.weitereKnoepfe,
              FilledButton.icon(
                key: const Key('formular-speichern'),
                onPressed: _s.speichert ? null : _speichern,
                style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
                icon: _s.speichert
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_s.speichert ? 'Wird gespeichert …' : widget.speichernText),
              ),
            ]);
            final kinder = <Widget>[
              if (_s.fehler != null) Hinweis(_s.fehler!, art: HinweisArt.fehler),
              ...widget.felder,
              knoepfe,
            ];
            final inhalt = widget.scrollen
                ? ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: kinder.length,
                    separatorBuilder: (_, _) => SizedBox(height: widget.abstand),
                    itemBuilder: (_, i) => kinder[i],
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < kinder.length; i++) ...[if (i > 0) SizedBox(height: widget.abstand), kinder[i]],
                  ]);
            return PopScope<Object?>(
              canPop: !(widget.fragenBeimVerlassen && _s.geaendert),
              onPopInvokedWithResult: _verlassen,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyS, control: true): _speichern,
                  const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _speichern,
                },
                child: Form(key: _form, child: inhalt),
              ),
            );
          },
        ),
      );
}

/// Pruefungen fuer Felder (`validator`). Alle liefern null = in Ordnung.
class Pruefen {
  Pruefen._();

  static String? pflicht(String? v) => (v == null || v.trim().isEmpty) ? 'Bitte ausfüllen.' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'Bitte eine gültige E-Mail-Adresse eingeben.';
  }

  static String? Function(String?) hoechstens(int zeichen) =>
      (v) => (v != null && v.length > zeichen) ? 'Höchstens $zeichen Zeichen.' : null;

  /// Mehrere Pruefungen nacheinander; der erste Fehler zaehlt.
  static String? Function(String?) alle(List<String? Function(String?)?> p) => (v) {
        for (final f in p) {
          final r = f?.call(v);
          if (r != null) return r;
        }
        return null;
      };
}

/// Textfeld. [name] verbindet es mit Fehlern der API (`felder.<name>`).
class TextFeld extends StatelessWidget {
  const TextFeld({
    super.key,
    this.name,
    required this.titel,
    this.controller,
    this.anfangswert,
    this.pflicht = false,
    this.pruefen,
    this.hinweis,
    this.zeilen = 1,
    this.tastatur,
    this.verdeckt = false,
    this.geaendert,
    this.aktiv = true,
    this.vorne,
    this.hinten,
    this.vorText,
    this.eingabeFilter,
    this.autofokus = false,
  });

  final String? name;
  final String titel;
  final TextEditingController? controller;
  final String? anfangswert;
  final bool pflicht;
  final String? Function(String?)? pruefen;
  final String? hinweis;

  /// Mehr als 1 = mehrzeilig.
  final int zeilen;
  final TextInputType? tastatur;
  final bool verdeckt;
  final ValueChanged<String>? geaendert;
  final bool aktiv;
  final Widget? vorne;
  final Widget? hinten;

  /// Fester Text vor der Eingabe (z. B. "CHF ").
  final String? vorText;
  final List<TextInputFormatter>? eingabeFilter;
  final bool autofokus;

  @override
  Widget build(BuildContext context) {
    final s = _steuerungVon(context);
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? anfangswert : null,
      enabled: aktiv && !(s?.speichert ?? false),
      obscureText: verdeckt,
      autofocus: autofokus,
      minLines: zeilen > 1 ? zeilen : null,
      maxLines: zeilen > 1 ? null : 1,
      keyboardType: tastatur ?? (zeilen > 1 ? TextInputType.multiline : null),
      inputFormatters: eingabeFilter,
      decoration: InputDecoration(
        labelText: pflicht ? '$titel *' : titel,
        helperText: hinweis,
        helperMaxLines: 3,
        prefixIcon: vorne,
        prefixText: vorText,
        suffixIcon: hinten,
      ),
      forceErrorText: s?.feldFehlerVon(name),
      validator: Pruefen.alle([if (pflicht) Pruefen.pflicht, pruefen]),
      onChanged: (v) {
        s?.markieren(name);
        geaendert?.call(v);
      },
    );
  }
}

/// Betrag in Franken, gespeichert in **Rappen** (int, kein Rundungsfehler).
/// Nimmt `12`, `12.5`, `12,50`, `1'234.50`, `CHF 12.–`.
class BetragFeld extends StatefulWidget {
  const BetragFeld({
    super.key,
    this.name,
    required this.titel,
    this.rappen,
    required this.geaendert,
    this.pflicht = false,
    this.hinweis,
    this.negativErlaubt = false,
  });
  final String? name;
  final String titel;

  /// Anfangswert in Rappen.
  final int? rappen;
  final ValueChanged<int?> geaendert;
  final bool pflicht;
  final String? hinweis;
  final bool negativErlaubt;

  @override
  State<BetragFeld> createState() => _BetragFeldState();
}

class _BetragFeldState extends State<BetragFeld> {
  late final _text = TextEditingController(text: widget.rappen == null ? '' : betragText(widget.rappen!));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFeld(
        name: widget.name,
        titel: widget.titel,
        controller: _text,
        pflicht: widget.pflicht,
        hinweis: widget.hinweis,
        tastatur: TextInputType.numberWithOptions(decimal: true, signed: widget.negativErlaubt),
        vorText: 'CHF ',
        pruefen: (v) {
          if (v == null || v.trim().isEmpty) return null;
          final r = betragLesen(v);
          if (r == null) return 'Bitte einen Betrag wie 12.50 eingeben.';
          if (r < 0 && !widget.negativErlaubt) return 'Der Betrag darf nicht negativ sein.';
          return null;
        },
        geaendert: (v) => widget.geaendert(betragLesen(v)),
      );
}

/// Text → Rappen; null = kein gueltiger Betrag.
int? betragLesen(String text) {
  var t = text.trim().replaceAll(RegExp(r'^(CHF|Fr\.?|SFr\.?)\s*', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r"[’'\s]"), '').replaceAll(RegExp(r'[.,][-–—]$'), '');
  if (t.isEmpty) return null;
  final m = RegExp(r'^(-?)(\d+)(?:[.,](\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final franken = int.parse(m.group(2)!);
  final r = (m.group(3) ?? '').padRight(2, '0');
  final rappen = franken * 100 + (r.isEmpty ? 0 : int.parse(r));
  return m.group(1) == '-' ? -rappen : rappen;
}

/// Rappen → `1'234.50` (Schweizer Schreibweise, ohne "CHF").
String betragText(int rappen) {
  final neg = rappen < 0;
  final a = rappen.abs();
  final f = '${a ~/ 100}';
  final b = StringBuffer();
  for (var i = 0; i < f.length; i++) {
    if (i > 0 && (f.length - i) % 3 == 0) b.write("'");
    b.write(f[i]);
  }
  return '${neg ? '-' : ''}$b.${(a % 100).toString().padLeft(2, '0')}';
}

/// Datum `27.11.2026`.
String datumText(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Zeit `14:05`.
String zeitText(TimeOfDay z) => '${z.hour.toString().padLeft(2, '0')}:${z.minute.toString().padLeft(2, '0')}';

/// Feld, das beim Antippen einen Dialog oeffnet (Datum, Zeit, Suche).
class _WahlFeld<T> extends FormField<T> {
  _WahlFeld({
    super.key,
    required String? name,
    required String titel,
    required T? wert,
    required String Function(T) text,
    required Future<T?> Function(BuildContext context, T? jetzt) waehlen,
    required ValueChanged<T?> geaendert,
    required IconData symbol,
    bool pflicht = false,
    String? hinweis,
    bool leerbar = true,
  }) : super(
          initialValue: wert,
          validator: (v) => pflicht && v == null ? 'Bitte auswählen.' : null,
          builder: (feld) {
            final context = feld.context;
            final s = _steuerungVon(context);
            final aus = s?.speichert ?? false;
            final v = feld.value;
            Future<void> tippen() async {
              final neu = await waehlen(context, v);
              if (neu == null) return;
              feld.didChange(neu);
              s?.markieren(name);
              geaendert(neu);
            }

            return InkWell(
              onTap: aus ? null : tippen,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                isEmpty: v == null,
                decoration: InputDecoration(
                  labelText: pflicht ? '$titel *' : titel,
                  helperText: hinweis,
                  enabled: !aus,
                  errorText: feld.errorText ?? s?.feldFehlerVon(name),
                  suffixIcon: v != null && leerbar && !pflicht
                      ? IconButton(
                          tooltip: 'Leeren',
                          icon: const Icon(Icons.close),
                          onPressed: aus
                              ? null
                              : () {
                                  feld.didChange(null);
                                  s?.markieren(name);
                                  geaendert(null);
                                },
                        )
                      : Icon(symbol),
                ),
                child: Text(v == null ? '' : text(v)),
              ),
            );
          },
        );
}

/// Datum mit dem Kalender des Systems (deutsch).
class DatumFeld extends StatelessWidget {
  const DatumFeld({
    super.key,
    this.name,
    required this.titel,
    this.wert,
    required this.geaendert,
    this.pflicht = false,
    this.erstes,
    this.letztes,
    this.hinweis,
  });
  final String? name;
  final String titel;
  final DateTime? wert;
  final ValueChanged<DateTime?> geaendert;
  final bool pflicht;
  final DateTime? erstes;
  final DateTime? letztes;
  final String? hinweis;

  @override
  Widget build(BuildContext context) => _WahlFeld<DateTime>(
        name: name,
        titel: titel,
        wert: wert,
        pflicht: pflicht,
        hinweis: hinweis,
        symbol: Icons.calendar_today_outlined,
        text: datumText,
        geaendert: geaendert,
        waehlen: (context, jetzt) => showDatePicker(
          context: context,
          initialDate: jetzt ?? DateTime.now(),
          firstDate: erstes ?? DateTime(2000),
          lastDate: letztes ?? DateTime(2100),
          helpText: titel,
        ),
      );
}

/// Uhrzeit (24 Stunden).
class ZeitFeld extends StatelessWidget {
  const ZeitFeld({super.key, this.name, required this.titel, this.wert, required this.geaendert, this.pflicht = false, this.hinweis});
  final String? name;
  final String titel;
  final TimeOfDay? wert;
  final ValueChanged<TimeOfDay?> geaendert;
  final bool pflicht;
  final String? hinweis;

  @override
  Widget build(BuildContext context) => _WahlFeld<TimeOfDay>(
        name: name,
        titel: titel,
        wert: wert,
        pflicht: pflicht,
        hinweis: hinweis,
        symbol: Icons.schedule,
        text: zeitText,
        geaendert: geaendert,
        waehlen: (context, jetzt) => showTimePicker(
          context: context,
          initialTime: jetzt ?? TimeOfDay.now(),
          helpText: titel,
          builder: (c, k) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: k!),
        ),
      );
}

/// Auswahl aus einer festen Liste (Wert → Text).
class AuswahlFeld<T> extends StatelessWidget {
  const AuswahlFeld({
    super.key,
    this.name,
    required this.titel,
    required this.optionen,
    this.wert,
    required this.geaendert,
    this.pflicht = false,
    this.hinweis,
  });
  final String? name;
  final String titel;
  final Map<T, String> optionen;
  final T? wert;
  final ValueChanged<T?> geaendert;
  final bool pflicht;
  final String? hinweis;

  @override
  Widget build(BuildContext context) {
    final s = _steuerungVon(context);
    return DropdownButtonFormField<T>(
      initialValue: wert,
      isExpanded: true,
      decoration: InputDecoration(labelText: pflicht ? '$titel *' : titel, helperText: hinweis),
      forceErrorText: s?.feldFehlerVon(name),
      validator: (v) => pflicht && v == null ? 'Bitte auswählen.' : null,
      items: [for (final e in optionen.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
      onChanged: (s?.speichert ?? false)
          ? null
          : (v) {
              s?.markieren(name);
              geaendert(v);
            },
    );
  }
}

/// Ja/Nein als Schalter mit Text.
class SchalterFeld extends StatelessWidget {
  const SchalterFeld({super.key, this.name, required this.titel, this.erklaerung, required this.wert, required this.geaendert});
  final String? name;
  final String titel;
  final String? erklaerung;
  final bool wert;
  final ValueChanged<bool> geaendert;

  @override
  Widget build(BuildContext context) {
    final s = _steuerungVon(context);
    final f = s?.feldFehlerVon(name);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(titel),
      subtitle: f != null
          ? Text(f, style: TextStyle(color: Theme.of(context).colorScheme.error))
          : (erklaerung == null ? null : Text(erklaerung!)),
      value: wert,
      onChanged: (s?.speichert ?? false)
          ? null
          : (v) {
              s?.markieren(name);
              geaendert(v);
            },
    );
  }
}

/// Auswahl mit Suche gegen die API (Person, Wohnung, Handwerker …): Tippen
/// oeffnet einen Dialog mit Suchfeld und Treffern.
///
/// ```dart
/// SuchAuswahlFeld<Person>(
///   titel: 'Person', wert: person, text: (p) => p.name,
///   suchen: (q) async => [for (final j in await api.liste('/api/admin/users?q=${Uri.encodeQueryComponent(q)}')) Person.ausJson(j)],
///   geaendert: (p) => setState(() => person = p),
/// )
/// ```
class SuchAuswahlFeld<T> extends StatelessWidget {
  const SuchAuswahlFeld({
    super.key,
    this.name,
    required this.titel,
    this.wert,
    required this.text,
    this.untertitel,
    required this.suchen,
    required this.geaendert,
    this.pflicht = false,
    this.hinweis,
    this.suchHinweis = 'Name eingeben',
  });
  final String? name;
  final String titel;
  final T? wert;
  final String Function(T) text;
  final String? Function(T)? untertitel;
  final Future<List<T>> Function(String suche) suchen;
  final ValueChanged<T?> geaendert;
  final bool pflicht;
  final String? hinweis;
  final String suchHinweis;

  @override
  Widget build(BuildContext context) => _WahlFeld<T>(
        name: name,
        titel: titel,
        wert: wert,
        pflicht: pflicht,
        hinweis: hinweis,
        symbol: Icons.search,
        text: text,
        geaendert: geaendert,
        waehlen: (context, _) => auswahlSuchen<T>(context,
            titel: titel, suchen: suchen, text: text, untertitel: untertitel, suchHinweis: suchHinweis),
      );
}

/// Dialog: suchen und einen Treffer waehlen. null = abgebrochen.
Future<T?> auswahlSuchen<T>(
  BuildContext context, {
  required String titel,
  required Future<List<T>> Function(String suche) suchen,
  required String Function(T) text,
  String? Function(T)? untertitel,
  String suchHinweis = 'Suchen',
}) =>
    showDialog<T>(
      context: context,
      builder: (_) => _SuchDialog<T>(titel: titel, suchen: suchen, text: text, untertitel: untertitel, suchHinweis: suchHinweis),
    );

class _SuchDialog<T> extends StatefulWidget {
  const _SuchDialog({required this.titel, required this.suchen, required this.text, this.untertitel, required this.suchHinweis});
  final String titel;
  final Future<List<T>> Function(String) suchen;
  final String Function(T) text;
  final String? Function(T)? untertitel;
  final String suchHinweis;
  @override
  State<_SuchDialog<T>> createState() => _SuchDialogState<T>();
}

class _SuchDialogState<T> extends State<_SuchDialog<T>> {
  var _treffer = <T>[];
  Object? _fehler;
  bool _laedt = false;
  Timer? _uhr;
  int _runde = 0;

  @override
  void initState() {
    super.initState();
    _los('');
  }

  @override
  void dispose() {
    _uhr?.cancel();
    super.dispose();
  }

  Future<void> _los(String q) async {
    final r = ++_runde;
    setState(() => _laedt = true);
    try {
      final t = await widget.suchen(q.trim());
      if (mounted && r == _runde) {
        setState(() {
          _treffer = t;
          _fehler = null;
          _laedt = false;
        });
      }
    } catch (e) {
      if (mounted && r == _runde) {
        setState(() {
          _fehler = e;
          _laedt = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.titel),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        content: SizedBox(
          width: 480,
          height: 420,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(hintText: widget.suchHinweis, prefixIcon: const Icon(Icons.search)),
              onChanged: (q) {
                _uhr?.cancel();
                _uhr = Timer(const Duration(milliseconds: 300), () => _los(q));
              },
              onSubmitted: (_) {
                if (_treffer.length == 1) Navigator.pop(context, _treffer.first);
              },
            ),
            const SizedBox(height: 4),
            if (_laedt) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
            Expanded(
              child: _fehler != null
                  ? Center(child: Text(fehlerText(_fehler!), textAlign: TextAlign.center))
                  : _treffer.isEmpty && !_laedt
                      ? const Center(child: Text('Keine Treffer.'))
                      : ListView.builder(
                          itemCount: _treffer.length,
                          itemBuilder: (context, i) {
                            final t = _treffer[i];
                            final u = widget.untertitel?.call(t);
                            return ListTile(
                              title: Text(widget.text(t)),
                              subtitle: u == null ? null : Text(u),
                              onTap: () => Navigator.pop(context, t),
                            );
                          },
                        ),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen'))],
      );
}

/// Rueckfrage vor Loeschen/Entziehen (roter Knopf). true = bestaetigt.
Future<bool> loeschenBestaetigen(BuildContext context, String was, {String? text, String ja = 'Löschen'}) =>
    frage(context, '$was ${ja.toLowerCase()}?', text ?? 'Das lässt sich nicht rückgängig machen.', ja: ja, gefaehrlich: true);
