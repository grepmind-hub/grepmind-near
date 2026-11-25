import 'package:flutter/material.dart';

import '../theme/abashyaka_colors.dart';
import '../theme/abashyaka_tokens.dart';
import '../theme/abashyaka_typography.dart';

/// The official glossy input field for Abashyaka authentication and forms.
class PremiumTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final FocusNode? focusNode;
  final Key? inputKey;
  final double height;
  final double radius;

  const PremiumTextField({
    super.key,
    this.controller,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.focusNode,
    this.inputKey,
    this.height = 56.0,
    this.radius = AbashyakaRadius.button,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AbashyakaColors.pureWhite,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AbashyakaColors.silverGlass, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08003F46),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: TextFormField(
          key: inputKey,
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          obscureText: obscureText,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          validator: validator,
          cursorColor: AbashyakaColors.metallicTeal,
          style: AbashyakaTypography.bodyLarge(),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            hintStyle: AbashyakaTypography.bodyMedium(),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
        ),
      ),
    );
  }
}
