class MayarCheckout {
  final String paymentId;
  final String checkoutUrl;
  final String status;

  const MayarCheckout({
    required this.paymentId,
    required this.checkoutUrl,
    required this.status,
  });

  factory MayarCheckout.fromJson(Map<String, dynamic> json) {
    final paymentId = json['payment_id'];
    final checkoutUrl = json['checkout_url'];
    final status = json['status'];
    final uri = checkoutUrl is String ? Uri.tryParse(checkoutUrl) : null;

    if (paymentId is! String || paymentId.isEmpty) {
      throw const FormatException('The API returned an invalid payment ID.');
    }
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('The API returned an invalid checkout URL.');
    }
    if (status is! String || status.isEmpty) {
      throw const FormatException(
        'The API returned an invalid payment status.',
      );
    }

    return MayarCheckout(
      paymentId: paymentId,
      checkoutUrl: checkoutUrl,
      status: status,
    );
  }
}
