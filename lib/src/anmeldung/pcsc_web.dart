// SPDX-License-Identifier: GPL-3.0-or-later

/// Web: kein PC/SC. Gleiche Schnittstelle wie pcsc_ffi.dart; [oeffnen] liefert
/// immer null (kein Leser).
abstract class Pcsc {
  static Pcsc? oeffnen() => null;

  List<String> leser();

  String? uid(String leser);

  void schliessen();
}
