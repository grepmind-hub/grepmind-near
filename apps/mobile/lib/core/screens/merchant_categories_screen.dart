import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/abashyaka_wave_header.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_painter.dart';

/// Merchant-owned catalog categories persisted by the API.
class MerchantCategoriesScreen extends StatefulWidget {
  const MerchantCategoriesScreen({super.key});
  @override
  State<MerchantCategoriesScreen> createState() =>
      _MerchantCategoriesScreenState();
}

class _MerchantCategoriesScreenState extends State<MerchantCategoriesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await apiClient.get('/merchant/catalog-categories');
      final items = (response.data['data'] as List)
          .cast<Map<String, dynamic>>();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to load your categories. Check your connection and sign-in status.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? category]) async {
    final controller = TextEditingController(
      text: category?['name'] as String? ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category == null ? 'Add category' : 'Edit category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Category name',
            hintText: 'e.g. Electrical supplies',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Dialog transition may still use the controller after its result completes.
    if (name == null || !mounted) return;
    await _mutate(() async {
      if (category == null) {
        await apiClient.post(
          '/merchant/catalog-categories',
          data: {'name': name},
        );
      } else {
        await apiClient.patch(
          '/merchant/catalog-categories/${category['id']}',
          data: {'name': name},
        );
      }
    });
  }

  Future<void> _delete(Map<String, dynamic> category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Remove “${category['name']}” from your categories?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep category'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _mutate(() async {
        await apiClient.delete(
          '/merchant/catalog-categories/${category['id']}',
        );
      });
    }
  }

  Future<void> _mutate(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Categories updated')));
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to save. Check permissions and use a unique category name.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.abashyaka;
    return Scaffold(
      backgroundColor: palette.canvas,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
      body: Column(
        children: [
          AbashyakaWaveHeader(
            title: 'Catalog Categories',
            subtitle: 'Organize products & services',
            variant: FluidWaveVariant.merchant,
            actions: [
              AbashyakaWaveActionButton(
                tooltip: 'Refresh categories',
                onPressed: _saving ? null : _load,
                icon: Icons.refresh,
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: palette.accent),
                  )
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.textPrimary),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Organize your catalog with categories.\nAdd your first category to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ),
                  )
                : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final category = _items[index];
                return Card(
                  color: palette.card,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: palette.border),
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.category_outlined,
                      color: palette.accent,
                    ),
                    title: Text(
                      category['name'] as String,
                      style: TextStyle(color: palette.textPrimary),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit category',
                          onPressed: _saving ? null : () => _edit(category),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete category',
                          onPressed: _saving ? null : () => _delete(category),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          ),
        ],
      ),
    );
  }
}
