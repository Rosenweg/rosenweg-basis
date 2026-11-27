// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Antwortet wie die Haupt-API, mit erfundenen Daten (keine echten Personen).
/// Fuer Tests, Bildschirmfotos und Entwicklung ohne Server
/// (--dart-define=RW_ATTRAPPE=1). Neue Endpunkte der App hier nachbilden.
class Attrappe implements Transport {
  /// Alle Anfragen in der Reihenfolge (fuer Tests).
  final anfragen = <({String methode, String pfad, Object? koerper})>[];

  /// Naechste Antwort fuer einen Pfad erzwingen (Tests), z. B. einen Fehler:
  /// `erzwungen['GET /api/auth/me'] = (status: 503, json: null);`
  final erzwungen = <String, ApiAntwort>{};

  final _ich = <String, dynamic>{
    'id': 7,
    'username': 'erika.muster',
    'name': 'Erika Muster',
    'email': 'erika.muster@example.org',
    'role': 'user',
    'groups': ['stweg3-eigentuemer', 'waschkueche'],
    'permissions': {'dashboard': 'read'},
  };

  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    anfragen.add((methode: methode, pfad: pfad, koerper: koerper));
    final z = erzwungen.remove('$methode $pfad');
    if (z != null) return z;
    switch ('$methode $pfad') {
      case 'GET /api/auth/me':
        return (status: 200, json: {'user': _ich});
    }
    return (status: 404, json: {'error': 'Nicht gefunden: $methode $pfad'});
  }
}
