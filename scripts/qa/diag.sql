SELECT p.user_id, p.display_name, av.is_online, (av.lease_expires_at > now()) as lease_valid, rl.status as loc_status,
  (SELECT count(*) FROM delivery_assignments a WHERE a.rider_user_id=p.user_id AND a.state='active') as active_assignments,
  (SELECT count(*) FROM delivery_offers x WHERE x.rider_user_id=p.user_id AND x.state='offered') as active_offers
FROM rider_profiles p
JOIN users u ON u.id=p.user_id AND u.status='active'
JOIN user_roles ur ON ur.user_id=p.user_id AND ur.role='rider'
JOIN rider_profile_localities rl ON rl.rider_profile_id=p.id AND rl.locality_id='02200000-0000-4000-8000-000000000101'
JOIN platform_delivery_localities l ON l.id=rl.locality_id AND l.is_active AND l.delivery_enabled
JOIN rider_availability_sessions av ON av.rider_user_id=p.user_id
WHERE p.user_id='4e300000-0000-4000-8000-000000000003';
