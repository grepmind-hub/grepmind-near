import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/abashyaka_wave_header.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_painter.dart';

class RiderApplicationScreen extends ConsumerStatefulWidget {
  const RiderApplicationScreen({super.key});

  @override
  ConsumerState<RiderApplicationScreen> createState() =>
      _RiderApplicationScreenState();
}

class _RiderApplicationScreenState
    extends ConsumerState<RiderApplicationScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _vehicleDetails = TextEditingController();
  final _fieldExecutiveCode = TextEditingController();
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _localities = [];
  List<Map<String, dynamic>> _requirements = [];
  List<Map<String, dynamic>> _fieldExecutives = [];
  Map<String, dynamic>? _application;
  final Set<String> _selectedLocalities = {};
  String _vehicleType = 'two_wheeler';
  String _onboardingSource = 'self';
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
      List<Map<String, dynamic>> fieldExecs = [];
      try {
        final feRes = await apiClient.get('/field-executives/directory');
        final feData =
            (feRes.data as Map<String, dynamic>)['data'] as List<dynamic>? ??
                [];
        fieldExecs = feData.whereType<Map<String, dynamic>>().toList();
      } catch (_) {
        // Optional directory; manual AFE-1000 entry still works.
      }
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
        _fieldExecutives = fieldExecs;
        _application = app;
        if (app != null) {
          _name.text = app['display_name'] as String? ?? '';
          _address.text = app['address'] as String? ?? '';
          _vehicleType = app['vehicle_type'] as String? ?? 'two_wheeler';
          _vehicleDetails.text = app['vehicle_details'] as String? ?? '';
          _onboardingSource =
              (app['onboarding_source'] as String?) == 'field_executive'
                  ? 'field_executive'
                  : 'self';
          _fieldExecutiveCode.text =
              app['field_executive_code'] as String? ?? '';
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
    if (_address.text.trim().length < 5) {
      setState(
        () => _error =
            'Enter your complete residential address (street, area, city & PIN).',
      );
      return;
    }
    if (_onboardingSource == 'field_executive' &&
        _fieldExecutiveCode.text.trim().isEmpty) {
      setState(
        () => _error =
            'Select or enter the Field Executive ID (AFE-1000 series).',
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
          'address': _address.text.trim(),
          'vehicle_type': _vehicleType,
          'vehicle_details': _vehicleDetails.text.trim(),
          'onboarding_source': _onboardingSource,
          if (_onboardingSource == 'field_executive')
            'field_executive_code': _fieldExecutiveCode.text.trim().toUpperCase(),
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
    if (_application == null) {
      if (_name.text.trim().length < 2 ||
          _address.text.trim().length < 5 ||
          _selectedLocalities.isEmpty) {
        setState(
          () => _error =
              'Enter your name, complete address, and select at least one locality before uploading documents.',
        );
        return;
      }
      await _save(submit: false);
      if (_application == null || !mounted) return;
    }
    final palette = context.abashyaka;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Upload Verification Document',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_rounded, color: palette.accent),
              title: Text(
                'Take Photo with Camera',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              subtitle: Text(
                'Capture Aadhaar Card or Driving Licence clearly',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: palette.accent),
              title: Text(
                'Choose from Mobile Gallery',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              subtitle: Text(
                'Select JPEG, PNG or WebP image (up to 8 MB)',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await _picker.pickImage(
      source: source,
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
    _address.dispose();
    _vehicleDetails.dispose();
    _fieldExecutiveCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final status = _application?['status'] as String?;
    final palette = context.abashyaka;
    return Scaffold(
      backgroundColor: palette.canvas,
      body: Column(
        children: [
          const AbashyakaWaveHeader(
            title: 'Rider Application',
            subtitle: 'Apply to deliver with Abashyaka',
            variant: FluidWaveVariant.rider,
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: RefreshIndicator(
                onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.abashyaka.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.riderAmberBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.pedal_bike_rounded,
                          color: AppTheme.riderAmberDark,
                          size: 34,
                        ),
                        const Spacer(),
                        if ((_application?['rider_code']?.toString() ?? '')
                            .isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accentSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: palette.border),
                            ),
                            child: Text(
                              'ID: ${_application!['rider_code']}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: palette.accent,
                              ),
                            ),
                          ),
                      ],
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
                      'Once approved, your Rider workspace unlocks delivery offers, pickup and customer handover verification, and earnings tracking.',
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
                      TextField(
                        controller: _address,
                        minLines: 2,
                        maxLines: 3,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Complete residential address *',
                          hintText:
                              'House/Flat No, Street, Landmark, City, PIN code',
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
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _onboardingSource,
                        decoration: const InputDecoration(
                          labelText: 'Onboarded Via',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'self',
                            child: Text('Self-Registered'),
                          ),
                          DropdownMenuItem(
                            value: 'field_executive',
                            child: Text('Field Executive (AFE-1000)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _onboardingSource = v);
                        },
                      ),
                      if (_onboardingSource == 'field_executive') ...[
                        const SizedBox(height: 12),
                        if (_fieldExecutives.isNotEmpty)
                          DropdownButtonFormField<String>(
                            initialValue: _fieldExecutives.any(
                              (e) =>
                                  e['executive_code']?.toString() ==
                                  _fieldExecutiveCode.text.trim().toUpperCase(),
                            )
                                ? _fieldExecutiveCode.text.trim().toUpperCase()
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Select Field Executive',
                              border: OutlineInputBorder(),
                            ),
                            items: _fieldExecutives
                                .map(
                                  (fe) => DropdownMenuItem<String>(
                                    value:
                                        fe['executive_code']?.toString() ?? '',
                                    child: Text(
                                      '${fe['executive_code']} · ${fe['display_name']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _fieldExecutiveCode.text = v);
                              }
                            },
                          ),
                        if (_fieldExecutives.isNotEmpty)
                          const SizedBox(height: 10),
                        TextField(
                          controller: _fieldExecutiveCode,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Field Executive ID (e.g. AFE-1000)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
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
                                .where((d) =>
                                    d['requirement_id'] == req['id'] &&
                                    d['review_status'] != 'superseded')
                                .toList();
                            final isDone = uploaded.isNotEmpty;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: palette.cardElevated,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDone
                                      ? AbashyakaColors.success
                                          .withValues(alpha: 0.45)
                                      : palette.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isDone
                                        ? Icons.check_circle_rounded
                                        : Icons.badge_outlined,
                                    color: isDone
                                        ? AbashyakaColors.success
                                        : palette.accent,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          req['label']?.toString() ?? '',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: palette.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          uploaded.isEmpty
                                              ? (req['is_required'] == true
                                                  ? 'Required · Upload via Camera or Gallery'
                                                  : 'Optional · Upload via Camera or Gallery')
                                              : 'Uploaded · ${uploaded.last['review_status']}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDone
                                                ? AbashyakaColors.success
                                                : palette.textSecondary,
                                            fontWeight: isDone
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: _saving
                                        ? null
                                        : () => _upload(req['code'] as String),
                                    icon: const Icon(
                                      Icons.add_a_photo_outlined,
                                      size: 16,
                                    ),
                                    label: Text(isDone ? 'Replace' : 'Upload'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: palette.accent,
                                      minimumSize: const Size(0, 40),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      side: BorderSide(color: palette.border),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ],
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
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.riderAmberDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _saving ? null : () => _save(submit: false),
                    child: _saving
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.abashyaka.card,
                            ),
                          )
                        : const Text(
                            'Save application',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.riderAmberDark,
                      side: const BorderSide(color: AppTheme.riderAmberDark),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _saving ? null : () => _save(submit: true),
                    child: const Text(
                      'Submit for review',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.riderAmberDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
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
                      label: const Text(
                        'Open Rider workspace',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
          ),
        ],
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
      color: context.abashyaka.card,
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
  Widget build(BuildContext context) {
    final palette = context.abashyaka;
    return Material(
      color: palette.isDark
          ? const Color(0xFF3A1A1E)
          : const Color(0xFFFFF1F2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.isDark
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFF991B1B),
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
