'use client';

import { useCallback, useEffect, useState } from 'react';
import { AlertCircle, Bike, RefreshCw, Truck } from 'lucide-react';
import { api } from '@/lib/api';

type DispatchJob = {
  id: string; order_id: string; customer_user_id: string; reference_code: string; business_name: string;
  locality: string; district: string; delivery_state: string; execution_state: string; fulfillment_status: string;
  active_offer_id?: string | null; offered_rider_name?: string | null;
  offer_expires_at?: string | null; assigned_rider_name?: string | null;
};
type EligibleRider = { user_id: string; display_name: string; vehicle_type: string; locality: string };
type DispatchEvent = { id:string; event_type:string; actor_name:string; reason?:string|null; created_at:string };
type DeliveryException = { id: string; job_id: string; exception_type: string; reason: string; reference_code: string; execution_state: string; business_name: string; locality: string; created_at: string; assignment_id: string };
type RecoveryCase = { id:string; job_id:string; order_id:string; reference_code:string; assignment_id:string|null; rider_user_id:string|null; rider_name:string; incident_type:string; state:string; reason:string; opened_at:string; locality:string; district:string; execution_state:string; order_status:string; assignment_active:boolean; custody_transferred:boolean; partner_confirmed_no_handover:boolean; inventory_disposition:string; return_received_at:string|null; return_finalized_at:string|null; business_name:string };
type RecoveryEvent = { id:string; actor_type:string; actor_name:string; event_type:string; reason:string; created_at:string };
type OperationsAlert = { id:string; alert_type:string; severity:string; occurred_at:string; age_seconds:number; job_id:string; order_id:string; reference_code:string; locality:string; district:string; partner:string; assignment_id:string; custody_active:boolean; condition_state:string; recommended_action:string };

