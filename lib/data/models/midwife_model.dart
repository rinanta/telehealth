class Midwife {
  final String uid;
  final String name;
  final String credentialLabel; // contoh: Bdn. Siti Rahmawati, S.Tr.Keb
  final String? bio;
  final double? rating;
  final int? reviewCount;
  final int? experienceYears;
  final int? price; // contoh: 50000
  final String? strNumber;
  final String? hospitalAffiliation;
  final bool active;

  const Midwife({
    required this.uid,
    required this.name,
    required this.credentialLabel,
    this.bio,
    this.rating,
    this.reviewCount,
    this.experienceYears,
    this.price,
    this.strNumber,
    this.hospitalAffiliation,
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
    name: json['display_name'] as String,
    credentialLabel: json['credential_label'] as String,
    bio: json['bio'] as String?,
    rating: (json['rating'] as num?)?.toDouble(),
    reviewCount: json['review_count'] as int?,
    experienceYears: json['experience_years'] as int?,
    price: (json['price'] as num?)?.toInt(),
    strNumber: json['str_number'] as String?,
    hospitalAffiliation: json['hospital_affiliation'] as String?,
    active: json['active'] as bool? ?? true,
  );
}
