DELETE FROM delivery_events WHERE job_id='9b58bba9-4fc7-4636-a043-e1f379bb8f3b';
DELETE FROM delivery_offers WHERE job_id='9b58bba9-4fc7-4636-a043-e1f379bb8f3b';
DELETE FROM delivery_dispatch_runs WHERE job_id='9b58bba9-4fc7-4636-a043-e1f379bb8f3b';
UPDATE delivery_jobs SET state='pending_dispatch', updated_at=now() WHERE id='9b58bba9-4fc7-4636-a043-e1f379bb8f3b';
