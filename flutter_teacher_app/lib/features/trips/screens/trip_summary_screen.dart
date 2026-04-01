/// Écran de résumé d'un voyage avant de démarrer les checkpoints.
/// Affiche les infos du voyage + liste des élèves inscrits (cliquables).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/local_db.dart';
import '../models/offline_bundle.dart';
import 'student_info_popup.dart';

class TripSummaryScreen extends StatefulWidget {
  final String tripId;
  final String tripDestination;

  const TripSummaryScreen({
    super.key,
    required this.tripId,
    required this.tripDestination,
  });

  @override
  State<TripSummaryScreen> createState() => _TripSummaryScreenState();
}

class _TripSummaryScreenState extends State<TripSummaryScreen> {
  List<OfflineStudent>? _students;
  OfflineTripInfo? _tripInfo;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = LocalDb.instance;
      final students = await db.getStudents(widget.tripId);
      // Charger les infos voyage depuis la DB locale
      final tripRow = await db.getTripInfo(widget.tripId);
      if (mounted) {
        setState(() {
          _students = students;
          _tripInfo = tripRow;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tripDestination),
        backgroundColor: const Color(0xFF1A73E8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _error != null
          ? _buildError()
          : _students == null
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(),
      bottomNavigationBar: _buildStartButton(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final students = _students!;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildTripCard()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Élèves inscrits (${students.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A73E8),
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _StudentTile(
              student: students[index],
              onTap: () => showStudentInfoPopup(context, students[index]),
            ),
            childCount: students.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildTripCard() {
    final trip = _tripInfo;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A73E8).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A73E8).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.explore, color: Color(0xFF1A73E8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.tripDestination,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          if (trip != null) ...[
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.calendar_today, label: 'Date', value: trip.date),
            if (trip.description != null && trip.description!.isNotEmpty)
              _InfoRow(icon: Icons.notes, label: 'Description', value: trip.description!),
            _InfoRow(
              icon: Icons.people,
              label: 'Élèves',
              value: '${_students?.length ?? trip.studentCount}',
            ),
            if (trip.classes.isNotEmpty)
              _InfoRow(
                icon: Icons.class_,
                label: 'Classes',
                value: trip.classes.join(', '),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: () => context.push(
            '/checkpoints',
            extra: {
              'tripId': widget.tripId,
              'tripDestination': widget.tripDestination,
            },
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F9D58),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Commencer les checkpoints', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Widgets internes
// ----------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text('$label : ', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  final OfflineStudent student;
  final VoidCallback onTap;

  const _StudentTile({required this.student, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF1A73E8).withOpacity(0.15),
        child: Text(
          '${student.firstName[0]}${student.lastName[0]}'.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF1A73E8),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      title: Text(student.fullName, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: student.className != null
          ? Text(student.className!, style: TextStyle(color: Colors.grey[600], fontSize: 12))
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
