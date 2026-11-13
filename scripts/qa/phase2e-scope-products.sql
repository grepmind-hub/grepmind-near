INSERT INTO platform_catalog_product_delivery_localities(product_id,locality_id,is_active)
SELECT p.id,l.id,true
FROM platform_catalog_products p
JOIN platform_catalog_product_district_visibility d ON d.product_id=p.id AND d.is_active
JOIN platform_districts di ON di.id=d.district_id
JOIN platform_delivery_localities l ON l.district_id=di.id AND l.delivery_enabled AND l.is_active
WHERE (p.sku='P2E-QA-FOOD-CTK' AND di.slug='cuttack' AND l.slug='kuanpal')
   OR (p.sku='P2E-QA-GROC-CTK' AND di.slug='cuttack' AND l.slug='kuanpal')
   OR (p.sku='P2E-QA-FOOD-JJP' AND di.slug='jajpur' AND l.slug='chhatia')
   OR (p.sku='P2E-QA-GROC-JJP' AND di.slug='jajpur' AND l.slug='chhatia')
ON CONFLICT (product_id,locality_id) DO UPDATE SET is_active=true;

