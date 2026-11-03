import 'package:intl/intl.dart';

class Formatters {
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static String toRupiah(num amount) {
    return _currencyFormat.format(amount);
  }

  static String formatDate(DateTime dateTime) {
    final formatter = DateFormat('EEEE, d MMMM yyyy', 'id_ID');
    return formatter.format(dateTime);
  }

  static String formatShortDate(DateTime dateTime) {
    final formatter = DateFormat('d MMM yyyy', 'id_ID');
    return formatter.format(dateTime);
  }

  static String formatTime(DateTime dateTime) {
    final formatter = DateFormat('HH:mm', 'id_ID');
    return '${formatter.format(dateTime)} WIB';
  }

  static String formatDateTime(DateTime dateTime) {
    return '${formatShortDate(dateTime)}, ${formatTime(dateTime)}';
  }

  static String formatTimer(int secondsRemaining) {
    if (secondsRemaining <= 0) return '00:00';
    final minutes = secondsRemaining ~/ 60;
    final seconds = secondsRemaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
