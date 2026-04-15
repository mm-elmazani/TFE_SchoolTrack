import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../providers/auth_provider.dart';

/// Ecran de connexion de l'app enseignants (US 6.1).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _totpCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _show2FA = false;

  // Ecoles
  List<Map<String, dynamic>> _schools = [];
  String? _selectedSlug;
  bool _loadingSchools = true;
  String? _schoolsError;

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  Future<void> _loadSchools() async {
    try {
      final schools = await ApiClient().getSchoolsPublic();
      if (!mounted) return;
      setState(() {
        _schools = schools;
        _loadingSchools = false;
        // Pre-selectionner si une seule ecole
        if (schools.length == 1) {
          _selectedSlug = schools[0]['slug'] as String?;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSchools = false;
        _schoolsError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSchools = false;
        _schoolsError = 'Impossible de charger les ecoles';
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _totpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      _emailCtrl.text.trim(),
      _passwordCtrl.text,
      totpCode: _show2FA ? _totpCtrl.text.trim() : null,
      schoolSlug: _selectedSlug,
    );

    if (!mounted) return;

    if (success) {
      context.go('/');
    } else if (auth.error == '2FA_REQUIRED') {
      setState(() => _show2FA = true);
      auth.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.school, size: 48, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SchoolTrack',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Espace enseignant',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 40),

                  // Ecole
                  if (_loadingSchools)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_schoolsError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _schoolsError!,
                              style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _loadingSchools = true;
                                _schoolsError = null;
                              });
                              _loadSchools();
                            },
                            child: const Text('Reessayer'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      value: _selectedSlug,
                      decoration: InputDecoration(
                        labelText: 'Ecole',
                        prefixIcon: const Icon(Icons.school_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _schools.map((school) {
                        return DropdownMenuItem<String>(
                          value: school['slug'] as String?,
                          child: Text(school['name'] as String? ?? ''),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedSlug = value),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Ecole requise';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Email
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email requis';
                      if (!v.contains('@')) return 'Email invalide';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Mot de passe
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    textInputAction: _show2FA ? TextInputAction.next : TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Mot de passe requis';
                      return null;
                    },
                    onFieldSubmitted: _show2FA ? null : (_) => _submit(),
                  ),

                  // Champ 2FA
                  if (_show2FA) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _totpCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 6,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Code 2FA',
                        prefixIcon: const Icon(Icons.security),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        counterText: '',
                        hintText: '000000',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().length != 6) return 'Code a 6 chiffres requis';
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 8),
                    // Bouton pour ouvrir l'app email sans quitter SchoolTrack
                    // (évite que Android tue l'app lors du changement d'app — problème OPPO/Xiaomi)
                    TextButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse('mailto:');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.mail_outline, size: 18),
                      label: const Text('Ouvrir les emails'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Message d'erreur
                  Consumer<AuthProvider>(
                    builder: (context, auth, child) {
                      if (auth.error == null || auth.error == '2FA_REQUIRED') {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  auth.error!,
                                  style: TextStyle(color: colorScheme.error, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Bouton connexion
                  Consumer<AuthProvider>(
                    builder: (context, auth, child) {
                      return SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: auth.isLoading ? null : _submit,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Se connecter', style: TextStyle(fontSize: 16)),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
