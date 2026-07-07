/// Seed data for the fixed UUDS Aero inspector roster. Used once to
/// populate the employees table on first run (and for anyone upgrading
/// from an older version of the app). After that, the database is the
/// single source of truth — this list is not read at runtime.
class InspectorRoster {
  /// (name, idNumber) — idNumber is '' for staff with no ID on file.
  static const List<(String, String)> seed = [
    ('CHARITH NIRMAL', '829'),
    ('VINCE KAVEEN', '288'),
    ('ANUSHKA SRIMAL', '129'),
    ('PARESH ABRAHAM', ''),
    ('KRISHEN MADUSHA', '418'),
    ('MANJULA JANAKA RANATHUNGA', '921'),
    ('JANATH BINENDRA', '669'),
    ('MOHAN ROSHAN', '1296'),
    ('KHURRAM MUNIR', '476'),
    ('SOM BAHADUR', '209'),
    ('MENAKA ISURANGA', '1272'),
    ('RAJIKA DILIP', '487'),
    ('DILSHAN BATADUWA', '194'),
    ('KALANA THIWANKA', '1271'),
    ('TUAN IFTIKHAAR', '377'),
    ('ASELA AMUGODA', '582'),
    ('MANJULA WATTHE', '071'),
    ('MALITHA RANGANA', '1488'),
  ];
}
