# ABASHYAKA — OFFICIAL CATEGORY TAXONOMY & SERVICE AREA STANDARD V2.0

## 1. Executive Summary

This document defines the authoritative **18 Top-Level Category Taxonomy** and **Service Area Policy** for the Abashyaka application. All customer discovery, explore home grids, categories directory screens, merchant listings, and search results must adhere strictly to these definitions.

---

## 2. Location & Service Area Standard

### Core Rule:
1. **Admin-Approved Service Places Only**: The application discovers and filters businesses strictly within admin-approved service places configured in `ServiceabilityService` and active on the platform:
   - **Chhatia** (Jajpur District) — *Delivery Active*
   - **Kuanpal** (Cuttack District) — *Delivery Active*
   - **Jagatpur** (Cuttack District) — *Discovery Active*
   - **Tangi** (Cuttack District) — *Discovery Active*
   - **Chandikhol** (Jajpur District) — *Discovery Active*
2. **No Raw Pincodes Displayed**: Do **NOT** render raw 6-digit postal code numbers (e.g. `751007`, `754023`) as prominent badges or filter options in customer-facing screens. Only clean, human-readable place names with distance in kilometers (e.g. `Chhatia • 1.2 km`, `Kuanpal • 0.8 km`) are permitted.
3. **Synchronized with Home Tab**: Location selection on directory or search screens must synchronize directly with the active delivery/discovery place selected in the Home tab.

---

## 3. The 18 Top-Level Categories

Trades and sub-categories are consolidated under parent umbrellas:
- **Plumber, Carpenter, Electrician, AC Mechanic, Home Painting & Decor, Cleaning** are consolidated inside **Services**.
- **Tailor / Tailoring & Stitching** is consolidated inside **Shops** (and Fashion).

```
+----+----------------------+-------------------+------------------------------------------+-----------------------------------------------------------+
| #  | Category Name        | Canonical Slug    | Official Icon Asset                      | Scope & Sub-services                                      |
+----+----------------------+-------------------+------------------------------------------+-----------------------------------------------------------+
| 1  | Food                 | food              | assets/icons/categories/food.webp        | Local restaurants, Odia dining, snacks, biryani, thalis   |
| 2  | Grocery              | grocery           | assets/icons/categories/grocery.webp     | Fresh kirana, provisions, daily dairy, packaged foods     |
| 3  | Medicines            | medicines         | assets/icons/categories/medicines.webp   | 24x7 pharmacies, OTC supplies, healthcare goods           |
| 4  | Doctors              | doctors           | assets/icons/categories/doctors.webp     | Verified doctors, polyclinics, OPD consultations          |
| 5  | Cab & Auto           | cab_auto          | assets/icons/categories/cab_auto.webp    | Auto-rickshaws, cabs, taxis, local passenger transport    |
| 6  | Services             | services          | assets/icons/categories/services.webp    | Consolidated Home & Technical Services:                   |
|    |                      |                   |                                          |   * Electrician                                           |
|    |                      |                   |                                          |   * Plumber                                               |
|    |                      |                   |                                          |   * Carpenter                                             |
|    |                      |                   |                                          |   * AC Mechanic                                           |
|    |                      |                   |                                          |   * Home Painting & Decor                                 |
|    |                      |                   |                                          |   * Cleaning & Housekeeping                               |
| 7  | Electronics          | electronics       | assets/icons/categories/electronics.webp | Smartphones, laptops, TVs, home appliances & care        |
| 8  | Shops                | shops             | assets/icons/categories/shops.webp       | Retail & Neighborhood Stores:                             |
|    |                      |                   |                                          |   * General & Variety Store                               |
|    |                      |                   |                                          |   * Tailoring & Stitching                                 |
|    |                      |                   |                                          |   * Stationery & Books                                    |
|    |                      |                   |                                          |   * Gifting & Plasticware                                 |
| 9  | Fashion              | fashion           | assets/icons/categories/fashion.webp     | Sambalpuri handloom, sarees, menswear, footwear           |
| 10 | Hotels & Stays       | hotels_stays      | assets/icons/categories/hotels_stays.webp| Verified hotels, lodges, guest houses, resorts            |
| 11 | Fitness & Wellness   | fitness_wellness  | assets/icons/categories/fitness_wellness | Gyms, yoga centers, diagnostic labs, wellness clinics     |
| 12 | Beauty & Salon       | beauty_salon      | assets/abashyaka/categories/cat_appo... | Men's grooming, women's salons, bridal makeup, spa        |
| 13 | Automobile           | automobile        | Icons.directions_car_rounded (3D glyph)  | Bike/car service, tyre shops, 24x7 puncture points        |
| 14 | Education            | education         | Icons.school_rounded (3D glyph)          | Schools, coaching centers, tuition, computer institutes   |
| 15 | Home & Furniture     | home_furniture    | Icons.chair_rounded (3D glyph)           | Furniture, modular decor, cookware, bedding, utensils     |
| 16 | Events & Catering    | events_catering   | assets/abashyaka/categories/cat_event... | Event planners, wedding caterers, tent houses, DJs        |
| 17 | Agriculture          | agriculture       | Icons.agriculture_rounded (3D glyph)     | Seeds, fertilizers, nurseries, farming tools & equipment  |
| 18 | Construction         | construction      | Icons.construction_rounded (3D glyph)    | Building materials, cement, TMT rods, sand, contractors   |
+----+----------------------+-------------------+------------------------------------------+-----------------------------------------------------------+
```

---

## 4. Sub-Service & Sub-Shop Architecture

### Inside "Services" (`services`):
Tapping **Services** presents sub-trade filter chips:
1. `All Services` (All active service pros)
2. `Electrician` (Wiring, inverter, geyser, appliance installation)
3. `Plumber` (Pipe repair, sanitaryware, water pump, leakages)
4. `Carpenter` (Furniture, woodcraft, modular kitchen, door locks)
5. `AC Mechanic` (AC installation, gas filling, coil cleaning, repair)
6. `Home Painting & Decor` (Interior/exterior paint, waterproofing, putty)
7. `Cleaning & Pest Control` (Deep cleaning, sofa shampoo, pest control)

### Inside "Shops" (`shops`):
Tapping **Shops** presents sub-retail filter chips:
1. `All Shops` (All active neighborhood retail shops)
2. `General Store` (Daily provisions, variety goods, essentials)
3. `Tailoring & Boutiques` (Custom stitching, alterations, blouse designs)
4. `Stationery & Books` (School supplies, photocopying, academic press)
5. `Gifting & Novelties` (Pooja articles, toys, cosmetics, kitchen plastics)

---

## 5. Implementation Rules for All Agents

1. **Never create individual top-level categories for sub-trades**: Do not add Plumber, Electrician, Carpenter, AC Mechanic, Home Painting, or Tailor as separate top-level rows in Screen 8 or Home Screen. They must reside under **Services** or **Shops**.
2. **Never expose raw 6-digit pincode tags**: Always display the place name (e.g. `Chhatia`, `Kuanpal`) and formatted distance in km (e.g. `1.2 km`).
3. **Synchronize location state**: Always use `appLocationProvider` and `ServiceabilityService` for location summaries and active place filters.
4. **Use approved 3D assets**: Top-level categories must use their designated `.webp` or `.png` 3D icon assets from `assets/icons/categories/` or `assets/abashyaka/categories/`.
