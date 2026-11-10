import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class RiderApplicationScreen extends ConsumerStatefulWidget {
  const RiderApplicationScreen({super.key});

  @override
  ConsumerState<RiderApplicationScreen> createState() =>
      _RiderApplicationScreenState();
}

class _RiderApplicationScreenState
    extends ConsumerState<RiderApplicationScreen> {
  final _name = TextEditingController();
  final _vehicleDetails = TextEditingController();
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _localities = [];
  List<Map<String, dynamic>> _requirements = [];
  Map<String, dynamic>? _application;
  final Set<String> _selectedLocalities = {};
  String _vehicleType = 'two_wheeler';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final responses = await Future.wait([
        apiClient.get('/rider/localities'),
        apiClient.get('/rider/document-requirements'),
        apiClient.get('/rider/application'),
      ]);
      final localityData =
          (responses[0].data as Map<String, dynamic>)['data']
              as List<dynamic>? ??
          [];
      final requirementData =
          (responses[1].data as Map<String, dynamic>)['data']
              as List<dynamic>? ??
          [];
      final rawApplication =
          (responses[2].data as Map<String, dynamic>)['data'];
      final app = rawApplication is Map<String, dynamic>
          ? rawApplication
          : null;
      if (!mounted) return;
      setState(() {
        _localities = localityData.cast<Map<String, dynamic>>();
        _requirements = requirementData.cast<Map<String, dynamic>>();
        _application = app;
        if (app != null) {
          _name.text = app['display_name'] as String? ?? '';
          _vehicleType = app['vehicle_type'] as String? ?? 'two_wheeler';
          _vehicleDetails.text = app['vehicle_details'] as String? ?? '';
          final places = app['localities'] as List<dynamic>? ?? [];
          _selectedLocalities.addAll(
            places
                .whereType<Map<String, dynamic>>()
                .where((e) => e['status'] == 'requested')
                .map((e) => e['locality_id'] as String),
          );
        } else {
          _name.text = ref.read(authProvider).user?.displayName ?? '';
        }
        _loading = false;
        _error = null;
      });
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.response?.statusCode == 404
              ? 'Rider onboarding is not enabled on this server yet. Please try again after the rider setup is deployed.'
              : 'Could not load rider application. Check your connection and retry.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load rider application. Check your connection and retry.';
        });
      }
    }
  }

  bool get _editable =>
      _application == null ||
      const {
        'draft',
        'changes_requested',
        'rejected',
      }.contains(_application?['status']);

  Future<void> _save({required bool submit}) async {
    if (_name.text.trim().length < 2 || _selectedLocalities.isEmpty) {
      setState(
        () => _error =
            'Enter your name and select at least one supported locality.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await apiClient.put(
        '/rider/application',
        data: {
          'display_name': _name.text.trim(),
          'vehicle_type': _vehicleType,
          'vehicle_details': _vehicleDetails.text.trim(),
          'locality_ids': _selectedLocalities.toList(),
        },
      );
      if (submit) await apiClient.post('/rider/application/submit');
      await _load();
      if (mounted && submit) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rider application submitted for review.'),
          ),
        );
      }
    } on DioException catch (e) {
      final body = e.response?.data;
      final message = body is Map && body['error'] is Map
          ? (body['error'] as Map)['message']?.toString()
          : null;
      if (mounted) {
        setState(
          () => _error =
              message ?? 'Application could not be saved. Retry when online.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Application could not be saved. Retry when online.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _upload(String code) async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2200,
    );
    if (image == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await apiClient.dio.post(
        '/rider/application/documents',
        data: FormData.fromMap({
          'requirement_code': code,
          'file': await MultipartFile.fromFile(
            image.path,
            filename: image.name,
          ),
        }),
      );
      await _load();
    } on DioException catch (e) {
      final body = e.response?.data;
      final message = body is Map && body['error'] is Map
          ? (body['error'] as Map)['message']?.toString()
          : null;
      if (mounted) {
        setState(
          () => _error =
              message ?? 'Private document upload failed. Retry later.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _vehicleDetails.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final status = _application?['status'] as String?;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Rider application'),
        backgroundColor: Colors.white,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD8E3F5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.pedal_bike_rounded,
                      color: AppTheme.primary,
                      size: 34,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      status == null
                          ? 'Become a delivery partner'
                          : 'Application ${status.replaceAll('_', ' ')}',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Rider approval provides workspace access only. Delivery assignments, GPS tracking and payments are not enabled in this phase.',
                    ),
                    if (status == 'changes_requested' ||
                        status == 'rejected') ...[
                      const SizedBox(height: 12),
                      Text(
                        _application?['review_notes'] as String? ?? 'Please update your application before resubmitting.',
                        style: const TextStyle(color: Color(0xFF9A3412)),
                      ),
                    ],
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _error!, onRetry: _load),
              ],
              const SizedBox(height: 16),
              if (_editable) ...[
                _Section(
                  title: 'Applicant details',
                  child: Column(
                    children: [
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _vehicleType,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'bicycle',
                            child: Text('Bicycle'),
                          ),
                          DropdownMenuItem(
                            value: 'two_wheeler',
                            child: Text('Two wheeler'),
                          ),
                          DropdownMenuItem(
                            value: 'three_wheeler',
                            child: Text('Three wheeler'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _vehicleType = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _vehicleDetails,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle details (optional)',
                          hintText: 'Make or model only; do not enter registration or ID numbers here',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _Section(
                  title: 'Requested service localities',
                  child: Column(
                    children: _localities.map((place) {
                      final id = place['id'] as String;
                      final selected = _selectedLocalities.contains(id);
                      return Material(
                        color: Colors.transparent,
                        child: CheckboxListTile(
                          value: selected,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selectedLocalities.add(id);
                            } else {
                              _selectedLocalities.remove(id);
                            }
                          }),
                          title: Text(place['name']?.toString() ?? ''),
                          subtitle: Text('${place['district']}, Odisha'),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
                _Section(
                  title: 'Verification documents',
                  child: _requirements.isEmpty
                      ? const Text(
                          'No document checklist is configured yet. The Admin team will configure requirements after the applicable legal review.',
                        )
                      : Column(
                          children: _requirements.map((req) {
                            final docs =
                                (_application?['documents'] as List<dynamic>? ??
                                []);
                            final uploaded = docs
                                .whereType<Map<String, dynamic>>()
                                .where((d) => d['requirement_id'] == req['id'])
                                .toList();
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(req['label']?.toString() ?? ''),
                              subtitle: Text(
                                uploaded.isEmpty
                                    ? (req['is_required'] == true
                                          ? 'Required by current platform policy'
                                          : 'Optional')
                                    : 'Uploaded · ${uploaded.last['review_status']}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Upload private document image',
                                onPressed: _saving
                                    ? null
                                    : () => _upload(req['code'] as String),
                                icon: const Icon(Icons.upload_file_outlined),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Documents are stored in private object storage and are not published as public profile images. Current upload supports JPEG, PNG and WebP images up to 8 MB.',
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(submit: false),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save application'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _save(submit: true),
                    child: const Text('Submit for review'),
                  ),
                ),
              ] else ...[
                _Section(
                  title: 'Current application',
                  child: Text(
                    'Status: ${(status ?? 'unknown').replaceAll('_', ' ')}\n\nThe Admin team will update this application if more information is needed. Pull down to refresh the latest status.',
                  ),
                ),
                const SizedBox(height: 12),
                if (status == 'approved')
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await ref
                          .read(authProvider.notifier)
                          .setActiveRole('rider');
                      if (mounted && !ok) {
                        setState(
                          () => _error = 'Rider authorization could not be verified. Refresh and retry.',
                        );
                      }
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Open Rider workspace'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE4EAF2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFF1F2),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
