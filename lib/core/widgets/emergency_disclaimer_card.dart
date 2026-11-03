import 'package:flutter/material.dart';

class EmergencyDisclaimerCard extends StatelessWidget {
  final String title;
  final String message;
  final bool isDismissible;

  const EmergencyDisclaimerCard({
    super.key,
    this.title = 'Penting: Informasi Edukasi & Bukan Diagnosis',
    this.message = 'Layanan AI dan chat konsultasi TeleBunda merupakan sarana edukasi awal. Apabila Anda mengalami tanda bahaya seperti perdarahan hebat, nyeri kepala berat, kejang, atau janin tidak bergerak, segera ke IGD rumah sakit terdekat.',
    this.isDismissible = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.emergency_rounded,
            color: Color(0xFFD97706),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
