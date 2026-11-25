import 'dart:math' as math;
import 'package:grepmind_mobile/core/models/business.dart';

/// Curated authentic local listings for the 18 Top-Level Categories across
/// Admin-Approved Service Places (Chhatia, Kuanpal, Jagatpur, Tangi, Chandikhol).
///
/// Sub-services (Electrician, Plumber, Carpenter, AC Mechanic, Home Painting & Decor)
/// are housed under 'services'. Tailoring is housed under 'shops'.
abstract final class CategoryListingsData {
  /// Admin-Approved Service Localities (matching ServiceabilityService)
  static const List<String> approvedServicePlaces = [
    'Chhatia',
    'Kuanpal',
    'Jagatpur',
    'Tangi',
    'Chandikhol',
  ];

  static const List<Business> allListings = [
    // -------------------------------------------------------------
    // 1. Food (food)
    // -------------------------------------------------------------
    Business(
      id: 'biz_food_1',
      name: 'Dalma Authentic Odia Restaurant',
      categorySlug: 'food',
      categoryName: 'Food & Dining',
      addressText: 'Main Chowk, Near Temple, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 450,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861012001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 310,
      deliveryEnabled: true,
      tableBookingEnabled: true,
      description:
          'Authentic Odia thalis, Dalma, Pakhala and fresh river fish curries.',
    ),
    Business(
      id: 'biz_food_2',
      name: 'Kuanpal Kitchen & Tandoor',
      categorySlug: 'food',
      categoryName: 'Food & Dining',
      addressText: 'College Road, Near Bus Stand, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1200,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861012002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 185,
      deliveryEnabled: true,
      tableBookingEnabled: true,
      description:
          'North Indian tandoor, biryani, Chinese starters and family dining.',
    ),
    Business(
      id: 'biz_food_3',
      name: 'Mahanadi River Family Diner',
      categorySlug: 'food',
      categoryName: 'Food & Dining',
      addressText: 'Industrial Estate Road, Jagatpur',
      locality: 'Jagatpur',
      city: 'Cuttack',
      distanceM: 2800,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861012003',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.6,
      reviewCount: 120,
      deliveryEnabled: false,
      tableBookingEnabled: true,
      description: 'Famous Dahibara Aloodum, mutton kasa, snacks and tea.',
    ),

    // -------------------------------------------------------------
    // 2. Grocery (grocery)
    // -------------------------------------------------------------
    Business(
      id: 'biz_groc_1',
      name: 'Maa Tarini Daily Mart & Kirana',
      categorySlug: 'grocery',
      categoryName: 'Grocery & Kirana',
      addressText: 'Bazaar Road, Near Durga Mandap, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 350,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861011001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 142,
      deliveryEnabled: true,
      deliveryTimeMins: 20,
      description:
          'Fresh vegetables, daily milk, staples and packaged food provisions.',
    ),
    Business(
      id: 'biz_groc_2',
      name: 'Kuanpal Fresh Provisions & Dairy',
      categorySlug: 'grocery',
      categoryName: 'Grocery & Kirana',
      addressText: 'Market Complex, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 950,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861011002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 98,
      deliveryEnabled: true,
      deliveryTimeMins: 25,
      description: 'Organic grains, fresh dairy, spices and FMCG essentials.',
    ),
    Business(
      id: 'biz_groc_3',
      name: 'Jagannath Super Store',
      categorySlug: 'grocery',
      categoryName: 'Grocery & Kirana',
      addressText: 'Near Highway Bridge, Chandikhol',
      locality: 'Chandikhol',
      city: 'Jajpur',
      distanceM: 3200,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861011003',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.6,
      reviewCount: 76,
      deliveryEnabled: false,
      description: 'Wholesale and retail grocery store with packaged staples.',
    ),

    // -------------------------------------------------------------
    // 3. Medicines (medicines)
    // -------------------------------------------------------------
    Business(
      id: 'biz_med_1',
      name: 'Apollo Pharmacy & Emergency Care',
      categorySlug: 'medicines',
      categoryName: 'Pharmacy & Health',
      addressText: 'Hospital Road, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 400,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861013001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 220,
      deliveryEnabled: true,
      deliveryTimeMins: 15,
      description: '24x7 prescription medicines, first aid, baby care and wellness items.',
    ),
    Business(
      id: 'biz_med_2',
      name: 'Kuanpal MedStore & Surgical',
      categorySlug: 'medicines',
      categoryName: 'Pharmacy & Health',
      addressText: 'Main Bazaar, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1100,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861013002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 140,
      deliveryEnabled: true,
      deliveryTimeMins: 20,
      description: 'Genuine medicines, health diagnostics, BP/Sugar testing.',
    ),

    // -------------------------------------------------------------
    // 4. Doctors (doctors)
    // -------------------------------------------------------------
    Business(
      id: 'biz_doc_1',
      name: 'Dr. Manoj Mohapatra Clinic (General Physician)',
      categorySlug: 'doctors',
      categoryName: 'Doctors & Clinics',
      addressText: 'Near Chhatia Polyclinic, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 500,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861031001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 175,
      description:
          'MBBS, MD. Daily OPD consultation for fever, diabetes, hypertension.',
    ),
    Business(
      id: 'biz_doc_2',
      name: 'Kuanpal Child & Family Health Clinic',
      categorySlug: 'doctors',
      categoryName: 'Doctors & Clinics',
      addressText: 'Hospital Road, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1350,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861031002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 110,
      description: 'Pediatric care, vaccination, family health consultation.',
    ),

    // -------------------------------------------------------------
    // 5. Cab & Auto (cab_auto)
    // -------------------------------------------------------------
    Business(
      id: 'biz_cab_1',
      name: 'Chhatia Auto-Rickshaw Stand Association',
      categorySlug: 'cab_auto',
      categoryName: 'Cab & Auto',
      addressText: 'NH-16 Junction Auto Stand, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 200,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861032001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 190,
      description: 'Local auto service, shared rides, emergency 24-hr drops to Cuttack/Jajpur.',
    ),
    Business(
      id: 'biz_cab_2',
      name: 'Kuanpal Taxi & Tour Cabs',
      categorySlug: 'cab_auto',
      categoryName: 'Cab & Auto',
      addressText: 'Near Canal Bridge, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 850,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861032002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 94,
      description: 'Sedan, SUV and commercial cab hire for airport, railway and outstation trips.',
    ),

    // -------------------------------------------------------------
    // 6. Services (services) -> Consolidating Electrician, Plumber, Carpenter, AC Mechanic, Home Painting, Cleaning
    // -------------------------------------------------------------
    Business(
      id: 'biz_serv_1',
      name: 'Biswal Electricals & Wiring Solutions',
      categorySlug: 'services',
      categoryName: 'Services (Electrician)',
      addressText: 'Market Lane, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 420,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861015001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 164,
      description: 'House wiring, fan installation, inverter setup, motor repair and electrical care.',
    ),
    Business(
      id: 'biz_serv_2',
      name: 'Rath Plumbing & Sanitary Works',
      categorySlug: 'services',
      categoryName: 'Services (Plumber)',
      addressText: 'Station Road, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 900,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861016001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 110,
      description: 'Pipeline leakage repair, tap/cistern replacement, water motor and tank cleaning.',
    ),
    Business(
      id: 'biz_serv_3',
      name: 'Mahapatra Woodcraft & Furniture',
      categorySlug: 'services',
      categoryName: 'Services (Carpenter)',
      addressText: 'Near High School, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 750,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861017001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 95,
      description: 'Wooden wardrobes, doors, window frames, lock fitting and custom repairs.',
    ),
    Business(
      id: 'biz_serv_4',
      name: 'CoolTech AC & Refrigeration Care',
      categorySlug: 'services',
      categoryName: 'Services (AC Mechanic)',
      addressText: 'NH-16 Chowk, Chandikhol',
      locality: 'Chandikhol',
      city: 'Jajpur',
      distanceM: 3100,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861033001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 82,
      description: 'Split AC installation, gas charging, jet pump coil wash and fridge repairs.',
    ),
    Business(
      id: 'biz_serv_5',
      name: 'Odisha Wall Decor & Home Painting',
      categorySlug: 'services',
      categoryName: 'Services (Home Painting & Decor)',
      addressText: 'Link Road, Jagatpur',
      locality: 'Jagatpur',
      city: 'Cuttack',
      distanceM: 2600,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861033002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 74,
      description: 'Interior and exterior painting, wall putty, waterproof primer and texture.',
    ),
    Business(
      id: 'biz_serv_6',
      name: 'CleanWave Home Deep Cleaning',
      categorySlug: 'services',
      categoryName: 'Services (Cleaning)',
      addressText: 'Near College Square, Tangi',
      locality: 'Tangi',
      city: 'Cuttack',
      distanceM: 2100,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861033003',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 88,
      description: 'Home deep cleaning, sofa shampoo, bathroom wash and pest disinfection.',
    ),

    // -------------------------------------------------------------
    // 7. Electronics (electronics)
    // -------------------------------------------------------------
    Business(
      id: 'biz_elec_1',
      name: 'TechZone Mobile & Electronics',
      categorySlug: 'electronics',
      categoryName: 'Electronics & Mobile',
      addressText: 'Main Bazaar, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 300,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861023001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 215,
      description: 'Smartphone screen replacement, mobile accessories, TV and laptop care.',
    ),
    Business(
      id: 'biz_elec_2',
      name: 'Kuanpal Digital World',
      categorySlug: 'electronics',
      categoryName: 'Electronics & Mobile',
      addressText: 'College Road, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1050,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861023002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 130,
      description: 'Smartphones, audio headphones, powerbanks, sound systems and repairs.',
    ),

    // -------------------------------------------------------------
    // 8. Shops (shops) -> Consolidating General Store, Tailoring, Stationery & Gifting
    // -------------------------------------------------------------
    Business(
      id: 'biz_shop_1',
      name: 'Ganesh General & Variety Store',
      categorySlug: 'shops',
      categoryName: 'Shops (General Store)',
      addressText: 'Temple Road, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 250,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861021001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 95,
      description:
          'Household plasticware, gifting, Pooja items, stationery and snacks.',
    ),
    Business(
      id: 'biz_shop_2',
      name: 'Padmini Tailoring & Designer Studio',
      categorySlug: 'shops',
      categoryName: 'Shops (Tailor & Boutiques)',
      addressText: 'Market Complex, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 800,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861020001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 135,
      description: 'Custom blouse stitching, kurti designing, alterations, salwar and picofall.',
    ),
    Business(
      id: 'biz_shop_3',
      name: 'Student Book Depot & Printing Hub',
      categorySlug: 'shops',
      categoryName: 'Shops (Stationery & Books)',
      addressText: 'Near High School, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 600,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861028001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 155,
      description: 'School books, photocopy, color print, spiral binding and stationery sets.',
    ),

    // -------------------------------------------------------------
    // 9. Fashion (fashion)
    // -------------------------------------------------------------
    Business(
      id: 'biz_fash_1',
      name: 'Sambalpuri Handloom & Silk Kendra',
      categorySlug: 'fashion',
      categoryName: 'Fashion & Apparel',
      addressText: 'Main Bazaar, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 400,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861022001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 260,
      description: 'Handwoven Sambalpuri Ikkat sarees, Pasapalli, Bomkai and cotton fabrics.',
    ),
    Business(
      id: 'biz_fash_2',
      name: 'Kuanpal Menswear & Footwear',
      categorySlug: 'fashion',
      categoryName: 'Fashion & Apparel',
      addressText: 'Bus Stand Road, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1100,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861022002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 110,
      description:
          'Casual shirts, formal pants, jeans, sports shoes and ethnic wear.',
    ),

    // -------------------------------------------------------------
    // 10. Hotels & Stays (hotels_stays)
    // -------------------------------------------------------------
    Business(
      id: 'biz_hot_1',
      name: 'Hotel Grand Chhatia Residency',
      categorySlug: 'hotels_stays',
      categoryName: 'Hotels & Stays',
      addressText: 'NH-16 Highway Junction, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 650,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861019001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 310,
      roomBookingEnabled: true,
      description: 'Deluxe AC rooms, 24-hr check-in, parking, free Wi-Fi and restaurant.',
    ),
    Business(
      id: 'biz_hot_2',
      name: 'Kuanpal Guest House & Lodge',
      categorySlug: 'hotels_stays',
      categoryName: 'Hotels & Stays',
      addressText: 'Near Canal, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1400,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861019002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 95,
      roomBookingEnabled: true,
      description:
          'Clean budget rooms for travelers, business trips and family stays.',
    ),

    // -------------------------------------------------------------
    // 11. Fitness & Wellness (fitness_wellness)
    // -------------------------------------------------------------
    Business(
      id: 'biz_fit_1',
      name: 'PowerHouse Fitness Gym & Crossfit',
      categorySlug: 'fitness_wellness',
      categoryName: 'Fitness & Wellness',
      addressText: 'College Road, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 700,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861026001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 180,
      description: 'Modern gym, cardio machines, strength training, diet plans and trainers.',
    ),
    Business(
      id: 'biz_fit_2',
      name: 'Kuanpal Yoga & Health Care',
      categorySlug: 'fitness_wellness',
      categoryName: 'Fitness & Wellness',
      addressText: 'Main Road, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1250,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861026002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 88,
      description:
          'Morning and evening yoga batches, meditation and physiotherapy.',
    ),

    // -------------------------------------------------------------
    // 12. Beauty & Salon (beauty_salon)
    // -------------------------------------------------------------
    Business(
      id: 'biz_sal_1',
      name: 'Trends Unisex Hair & Beauty Salon',
      categorySlug: 'beauty_salon',
      categoryName: 'Beauty & Salon',
      addressText: 'Market Complex, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 320,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861018001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 230,
      description:
          'Hair styling, fade haircuts, bridal makeup, facial and hair spa.',
    ),
    Business(
      id: 'biz_sal_2',
      name: 'Natural Glow Beauty Parlour',
      categorySlug: 'beauty_salon',
      categoryName: 'Beauty & Salon',
      addressText: 'Near Bus Stand, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 900,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861018002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 115,
      description:
          'Organic skin care, hair coloring, threading, waxing and manicure.',
    ),

    // -------------------------------------------------------------
    // 13. Automobile (automobile)
    // -------------------------------------------------------------
    Business(
      id: 'biz_auto_1',
      name: 'Sai Krupa Two-Wheeler Multi-Brand Service',
      categorySlug: 'automobile',
      categoryName: 'Automobile',
      addressText: 'NH-16 Link, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 500,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861027001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 145,
      description: 'Bike servicing, engine tuning, oil change, brake pads and water foam wash.',
    ),
    Business(
      id: 'biz_auto_2',
      name: 'Kuanpal SpeedWay Tyres & 24x7 Puncture',
      categorySlug: 'automobile',
      categoryName: 'Automobile',
      addressText: 'Main Highway, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 850,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861027002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 88,
      description: 'Tubeless tyre puncture, nitrogen filling, wheel alignment and battery check.',
    ),

    // -------------------------------------------------------------
    // 14. Education (education)
    // -------------------------------------------------------------
    Business(
      id: 'biz_edu_1',
      name: 'Pragati Coaching Academy & Computer Institute',
      categorySlug: 'education',
      categoryName: 'Education',
      addressText: 'College Road, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 600,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861034001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 130,
      description: 'Class 8-12 science/arts tuition, PGDCA/DCA computer courses, spoken English.',
    ),
    Business(
      id: 'biz_edu_2',
      name: 'Saraswati Vidya Hub',
      categorySlug: 'education',
      categoryName: 'Education',
      addressText: 'Near High School, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1100,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861034002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 92,
      description:
          'Competitive exam foundation, mathematics and science coaching.',
    ),

    // -------------------------------------------------------------
    // 15. Home & Furniture (home_furniture)
    // -------------------------------------------------------------
    Business(
      id: 'biz_furn_1',
      name: 'Maa Durga Furniture & Mattress House',
      categorySlug: 'home_furniture',
      categoryName: 'Home & Furniture',
      addressText: 'NH-16 Highway Bazaar, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 800,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861035001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 110,
      description: 'Solid wooden double beds, steel almirahs, dining sets and foam mattresses.',
    ),
    Business(
      id: 'biz_furn_2',
      name: 'Kuanpal Kitchenware & Utensils',
      categorySlug: 'home_furniture',
      categoryName: 'Home & Furniture',
      addressText: 'Market Chowk, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 950,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861035002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 78,
      description: 'Pressure cookers, nonstick cookware, dinner sets, kitchen racks and plastics.',
    ),

    // -------------------------------------------------------------
    // 16. Events & Catering (events_catering)
    // -------------------------------------------------------------
    Business(
      id: 'biz_ev_1',
      name: 'Kalinga Tent House & Light Sound',
      categorySlug: 'events_catering',
      categoryName: 'Events & Catering',
      addressText: 'Near Bus Stand, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 450,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861036001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 145,
      description: 'Wedding mandap decoration, sound systems, generator backup, stage lighting.',
    ),
    Business(
      id: 'biz_ev_2',
      name: 'Shree Jagannath Royal Caterers',
      categorySlug: 'events_catering',
      categoryName: 'Events & Catering',
      addressText: 'Main Road, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1200,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861036002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 112,
      description: 'Traditional and continental catering for marriages, receptions and birthdays.',
    ),

    // -------------------------------------------------------------
    // 17. Agriculture (agriculture)
    // -------------------------------------------------------------
    Business(
      id: 'biz_agro_1',
      name: 'Krushak Seva Kendra (Seeds & Fertilizers)',
      categorySlug: 'agriculture',
      categoryName: 'Agriculture',
      addressText: 'Block Chowk, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 600,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861037001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.9,
      reviewCount: 160,
      description: 'Certified paddy seeds, organic fertilizers, pesticides, sprayers & crop tools.',
    ),
    Business(
      id: 'biz_agro_2',
      name: 'Kuanpal Agro Machinery & Pumps',
      categorySlug: 'agriculture',
      categoryName: 'Agriculture',
      addressText: 'Canal Road, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1000,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861037002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 88,
      description: 'Submersible farm motors, irrigation pipes, tractor spare parts and diesel pumps.',
    ),

    // -------------------------------------------------------------
    // 18. Construction (construction)
    // -------------------------------------------------------------
    Business(
      id: 'biz_const_1',
      name: 'Shree Balaji Building Materials & Cement',
      categorySlug: 'construction',
      categoryName: 'Construction',
      addressText: 'NH-16 Highway, Chhatia',
      locality: 'Chhatia',
      city: 'Jajpur',
      distanceM: 700,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861038001',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.8,
      reviewCount: 135,
      description: 'Ultratech & ACC Cement, Jindal TMT steel rods, river sand, red bricks and stone chips.',
    ),
    Business(
      id: 'biz_const_2',
      name: 'Kuanpal Hardware & Civil Supplies',
      categorySlug: 'construction',
      categoryName: 'Construction',
      addressText: 'College Road, Kuanpal',
      locality: 'Kuanpal',
      city: 'Cuttack',
      distanceM: 1150,
      status: 'active',
      verificationStatus: 'verified',
      phoneE164: '+919861038002',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.7,
      reviewCount: 90,
      description: 'Roofing sheets, water tanks, sanitaryware, paints, binding wire and building tools.',
    ),
  ];

