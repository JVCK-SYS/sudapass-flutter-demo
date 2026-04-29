import 'package:flutter/material.dart';
import '../auth_service.dart';
import 'home_screen.dart';

class SuccessScreen extends StatelessWidget {
  final SudaPassUser user;
  const SuccessScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Success badge
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF4ADE80), size: 22),
                  const SizedBox(width: 8),
                  const Text('Authenticated via SudaPass',
                      style: TextStyle(color: Color(0xFF4ADE80), fontSize: 14)),
                ],
              ),
              const SizedBox(height: 32),

              // Citizen info card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (user.name != null) ...[
                      const Text('Full Name',
                          style: TextStyle(color: Colors.white38, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(user.name!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                    ],
                    _field('National Number', user.nationalNumber),
                    _field('Email', user.email),
                    _field('Gender', user.gender),
                    _field('Date of Birth', user.birthdate),
                    _field('Nationality', user.nationality),
                    _field('Assurance Level', user.assuranceLevel),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Raw JSON — useful for developers
              ExpansionTile(
                title: const Text('Raw user data (JSON)',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                iconColor: Colors.white38,
                collapsedIconColor: Colors.white38,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _prettyJson(user.raw),
                      style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              OutlinedButton.icon(
                onPressed: () async {
                  await auth.logout();
                  if (!context.mounted) return;
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()));
                },
                icon: const Icon(Icons.logout, color: Colors.white54),
                label: const Text('Sign out',
                    style: TextStyle(color: Colors.white54)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, String? value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 15)),
        ],
      ),
    );
  }

  String _prettyJson(Map<String, dynamic> json) {
    final buffer = StringBuffer();
    json.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    return buffer.toString();
  }
}
