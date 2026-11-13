-- Disposable-only Phase 4C QA finance actor and synthetic COD feature gate.
INSERT INTO users(id,phone_e164,display_name,status) VALUES
 ('4c000000-0000-4000-8000-000000000005','+919990000175','Phase 4C QA Finance Approver','active')
ON CONFLICT (id) DO NOTHING;
INSERT INTO user_roles(user_id,role) VALUES
 ('4c000000-0000-4000-8000-000000000005','admin')
ON CONFLICT DO NOTHING;
INSERT INTO financial_access_grants(user_id,permission,granted_by,approved_by,reason)
SELECT '3e000000-0000-4000-8000-000000000004',permission,
       (SELECT id FROM users WHERE phone_e164='+910000000000'),
       '4c000000-0000-4000-8000-000000000005',
       'Temporary Phase 4C isolated QA finance access grant'
FROM (VALUES ('finance.read'),('finance.post')) AS grants(permission)
ON CONFLICT (user_id,permission) WHERE revoked_at IS NULL DO NOTHING;
UPDATE financial_feature_config
SET financial_posting_enabled=true,sandbox_cod_enabled=true,upi_enabled=false,
    cod_enabled=false,merchant_settlement_enabled=false,real_money_enabled=false,
    updated_by=(SELECT id FROM users WHERE phone_e164='+910000000000'),
    change_reason='Temporary synthetic Phase 4C isolated QA validation'
WHERE singleton=true;