  /// Checks whether a business category slug matches a target category slug,
  /// accounting for aliases and consolidated sub-trades under the 18 Top-Level Categories.
  static bool matchesCategory(String? itemSlug, String? targetSlug) {
    if (targetSlug == null || targetSlug.isEmpty || targetSlug == 'all') {
      return true;
    }
    if (itemSlug == null || itemSlug.isEmpty) return false;
    final item = itemSlug.toLowerCase().trim();
    final target = targetSlug.toLowerCase().trim();
    if (item == target) return true;

    // Services consolidation
    if (target == 'services' || target == 'service') {
      return item == 'services' ||
          item == 'service' ||
          item == 'electrician' ||
          item == 'plumber' ||
          item == 'carpenter' ||
          item == 'home_painting_decor' ||
          item == 'painting' ||
          item == 'ac_mechanic';
    }

    // Shops consolidation
    if (target == 'shops' || target == 'retail') {
      return item == 'shops' ||
          item == 'retail' ||
          item == 'general' ||
          item == 'tailor' ||
          item == 'tailoring';
    }

    // Food & Dining
    if (target == 'food' || target == 'restaurant') {
      return item == 'food' || item == 'restaurant';
    }

    // Medicines & Health
    if (target == 'medicines' || target == 'medical' || target == 'pharmacy') {
      return item == 'medicines' || item == 'medical' || item == 'pharmacy';
    }

    // Doctors & Clinics
    if (target == 'doctors' || target == 'doctor' || target == 'clinic') {
      return item == 'doctors' || item == 'doctor' || item == 'clinic';
    }

    // Cab & Auto
    if (target == 'cab_auto' || target == 'transport' || target == 'cab' || target == 'auto') {
      return item == 'cab_auto' || item == 'transport' || item == 'cab' || item == 'auto';
    }

    // Hotels & Stays
    if (target == 'hotels_stays' || target == 'hotel' || target == 'stays') {
      return item == 'hotels_stays' || item == 'hotel' || item == 'stays';
    }

    // Beauty & Salon
    if (target == 'beauty_salon' || target == 'salon' || target == 'beauty') {
      return item == 'beauty_salon' || item == 'salon' || item == 'beauty';
    }

    // Automobile
    if (target == 'automobile' || target == 'automotive' || target == 'auto_repair') {
      return item == 'automobile' || item == 'automotive' || item == 'auto_repair';
    }

    return false;
  }

