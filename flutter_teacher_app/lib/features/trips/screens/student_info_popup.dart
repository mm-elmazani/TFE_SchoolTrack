/// Popup affichant les données personnelles d'un élève.
/// Accessible depuis TripSummaryScreen en cliquant sur un élève.
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import '../models/offline_bundle.dart';

/// Affiche le popup d'informations d'un élève sous forme de BottomSheet.
void showStudentInfoPopup(BuildContext context, OfflineStudent student) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _StudentInfoSheet(student: student),
  );
}

class _StudentInfoSheet extends StatefulWidget {
  final OfflineStudent student;

  const _StudentInfoSheet({required this.student});

  @override
  State<_StudentInfoSheet> createState() => _StudentInfoSheetState();
}

class _StudentInfoSheetState extends State<_StudentInfoSheet> {
  Uint8List? _photoBytes;
  bool _loadingPhoto = false;

  @override
  void initState() {
    super.initState();
    if (widget.student.photoUrl != null) _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    setState(() => _loadingPhoto = true);
    try {
      final bytes = await ApiClient().getStudentPhoto(widget.student.id);
      if (mounted && bytes != null) {
        setState(() => _photoBytes = Uint8List.fromList(bytes));
      }
    } finally {
      if (mounted) setState(() => _loadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Poignée
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Photo + nom
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _buildAvatar(student),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.fullName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (student.className != null)
                          Text(
                            student.className!,
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Divider(height: 1),

            // Infos de contact
            if (student.phone != null) ...[
              _ContactTile(
                icon: Icons.phone,
                label: 'Téléphone',
                value: student.phone!,
                color: const Color(0xFF0F9D58),
                onTap: () => _copyToClipboard(context, student.phone!),
              ),
              const Divider(height: 1, indent: 56),
            ],
            if (student.email != null) ...[
              _ContactTile(
                icon: Icons.email,
                label: 'Email',
                value: student.email!,
                color: const Color(0xFF1A73E8),
                onTap: () => _copyToClipboard(context, student.email!),
              ),
              const Divider(height: 1, indent: 56),
            ],
            if (student.phone == null && student.email == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Aucune coordonnée disponible',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(OfflineStudent student) {
    if (_loadingPhoto) {
      return const CircleAvatar(
        radius: 32,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_photoBytes != null) {
      return CircleAvatar(
        radius: 32,
        backgroundImage: MemoryImage(_photoBytes!),
      );
    }
    // Fallback initiales
    return CircleAvatar(
      radius: 32,
      backgroundColor: const Color(0xFF1A73E8).withOpacity(0.15),
      child: Text(
        '${student.firstName[0]}${student.lastName[0]}'.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF1A73E8),
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copié : $value'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _ContactTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      subtitle: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      trailing: Icon(Icons.copy, size: 18, color: Colors.grey[400]),
      onTap: onTap,
    );
  }
}
