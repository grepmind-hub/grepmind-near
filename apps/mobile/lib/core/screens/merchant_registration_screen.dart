import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Screen 19: Merchant Registration & Claim Screen
///
/// Onboarding funnel for local shop owners and skilled service professionals
/// to either register a new enterprise or claim an existing unverified directory listing.
class MerchantRegistrationScreen extends ConsumerStatefulWidget {
  const MerchantRegistrationScreen({super.key, this.initialMode = 0});

  /// 0 = Register New, 1 = Claim Existing Listing
  final int initialMode;

  @override
  ConsumerState<MerchantRegistrationScreen> createState() => _MerchantRegistrationScreenState();
}

class _MerchantRegistrationScreenState extends ConsumerState<MerchantRegistrationScreen> {
  late int _mode; // 0 = Register New, 1 = Claim Existing
  int _currentStep = 0; // 0 = Category & Type, 1 = Basic Info, 2 = Location & Storefront, 3 = Operations

  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _businessNameController = TextEditingController(text: 'Maa Tarini Hardware & Tools');
  final _ownerNameController = TextEditingController(text: 'Srikant Mohanty');
  final _phoneController = TextEditingController(text: '+91 98765 43210');
  final _emailController = TextEditingController(text: 'contact@tarinihardware.com');
  final _taxIdController = TextEditingController(text: '21AAAAA0000A1Z5');
  final _taglineController = TextEditingController(text: 'Leading supplier of sanitary fittings, power tools, and electrical items.');

  final _addressController = TextEditingController(text: 'Plot 42, Saheed Nagar Main Road');
  final _localityController = TextEditingController(text: 'Saheed Nagar');
  final _cityController = TextEditingController(text: 'Bhubaneswar');
  final _pinController = TextEditingController(text: '751007');

  final _searchClaimController = TextEditingController();

  // Registration Selections
  String _enterpriseType = 'retail'; // retail, service_pro, food, wellness
  String _selectedCategory = 'Hardware & Tools';
  bool _isUnorganized = false;
  bool _hasStorefrontPhoto = true;
  bool _isGpsDetected = true;
  String _operatingMode = 'both'; // store_only, home_only, both
  double _serviceRadiusKm = 6.0;
  String _hoursPreset = 'mon_sat'; // mon_sat, all_days, emergency

  bool _isSubmitting = false;
  bool _isSuccess = false;
  String _generatedAppId = '#MR-8921';

  // Claim Search State
  final List<Map<String, dynamic>> _allClaimable = [
    {
      'id': 'clm-001',
      'name': 'Maa Tarini Hardware & Sanitary',
      'category': 'Hardware & Tools',
      'locality': 'Saheed Nagar, Bhubaneswar',
      'phone_hint': '+91 98*** **210',
      'unverified': true,
      'visits': 142,
    },
    {
      'id': 'clm-002',
      'name': 'Shree Ganesh Electricals & Repair',
      'category': 'Electrician & Repairs',
      'locality': 'Nayapalli, Bhubaneswar',
      'phone_hint': '+91 94*** **882',
      'unverified': true,
      'visits': 89,
    },
    {
      'id': 'clm-003',
      'name': 'Kalinga Fresh Organic Groceries',
      'category': 'Grocery & Daily Needs',
      'locality': 'Patia, Bhubaneswar',
      'phone_hint': '+91 99*** **104',
      'unverified': true,
      'visits': 230,
    },
    {
      'id': 'clm-004',
      'name': 'Royal Cuts & Men Salon',
      'category': 'Salon & Grooming',
      'locality': 'Jaydev Vihar, Bhubaneswar',
      'phone_hint': '+91 70*** **951',
      'unverified': true,
      'visits': 67,
    },
  ];

  late List<Map<String, dynamic>> _filteredClaimable;

