class User {
  final String id;
  final String email;
  final String passwordHash;
  final String pbkdf2Salt;
  final String encryptionSalt;
  final String createdAt;
  final String updatedAt;

  const User({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.pbkdf2Salt,
    required this.encryptionSalt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromRow(Map<String, dynamic> row) => User(
        id: row['id'] as String,
        email: row['email'] as String,
        passwordHash: row['password_hash'] as String,
        pbkdf2Salt: row['pbkdf2_salt'] as String,
        encryptionSalt: row['encryption_salt'] as String,
        createdAt: row['created_at'] as String,
        updatedAt: row['updated_at'] as String,
      );

  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'email': email,
        'createdAt': createdAt,
      };
}
