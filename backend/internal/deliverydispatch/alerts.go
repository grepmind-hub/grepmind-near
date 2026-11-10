package deliverydispatch

import (
	"net/http"
)

// AdminOperationsAlerts reports persisted delivery conditions that need human
// review. It is intentionally read-only: loading the dashboard never mutates
// dispatch, custody, inventory, or financial state.
func (s *Service) AdminOperationsAlerts(w http.ResponseWriter, r *http.Request, _ string) {
	if !s.requireEnabled(w) {
		return
	}
	rows, err := queryMaps(r.Context(), s.db, `
		WITH alerts AS (
			SELECT 'recovery:'||c.id::text id, c.incident_type alert_type,
				CASE WHEN c.state='escalated' OR c.incident_type='assignment_heartbeat_stale' THEN 'critical' ELSE 'high' END severity,
				c.opened_at occurred_at, j.id::text job_id, o.id::text order_id, o.reference_code,
				l.name locality, d.name district, b.name partner,
				COALESCE(c.assignment_id::text,'') assignment_id,
				(j.execution_state IN ('picked_up','en_route','customer_unreachable','delivery_failed','return_required','return_in_progress')) custody_active,
				c.state condition_state,
				CASE WHEN c.incident_type='assignment_heartbeat_stale' THEN 'Investigate rider lease; assignment retained' ELSE 'Review recovery case' END recommended_action
			FROM delivery_recovery_cases c
			JOIN delivery_jobs j ON j.id=c.job_id JOIN customer_orders o ON o.id=c.order_id
			JOIN businesses b ON b.id=j.business_id JOIN platform_delivery_localities l ON l.id=j.locality_id
			JOIN platform_districts d ON d.id=l.district_id
			WHERE c.state IN ('open','investigating','action_pending','escalated')
			UNION ALL
			SELECT 'exception:'||e.id::text, e.exception_type,
				CASE WHEN e.exception_type IN ('delivery_failed','return_required') THEN 'critical' ELSE 'high' END,
				e.created_at, j.id::text, o.id::text, o.reference_code, l.name, d.name, b.name,
				COALESCE(a.id::text,''),
				(j.execution_state IN ('picked_up','en_route','customer_unreachable','delivery_failed','return_required','return_in_progress')),
				e.state, 'Review delivery exception'
			FROM delivery_exceptions e JOIN delivery_jobs j ON j.id=e.job_id
			JOIN customer_orders o ON o.id=j.order_id JOIN businesses b ON b.id=j.business_id
			JOIN platform_delivery_localities l ON l.id=j.locality_id JOIN platform_districts d ON d.id=l.district_id
			LEFT JOIN LATERAL (SELECT id FROM delivery_assignments WHERE job_id=j.id ORDER BY assigned_at DESC LIMIT 1) a ON true
			WHERE e.state='open'
			UNION ALL
			SELECT 'stale-assignment:'||a.id::text, 'assignment_heartbeat_stale', 'critical',
				COALESCE(rs.lease_expires_at,a.assigned_at), j.id::text, o.id::text, o.reference_code,
				l.name,d.name,b.name,a.id::text,true,'open','Investigate rider lease; assignment retained'
			FROM delivery_assignments a JOIN delivery_jobs j ON j.id=a.job_id JOIN customer_orders o ON o.id=j.order_id
			JOIN businesses b ON b.id=j.business_id JOIN platform_delivery_localities l ON l.id=j.locality_id
			JOIN platform_districts d ON d.id=l.district_id
			LEFT JOIN rider_availability_sessions rs ON rs.rider_user_id=a.rider_user_id
			WHERE a.state='active' AND (rs.rider_user_id IS NULL OR NOT rs.is_online OR rs.lease_expires_at<=now())
			AND NOT EXISTS (SELECT 1 FROM delivery_recovery_cases c WHERE c.job_id=j.id AND c.assignment_id=a.id AND c.incident_type='assignment_heartbeat_stale' AND c.state IN ('open','investigating','action_pending','escalated'))
			UNION ALL
			SELECT 'return:'||rr.job_id::text, 'return_disposition_pending', 'high', rr.received_at,
				j.id::text,o.id::text,o.reference_code,l.name,d.name,b.name,'',true,'open',
				'Record return disposition and finalize case'
			FROM delivery_return_receipts rr JOIN delivery_jobs j ON j.id=rr.job_id JOIN customer_orders o ON o.id=rr.order_id
			JOIN businesses b ON b.id=j.business_id JOIN platform_delivery_localities l ON l.id=j.locality_id
			JOIN platform_districts d ON d.id=l.district_id
			WHERE rr.inventory_disposition='pending' OR rr.finalized_at IS NULL
			UNION ALL
			SELECT 'dispatch-exhausted:'||j.id::text, 'dispatch_exhausted', 'high', j.updated_at,
				j.id::text,o.id::text,o.reference_code,l.name,d.name,b.name,'',false,
				j.state,'Review failed dispatch and eligible rider coverage'
			FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN businesses b ON b.id=j.business_id
			JOIN platform_delivery_localities l ON l.id=j.locality_id JOIN platform_districts d ON d.id=l.district_id
			WHERE j.state='no_rider_available'
			UNION ALL
			SELECT 'stalled:'||j.id::text, 'delivery_stalled', 'high', j.updated_at, j.id::text,o.id::text,
				o.reference_code,l.name,d.name,b.name,COALESCE(a.id::text,''),
				(j.execution_state IN ('picked_up','en_route','customer_unreachable','delivery_failed','return_required','return_in_progress')),
				j.execution_state,'Review stale delivery state'
			FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN businesses b ON b.id=j.business_id
			JOIN platform_delivery_localities l ON l.id=j.locality_id JOIN platform_districts d ON d.id=l.district_id
			LEFT JOIN LATERAL (SELECT id FROM delivery_assignments WHERE job_id=j.id ORDER BY assigned_at DESC LIMIT 1) a ON true
			WHERE j.execution_state IN ('assigned','arriving_at_pickup','at_pickup','picked_up','en_route','return_required','return_in_progress')
			AND j.updated_at < now()-interval '30 minutes'
			UNION ALL
			SELECT 'earnings:'||j.id::text, 'earnings_reconciliation', 'high', j.updated_at,
				j.id::text,o.id::text,o.reference_code,l.name,d.name,b.name,'',false,
				'exception','Review rider earnings reconciliation'
			FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN businesses b ON b.id=j.business_id
			JOIN platform_delivery_localities l ON l.id=j.locality_id JOIN platform_districts d ON d.id=l.district_id
			LEFT JOIN rider_earning_entries e ON e.delivery_job_id=j.id AND e.entry_type IN ('delivery_earning','unpriced')
			LEFT JOIN rider_compensation_policies p ON p.id=e.policy_id
			WHERE (j.execution_state='delivered' AND e.id IS NULL)
			OR (e.id IS NOT NULL AND (j.execution_state<>'delivered'
				OR e.rider_user_id IS DISTINCT FROM (SELECT a.rider_user_id FROM delivery_assignments a WHERE a.job_id=j.id ORDER BY a.assigned_at DESC LIMIT 1)
				OR (e.entry_type='delivery_earning' AND (e.policy_id IS NULL OR e.policy_version IS DISTINCT FROM p.version OR e.amount_minor IS DISTINCT FROM e.rate_snapshot_minor OR e.rate_snapshot_minor IS DISTINCT FROM p.fixed_amount_minor OR e.currency IS DISTINCT FROM p.currency))))
		)
		SELECT id,alert_type,severity,occurred_at::text occurred_at,
			GREATEST(0,floor(extract(epoch FROM (now()-occurred_at)))::bigint) age_seconds,
			job_id,order_id,reference_code,locality,district,partner,assignment_id,custody_active,condition_state,recommended_action
		FROM alerts ORDER BY CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 ELSE 2 END,occurred_at ASC LIMIT 300`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load delivery operations alerts.")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"data": rows, "meta": map[string]any{"count": len(rows), "automatic_resolution": false}})
}
