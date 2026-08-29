class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessage;

  /// Name of the project folder this chat works in, relative to the workspace
  /// root (e.g. "my-project"). Null = no project bound (a general chat).
  final String? projectPath;

  ChatSession({
    required this.id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastMessage,
    this.projectPath,
  })  : title = title ?? 'New Chat',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastMessage': lastMessage,
        'projectPath': projectPath,
      };

  factory ChatSession.fromMap(Map<dynamic, dynamic> map) => ChatSession(
        id: map['id'] ?? '',
        title: map['title'] ?? 'New Chat',
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
        lastMessage: map['lastMessage'],
        projectPath: map['projectPath'],
      );

  /// [clearProject] unbinds the chat from its folder. A null [projectPath]
  /// cannot say that on its own — it means "leave it alone".
  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    String? lastMessage,
    String? projectPath,
    bool clearProject = false,
  }) =>
      ChatSession(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        lastMessage: lastMessage ?? this.lastMessage,
        projectPath: clearProject ? null : (projectPath ?? this.projectPath),
      );
}
