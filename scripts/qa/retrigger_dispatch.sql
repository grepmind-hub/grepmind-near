UPDATE delivery_offers SET state='expired', responded_at=now() WHERE rider_user_id='3e000000-0000-4000-8000-000000000003' AND state='offered';
UPDATE delivery_jobs SET state='pending_dispatch', updated_at=now() WHERE id='9b58bba9-4fc7-4636-a043-e1f379bb8f3b';
UPDATE delivery_dispatch_runs SET state='cancelled', completed_at=now() WHERE job_id='9b58bba9-4fc7-4636-a043-e1f379bb8f3b' AND state IN ('searching', 'no_rider_available');
