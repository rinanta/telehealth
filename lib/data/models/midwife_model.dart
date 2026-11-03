class Midwife {
  final String uid;
  final String name;
  final String credentialLabel; // contoh: Bdn. Siti Rahmawati, S.Tr.Keb
  final String bio;
  final double rating;
  final int reviewCount;
  final int experienceYears;
  final int price; // contoh: 50000
  final String strNumber;
  final String hospitalAffiliation;
  final bool active;

  const Midwife({
    required this.uid,
    required this.name,
    required this.credentialLabel,
    required this.bio,
    this.rating = 4.9,
    this.reviewCount = 128,
    required this.experienceYears,
    required this.price,
    required this.strNumber,
    required this.hospitalAffiliation,
    this.active = true,
  });

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'name': name,
    'credential_label': credentialLabel,
    'bio': bio,
    'rating': rating,
    'review_count': reviewCount,
    'experience_years': experienceYears,
    'price': price,
    'str_number': strNumber,
    'hospital_affiliation': hospitalAffiliation,
    'active': active,
  };

  factory Midwife.fromJson(Map<String, dynamic> json) => Midwife(
    uid: json['uid'] as String,
    name: json['name'] as String,
    credentialLabel: json['credential_label'] as String,
    bio: json['bio'] as String,
    rating: (json['rating'] as num?)?.toDouble() ?? 4.9,
    reviewCount: json['review_count'] as int? ?? 0,
    experienceYears: json['experience_years'] as int? ?? 5,
    price: json['price'] as int? ?? 50000,
    strNumber: json['str_number'] as String? ?? '',
    hospitalAffiliation: json['hospital_affiliation'] as String? ?? 'Praktik Mandiri Bidan',
    active: json['active'] as bool? ?? true,
  );
}
