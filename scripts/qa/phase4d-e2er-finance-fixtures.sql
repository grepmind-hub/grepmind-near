-- Disposable Phase 4D-E2E-R prerequisites; apply only to grepmind_3e_qa.
-- Enables sandbox ledger paths without enabling live UPI, COD, settlement,
-- real money, or any external transfer.

INSERT INTO users(id,phone_e164,display_name,status) VALUES
 ('4c000000-0000-4000-8000-000000000005','+919990000175','Phase 4D QA Finance Reviewer','active'),
 ('4c000000-0000-4000-8000-000000000006','+919990000176','Phase 4D QA Finance Operator','active')
ON CONFLICT (id) DO NOTHING;
INSERT INTO user_roles(user_id,role) VALUES
 ('4c000000-0000-4000-8000-000000000005','admin'),
 ('4c000000-0000-4000-8000-000000000006','admin')
ON CONFLICT DO NOTHING;

-- Finance policy/batch approvals use separate QA principals.
INSERT INTO financial_access_grants(user_id,permission,granted_by,approved_by,reason)
SELECT '3e000000-0000-4000-8000-000000000004',permission,
       (SELECT id FROM users WHERE phone_e164='+910000000000'),
       '4c000000-0000-4000-8000-000000000005',
       'Phase 4D isolated QA finance configuration access'
FROM (VALUES ('finance.configure')) AS grants(permission)
ON CONFLICT (user_id,permission) WHERE revoked_at IS NULL DO NOTHING;

INSERT INTO financial_access_grants(user_id,permission,granted_by,approved_by,reason)
SELECT '4c000000-0000-4000-8000-000000000005',permission,
       (SELECT id FROM users WHERE phone_e164='+910000000000'),
       '3e000000-0000-4000-8000-000000000004',
       'Phase 4D isolated QA independent finance reviewer access'
FROM (VALUES ('finance.read'),('finance.post'),('finance.configure')) AS grants(permission)
ON CONFLICT (user_id,permission) WHERE revoked_at IS NULL DO NOTHING;

INSERT INTO financial_access_grants(user_id,permission,granted_by,approved_by,reason)
SELECT '4c000000-0000-4000-8000-000000000006',permission,
       (SELECT id FROM users WHERE phone_e164='+910000000000'),
       '4c000000-0000-4000-8000-000000000005',
       'Phase 4D isolated QA independent finance operator access'
FROM (VALUES ('finance.read'),('finance.post'),('finance.configure')) AS grants(permission)
ON CONFLICT (user_id,permission) WHERE revoked_at IS NULL DO NOTHING;

INSERT INTO financial_accounts(account_code,display_name,account_class,currency,normal_side)
VALUES ('qa_provider_clearing','QA provider clearing','asset','INR','debit'),
       ('qa_customer_receipts_unapplied','QA customer receipts unapplied','liability','INR','credit')
ON CONFLICT (account_code) DO NOTHING;
INSERT INTO payment_ledger_account_mappings(purpose,account_id,configured_by)
SELECT mapping.purpose,account.id,(SELECT id FROM users WHERE phone_e164='+910000000000')
FROM (VALUES ('provider_clearing','qa_provider_clearing'),
             ('customer_receipts_unapplied','qa_customer_receipts_unapplied')) AS mapping(purpose,account_code)
JOIN financial_accounts account ON account.account_code=mapping.account_code
ON CONFLICT (purpose) DO NOTHING;

UPDATE financial_feature_config
SET financial_posting_enabled=true,
    payment_intent_creation_enabled=true,
    payment_attempt_creation_enabled=true,
    sandbox_payment_enabled=true,
    sandbox_cod_enabled=true,
    sandbox_merchant_settlement_enabled=true,
    upi_enabled=false,
    cod_enabled=false,
    merchant_settlement_enabled=false,
    real_money_enabled=false,
    updated_by=(SELECT id FROM users WHERE phone_e164='+910000000000'),
    change_reason='Phase 4D-E2R isolated sandbox acceptance only',
    updated_at=now()
WHERE singleton=true;
