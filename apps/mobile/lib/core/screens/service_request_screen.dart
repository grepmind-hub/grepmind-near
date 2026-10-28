import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Service request submission screen.
class ServiceRequestScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String businessName;
  const ServiceRequestScreen({super.key, required this.businessId, required this.businessName});

  @override
  ConsumerState<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends ConsumerState<ServiceRequestScreen> {
  final _descController = TextEditingController();
  String? _selectedServiceId;
  DateTime? _requestedFor;
  bool _isLoading = false;

  Future<void> _submit() async {
    if (_descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your request')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      // TODO: Call API to create service request
      // For now, use mock success
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service request submitted successfully')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fetch business services for dropdown
    final businessDetailState = ref.watch(businessDetailProvider);
    final services = businessDetailState.services;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Request from ${widget.businessName}'),
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
            if (services.isNotEmpty)
              DropdownButtonFormField<String>(
                hint: const Text('Select a service'),
                initialValue: _selectedServiceId,
                items: services
                    .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedServiceId = v;
                }),
                decoration: const InputDecoration(
                  labelText: 'Service type',
                  border: OutlineInputBorder(),
                ),
              )
            else
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Service type (no services listed)',
                  border: OutlineInputBorder(),
                ),
                readOnly: true,
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
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}