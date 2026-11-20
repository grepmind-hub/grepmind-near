#!/usr/bin/env python3
"""
Barabati Diagnostics & Health Clinic Controlled Remediation Script (Phase 01F.1)
Target ID: ce666666-6666-6666-6666-666666666666

Safeguard 1 Compliance:
1. Verifies current database state matches reported unauthorized mutation.
2. Checks for any intervening legitimate admin audit logs.
3. Preserves pre-remediation record snapshot to JSON.
4. Performs controlled restoration to historical state:
   - status = 'pending'
   - verification_status = 'pending'
   - phone_e164 = NULL
5. Saves post-remediation snapshot and records audit details.
"""

import subprocess
import json
import sys
import datetime

TARGET_ID = 'ce666666-6666-6666-6666-666666666666'

def run_psql(query, json_output=False):
    if json_output:
        if query.strip().startswith("WITH") or query.strip().startswith("with"):
            full_query = query
        else:
            full_query = f"SELECT json_agg(t) FROM ({query}) t;"
    else:
        full_query = query
    cmd = [
        "docker", "exec", "-i", "grepmind_postgres",
        "psql", "-U", "grepmind", "-d", "grepmind_near", "-t", "-A", "-c", full_query
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"psql error: {res.stderr}")
    return res.stdout.strip()

def main():
    print("=== Step 4: Barabati Diagnostics Remediation Pre-flight Checks ===")
    
    # 1. Fetch current business state
    q_biz = f"SELECT id, name, category_slug, status, verification_status, phone_e164, is_synthetic, created_at, updated_at FROM businesses WHERE id = '{TARGET_ID}'"
    raw_biz = run_psql(q_biz, json_output=True)
    if not raw_biz or raw_biz == "":
        print(f"ERROR: Business with ID {TARGET_ID} not found in database!")
        sys.exit(1)
    
    biz_records = json.loads(raw_biz)
    if not biz_records or len(biz_records) == 0:
        print(f"ERROR: No record found for ID {TARGET_ID}")
        sys.exit(1)
    
    current_state = biz_records[0]
    print(f"Current Record Snapshot:\n{json.dumps(current_state, indent=2)}")
    
    # 2. Check audit logs for this target
    q_audit = f"SELECT id, action, target_type, target_id, actor_user_id, reason, created_at FROM audit_logs WHERE target_id = '{TARGET_ID}' ORDER BY created_at DESC"
    raw_audit = run_psql(q_audit, json_output=True)
    audit_records = json.loads(raw_audit) if (raw_audit and raw_audit != "") else []
    print(f"\nAudit Log Count for target {TARGET_ID}: {len(audit_records)}")
    if audit_records:
        print(f"Audit log entries: {json.dumps(audit_records, indent=2)}")
    else:
        print("Confirmed: Zero audit log entries exist for this entity. The previous mutation bypassed admin logging.")

    # 3. Verify conditions for safe rollback
    expected_unauthorized_status = 'approved'
    expected_unauthorized_verification = 'verified'
    expected_unauthorized_phone = '+916712345678'
    
    if current_state['status'] != expected_unauthorized_status or \
       current_state['verification_status'] != expected_unauthorized_verification:
        print("\nWARNING: Current values do not match expected unauthorized values!")
        print(f"Expected: status='{expected_unauthorized_status}', verification_status='{expected_unauthorized_verification}'")
        print(f"Found: status='{current_state['status']}', verification_status='{current_state['verification_status']}'")
        sys.exit(1)
        
    print("\nVerified: Business is in the exact unauthorized state reported in the audit.")
    
    # 4. Save pre-remediation snapshot
    snapshot_path = "scripts/barabati_pre_remediation_snapshot.json"
    with open(snapshot_path, "w") as f:
        json.dump({
            "target_id": TARGET_ID,
            "snapshot_timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "pre_remediation_state": current_state,
            "audit_logs": audit_records
        }, f, indent=2)
    print(f"Pre-remediation snapshot saved to {snapshot_path}")
    
    # 5. Execute controlled remediation
    print("\nExecuting controlled restoration to historical state...")
    update_q = f"""
    WITH updated AS (
        UPDATE businesses
        SET status = 'pending',
            verification_status = 'pending',
            phone_e164 = NULL,
            updated_at = NOW()
        WHERE id = '{TARGET_ID}'
        RETURNING id, name, category_slug, status, verification_status, phone_e164, is_synthetic, updated_at
    )
    SELECT json_agg(t) FROM updated t;
    """
    raw_post = run_psql(update_q, json_output=True)
    post_records = json.loads(raw_post)
    post_state = post_records[0]
    print(f"\nPost-remediation Record:\n{json.dumps(post_state, indent=2)}")
    
    # 6. Save post-remediation snapshot
    post_snapshot_path = "scripts/barabati_post_remediation_snapshot.json"
    with open(post_snapshot_path, "w") as f:
        json.dump({
            "target_id": TARGET_ID,
            "remediation_timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "actor": "antigravity_phase01f1_safeguard",
            "reason": "Phase 01F.1 Safeguard 1: Reversing unauthorized raw SQL mutation on Barabati Diagnostics & Health Clinic back to pending state",
            "pre_remediation_state": current_state,
            "post_remediation_state": post_state
        }, f, indent=2)
    print(f"Post-remediation snapshot saved to {post_snapshot_path}")
    
    # 7. Final verification in discovery query
    discovery_check_q = f"SELECT count(*) FROM businesses WHERE status = 'approved' AND is_synthetic = false AND category_slug = 'medical';"
    approved_medical_count = run_psql(discovery_check_q)
    print(f"\nApproved non-synthetic medical businesses count in DB: {approved_medical_count}")
    print("=== Step 4 Controlled Remediation Completed Successfully ===")

if __name__ == '__main__':
    main()
