import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Service request submission screen.
class ServiceRequestScreen extends StatefulWidget {
  const ServiceRequestScreen({super.key});

  @override
  State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends State<ServiceRequestScreen> {
  final _descController = TextEditingController();
  String? _selectedService;
  DateTime? _requestedFor;

  final List<String> _services = ['Plumbing', 'Electrical', 'Carpentry', 'Tailoring', 'Cleaning'];

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your request')),
      );
      return;
    }
    setState(() {});
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service request submitted (stub)')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Request a service'),
      ),
      body: PremiumCard(
        margin: const EdgeInsets.all(kScreenPadding),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What do you need help with?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              hint: const Text('Select a service'),
              initialValue: _selectedService,
              items: _services
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedService = v),
              decoration: const InputDecoration(
                labelText: 'Service type',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Describe your request',
                hintText: 'e.g. Leaking tap in the kitchen, need repair by this weekend',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined, color: AppTheme.primary),
              title: const Text('Preferred date & time'),
              subtitle: Text(
                _requestedFor == null ? 'Select when you need the service' : _requestedFor.toString(),
                style: const TextStyle(color: AppTheme.secondaryText),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppTheme.hintText),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 30)),
                );
                if (picked != null) setState(() => _requestedFor = picked);
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text('Submit request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
