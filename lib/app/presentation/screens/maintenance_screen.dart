import 'package:flutter/material.dart';

class MaintenanceScreen extends StatelessWidget {
  final String? message;
  const MaintenanceScreen({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.build_circle_outlined, size: 80, color: Color(0xFF00A3FF)),
              const SizedBox(height: 32),
              const Text(
                "نحن بصدد تحسين تجربتكم",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                message ?? "نحن نجري بعض التحديثات الأمنية الهامة. سنعود إليكم قريباً جداً.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(color: Color(0xFF00A3FF)),
            ],
          ),
        ),
      ),
    );
  }
}
