import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:telebunda_app/core/utils/formatters.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  test('formats UTC slot instants in WIB without changing the instant', () {
    final slotStart = DateTime.parse('2026-11-05T02:00:00Z');

    expect(Formatters.formatShortDate(slotStart), '5 Nov 2026');
    expect(Formatters.formatTime(slotStart), '09:00 WIB');
    expect(Formatters.formatDateTime(slotStart), '5 Nov 2026, 09:00 WIB');
    expect(slotStart.toUtc(), DateTime.utc(2026, 11, 5, 2));
  });
}
