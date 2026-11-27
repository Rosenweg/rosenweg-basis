// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../netz/fehler.dart';
import '../rechte.dart';
import 'bausteine.dart';

/// Stellt die [RosenwegRechte] der Sitzung unter sich bereit.
/// [AnmeldeTor] legt ihn automatisch um den Inhalt der App; in Tests oder
/// eigenen Fenstern von Hand.
class RechteBereich extends InheritedNotifier<RosenwegRechte> {
  const RechteBereich({super.key, required RosenwegRechte rechte, required super.child}) : super(notifier: rechte);

  /// Die Rechte ueber [context]; meldet Aenderungen (neu bauen).
  static RosenwegRechte von(BuildContext context) {
    final r = vielleicht(context);
    assert(r != null, 'Kein RechteBereich ueber diesem Widget (AnmeldeTor/RosenwegRahmen legt ihn an).');
    return r!;
  }

  static RosenwegRechte? vielleicht(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RechteBereich>()?.notifier;
}

/// Zeigt [kind] nur, wenn die Person das Recht hat — sonst nichts (Knoepfe,
/// Menuepunkte) oder mit [hinweis] den einheitlichen Satz "Keine
/// Berechtigung" (ganze Seiten).
///
/// ```dart
/// NurMit(recht: 'reklamationen', zugriff: Zugriff.schreiben, kind: FilledButton(...))
/// NurMit(recht: 'rechteverwaltung', stufe: Anmeldestufe.konto, hinweis: true, kind: RechteSeite())
/// ```
///
/// Mit [stufe]: reicht die Anmeldung nicht (z. B. nur Karte), zeigt [hinweis]
/// "Mit Rosenweg-Konto anmelden" samt Knopf; ohne [hinweis] bleibt [kind]
/// verborgen.
class NurMit extends StatefulWidget {
  const NurMit({
    super.key,
    this.recht,
    this.eines,
    this.zugriff = Zugriff.lesen,
    this.stufe,
    required this.kind,
    this.sonst,
    this.hinweis = false,
    this.rechte,
  }) : assert(recht != null || eines != null || stufe != null, 'recht, eines oder stufe angeben');

  /// Schluessel der Seite in `permissions` (z. B. 'reklamationen').
  final String? recht;

  /// Mindestens eine dieser Seiten (wie `permAny` im Menue).
  final List<String>? eines;
  final Zugriff zugriff;

  /// Mindest-Stufe der Anmeldung (null = egal).
  final Anmeldestufe? stufe;
  final Widget kind;

  /// Statt nichts (z. B. ein ausgegrauter Knopf). Vorrang vor [hinweis].
  final Widget? sonst;

  /// Ganze Seite: einheitlichen Hinweis statt nichts zeigen.
  final bool hinweis;

  /// Ohne [RechteBereich] (z. B. in Tests).
  final RosenwegRechte? rechte;

  @override
  State<NurMit> createState() => _NurMitState();
}

class _NurMitState extends State<NurMit> {
  @override
  Widget build(BuildContext context) {
    final r = widget.rechte ?? RechteBereich.von(context);
    if (widget.rechte != null) {
      // Ohne Bereich selber auf Aenderungen hoeren
      return ListenableBuilder(listenable: r, builder: (context, _) => _bauen(context, r));
    }
    return _bauen(context, r);
  }

  Widget _bauen(BuildContext context, RosenwegRechte r) {
    final leer = widget.sonst ?? const SizedBox.shrink();
    final s = r.stand;
    if (s == null) {
      if (!r.laedt && r.fehler == null) {
        // Erstes Mal: laden (nach dem Bauen, nicht waehrenddessen)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !r.geladen && !r.laedt) r.laden().then((_) {}, onError: (_) {});
        });
      }
      if (!widget.hinweis) return leer;
      if (r.fehler != null) {
        return FehlerAnzeige(text: fehlerText(r.fehler!), nochmals: () => r.laden(neu: true));
      }
      return const LadeAnzeige(text: 'Berechtigungen werden geprüft …');
    }
    final recht = widget.recht;
    final eines = widget.eines;
    final darf = (recht == null || s.darf(recht, widget.zugriff)) && (eines == null || s.darfEine(eines, widget.zugriff));
    if (!darf) return widget.sonst ?? (widget.hinweis ? const KeineBerechtigungAnzeige() : leer);
    final stufe = widget.stufe;
    if (stufe != null && !r.hatStufe(stufe)) {
      return widget.sonst ?? (widget.hinweis ? StufeNoetigAnzeige(stufe: stufe, rechte: r) : leer);
    }
    return widget.kind;
  }
}