export function DispatchBoardView() {
  const [jobs, setJobs] = useState<DispatchJob[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [disabled, setDisabled] = useState(false);
  const [reason, setReason] = useState<Record<string, string>>({});
  const [riders, setRiders] = useState<Record<string, EligibleRider[]>>({});
  const [selected, setSelected] = useState<Record<string, string>>({});
  const [history, setHistory] = useState<Record<string, DispatchEvent[]>>({});
  const [executionHistory, setExecutionHistory] = useState<Record<string, DispatchEvent[]>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [exceptions, setExceptions] = useState<DeliveryException[]>([]);
  const [resolutionReason, setResolutionReason] = useState<Record<string, string>>({});
  const [exceptionAction, setExceptionAction] = useState<{ item: DeliveryException; action: 'require_return' | 'cancel_before_pickup'; idempotencyKey: string } | null>(null);
  const [exceptionConfirmText, setExceptionConfirmText] = useState('');
  const [search, setSearch] = useState('');
  const [confirmation, setConfirmation] = useState<{ job: DispatchJob; action: 'retry' | 'assign' } | null>(null);
  const [confirmationText, setConfirmationText] = useState('');
  const [recoveryCases, setRecoveryCases] = useState<RecoveryCase[]>([]);
  const [recoveryError, setRecoveryError] = useState<string | null>(null);
  const [recoveryEvents, setRecoveryEvents] = useState<Record<string, RecoveryEvent[]>>({});
  const [recoveryAction, setRecoveryAction] = useState<{ item: RecoveryCase; action: 'release_and_reassign_before_pickup'|'cancel_before_pickup'|'finalize_return'; idempotencyKey: string } | null>(null);
  const [recoveryReason, setRecoveryReason] = useState('');
  const [recoveryConfirmText, setRecoveryConfirmText] = useState('');
  const [alerts, setAlerts] = useState<OperationsAlert[]>([]);
  const [alertsError, setAlertsError] = useState<string | null>(null);
  const [alertSeverity, setAlertSeverity] = useState('all');
  const [alertSearch, setAlertSearch] = useState('');

  function reviewAlert(alert: OperationsAlert) {
    setSearch(alert.reference_code);
    window.setTimeout(() => {
      document.querySelector(`[data-job-id="${alert.job_id}"]`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }, 50);
  }

  const refresh = useCallback(async () => {
    setLoading(true); setError(null); setDisabled(false);
    try {
      const [response, exceptionResponse] = await Promise.all([
        api.get<{ data: DispatchJob[] }>('/admin/delivery-jobs'),
        api.get<{ data: DeliveryException[] }>('/admin/delivery-exceptions'),
      ]);
      setJobs(response.data.data ?? []); setExceptions(exceptionResponse.data.data ?? []);
      try {
        const alertResponse = await api.get<{ data: OperationsAlert[] }>('/admin/delivery-operations/alerts');
        setAlerts(alertResponse.data.data ?? []); setAlertsError(null);
      } catch { setAlertsError('Operational alerts could not be loaded. Verify delivery_operator access and retry.'); }
      try {
        const recoveries = await api.get<{ data: RecoveryCase[] }>('/admin/delivery-recovery-cases');
        setRecoveryCases(recoveries.data.data ?? []); setRecoveryError(null);
      } catch { setRecoveryError('Recovery queue could not be loaded. Your account may need the delivery_operator permission.'); }
    }
    catch (e: any) {
      if (e?.response?.status === 503) { setDisabled(true); setJobs([]); }
      else setError('Dispatch records could not be loaded. Retry after checking the Admin API connection.');
    } finally { setLoading(false); }
  }, []);

  async function loadRecoveryEvents(item: RecoveryCase) {
    setBusy(item.id); setRecoveryError(null);
    try {
      const response = await api.get<{data:RecoveryEvent[]}>(`/admin/delivery-recovery-cases/${item.id}/events`);
      setRecoveryEvents(old => ({...old,[item.id]:response.data.data ?? []}));
    } catch { setRecoveryError('Recovery audit history could not be loaded.'); }
    finally { setBusy(null); }
  }

  function openRecoveryAction(item: RecoveryCase, action: 'release_and_reassign_before_pickup'|'cancel_before_pickup'|'finalize_return') {
    setRecoveryAction({item, action, idempotencyKey: crypto.randomUUID()});
    setRecoveryReason(''); setRecoveryConfirmText('');
  }

  async function submitRecoveryAction() {
    if (!recoveryAction || recoveryReason.trim().length < 10 || recoveryReason.trim().length > 500 || recoveryConfirmText.trim().toUpperCase() !== recoveryAction.item.reference_code.toUpperCase()) return;
    const {item, action} = recoveryAction;
    setBusy(item.id); setRecoveryError(null);
    try {
      const headers = {'Idempotency-Key': recoveryAction.idempotencyKey};
      if (action === 'finalize_return') {
        await api.post(`/admin/delivery-jobs/${item.job_id}/return/finalize`, {reason:recoveryReason.trim()}, {headers});
      } else {
        await api.post(`/admin/delivery-jobs/${item.job_id}/recovery`, {action,reason:recoveryReason.trim(),expected_assignment_id:item.assignment_id,expected_execution_state:item.execution_state,partner_confirmed_no_handover:true}, {headers});
      }
      setRecoveryAction(null); setRecoveryReason(''); setRecoveryConfirmText('');
      await refresh();
    } catch (err:any) {
      setRecoveryError(err?.response?.status === 409 ? 'Recovery state changed or custody is active. Refresh the queue and review the latest evidence.' : 'Recovery action was rejected. No successful change was confirmed.');
    } finally { setBusy(null); }
  }
  useEffect(() => { void refresh(); const timer = setInterval(() => void refresh(), 15000); return () => clearInterval(timer); }, [refresh]);

  async function loadRiders(jobId: string) {
    setBusy(jobId);
    try { const response = await api.get<{ data: EligibleRider[] }>(`/admin/delivery-jobs/${jobId}/eligible-riders`); setRiders((old) => ({ ...old, [jobId]: response.data.data ?? [] })); }
    catch { setError('Eligible riders could not be loaded.'); }
    finally { setBusy(null); }
  }
  async function loadHistory(jobId: string) {
    setBusy(jobId);
    try { const response = await api.get<{ data: DispatchEvent[] }>(`/admin/delivery-jobs/${jobId}/events`); setHistory((old) => ({ ...old, [jobId]: response.data.data ?? [] })); }
    catch { setError('Dispatch history could not be loaded.'); }
    finally { setBusy(null); }
  }
  async function loadExecutionHistory(jobId: string) {
    setBusy(jobId);
    try { const response = await api.get<{ data: DispatchEvent[] }>(`/admin/delivery-jobs/${jobId}/execution-events`); setExecutionHistory((old) => ({ ...old, [jobId]: response.data.data ?? [] })); }
    catch { setError('Delivery execution history could not be loaded.'); }
    finally { setBusy(null); }
  }
  function requestConfirmation(job: DispatchJob, action: 'retry' | 'assign') {
    const why = reason[job.id]?.trim() ?? '';
    if (why.length < 10) { setError('Enter an audit reason of at least 10 characters before taking this action.'); return; }
    if (action === 'assign' && !selected[job.id]) { setError('Select an eligible rider first.'); return; }
    setError(null); setConfirmation({ job, action }); setConfirmationText('');
  }
  async function act(job: DispatchJob, action: 'retry' | 'assign' | 'cancel-offer') {
    const key = `${job.id}:${action}`; const why = reason[job.id]?.trim() ?? '';
    if (why.length < 10) { setError('Enter an audit reason of at least 10 characters before taking this action.'); return; }
    setBusy(key); setError(null);
    try {
      if (action === 'retry') await api.post(`/admin/delivery-jobs/${job.id}/retry`, { reason: why });
      if (action === 'assign') {
        const riderId = selected[job.id]; if (!riderId) { setError('Select an eligible rider first.'); return; }
        await api.post(`/admin/delivery-jobs/${job.id}/assign`, { rider_user_id: riderId, reason: why });
      }
      if (action === 'cancel-offer' && job.active_offer_id) await api.post(`/admin/delivery-offers/${job.active_offer_id}/cancel`, { reason: why });
      await refresh();
    } catch { setError('Dispatch action was rejected. Refresh the board and review the current state.'); }
    finally { setBusy(null); }
  }
  async function confirmDispatchAction() {
    if (!confirmation || confirmationText.trim().toUpperCase() !== confirmation.job.reference_code.toUpperCase()) return;
    const { job, action } = confirmation;
    setConfirmation(null); setConfirmationText('');
    await act(job, action);
  }

  function openExceptionAction(item: DeliveryException, action: 'require_return' | 'cancel_before_pickup') {
    setExceptionAction({item, action, idempotencyKey: crypto.randomUUID()});
    setExceptionConfirmText(''); setError(null);
  }

  async function resolveException() {
    if (!exceptionAction) return;
    const {item, action, idempotencyKey} = exceptionAction;
    const reason = resolutionReason[item.id]?.trim() ?? '';
    if (reason.length < 10 || exceptionConfirmText.trim().toUpperCase() !== item.reference_code.toUpperCase()) return;
    setBusy(item.id); setError(null);
    try {
      await api.post(`/admin/delivery-jobs/${item.job_id}/exceptions/${item.id}/resolve`, { action, reason, ...(action === 'require_return' ? {expected_assignment_id: item.assignment_id} : {}) }, {headers: {'Idempotency-Key': idempotencyKey}});
      setResolutionReason((old) => ({ ...old, [item.id]: '' })); setExceptionAction(null); setExceptionConfirmText(''); await refresh();
    } catch (err:any) { setError(err?.response?.status === 409 ? 'Assignment or custody changed. Refresh the board and inspect the latest recovery evidence.' : 'Exception resolution was rejected. No successful change was confirmed.'); }
    finally { setBusy(null); }
  }

  return <section className="space-y-6">
    <header className="flex flex-wrap items-center justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wider text-[#0F766E]">Delivery operations</p><h1 className="mt-1 text-2xl font-bold text-[#172033]">Dispatch board</h1><p className="mt-1 text-sm text-[#667085]">Approved rider offers and delivery assignment exceptions. No GPS or delivery completion controls.</p></div><button onClick={() => void refresh()} className="inline-flex min-h-11 items-center gap-2 rounded-xl border bg-white px-4 text-sm font-semibold"><RefreshCw size={16}/> Refresh</button></header>
    {error && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">{error}</div>}
    {disabled && <div className="rounded-2xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-900"><b>Dispatch is disabled in this environment.</b><p className="mt-1">The API feature gate is off. No delivery jobs are being offered to riders.</p></div>}
    <section className="space-y-3" aria-labelledby="delivery-alerts-title">
      <div className="flex flex-wrap items-end justify-between gap-2"><div><p className="text-xs font-bold uppercase tracking-wider text-rose-700">Needs attention</p><h2 id="delivery-alerts-title" className="mt-1 text-xl font-bold text-[#172033]">Operational alerts</h2><p className="text-sm text-slate-600">Derived from persisted delivery and recovery state. Alerts require review and are never auto-resolved.</p></div><button onClick={() => void refresh()} className="min-h-10 rounded-lg border bg-white px-3 text-sm font-semibold">Refresh alerts</button></div>
      <div className="grid gap-2 sm:grid-cols-[180px_1fr]"><label className="text-xs font-semibold text-slate-600">Severity<select value={alertSeverity} onChange={event=>setAlertSeverity(event.target.value)} className="mt-1 min-h-10 w-full rounded-lg border bg-white px-3 text-sm"><option value="all">All severities</option><option value="critical">Critical</option><option value="high">High</option></select></label><label className="text-xs font-semibold text-slate-600">Find by order, partner or locality<input value={alertSearch} onChange={event=>setAlertSearch(event.target.value)} className="mt-1 min-h-10 w-full rounded-lg border bg-white px-3 text-sm" /></label></div>
      {alertsError && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">{alertsError}</div>}
      {!alertsError && loading && <div className="rounded-xl border bg-white p-4 text-sm text-slate-500">Loading operational alerts…</div>}
      {!alertsError && !loading && alerts.filter(alert=>(alertSeverity==='all'||alert.severity===alertSeverity)&&[alert.reference_code,alert.partner,alert.locality,alert.district,alert.alert_type].some(value=>value.toLowerCase().includes(alertSearch.trim().toLowerCase()))).length === 0 && <div className="rounded-xl border border-dashed bg-white p-5 text-sm text-slate-500">{alerts.length ? 'No alerts match these filters.' : 'No unresolved delivery alerts.'}</div>}
      {!alertsError && alerts.filter(alert=>(alertSeverity==='all'||alert.severity===alertSeverity)&&[alert.reference_code,alert.partner,alert.locality,alert.district,alert.alert_type].some(value=>value.toLowerCase().includes(alertSearch.trim().toLowerCase()))).map((alert) => <article key={alert.id} className={`rounded-xl border bg-white p-4 ${alert.severity === 'critical' ? 'border-rose-300' : 'border-amber-200'}`} data-alert-id={alert.id}>
        <div className="flex flex-wrap justify-between gap-2"><div><p className={`text-xs font-bold uppercase ${alert.severity === 'critical' ? 'text-rose-700' : 'text-amber-800'}`}>{alert.severity} · {alert.alert_type.replaceAll('_',' ')}</p><h3 className="mt-1 font-semibold">{alert.reference_code} · {alert.partner}</h3><p className="text-sm text-slate-600">{alert.locality}, {alert.district} · {alert.condition_state.replaceAll('_',' ')}</p></div><span className="text-sm font-semibold text-slate-700">{Math.floor(alert.age_seconds / 60)} min open</span></div>
        <dl className="mt-3 grid gap-2 rounded-lg bg-slate-50 p-3 text-xs sm:grid-cols-2"><div><dt className="text-slate-500">Order / job</dt><dd className="break-all font-mono">{alert.order_id} · {alert.job_id}</dd></div><div><dt className="text-slate-500">Assignment / custody</dt><dd className="break-all font-mono">{alert.assignment_id || 'None'} · {alert.custody_active ? 'active custody' : 'not transferred'}</dd></div><div className="sm:col-span-2"><dt className="text-slate-500">Recommended review</dt><dd>{alert.recommended_action}</dd></div></dl>
        <button type="button" onClick={() => reviewAlert(alert)} className="mt-3 min-h-10 rounded-lg border border-[#2457D6] bg-white px-3 text-sm font-semibold text-[#2457D6]">Review delivery record</button>
      </article>)}
    </section>
    <section className="space-y-3" aria-labelledby="recovery-queue-title">
      <div><p className="text-xs font-bold uppercase tracking-wider text-amber-700">Audited operations</p><h2 id="recovery-queue-title" className="mt-1 text-xl font-bold text-[#172033]">Delivery recovery queue</h2><p className="text-sm text-slate-600">Lease expiry does not release a rider. Pre-pickup actions require exact partner no-handover evidence; post-pickup custody cannot be reassigned here.</p></div>
      {recoveryError && <div role="alert" className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">{recoveryError}</div>}
      {!recoveryError && recoveryCases.length === 0 && !loading && <div className="rounded-xl border border-dashed bg-white p-6 text-sm text-slate-500">No unresolved delivery recovery cases.</div>}
      {recoveryCases.map(item => <article key={item.id} className="rounded-2xl border border-amber-200 bg-white p-4 shadow-sm" data-recovery-case={item.id}>
        <div className="flex flex-wrap justify-between gap-3"><div><p className="text-xs font-bold uppercase text-amber-800">{item.incident_type.replaceAll('_',' ')} · {item.state}</p><h3 className="mt-1 text-lg font-bold">{item.reference_code} · {item.business_name}</h3><p className="text-sm text-slate-600">{item.locality}, {item.district} · {item.rider_name || 'Rider unavailable'}</p><p className="mt-2 text-sm">{item.reason}</p></div><span className={`h-fit rounded-full px-3 py-1 text-xs font-bold ${item.custody_transferred ? 'bg-rose-100 text-rose-800' : 'bg-blue-50 text-blue-800'}`}>{item.custody_transferred ? 'Custody active / transferred' : 'Before pickup'}</span></div>
        <dl className="mt-3 grid gap-2 rounded-xl bg-slate-50 p-3 text-xs sm:grid-cols-2"><div><dt className="text-slate-500">Order / job</dt><dd className="break-all font-mono">{item.order_id} · {item.job_id}</dd></div><div><dt className="text-slate-500">Execution / order</dt><dd>{item.execution_state} / {item.order_status}</dd></div><div><dt className="text-slate-500">Assignment</dt><dd className="break-all font-mono">{item.assignment_id || 'None'} · {item.assignment_active ? 'active' : 'inactive'}</dd></div><div><dt className="text-slate-500">Partner evidence / return</dt><dd>{item.partner_confirmed_no_handover ? 'No handover confirmed' : 'No handover not confirmed'} · {item.inventory_disposition || 'no return disposition'}</dd></div></dl>
        <button disabled={busy !== null} onClick={() => void loadRecoveryEvents(item)} className="mt-3 min-h-10 rounded-lg border px-3 text-sm font-semibold">View immutable recovery history</button>
        {recoveryEvents[item.id] && <ol className="mt-2 space-y-2 rounded-xl border bg-slate-50 p-3">{recoveryEvents[item.id].map(event => <li key={event.id} className="border-b pb-2 text-xs last:border-0"><b>{event.event_type.replaceAll('_',' ')}</b> · {event.actor_name} ({event.actor_type}) · {new Date(event.created_at).toLocaleString()}{event.reason && <p className="mt-1 text-slate-600">{event.reason}</p>}</li>)}</ol>}
        <div className="mt-3 flex flex-wrap gap-2">
          {!item.custody_transferred && item.assignment_active && item.partner_confirmed_no_handover && item.order_status === 'ready_for_pickup' && <><button disabled={busy!==null} onClick={()=>openRecoveryAction(item,'release_and_reassign_before_pickup')} className="min-h-10 rounded-xl bg-[#2457D6] px-4 text-sm font-semibold text-white">Release and reassign</button><button disabled={busy!==null} onClick={()=>openRecoveryAction(item,'cancel_before_pickup')} className="min-h-10 rounded-xl border border-rose-300 px-4 text-sm font-semibold text-rose-700">Cancel before pickup</button></>}
          {item.incident_type==='return_disposition_pending' && item.inventory_disposition && item.inventory_disposition!=='pending' && !item.return_finalized_at && <button disabled={busy!==null} onClick={()=>openRecoveryAction(item,'finalize_return')} className="min-h-10 rounded-xl bg-teal-700 px-4 text-sm font-semibold text-white">Finalize inspected return</button>}
          {!item.custody_transferred && item.assignment_active && !item.partner_confirmed_no_handover && <p className="text-sm font-medium text-amber-800">Waiting for the assigned partner to confirm that goods were not handed over.</p>}
          {item.custody_transferred && <p className="text-sm font-semibold text-rose-800">Custody has transferred. Reassignment and pre-pickup cancellation are blocked.</p>}
        </div>
      </article>)}
    </section>
    {loading && <div className="rounded-2xl border bg-white p-8 text-sm text-slate-500">Loading delivery jobs…</div>}
    {!loading && !disabled && <section className="space-y-3"><div><h2 className="text-lg font-bold text-[#172033]">Delivery exceptions</h2><p className="text-sm text-slate-500">Review rider-reported issues. Resolutions require an audit reason and exact order confirmation.</p></div>{exceptions.length === 0 ? <div className="rounded-xl border bg-white p-4 text-sm text-slate-500">No open delivery exceptions.</div> : exceptions.map((item) => <article key={item.id} className="rounded-2xl border border-amber-200 bg-amber-50/50 p-4"><div className="flex flex-wrap justify-between gap-2"><div><p className="font-semibold">{item.exception_type.replaceAll('_',' ')} · {item.reference_code}</p><p className="text-sm text-slate-600">{item.business_name} · {item.locality} · {item.execution_state.replaceAll('_',' ')}</p><p className="mt-2 text-sm">{item.reason}</p><p className="mt-2 break-all font-mono text-xs text-slate-500">Assignment · {item.assignment_id || 'No active assignment'}</p></div><time className="text-xs text-slate-500">{new Date(item.created_at).toLocaleString()}</time></div><div className="mt-2 flex flex-wrap gap-2">{['customer_unreachable','delivery_failed','return_required','rider_unable_to_continue'].includes(item.exception_type) && item.assignment_id && <button disabled={busy !== null} onClick={() => openExceptionAction(item,'require_return')} className="min-h-10 rounded-xl bg-[#2457D6] px-4 text-sm font-semibold text-white">Require return</button>}{item.exception_type === 'pickup_failed' && <button disabled={busy !== null} onClick={() => openExceptionAction(item,'cancel_before_pickup')} className="min-h-10 rounded-xl border border-rose-300 bg-white px-4 text-sm font-semibold text-rose-700">Cancel before pickup</button>}</div></article>)}</section>}
    {!loading && !disabled && jobs.length === 0 && <div className="rounded-2xl border bg-white p-10 text-center"><Truck className="mx-auto text-slate-400"/><p className="mt-3 font-semibold">No delivery jobs</p><p className="mt-1 text-sm text-slate-500">Jobs appear after an eligible platform order enters preparation.</p></div>}
    {!loading && !disabled && jobs.length > 0 && <label className="block max-w-2xl text-sm font-semibold text-slate-700">Find an exact order or delivery job
      <input value={search} onChange={(event) => setSearch(event.target.value)} className="mt-1 min-h-11 w-full rounded-xl border border-slate-300 bg-white px-3 font-normal" placeholder="Order number, order UUID, job UUID, customer ID, partner or locality" />
    </label>}
    {!loading && jobs.filter((job) => [job.reference_code, job.order_id, job.id, job.customer_user_id, job.business_name, job.locality, job.district].some((value) => value.toLowerCase().includes(search.trim().toLowerCase()))).length === 0 && <div className="rounded-2xl border bg-white p-8 text-center text-sm text-slate-500">No delivery jobs match that order, job, customer, partner or locality.</div>}
    {!loading && jobs.filter((job) => [job.reference_code, job.order_id, job.id, job.customer_user_id, job.business_name, job.locality, job.district].some((value) => value.toLowerCase().includes(search.trim().toLowerCase()))).map((job) => <article key={job.id} className="rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-sm" data-order-id={job.order_id} data-job-id={job.id}><div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-wide text-slate-500">{job.reference_code}</p><h2 className="mt-1 text-lg font-bold text-[#172033]">{job.business_name}</h2><p className="text-sm text-slate-600">Destination · {job.locality}, {job.district}</p><p className="mt-1 break-all text-xs text-slate-500">Order ID · {job.order_id}</p><p className="break-all text-xs text-slate-500">Customer ID · {job.customer_user_id}</p><p className="break-all text-xs text-slate-500">Delivery job ID · {job.id}</p></div><div className="space-y-1 text-right"><span className="block rounded-full bg-blue-50 px-3 py-1 text-xs font-bold capitalize text-blue-800">Dispatch · {job.delivery_state.replaceAll('_',' ')}</span><span className="block rounded-full bg-teal-50 px-3 py-1 text-xs font-bold capitalize text-teal-800">Execution · {job.execution_state?.replaceAll('_',' ') ?? 'assigned'}</span></div></div>
      <div className="mt-4 grid gap-3 text-sm md:grid-cols-3"><div className="rounded-xl bg-slate-50 p-3"><span className="text-slate-500">Fulfillment</span><p className="mt-1 font-semibold capitalize">{job.fulfillment_status?.replaceAll('_',' ') ?? '—'}</p></div><div className="rounded-xl bg-slate-50 p-3"><span className="text-slate-500">Active offer</span><p className="mt-1 font-semibold">{job.offered_rider_name ?? 'None'}</p></div><div className="rounded-xl bg-slate-50 p-3"><span className="text-slate-500">{job.execution_state === 'delivered' ? 'Delivered by rider' : 'Assigned rider'}</span><p className="mt-1 font-semibold">{job.assigned_rider_name ?? 'Not assigned'}</p></div></div>
      <button disabled={busy !== null} onClick={() => void loadHistory(job.id)} className="mt-3 min-h-9 rounded-lg border px-3 text-xs font-semibold">View dispatch history</button>
      {history[job.id] && <ol className="mt-3 space-y-2 rounded-xl bg-slate-50 p-4">{history[job.id].map((event) => <li key={event.id} className="flex flex-wrap justify-between gap-2 border-b border-slate-200 pb-2 text-xs last:border-0"><span><b className="capitalize">{event.event_type.replaceAll('_',' ')}</b><span className="ml-2 text-slate-500">by {event.actor_name}{event.reason ? ` · ${event.reason}` : ''}</span></span><time className="text-slate-500">{new Date(event.created_at).toLocaleString()}</time></li>)}</ol>}
      <button disabled={busy !== null} onClick={() => void loadExecutionHistory(job.id)} className="ml-2 mt-3 min-h-9 rounded-lg border px-3 text-xs font-semibold">View delivery history</button>
      {executionHistory[job.id] && <ol className="mt-3 space-y-2 rounded-xl border border-teal-100 bg-teal-50/50 p-4">{executionHistory[job.id].map((event) => <li key={event.id} className="flex flex-wrap justify-between gap-2 border-b border-teal-100 pb-2 text-xs last:border-0"><span><b className="capitalize">{event.event_type.replaceAll('_',' ')}</b><span className="ml-2 text-slate-600">by {event.actor_name}{event.reason ? ` · ${event.reason}` : ''}</span></span><time className="text-slate-500">{new Date(event.created_at).toLocaleString()}</time></li>)}</ol>}
      {['pending_dispatch','no_rider_available','offered'].includes(job.delivery_state) && <div className="mt-4 border-t pt-4"><label className="block text-xs font-semibold text-slate-600">Audit reason for Admin override<textarea maxLength={500} rows={2} value={reason[job.id] ?? ''} onChange={(e) => setReason((old) => ({ ...old, [job.id]: e.target.value }))} className="mt-1 w-full rounded-xl border p-3 text-sm" placeholder="Explain the dispatch exception or override (10–500 characters)."/></label>
        <div className="mt-3 flex flex-wrap gap-2">{job.delivery_state === 'no_rider_available' && <button disabled={busy !== null} onClick={() => requestConfirmation(job,'retry')} className="min-h-10 rounded-xl bg-[#2457D6] px-4 text-sm font-semibold text-white">Retry dispatch</button>}{job.delivery_state === 'offered' && <button disabled={busy !== null} onClick={() => void act(job,'cancel-offer')} className="min-h-10 rounded-xl border px-4 text-sm font-semibold">Cancel active offer</button>}<button disabled={busy !== null} onClick={() => void loadRiders(job.id)} className="inline-flex min-h-10 items-center gap-2 rounded-xl border px-4 text-sm font-semibold"><Bike size={16}/> Find eligible rider</button></div>
        {riders[job.id] && <div className="mt-3 flex flex-wrap items-center gap-2"><select aria-label={`Eligible rider for ${job.reference_code}`} value={selected[job.id] ?? ''} onChange={(e) => setSelected((old) => ({ ...old, [job.id]: e.target.value }))} className="min-h-10 rounded-xl border px-3 text-sm"><option value="">Select an available rider</option>{riders[job.id].map((rider) => <option key={rider.user_id} value={rider.user_id}>{rider.display_name} · {rider.vehicle_type.replaceAll('_',' ')}</option>)}</select><button disabled={busy !== null || !selected[job.id]} onClick={() => requestConfirmation(job,'assign')} className="min-h-10 rounded-xl bg-emerald-700 px-4 text-sm font-semibold text-white">Assign with audit</button>{riders[job.id].length === 0 && <span className="inline-flex items-center gap-1 text-sm text-amber-800"><AlertCircle size={15}/> No eligible riders online</span>}</div>}
      </div>}
    </article>)}
    {confirmation && <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/50 p-4" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) { setConfirmation(null); setConfirmationText(''); } }}>
      <section role="alertdialog" aria-modal="true" aria-labelledby="dispatch-confirm-title" className="max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-2xl bg-white p-6 shadow-2xl">
        <p className="text-xs font-bold uppercase tracking-wider text-amber-700">Confirm exact dispatch target</p>
        <h2 id="dispatch-confirm-title" className="mt-1 text-xl font-bold text-slate-900">{confirmation.action === 'retry' ? 'Retry dispatch?' : 'Assign rider?'}</h2>
        <p className="mt-2 text-sm text-slate-600">Verify every identifier before continuing. This action will use this delivery job ID.</p>
        <dl className="mt-4 grid gap-2 rounded-xl bg-slate-50 p-4 text-sm sm:grid-cols-[140px_1fr]">
          <dt className="font-semibold text-slate-600">Order number</dt><dd className="font-bold">{confirmation.job.reference_code}</dd>
          <dt className="font-semibold text-slate-600">Order UUID</dt><dd className="break-all font-mono text-xs">{confirmation.job.order_id}</dd>
          <dt className="font-semibold text-slate-600">Customer ID</dt><dd className="break-all font-mono text-xs">{confirmation.job.customer_user_id}</dd>
          <dt className="font-semibold text-slate-600">Delivery job UUID</dt><dd className="break-all font-mono text-xs">{confirmation.job.id}</dd>
          <dt className="font-semibold text-slate-600">Partner</dt><dd>{confirmation.job.business_name}</dd>
          <dt className="font-semibold text-slate-600">Destination</dt><dd>{confirmation.job.locality}, {confirmation.job.district}</dd>
          <dt className="font-semibold text-slate-600">Fulfillment</dt><dd>{confirmation.job.fulfillment_status}</dd>
          <dt className="font-semibold text-slate-600">Dispatch / execution</dt><dd>{confirmation.job.delivery_state} / {confirmation.job.execution_state}</dd>
          {confirmation.action === 'assign' && <><dt className="font-semibold text-slate-600">Selected rider</dt><dd>{(() => { const rider = riders[confirmation.job.id]?.find((candidate) => candidate.user_id === selected[confirmation.job.id]); return rider ? <><span>{rider.display_name}</span><span className="mt-1 block break-all font-mono text-xs text-slate-500">{rider.user_id}</span></> : 'No rider selected'; })()}</dd></>}
        </dl>
        <label className="mt-4 block text-sm font-semibold text-slate-700">Type <span className="font-mono">{confirmation.job.reference_code}</span> to confirm
          <input autoFocus value={confirmationText} onChange={(event) => setConfirmationText(event.target.value)} className="mt-1 min-h-11 w-full rounded-xl border border-slate-300 px-3 font-normal" autoComplete="off" />
        </label>
        <div className="mt-5 flex justify-end gap-2"><button onClick={() => { setConfirmation(null); setConfirmationText(''); }} className="min-h-11 rounded-xl border px-4 text-sm font-semibold">Cancel</button><button disabled={confirmationText.trim().toUpperCase() !== confirmation.job.reference_code.toUpperCase() || busy !== null} onClick={() => void confirmDispatchAction()} className="min-h-11 rounded-xl bg-[#2457D6] px-4 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50">Confirm exact target</button></div>
      </section>
    </div>}
    {recoveryAction && <div className="fixed inset-0 z-[70] grid place-items-center bg-slate-950/60 p-4"><section role="alertdialog" aria-modal="true" aria-labelledby="recovery-confirm-title" className="max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-2xl bg-white p-6 shadow-2xl"><p className="text-xs font-bold uppercase tracking-wider text-amber-700">Confirm audited recovery</p><h2 id="recovery-confirm-title" className="mt-1 text-xl font-bold">{recoveryAction.action.replaceAll('_',' ')}</h2><p className="mt-2 text-sm text-slate-600">This action is scoped to the exact order below. Server-side custody and partner evidence checks remain authoritative.</p><dl className="mt-4 grid gap-2 rounded-xl bg-slate-50 p-4 text-sm sm:grid-cols-[130px_1fr]"><dt>Order reference</dt><dd className="font-bold">{recoveryAction.item.reference_code}</dd><dt>Order UUID</dt><dd className="break-all font-mono text-xs">{recoveryAction.item.order_id}</dd><dt>Delivery job</dt><dd className="break-all font-mono text-xs">{recoveryAction.item.job_id}</dd><dt>Assignment</dt><dd className="break-all font-mono text-xs">{recoveryAction.item.assignment_id}</dd><dt>Current state</dt><dd>{recoveryAction.item.execution_state} · {recoveryAction.item.custody_transferred ? 'custody active' : 'pre-pickup'}</dd></dl><label className="mt-4 block text-sm font-semibold">Audit reason (10–500 characters)<textarea maxLength={500} rows={3} value={recoveryReason} onChange={event=>setRecoveryReason(event.target.value)} className="mt-1 w-full rounded-xl border p-3 font-normal" /></label><label className="mt-3 block text-sm font-semibold">Type {recoveryAction.item.reference_code} to confirm<input autoFocus value={recoveryConfirmText} onChange={event=>setRecoveryConfirmText(event.target.value)} className="mt-1 min-h-11 w-full rounded-xl border px-3 font-normal" autoComplete="off" /></label><div className="mt-5 flex justify-end gap-2"><button onClick={()=>setRecoveryAction(null)} className="min-h-11 rounded-xl border px-4">Cancel</button><button disabled={busy!==null||recoveryReason.trim().length<10||recoveryConfirmText.trim().toUpperCase()!==recoveryAction.item.reference_code.toUpperCase()} onClick={()=>void submitRecoveryAction()} className="min-h-11 rounded-xl bg-[#2457D6] px-4 font-semibold text-white disabled:opacity-50">Confirm recovery</button></div></section></div>}
    {exceptionAction && <div className="fixed inset-0 z-[80] grid place-items-center bg-slate-950/60 p-4"><section role="alertdialog" aria-modal="true" aria-labelledby="exception-confirm-title" className="w-full max-w-xl rounded-2xl bg-white p-6 shadow-2xl"><p className="text-xs font-bold uppercase tracking-wider text-amber-700">Confirm audited delivery action</p><h2 id="exception-confirm-title" className="mt-1 text-xl font-bold">{exceptionAction.action.replaceAll('_',' ')}</h2><p className="mt-2 text-sm text-slate-600">The rider remains responsible for physical custody until the partner records receipt. This action does not return goods or change inventory.</p><dl className="mt-4 grid gap-2 rounded-xl bg-slate-50 p-4 text-sm sm:grid-cols-[130px_1fr]"><dt>Order reference</dt><dd className="font-bold">{exceptionAction.item.reference_code}</dd><dt>Delivery job</dt><dd className="break-all font-mono text-xs">{exceptionAction.item.job_id}</dd><dt>Rider assignment</dt><dd className="break-all font-mono text-xs">{exceptionAction.item.assignment_id || 'No active assignment'}</dd><dt>Current delivery state</dt><dd>{exceptionAction.item.execution_state}</dd><dt>Recovery report</dt><dd>{exceptionAction.item.exception_type.replaceAll('_',' ')}</dd></dl><label className="mt-4 block text-sm font-semibold">Audit reason (10–500 characters)<textarea maxLength={500} rows={3} value={resolutionReason[exceptionAction.item.id] ?? ''} onChange={event=>setResolutionReason(old=>({...old,[exceptionAction.item.id]:event.target.value}))} className="mt-1 w-full rounded-xl border p-3 font-normal" /></label><label className="mt-3 block text-sm font-semibold">Type {exceptionAction.item.reference_code} to confirm<input autoFocus value={exceptionConfirmText} onChange={event=>setExceptionConfirmText(event.target.value)} className="mt-1 min-h-11 w-full rounded-xl border px-3 font-normal" autoComplete="off" /></label><div className="mt-5 flex justify-end gap-2"><button onClick={()=>setExceptionAction(null)} className="min-h-11 rounded-xl border px-4">Cancel</button><button disabled={busy!==null||(resolutionReason[exceptionAction.item.id]?.trim().length ?? 0)<10||exceptionConfirmText.trim().toUpperCase()!==exceptionAction.item.reference_code.toUpperCase()} onClick={()=>void resolveException()} className="min-h-11 rounded-xl bg-[#2457D6] px-4 font-semibold text-white disabled:opacity-50">Confirm action</button></div></section></div>}
  </section>;
}
