enum UserRole { owner, worker }

class Account {
  const Account({required this.id, required this.role});

  final String id;
  final UserRole role;
}
