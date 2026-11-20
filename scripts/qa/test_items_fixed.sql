SELECT product_name, '' AS variant_name, '' AS unit_label, quantity FROM customer_order_items WHERE order_id='49ce51bb-b1eb-48d4-ad55-147731e29103'
UNION ALL
SELECT product_name, variant_name, unit_label, quantity FROM platform_customer_order_items WHERE order_id='49ce51bb-b1eb-48d4-ad55-147731e29103'
ORDER BY product_name;
