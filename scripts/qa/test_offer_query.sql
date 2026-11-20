SELECT x.id::text id,j.id::text job_id,o.id::text order_id,o.reference_code,
	COALESCE(o.platform_vertical, CASE WHEN o.order_type='food_delivery' THEN 'food' ELSE 'grocery' END) AS platform_vertical,
	b.name pickup_business,b.address_text pickup_address,COALESCE(b.locality,b.city,'') pickup_locality,dl.name destination_locality,d.name destination_district,
	COALESCE(o.payment_method,'') payment_method,COALESCE(o.payment_status,'') payment_status,
	COALESCE((SELECT ob.amount_minor FROM cod_obligations ob WHERE ob.order_id=o.id),0) cod_amount_minor,
	CASE WHEN EXISTS(SELECT 1 FROM cod_collections c WHERE c.order_id=o.id) THEN 'collected' WHEN EXISTS(SELECT 1 FROM cod_obligations ob WHERE ob.order_id=o.id) THEN 'due' ELSE 'not_applicable' END cod_collection_state,
	x.expires_at::text expires_at
	FROM delivery_offers x JOIN delivery_jobs j ON j.id=x.job_id JOIN customer_orders o ON o.id=j.order_id
	JOIN businesses b ON b.id=j.business_id JOIN platform_delivery_localities l ON l.id=j.locality_id JOIN platform_districts d ON d.id=l.district_id
	JOIN platform_delivery_localities dl ON dl.id=j.locality_id
WHERE x.rider_user_id='3e000000-0000-4000-8000-000000000003' AND x.state='offered' AND x.expires_at>now();
