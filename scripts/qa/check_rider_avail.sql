SELECT 
  CASE 
    WHEN EXISTS(SELECT 1 FROM delivery_assignments a WHERE a.rider_user_id='3e000000-0000-4000-8000-000000000003' AND a.state='active') THEN 'active assignment'
    WHEN EXISTS(SELECT 1 FROM delivery_offers x WHERE x.rider_user_id='3e000000-0000-4000-8000-000000000003' AND x.state='offered') THEN 'pending offer'
    WHEN EXISTS(SELECT 1 FROM rider_document_requirements q JOIN rider_profiles p ON p.user_id='3e000000-0000-4000-8000-000000000003' AND p.status='approved' WHERE q.is_active AND q.is_required AND q.vehicle_type IN ('any',p.vehicle_type) AND NOT EXISTS(SELECT 1 FROM rider_documents d WHERE d.rider_profile_id=p.id AND d.requirement_id=q.id AND d.review_status='accepted')) THEN 'docs not current'
    ELSE 'ok'
  END AS check_result;
