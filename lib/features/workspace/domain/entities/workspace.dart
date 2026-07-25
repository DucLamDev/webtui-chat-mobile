final class Workspace {
  const Workspace({
    required this.id,
    required this.slug,
    required this.name,
    required this.plan,
    required this.status,
    this.description,
    this.ownerId,
  });

  final String id;
  final String slug;
  final String name;
  final String plan;
  final String status;
  final String? description;
  final String? ownerId;

  bool get isActive => status == 'active';
}
