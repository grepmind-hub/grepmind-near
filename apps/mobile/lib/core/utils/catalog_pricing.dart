List<String> catalogUnits(String? category) {
  return switch (category?.trim().toLowerCase()) {
    'grocery' => [
      '1 kg',
      '500 g',
      '250 g',
      '1 L',
      '500 mL',
      'Dozen',
      'Pack',
      '1 pc',
    ],
    'food' || 'restaurant' || 'dining' => [
      'Portion',
      'Plate',
      'Bowl',
      'Meal',
      'Combo',
      '250 mL',
      '500 mL',
      '1 pc',
    ],
    'medicines' ||
    'pharmacy' => ['Strip', 'Bottle', 'Tube', 'Vial', 'Box', 'Pack', '1 pc'],
    'fashion' || 'tailor' => ['1 pc', 'Pair', 'Set', '1 m', 'Roll'],
    'hardware' || 'construction' || 'home_decor' || 'home_kitchen' => [
      '1 pc',
      'Box',
      'Set',
      '1 m',
      'Roll',
      '1 kg',
      'Bag',
      '1 L',
    ],
    'agriculture' => ['1 kg', 'Bag', 'Sack', 'Tray', 'Bunch', '1 L'],
    'electronics' ||
    'furniture' ||
    'auto_care' => ['1 pc', 'Pair', 'Set', 'Kit', 'Box'],
    _ => ['1 pc', 'Pack', 'Pair', 'Box', 'Set'],
  };
}

int? parseCatalogGstRate(String text) {
  final value = text.trim();
  if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(value)) return null;
  final pieces = value.split('.');
  final basisPoints =
      int.parse(pieces.first) * 100 +
      (pieces.length == 1 ? 0 : int.parse(pieces.last.padRight(2, '0')));
  return basisPoints <= 10000 ? basisPoints : null;
}

int catalogGstPaise(int pricePaise, int rateBasisPoints) {
  return (pricePaise * rateBasisPoints + 5000) ~/ 10000;
}