/// Einheitlicher Hinweis fuer alle Apps: angemeldet, aber ohne Recht.
class KeineBerechtigungAnzeige extends StatelessWidget {
  const KeineBerechtigungAnzeige({super.key, this.text});

  /// Eigener Satz statt des allgemeinen (z. B. Text der API).
  final String? text;

  static const standardText = 'Für diesen Bereich fehlt dir die Berechtigung. '
      'Wenn du sie brauchst, melde dich bei der Technik oder beim Ausschuss.';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Keine Berechtigung', style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text ?? standardText, style: t.bodyMedium, textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

/// Recht vorhanden, aber die Anmeldung ist zu schwach (z. B. nur Karte):
/// Knopf "Mit Rosenweg-Konto anmelden" bzw. "Bestätigen".
class StufeNoetigAnzeige extends StatefulWidget {
  const StufeNoetigAnzeige({super.key, required this.stufe, this.rechte});
  final Anmeldestufe stufe;
  final RosenwegRechte? rechte;

  static String textFuer(Anmeldestufe stufe) => stufe == Anmeldestufe.kontoFrisch
      ? 'Für diesen Schritt bitte kurz mit dem Rosenweg-Konto bestätigen.'
      : 'Für diesen Bereich reicht die Rosenweg-Karte nicht. Bitte mit dem Rosenweg-Konto anmelden.';

  @override
  State<StufeNoetigAnzeige> createState() => _StufeNoetigAnzeigeState();
}

class _StufeNoetigAnzeigeState extends State<StufeNoetigAnzeige> {
  bool _laeuft = false;

  Future<void> _los() async {
    final r = widget.rechte ?? RechteBereich.von(context);
    setState(() => _laeuft = true);
    try {
      final ok = await r.stufeErreichen(widget.stufe);
      if (!ok && mounted) zeigeMeldung(context, 'Nicht bestätigt.');
    } catch (e) {
      if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final frisch = widget.stufe == Anmeldestufe.kontoFrisch;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.verified_user_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(frisch ? 'Bitte bestätigen' : 'Rosenweg-Konto nötig', style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(StufeNoetigAnzeige.textFuer(widget.stufe), style: t.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _laeuft ? null : _los,
              icon: _laeuft
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: Text(frisch ? 'Bestätigen' : 'Mit Rosenweg-Konto anmelden'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Fuehrt [aktion] aus; lehnt die API mit "bitte bestaetigen" ab (403 mit
/// `reauth` oder `stufe`), fragt die Person, bestaetigt mit dem
/// Rosenweg-Konto und versucht es **einmal** nochmals. Andere Fehler gehen
/// unveraendert weiter. null = Person hat abgebrochen.
///
/// ```dart
/// await mitBestaetigung(context, () => api.post('/api/auth/change-password', {...}));
/// ```
Future<T?> mitBestaetigung<T>(BuildContext context, Future<T> Function() aktion, {RosenwegRechte? rechte}) async {
  try {
    return await aktion();
  } on KeineBerechtigung catch (e) {
    final stufe = e.neuAnmelden ? Anmeldestufe.kontoFrisch : Anmeldestufe.ausText(e.stufeNoetig);
    if (stufe == null || !context.mounted) rethrow;
    final r = rechte ?? RechteBereich.von(context);
    final ja = await frage(context, stufe == Anmeldestufe.kontoFrisch ? 'Bitte bestätigen' : 'Rosenweg-Konto nötig',
        StufeNoetigAnzeige.textFuer(stufe),
        ja: stufe == Anmeldestufe.kontoFrisch ? 'Bestätigen' : 'Anmelden');
    if (!ja) return null;
    // Die API hat gerade "zu schwach" gesagt: auf jeden Fall bestaetigen
    if (!await r.bestaetigen()) return null;
    return aktion();
  }
}


/// Hinweis „Bestätigung per E-Mail nötig“ (202 der API, siehe
/// [BestaetigungPerEmail]): Die heikle Aktion wartet, bis die Person den Link
/// in der Mail bestaetigt. Mit dem Rosenweg-Konto angemeldet laeuft sie sofort.
Future<void> zeigeEmailBestaetigung(BuildContext context, BestaetigungPerEmail e) {
  final bis = e.ablauf;
  final zeit = bis == null ? null : '${bis.hour.toString().padLeft(2, '0')}:${bis.minute.toString().padLeft(2, '0')}';
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.mark_email_unread_outlined, size: 40),
      title: const Text('Bestätigung per E-Mail nötig'),
      content: Text([
        e.text,
        if (zeit != null) 'Der Link gilt bis $zeit Uhr.',
        'Mit der Karte angemeldet braucht diese Aktion deine Bestätigung. Mit dem Rosenweg-Konto angemeldet geht sie sofort.',
      ].join('\n\n')),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Verstanden'))],
    ),
  );
}