  final List<String> _categories = [
    'Hardware & Tools',
    'Electrician & Repairs',
    'Plumber & Sanitary',
    'Grocery & Daily Needs',
    'Medical & Pharmacy',
    'Electronics & Mobiles',
    'Salon & Grooming',
    'Restaurant & Cafe',
    'Carpenter & Furniture',
    'Automotive & Bike Care',
    'Cleaning & Pest Control',
    'Tailor & Boutiques',
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _filteredClaimable = List.from(_allClaimable);
    _searchClaimController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchClaimController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredClaimable = List.from(_allClaimable);
      } else {
        _filteredClaimable = _allClaimable.where((item) {
          final name = (item['name'] as String).toLowerCase();
          final category = (item['category'] as String).toLowerCase();
          final locality = (item['locality'] as String).toLowerCase();
          return name.contains(query) || category.contains(query) || locality.contains(query);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _taxIdController.dispose();
    _taglineController.dispose();
    _addressController.dispose();
    _localityController.dispose();
    _cityController.dispose();
    _pinController.dispose();
    _searchClaimController.dispose();
    super.dispose();
  }

  Future<void> _submitRegistration() async {
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _isSuccess = true;
        _generatedAppId = '#MR-${(1000 + DateTime.now().millisecond % 9000)}';
      });
    }
  }

  void _showClaimConfirmationSheet(Map<String, dynamic> business) {
    final otpController = TextEditingController(text: '7492');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.verified_user_outlined, color: AppTheme.primary, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Claim Business Listing',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        Text(
                          business['name'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryText,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.phone_android, size: 16, color: AppTheme.secondaryText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'OTP sent to registered number: ${business['phone_hint']}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mainText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter the 4-digit verification code to prove ownership.',
                      style: TextStyle(fontSize: 12, color: AppTheme.hintText),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: 'Verification OTP',
                  hintText: 'Enter 4-digit code',
                  prefixIcon: const Icon(Icons.lock_clock_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _isSuccess = true;
                          _businessNameController.text = business['name'] as String;
                          _generatedAppId = '#CLM-${business['id']}';
                        });
                      },
                      child: const Text('Verify & Claim'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSuccess) {
      return _buildSuccessScreen();
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Merchant Onboarding'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.mainText,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildModeSegmentedControl(),
          ),
          Expanded(
            child: IndexedStack(
              index: _mode,
              children: [
                _buildRegisterWizard(),
                _buildClaimListingView(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _mode == 0 ? _buildWizardBottomBar() : null,
    );
  }

  // -------------------------------------------------------------
  // Mode Switcher (Register New vs Claim Existing)
  // -------------------------------------------------------------
  Widget _buildModeSegmentedControl() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _mode = 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _mode == 0 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _mode == 0
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_business_outlined,
                      size: 16,
                      color: _mode == 0 ? AppTheme.primary : AppTheme.secondaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Register New',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _mode == 0 ? FontWeight.w700 : FontWeight.w500,
                        color: _mode == 0 ? AppTheme.primary : AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _mode = 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _mode == 1 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _mode == 1
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.store_mall_directory_outlined,
                      size: 16,
                      color: _mode == 1 ? AppTheme.primary : AppTheme.secondaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Claim Existing',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _mode == 1 ? FontWeight.w700 : FontWeight.w500,
                        color: _mode == 1 ? AppTheme.primary : AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Register New Wizard
  // -------------------------------------------------------------
  Widget _buildRegisterWizard() {
    return SingleChildScrollView(
      key: const ValueKey('register_wizard'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step Stepper Indicator
          _buildStepProgressIndicator(),
          const SizedBox(height: 20),

          // Active Step View
          if (_currentStep == 0) _buildStepCategoryAndType(),
          if (_currentStep == 1) _buildStepBasicInfo(),
          if (_currentStep == 2) _buildStepLocationAndMedia(),
          if (_currentStep == 3) _buildStepOperationsAndReview(),

          const SizedBox(height: 80), // bottom bar padding
        ],
      ),
    );
  }

  Widget _buildStepProgressIndicator() {
    final steps = ['Type & Sector', 'Basic Info', 'Location & Store', 'Operations'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: List.generate(steps.length, (idx) {
          final isDone = idx < _currentStep;
          final isCurrent = idx == _currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? const Color(0xFF0F766E)
                              : (isCurrent ? AppTheme.primary : const Color(0xFFE2E8F0)),
                        ),
                        child: Center(
                          child: isDone
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isCurrent ? Colors.white : AppTheme.hintText,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        steps[idx],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isCurrent ? AppTheme.primary : AppTheme.secondaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (idx < steps.length - 1)
                  Container(
                    width: 16,
                    height: 2,
                    color: isDone ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
                    margin: const EdgeInsets.only(bottom: 14),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // Step 1: Enterprise Type & Category
  Widget _buildStepCategoryAndType() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Enterprise Classification',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose the model that best describes how you conduct business.',
          style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        const SizedBox(height: 16),

        _buildEnterpriseTypeCard(
          typeId: 'retail',
          icon: Icons.storefront_outlined,
          title: 'Retail Shop & Showroom',
          subtitle: 'Physical storefront with counter sales and customer walk-ins.',
          color: const Color(0xFF2457D6),
        ),
        const SizedBox(height: 12),
        _buildEnterpriseTypeCard(
          typeId: 'service_pro',
          icon: Icons.handyman_outlined,
          title: 'Skilled Trade & Professional',
          subtitle: 'Electrician, plumber, technician, or artisan offering on-site work.',
          color: const Color(0xFF0F766E),
        ),
        const SizedBox(height: 12),
        _buildEnterpriseTypeCard(
          typeId: 'food',
          icon: Icons.restaurant_outlined,
          title: 'Food, Dining & Cafe',
          subtitle: 'Dine-in restaurant, takeaway outlet, bakery, or cafe.',
          color: const Color(0xFFEA580C),
        ),
        const SizedBox(height: 12),
        _buildEnterpriseTypeCard(
          typeId: 'wellness',
          icon: Icons.spa_outlined,
          title: 'Salon, Spa & Wellness',
          subtitle: 'Appointment-based beauty salon, unisex parlour, or therapy studio.',
          color: const Color(0xFF7C3AED),
        ),

        const SizedBox(height: 24),
        const Text(
          'Primary Trade Category',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.mainText),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
          items: _categories.map((c) {
            return DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14)));
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _selectedCategory = v);
          },
        ),
      ],
    );
  }

  Widget _buildEnterpriseTypeCard({
    required String typeId,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final isSelected = _enterpriseType == typeId;

    return PremiumCard(
      padding: const EdgeInsets.all(14),
      borderColor: isSelected ? color : AppTheme.border,
      color: isSelected ? color.withValues(alpha: 0.04) : Colors.white,
      onTap: () => setState(() => _enterpriseType = typeId),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? color : AppTheme.mainText,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle, color: color, size: 20),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Step 2: Basic & Tax Info
  Widget _buildStepBasicInfo() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enterprise & Ownership Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
          ),
          const SizedBox(height: 4),
          const Text(
            'Official details displayed to customers and verified on receipts.',
            style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _businessNameController,
            decoration: InputDecoration(
              labelText: 'Business / Trade Name *',
              hintText: 'e.g. Maa Tarini Hardware & Tools',
              prefixIcon: const Icon(Icons.business_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _ownerNameController,
            decoration: InputDecoration(
              labelText: 'Owner / Authorized Person *',
              hintText: 'e.g. Srikant Mohanty',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Contact Phone *',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified, size: 14, color: Color(0xFF059669)),
                    SizedBox(width: 4),
                    Text('Verified', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Support Email (Optional)',
              hintText: 'e.g. contact@business.com',
              prefixIcon: const Icon(Icons.alternate_email),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _taglineController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Short Description / Tagline',
              hintText: 'What products or services do you specialize in?',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 18),

          // GST / PAN Section
          PremiumCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tax / Registration ID',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: _isUnorganized,
                          onChanged: (v) => setState(() => _isUnorganized = v ?? false),
                          activeColor: AppTheme.primary,
                        ),
                        const Text('Local artisan / No GST', style: TextStyle(fontSize: 12, color: AppTheme.secondaryText)),
                      ],
                    ),
                  ],
                ),
                if (!_isUnorganized) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _taxIdController,
                    decoration: InputDecoration(
                      labelText: 'GSTIN / Business PAN',
                      hintText: 'e.g. 21AAAAA0000A1Z5',
                      prefixIcon: const Icon(Icons.receipt_long_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Unregistered businesses and artisans can still list with Aadhaar or Electricity Bill proof.',
                      style: TextStyle(fontSize: 11, color: AppTheme.secondaryText),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Step 3: Location & Storefront Media
  Widget _buildStepLocationAndMedia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Storefront Location & Signage',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
        ),
        const SizedBox(height: 4),
        const Text(
          'Accurate location ensures nearby customers can find and visit your shop.',
          style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: _addressController,
          decoration: InputDecoration(
            labelText: 'Street Address & Landmark *',
            hintText: 'e.g. Plot 42, Saheed Nagar Main Road',
            prefixIcon: const Icon(Icons.location_on_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _localityController,
                decoration: InputDecoration(
                  labelText: 'Locality *',
                  hintText: 'e.g. Saheed Nagar',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _cityController,
                decoration: InputDecoration(
                  labelText: 'City *',
                  hintText: 'Bhubaneswar',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        TextFormField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Postal PIN Code *',
            hintText: '751007',
            prefixIcon: const Icon(Icons.pin_drop_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 18),

        // Geolocation GPS Card
        PremiumCard(
          padding: const EdgeInsets.all(14),
          color: const Color(0xFFF0FDF4),
          borderColor: const Color(0xFFBBF7D0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.my_location, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GPS Coordinates Locked',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                        ),
                        Text(
                          '20.2961° N, 85.8245° E (Bhubaneswar, Odisha)',
                          style: TextStyle(fontSize: 12, color: Color(0xFF166534)),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _isGpsDetected = true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Accurate location updated via GPS')),
                      );
                    },
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Update', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Storefront Photo Upload Card
        const Text(
          'Storefront Signage Photo',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.mainText),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            setState(() => _hasStorefrontPhoto = !_hasStorefrontPhoto);
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hasStorefrontPhoto ? AppTheme.primary : AppTheme.border,
                width: _hasStorefrontPhoto ? 1.5 : 1,
              ),
            ),
            child: _hasStorefrontPhoto
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF1E293B), Color(0xFF334155)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.storefront, size: 48, color: Colors.white),
                                  const SizedBox(height: 6),
                                  Text(
                                    _businessNameController.text.isNotEmpty
                                        ? _businessNameController.text
                                        : 'Storefront Signage',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Text(
                                    'storefront_cover_751007.jpg (Uploaded)',
                                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.edit, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Change', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_a_photo_outlined, size: 36, color: AppTheme.primary),
                        SizedBox(height: 8),
                        Text(
                          'Upload Storefront Photo with Signage',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.mainText),
                        ),
                        Text(
                          'JPEG or PNG up to 5 MB',
                          style: TextStyle(fontSize: 11, color: AppTheme.hintText),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // Step 4: Operations, Service Radius & Review
  Widget _buildStepOperationsAndReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Operating Mode & Radius',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
        ),
        const SizedBox(height: 4),
        const Text(
          'Set how you service orders and define your service reach.',
          style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        const SizedBox(height: 16),

        // Operating Mode Selector
        Row(
          children: [
            _buildModePill('store_only', 'Walk-in Only', Icons.store),
            const SizedBox(width: 8),
            _buildModePill('home_only', 'On-site Visits', Icons.electric_bolt),
            const SizedBox(width: 8),
            _buildModePill('both', 'Store & On-site', Icons.alt_route),
          ],
        ),
        const SizedBox(height: 20),

        // Service Radius Slider
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Service & Delivery Coverage',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_serviceRadiusKm.toInt()} km radius',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Customers within this perimeter will see your listing under "Nearby".',
                style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
              ),
              Slider(
                value: _serviceRadiusKm,
                min: 1.0,
                max: 20.0,
                divisions: 19,
                activeColor: AppTheme.primary,
                onChanged: (v) => setState(() => _serviceRadiusKm = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('1 km (Neighbourhood)', style: TextStyle(fontSize: 10, color: AppTheme.hintText)),
                  Text('20 km (City-wide)', style: TextStyle(fontSize: 10, color: AppTheme.hintText)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Operating Hours Preset
        const Text(
          'Operating Schedule Preset',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.mainText),
        ),
        const SizedBox(height: 8),
        _buildHoursRadio('mon_sat', 'Mon - Sat (9:00 AM - 8:30 PM)', 'Standard retail timing, Sunday closed'),
        const SizedBox(height: 8),
        _buildHoursRadio('all_days', 'All 7 Days (8:00 AM - 10:00 PM)', 'Open daily for retail & grocery walk-ins'),
        const SizedBox(height: 8),
        _buildHoursRadio('emergency', '24x7 Emergency Service', 'Available around the clock for priority repairs'),

        const SizedBox(height: 20),

        // Application Summary Verification Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.fact_check_outlined, size: 18, color: AppTheme.primary),
                  SizedBox(width: 8),
                  Text('Application Summary', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mainText)),
                ],
              ),
              const Divider(height: 16),
              _buildSummaryRow('Trade Name', _businessNameController.text),
              _buildSummaryRow('Sector', _selectedCategory),
              _buildSummaryRow('Locality', '${_localityController.text}, ${_cityController.text}'),
              _buildSummaryRow('Coverage', '${_serviceRadiusKm.toInt()} km radius'),
              _buildSummaryRow('Contact', _phoneController.text),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mainText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModePill(String modeId, String label, IconData icon) {
    final isSelected = _operatingMode == modeId;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _operatingMode = modeId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: isSelected ? Colors.white : AppTheme.secondaryText),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppTheme.mainText,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHoursRadio(String val, String title, String subtitle) {
    final isSelected = _hoursPreset == val;
    return PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderColor: isSelected ? AppTheme.primary : AppTheme.border,
      color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
      onTap: () => setState(() => _hoursPreset = val),
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: isSelected ? AppTheme.primary : AppTheme.hintText,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? AppTheme.primary : AppTheme.mainText,
                  ),
                ),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Wizard Bottom Navigation Bar
  Widget _buildWizardBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => setState(() => _currentStep--),
                  child: const Text('Back'),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 5,
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSubmitting
                    ? null
                    : () {
                        if (_currentStep < 3) {
                          setState(() => _currentStep++);
                        } else {
                          _submitRegistration();
                        }
                      },
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _currentStep < 3 ? 'Save & Continue' : 'Submit Application',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Claim Existing Listing View
  // -------------------------------------------------------------
  Widget _buildClaimListingView() {
    return SingleChildScrollView(
      key: const ValueKey('claim_listings'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Notice
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Is your shop already listed by local patrons? Search your trade name below and claim ownership to manage hours, reply to queries, and accept requests.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A), height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search Field
          TextField(
            controller: _searchClaimController,
            decoration: InputDecoration(
              hintText: 'Search business name or locality...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Available for Claim in Bhubaneswar',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.mainText),
              ),
              Text(
                '${_filteredClaimable.length} found',
                style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_filteredClaimable.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const Icon(Icons.search_off, size: 48, color: AppTheme.hintText),
                    const SizedBox(height: 8),
                    const Text('No existing listing found', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text('Try searching another name or switch to Register New.', style: TextStyle(fontSize: 12, color: AppTheme.secondaryText)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => setState(() => _mode = 0),
                      child: const Text('Register as New Business'),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final item in _filteredClaimable)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildClaimCard(item),
              ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildClaimCard(Map<String, dynamic> item) {
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.store, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] as String,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item['category']} • ${item['locality']}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Unclaimed',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${item['visits']} local views this month',
                style: const TextStyle(fontSize: 11, color: AppTheme.hintText),
              ),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => _showClaimConfirmationSheet(item),
                  icon: const Icon(Icons.verified_outlined, size: 14),
                  label: const Text('Claim Store', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Success & Confirmation Screen
  // -------------------------------------------------------------
  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 30),
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFECFDF5),
                ),
                child: const Icon(Icons.check_circle_rounded, size: 52, color: Color(0xFF059669)),
              ),
              const SizedBox(height: 20),
              Text(
                _mode == 0 ? 'Enterprise Registered!' : 'Business Claimed Successfully!',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.mainText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Application Ref: $_generatedAppId',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary),
              ),
              const SizedBox(height: 24),

              PremiumCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _buildSuccessRow(Icons.business, 'Business', _businessNameController.text),
                    const Divider(height: 18),
                    _buildSuccessRow(Icons.category_outlined, 'Category', _selectedCategory),
                    const Divider(height: 18),
                    _buildSuccessRow(Icons.place_outlined, 'Location', '${_localityController.text}, ${_cityController.text}'),
                    const Divider(height: 18),
                    _buildSuccessRow(Icons.verified_outlined, 'Status', 'Instant Listing Active (Review in 2h)'),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.shield_outlined, color: Color(0xFF16A34A), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your enterprise is now visible to customers in Bhubaneswar. Set up products & services in your workspace to accept orders.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF15803D), height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const MerchantWorkspaceScreen()),
                    );
                  },
                  icon: const Icon(Icons.dashboard_outlined),
                  label: const Text('Open Merchant Workspace', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Profile'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.secondaryText),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText)),
        const Spacer(),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mainText),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