  /// Returns listings for a given category slug. If slug is null or 'all', returns all listings.
  /// Can be optionally filtered by search query, locality, or maximum distance in meters.
  static List<Business> getListingsForCategory(
    String? categorySlug, {
    String? query,
    String? locality,
    int? maxRadiusM,
    String? sortBy, // 'distance', 'rating', 'relevance'
  }) {
    var items = allListings;

    if (categorySlug != null &&
        categorySlug.isNotEmpty &&
        categorySlug != 'all') {
      items = items.where((b) => matchesCategory(b.categorySlug, categorySlug)).toList();
    }

    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      items = items.where((b) {
        return b.name.toLowerCase().contains(q) ||
            (b.description?.toLowerCase().contains(q) ?? false) ||
            (b.locality?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    if (locality != null &&
        locality.trim().isNotEmpty &&
        locality != 'All' &&
        locality != 'All Service Areas') {
      items = items.where((b) => b.locality == locality).toList();
    }

    if (maxRadiusM != null && maxRadiusM > 0) {
      items = items.where((b) => (b.distanceM ?? 0) <= maxRadiusM).toList();
    }

    final sorted = List<Business>.from(items);
    if (sortBy == 'distance') {
      sorted.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
    } else if (sortBy == 'rating') {
      sorted.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    }

    return sorted.asMap().entries.map((entry) {
      final b = entry.value;
      if (b.latitude != null && b.longitude != null) return b;
      final (lat, lng) = _getCoordinates(b.locality, entry.key, (b.distanceM ?? 500).toInt());
      return b.copyWith(latitude: lat, longitude: lng);
    }).toList();
  }

  static (double, double) _getCoordinates(String? locality, int index, int distanceM) {
    final (baseLat, baseLng) = switch (locality?.toLowerCase()) {
      'kuanpal' => (20.5750, 86.0120),
      'jagatpur' => (20.5050, 85.9250),
      'chandikhol' => (20.6850, 86.1550),
      'tangi' => (20.5900, 85.9800),
      'chhatia' || _ => (20.6120, 86.0465),
    };
    final angle = (index * 137.5) * (3.141592653589793 / 180);
    final dLat = (distanceM * math.cos(angle)) / 111320;
    final dLng = (distanceM * math.sin(angle)) / (111320 * math.cos(baseLat * 3.141592653589793 / 180));
    return (baseLat + dLat, baseLng + dLng);
  }

  /// Returns approved service localities (Chhatia, Kuanpal, Jagatpur, Tangi, Chandikhol)
  static List<String> getAvailableLocalities() => approvedServicePlaces;
}
