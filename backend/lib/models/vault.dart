class Vault {
  final String id;
  final String userId;
  final String name;
  final String remoteUrl;
  final String clonePath;
  final String? sshKeyId;
  final String? lastSyncedAt;
  final String createdAt;

  const Vault({
    required this.id,
    required this.userId,
    required this.name,
    required this.remoteUrl,
    required this.clonePath,
    this.sshKeyId,
    this.lastSyncedAt,
    required this.createdAt,
  });

  factory Vault.fromRow(Map<String, dynamic> row) => Vault(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        name: row['name'] as String,
        remoteUrl: row['remote_url'] as String,
        clonePath: row['clone_path'] as String,
        sshKeyId: row['ssh_key_id'] as String?,
        lastSyncedAt: row['last_synced_at'] as String?,
        createdAt: row['created_at'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'remoteUrl': remoteUrl,
        'sshKeyId': sshKeyId,
        'lastSyncedAt': lastSyncedAt,
        'createdAt': createdAt,
      };
}
