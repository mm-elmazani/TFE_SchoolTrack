import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';

/// Ecran de gestion des utilisateurs (Direction uniquement).
class UserListScreen extends StatelessWidget {
  const UserListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UserProvider()..loadUsers(),
      child: const _UserListBody(),
    );
  }
}

class _UserListBody extends StatelessWidget {
  const _UserListBody();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<UserProvider>(
      builder: (context, provider, _) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Toolbar
              Row(
                children: [
                  Text(
                    '${provider.users.length} utilisateur(s)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _showCreateDialog(context, provider),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Nouveau compte'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Erreur
              if (provider.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(provider.error!, style: TextStyle(color: colorScheme.error))),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: provider.clearError,
                        ),
                      ],
                    ),
                  ),
                ),

              // Table
              Expanded(
                child: provider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: SizedBox(
                          width: double.infinity,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            ),
                            columns: const [
                              DataColumn(label: Text('Nom')),
                              DataColumn(label: Text('Email')),
                              DataColumn(label: Text('Rôle')),
                              DataColumn(label: Text('2FA')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: provider.users.map((u) {
                              final role = u['role'] as String? ?? '';
                              return DataRow(cells: [
                                DataCell(Text(
                                  '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim(),
                                )),
                                DataCell(Text(u['email'] ?? '')),
                                DataCell(_RoleBadge(role: role)),
                                DataCell(Icon(
                                  u['is_2fa_enabled'] == true ? Icons.verified_user : Icons.shield_outlined,
                                  color: u['is_2fa_enabled'] == true ? Colors.green : Colors.grey,
                                  size: 20,
                                )),
                                DataCell(
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, color: colorScheme.error, size: 20),
                                    tooltip: 'Supprimer',
                                    onPressed: () => _confirmDelete(context, provider, u),
                                  ),
                                ),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateDialog(BuildContext context, UserProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => _CreateUserDialog(provider: provider),
    );
  }

  void _confirmDelete(BuildContext context, UserProvider provider, Map<String, dynamic> user) {
    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet utilisateur ?'),
        content: Text('Voulez-vous vraiment supprimer le compte de $name (${user['email']}) ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await provider.deleteUser(user['id']);
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Utilisateur supprime')),
                );
              }
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog creation utilisateur
// ---------------------------------------------------------------------------

class _CreateUserDialog extends StatefulWidget {
  final UserProvider provider;
  const _CreateUserDialog({required this.provider});

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _role = 'TEACHER';
  bool _loading = false;
  String? _error;

  static const _roles = {
    'DIRECTION': 'Direction',
    'TEACHER': 'Enseignant',
    'OBSERVER': 'Observateur',
    'ADMIN_TECH': 'Admin Technique',
  };

  @override
  void dispose() {
    _emailCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _loading = true; _error = null; });

    final ok = await widget.provider.createUser(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      role: _role,
      firstName: _firstNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
    );

    if (!mounted) return;

    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utilisateur cree avec succes')),
      );
    } else {
      setState(() {
        _loading = false;
        _error = widget.provider.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau compte utilisateur'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameCtrl,
                      decoration: const InputDecoration(labelText: 'Prénom', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email *', border: OutlineInputBorder()),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email requis';
                  if (!v.contains('@')) return 'Email invalide';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe *',
                  border: OutlineInputBorder(),
                  helperText: 'Min 8 car., 1 majuscule, 1 chiffre, 1 special',
                  helperMaxLines: 2,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Mot de passe requis';
                  if (v.length < 8) return 'Min 8 caracteres';
                  if (!RegExp(r'[A-Z]').hasMatch(v)) return '1 majuscule requise';
                  if (!RegExp(r'\d').hasMatch(v)) return '1 chiffre requis';
                  if (!RegExp(r'[^A-Za-z0-9]').hasMatch(v)) return '1 caractere special requis';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Rôle *', border: OutlineInputBorder()),
                items: _roles.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _role = v!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Créer'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Badge role
// ---------------------------------------------------------------------------

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      'DIRECTION' => ('Direction', Colors.blue),
      'TEACHER' => ('Enseignant', Colors.teal),
      'OBSERVER' => ('Observateur', Colors.grey),
      'ADMIN_TECH' => ('Admin Tech', Colors.orange),
      _ => (role, Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color.shade700)),
    );
  }
}
