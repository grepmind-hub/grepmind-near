INSERT INTO platform_checkout_quotes (
  id, customer_user_id, vertical, locality_id, service_date, address_id, address_updated_at,
  partner_business_id, items, item_subtotal_minor, delivery_fee_minor, tax_minor, grand_total_minor, currency, expires_at
) VALUES 
  ('3e000000-0000-4000-8000-000000000701', '3e000000-0000-4000-8000-000000000001', 'food', '02200000-0000-4000-8000-000000000101', CURRENT_DATE, '3e000000-0000-4000-8000-000000000301', now(), '3e000000-0000-4000-8000-000000000101', '[{"variant_id":"3e000000-0000-4000-8000-000000000202","quantity":1}]'::jsonb, 35000, 3000, 0, 38000, 'INR', now() + interval '1 day'),
  ('3e000000-0000-4000-8000-000000000702', '3e000000-0000-4000-8000-000000000001', 'food', '02200000-0000-4000-8000-000000000101', CURRENT_DATE, '3e000000-0000-4000-8000-000000000301', now(), '3e000000-0000-4000-8000-000000000101', '[{"variant_id":"3e000000-0000-4000-8000-000000000202","quantity":1}]'::jsonb, 70000, 4000, 0, 74000, 'INR', now() + interval '1 day'),
  ('3e000000-0000-4000-8000-000000000703', '3e000000-0000-4000-8000-000000000001', 'grocery', '02200000-0000-4000-8000-000000000101', CURRENT_DATE, '3e000000-0000-4000-8000-000000000301', now(), '3e000000-0000-4000-8000-000000000101', '[{"variant_id":"3e000000-0000-4000-8000-000000000202","quantity":2}]'::jsonb, 48000, 3000, 0, 51000, 'INR', now() + interval '1 day')
ON CONFLICT (id) DO NOTHING;

INSERT INTO customer_orders (
  id, customer_user_id, business_id, order_type, status, fulfillment_type, 
  item_total, grand_total, currency, reference_code, order_source, 
  platform_vertical, delivery_locality_id, delivery_address_id, platform_checkout_quote_id, payment_status, 
  payment_method, customer_notes
) VALUES
  ('3e000000-0000-4000-8000-000000000901', '3e000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000101', 'platform_order', 'placed', 'delivery', 350, 380, 'INR', 'AB-ORD-901', 'platform_catalog', 'food', '02200000-0000-4000-8000-000000000101', '3e000000-0000-4000-8000-000000000301', '3e000000-0000-4000-8000-000000000701', 'not_collected', 'cash_on_delivery', 'Less spicy, extra raita please.'),
  ('3e000000-0000-4000-8000-000000000902', '3e000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000101', 'platform_order', 'preparing', 'delivery', 700, 740, 'INR', 'AB-ORD-902', 'platform_catalog', 'food', '02200000-0000-4000-8000-000000000101', '3e000000-0000-4000-8000-000000000301', '3e000000-0000-4000-8000-000000000702', 'paid', 'upi', 'Pack in heat-sealed eco box.'),
  ('3e000000-0000-4000-8000-000000000903', '3e000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000101', 'platform_order', 'ready_for_pickup', 'delivery', 480, 510, 'INR', 'AB-ORD-903', 'platform_catalog', 'grocery', '02200000-0000-4000-8000-000000000101', '3e000000-0000-4000-8000-000000000301', '3e000000-0000-4000-8000-000000000703', 'paid', 'upi', 'Deliver before 8 PM.')
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status;

INSERT INTO platform_customer_order_items (
  order_id, product_id, variant_id, vertical, product_name, variant_name, unit_label, unit_price_minor, quantity, price_revision
) VALUES
  ('3e000000-0000-4000-8000-000000000901', '3e000000-0000-4000-8000-000000000201', '3e000000-0000-4000-8000-000000000202', 'food', 'Hyderabadi Chicken Biryani', 'Full', 'plate', 35000, 1, 1),
  ('3e000000-0000-4000-8000-000000000902', '3e000000-0000-4000-8000-000000000201', '3e000000-0000-4000-8000-000000000202', 'food', 'Mutton Kassa Special', 'Full', 'plate', 70000, 1, 1),
  ('3e000000-0000-4000-8000-000000000903', '3e000000-0000-4000-8000-000000000201', '3e000000-0000-4000-8000-000000000202', 'grocery', 'Fortune Mustard Oil 1L', '1 Litre', 'bottle', 24000, 2, 1)
ON CONFLICT (order_id, variant_id) DO NOTHING;
