SELECT id, order_id, state, locality_id FROM delivery_jobs WHERE id='9b58bba9-4fc7-4636-a043-e1f379bb8f3b';
SELECT id, state, rider_user_id, expires_at FROM delivery_offers WHERE job_id='9b58bba9-4fc7-4636-a043-e1f379bb8f3b';
SELECT id, state FROM delivery_dispatch_runs WHERE job_id='9b58bba9-4fc7-4636-a043-e1f379bb8f3b';
