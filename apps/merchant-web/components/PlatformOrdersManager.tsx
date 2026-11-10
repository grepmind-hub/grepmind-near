'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, Check, ChevronDown, ChevronUp, Clock3, Loader2, PackageCheck, RefreshCw, Store, X } from 'lucide-react';
import { confirmMerchantNoHandover, confirmMerchantReturn, fetchMerchantDeliveryDispatch, issueMerchantPickupCode, submitMerchantReturnDisposition, type MerchantDeliveryDispatchSummary, type MerchantPlatformOrder } from '../lib/api';

type Action = 'accept' | 'reject' | 'prepare' | 'ready';

interface Props {
  businessId: string;
  orders: MerchantPlatformOrder[];
  isLoading: boolean;
  error: string | null;
  busyOrderId: string | null;
  onRefresh: () => void;
  onAction: (order: MerchantPlatformOrder, action: Action, reason?: string) => void;
}

const statusLabel: Record<string, string> = {
  placed: 'Awaiting your response',
  accepted: 'Accepted',
  preparing: 'Preparing',
  ready_for_pickup: 'Ready for pickup',
  rejected: 'Rejected',
  cancelled: 'Cancelled by customer',
};

export function PlatformOrdersManager({ businessId, orders, isLoading, error, busyOrderId, onRefresh, onAction }: Props) {
  const [expanded, setExpanded] = useState<string | null>(null);
  const [rejecting, setRejecting] = useState<MerchantPlatformOrder | null>(null);
  const [reason, setReason] = useState('');
  const [dispatch, setDispatch] = useState<Record<string, MerchantDeliveryDispatchSummary>>({});
  const [dispatchError, setDispatchError] = useState<string | null>(null);
  const [dispatchBusy, setDispatchBusy] = useState<string | null>(null);
  const [pickupCode, setPickupCode] = useState<{ orderId: string; code: string; expires: number } | null>(null);
  const [recoveryReason, setRecoveryReason] = useState<Record<string,string>>({});
  const [returnReason, setReturnReason] = useState<Record<string,string>>({});
  const [returnKind, setReturnKind] = useState<Record<string,'restockable'|'not_restockable'>>({});
  const [recoveryKeys, setRecoveryKeys] = useState<Record<string,{fingerprint:string;key:string}>>({});
  const refreshDispatch = useCallback(async () => {
    try {
      const rows = await fetchMerchantDeliveryDispatch(businessId);
      setDispatch(Object.fromEntries(rows.map((row) => [row.order_id, row])));
      setDispatchError(null);
    } catch { setDispatchError('Delivery assignment status is unavailable right now.'); }
  }, [businessId]);
  useEffect(() => { void refreshDispatch(); const timer = window.setInterval(() => void refreshDispatch(), 15000); return () => window.clearInterval(timer); }, [refreshDispatch]);
  const pickupCodeKey = pickupCode?.code;
  useEffect(() => {
    if (!pickupCodeKey) return;
    const timer = window.setInterval(() => setPickupCode((current) => {
      if (!current || current.expires <= 1) return null;
      return { ...current, expires: current.expires - 1 };
    }), 1000);
    return () => window.clearInterval(timer);
  }, [pickupCodeKey]);
  const pending = orders.filter(order => order.status === 'placed').length;

  function idempotencyKey(orderId: string, operation: string, request: unknown) {
    const fingerprint = `${operation}:${JSON.stringify(request)}`;
    const existing = recoveryKeys[orderId];
    if (existing?.fingerprint === fingerprint) return existing.key;
    const key = crypto.randomUUID();
    setRecoveryKeys(old => ({...old,[orderId]:{fingerprint,key}}));
    return key;
  }

  const reject = () => {
    if (!rejecting || reason.trim().length < 10 || reason.trim().length > 500) return;
    onAction(rejecting, 'reject', reason.trim());
    setRejecting(null);
    setReason('');
  };

  async function issuePickup(orderId: string, summary: MerchantDeliveryDispatchSummary) {
    setDispatchBusy(orderId); setDispatchError(null);
    try { const result = await issueMerchantPickupCode(businessId, summary.job_id); setPickupCode({ orderId, code: result.pickup_code, expires: result.expires_in_seconds }); await refreshDispatch(); }
    catch { setDispatchError('Pickup verification could not be issued. Confirm the order is ready and the assigned rider is at the partner.'); }
    finally { setDispatchBusy(null); }
  }

  async function confirmReturn(orderId: string, summary: MerchantDeliveryDispatchSummary) {
    setDispatchBusy(orderId); setDispatchError(null);
    try { await confirmMerchantReturn(businessId, summary.job_id); await refreshDispatch(); }
    catch { setDispatchError('Return handover could not be confirmed. Refresh the dispatch status and retry.'); }
    finally { setDispatchBusy(null); }
  }

  async function confirmNoHandover(orderId: string, summary: MerchantDeliveryDispatchSummary) {
    const reason = recoveryReason[orderId]?.trim() ?? '';
    if (!summary.assignment_id || reason.length < 10 || reason.length > 500) return;
    setDispatchBusy(orderId); setDispatchError(null);
    const request = {assignment_id:summary.assignment_id,reason};
    try { await confirmMerchantNoHandover(businessId, summary.job_id, summary.assignment_id, reason, idempotencyKey(orderId,'no-handover',request)); setRecoveryKeys(old=>{const next={...old};delete next[orderId];return next;}); await refreshDispatch(); }
    catch (error:any) { setDispatchError(error?.status === 409 ? 'The assignment changed. Refresh before recording partner evidence.' : 'No-handover evidence was not accepted. Confirm this is the assigned order and retry.'); }
    finally { setDispatchBusy(null); }
  }

  async function submitDisposition(orderId: string, summary: MerchantDeliveryDispatchSummary) {
    const reason = returnReason[orderId]?.trim() ?? '';
    const kind = returnKind[orderId] ?? 'not_restockable';
    if (reason.length < 10 || reason.length > 500) return;
    setDispatchBusy(orderId); setDispatchError(null);
    const request = {inventory_disposition:kind,reason};
    try { await submitMerchantReturnDisposition(businessId, summary.job_id, kind, reason, idempotencyKey(orderId,'return-disposition',request)); setRecoveryKeys(old=>{const next={...old};delete next[orderId];return next;}); await refreshDispatch(); }
    catch (error:any) { setDispatchError(error?.status === 409 ? 'Return disposition has changed. Refresh the order before retrying.' : 'Inventory inspection was not recorded. No stock change was confirmed.'); }
    finally { setDispatchBusy(null); }
  }

  return <section className="space-y-5" aria-labelledby="platform-orders-title">
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div>
        <p className="text-xs font-semibold uppercase tracking-[.14em] text-primary">Grepmind commerce</p>
        <h2 id="platform-orders-title" className="mt-1 text-xl font-bold">Assigned orders</h2>
        <p className="mt-1 text-sm text-slateText-secondary">Prepare orders assigned to this business. Grepmind controls customer prices and checkout.</p>
      </div>
      <button onClick={onRefresh} disabled={isLoading} className="inline-flex min-h-10 items-center gap-2 rounded-xl border border-borderMuted bg-white px-3 text-sm font-semibold text-primary disabled:opacity-60">
        {isLoading ? <Loader2 size={16} className="animate-spin"/> : <RefreshCw size={16}/>} Refresh
      </button>
    </div>

    <div className="grid gap-3 sm:grid-cols-3">
      <Metric label="New orders" value={pending} tone="blue"/>
      <Metric label="In preparation" value={orders.filter(order => order.status === 'accepted' || order.status === 'preparing').length} tone="amber"/>
      <Metric label="Ready for pickup" value={orders.filter(order => order.status === 'ready_for_pickup').length} tone="teal"/>
    </div>

    {error && <div role="alert" className="flex items-start gap-2 rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800"><AlertTriangle size={18} className="mt-0.5 shrink-0"/>{error}</div>}
    {dispatchError && <div role="status" className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">{dispatchError}</div>}
    {isLoading && orders.length === 0 ? <div className="grid min-h-48 place-items-center rounded-2xl border border-borderMuted bg-white text-sm text-slateText-secondary"><Loader2 className="animate-spin text-primary"/></div> : null}
    {!isLoading && !error && orders.length === 0 && <div className="rounded-2xl border border-dashed border-borderMuted bg-white p-10 text-center"><Store className="mx-auto text-primary"/><h3 className="mt-3 font-semibold">No assigned platform orders</h3><p className="mt-1 text-sm text-slateText-secondary">New orders will appear here when Grepmind selects this business for fulfillment.</p></div>}

    <div className="space-y-3">
      {orders.map(order => {
        const open = expanded === order.id;
        const busy = busyOrderId === order.id;
        return <article key={order.id} className="overflow-hidden rounded-2xl border border-borderMuted bg-white shadow-card">
          <button className="flex min-h-20 w-full items-center gap-3 p-4 text-left" aria-expanded={open} onClick={() => setExpanded(open ? null : order.id)}>
            <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-blue-50 text-primary"><PackageCheck size={21}/></span>
            <span className="min-w-0 flex-1">
              <span className="flex flex-wrap items-center gap-2 font-semibold text-slateText-main">{order.vertical === 'food' ? 'Food order' : 'Grocery order'} <StatusPill status={order.status}/></span>
              <span className="mt-1 block truncate text-xs text-slateText-secondary">{order.reference_code} · {order.delivery_locality}, {order.delivery_district}</span>
              <span className="mt-1 block text-xs text-slateText-muted">{new Date(order.created_at).toLocaleString()} · {order.items.length} line item{order.items.length === 1 ? '' : 's'}</span>
              {dispatch[order.id] && <span className="mt-1 block text-xs font-semibold text-teal-800">Delivery dispatch · {dispatch[order.id].dispatch_status.replaceAll('_',' ')}{dispatch[order.id].rider_assigned ? ' · rider assigned' : ''}</span>}
              {dispatch[order.id] && <span className="mt-1 block text-xs text-slateText-secondary">Execution · {dispatch[order.id].execution_state.replaceAll('_',' ')}{dispatch[order.id].rider_name ? ` · ${dispatch[order.id].rider_name}` : ''}</span>}
            </span>
            {open ? <ChevronUp size={18}/> : <ChevronDown size={18}/>}
          </button>

          {open && <div className="border-t border-borderMuted bg-slate-50/70 p-4 sm:p-5">
            <div className="grid gap-4 lg:grid-cols-[1fr_auto]">
              <div className="space-y-4">
                <div>
                  <h3 className="text-sm font-semibold">Items to prepare</h3>
                  <ul className="mt-2 divide-y divide-borderMuted rounded-xl border border-borderMuted bg-white px-3">
                    {order.items.map((item, index) => <li key={`${item.product_name}-${index}`} className="flex items-center justify-between gap-3 py-3 text-sm"><span>{item.product_name}<span className="block text-xs text-slateText-secondary">{item.variant_name} · {item.unit_label}</span></span><span className="rounded-lg bg-blue-50 px-2.5 py-1 font-bold text-primary">× {item.quantity}</span></li>)}
                  </ul>
                </div>
                {order.special_instructions && <div className="rounded-xl border border-amber-200 bg-amber-50 p-3"><p className="text-xs font-bold uppercase tracking-wide text-amber-800">Customer instructions</p><p className="mt-1 whitespace-pre-wrap text-sm text-amber-950">{order.special_instructions}</p></div>}
                {dispatch[order.id] && <div className="rounded-xl border border-teal-100 bg-teal-50/60 p-3"><p className="text-xs font-bold uppercase tracking-wide text-teal-900">Delivery progress</p><p className="mt-1 text-sm text-teal-950">{dispatch[order.id].execution_state.replaceAll('_',' ')}{dispatch[order.id].rider_name ? ` · ${dispatch[order.id].rider_name}` : ''}</p><div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slateText-secondary">{dispatch[order.id].rider_arriving_at && <span>Rider arrival recorded</span>}{dispatch[order.id].pickup_verified_at && <span>Handover verified</span>}{dispatch[order.id].picked_up_at && <span>Picked up</span>}{dispatch[order.id].en_route_at && <span>En route</span>}{dispatch[order.id].delivered_at && <span>Delivered</span>}</div>{dispatch[order.id].open_exception_type && <p role="status" className="mt-2 rounded-lg bg-amber-100 p-2 text-xs text-amber-900">Open issue · {dispatch[order.id].open_exception_type?.replaceAll('_',' ')}{dispatch[order.id].open_exception_reason ? ` · ${dispatch[order.id].open_exception_reason}` : ''}</p>}
                  {dispatch[order.id].open_exception_type === 'rider_unable_to_continue' && dispatch[order.id].rider_assigned && dispatch[order.id].execution_state !== 'picked_up' && dispatch[order.id].execution_state !== 'en_route' && dispatch[order.id].execution_state !== 'delivered' && dispatch[order.id].assignment_id && <div className="mt-3 rounded-lg border border-amber-200 bg-white p-3"><p className="text-xs font-semibold text-amber-900">Confirm no handover (only if goods are still with your business)</p><label className="mt-2 block text-xs">Reason<textarea maxLength={500} rows={2} value={recoveryReason[order.id] ?? ''} onChange={event=>setRecoveryReason(old=>({...old,[order.id]:event.target.value}))} className="mt-1 w-full rounded-lg border p-2" placeholder="Confirm the goods were not handed to the rider (10–500 characters)." /></label><button disabled={dispatchBusy===order.id|| (recoveryReason[order.id]?.trim().length ?? 0)<10} onClick={()=>void confirmNoHandover(order.id,dispatch[order.id])} className="mt-2 min-h-10 rounded-lg bg-amber-700 px-3 text-xs font-semibold text-white disabled:opacity-50">Record partner evidence</button>{dispatch[order.id].partner_confirmed_no_handover && <p className="mt-2 text-xs font-semibold text-emerald-700">No-handover evidence is recorded for this assignment.</p>}</div>}
                  {dispatch[order.id].execution_state === 'returned' && !dispatch[order.id].return_finalized_at && <div className="mt-3 rounded-lg border border-teal-200 bg-white p-3"><p className="text-xs font-semibold text-teal-900">Return receipt recorded · inventory inspection required</p><p className="mt-1 text-xs text-slateText-secondary">Choose whether the returned items are safe to restock. Admin finalization applies the inventory outcome exactly once.</p><label className="mt-2 block text-xs font-semibold">Inventory disposition<select value={returnKind[order.id] ?? 'not_restockable'} onChange={event=>setReturnKind(old=>({...old,[order.id]:event.target.value as 'restockable'|'not_restockable'}))} className="mt-1 min-h-10 w-full rounded-lg border px-2"><option value="restockable">Restockable after inspection</option><option value="not_restockable">Not restockable</option></select></label><label className="mt-2 block text-xs">Inspection reason<textarea maxLength={500} rows={2} value={returnReason[order.id] ?? ''} onChange={event=>setReturnReason(old=>({...old,[order.id]:event.target.value}))} className="mt-1 w-full rounded-lg border p-2" placeholder="Record condition and inspection result (10–500 characters)." /></label><button disabled={dispatchBusy===order.id||(returnReason[order.id]?.trim().length??0)<10} onClick={()=>void submitDisposition(order.id,dispatch[order.id])} className="mt-2 min-h-10 rounded-lg bg-teal-700 px-3 text-xs font-semibold text-white disabled:opacity-50">Submit inspected disposition</button></div>}
                </div>}
                <p className="flex items-center gap-2 text-xs text-slateText-secondary"><Clock3 size={14}/>Payment remains uncollected. Use the delivery progress controls below for verified partner handover.</p>
              </div>
              <div className="min-w-52 space-y-2">
                {dispatch[order.id]?.execution_state === 'at_pickup' && order.status === 'ready_for_pickup' && <ActionButton disabled={dispatchBusy === order.id} onClick={() => void issuePickup(order.id, dispatch[order.id])} tone="primary"><Check size={16}/>{dispatchBusy === order.id ? 'Issuing…' : 'Issue pickup code'}</ActionButton>}
                {dispatch[order.id]?.execution_state === 'return_in_progress' && <ActionButton disabled={dispatchBusy === order.id} onClick={() => void confirmReturn(order.id, dispatch[order.id])} tone="primary"><Check size={16}/>{dispatchBusy === order.id ? 'Confirming…' : 'Confirm return handover'}</ActionButton>}
                {order.status === 'placed' && <>
                  <ActionButton disabled={busy} onClick={() => onAction(order, 'accept')} tone="primary"><Check size={16}/> Accept order</ActionButton>
                  <ActionButton disabled={busy} onClick={() => { setRejecting(order); setReason(''); }} tone="danger"><X size={16}/> Reject with reason</ActionButton>
                </>}
                {order.status === 'accepted' && <ActionButton disabled={busy} onClick={() => onAction(order, 'prepare')} tone="primary"><PackageCheck size={16}/> Start preparation</ActionButton>}
                {order.status === 'preparing' && <ActionButton disabled={busy} onClick={() => onAction(order, 'ready')} tone="primary"><Check size={16}/> Mark ready for pickup</ActionButton>}
                {busy && <p className="flex items-center justify-center gap-2 py-2 text-xs text-primary"><Loader2 size={14} className="animate-spin"/>Saving status…</p>}
                {!['placed', 'accepted', 'preparing'].includes(order.status) && <p className="rounded-xl border border-borderMuted bg-white p-3 text-xs text-slateText-secondary">This order is in a terminal or handoff state. No further partner action is available.</p>}
              </div>
            </div>
          </div>}
        </article>;
      })}
    </div>

    {rejecting && <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/40 p-4" role="presentation">
      <section role="dialog" aria-modal="true" aria-labelledby="reject-title" className="w-full max-w-md rounded-2xl bg-white p-5 shadow-2xl">
        <h3 id="reject-title" className="text-lg font-bold">Reject platform order</h3>
        <p className="mt-1 text-sm text-slateText-secondary">Your reason will be recorded and shown to the customer. The reserved stock will be released once. Grepmind will not reassign or refund this unpaid order automatically.</p>
        <label htmlFor="reject-reason" className="mt-4 block text-sm font-semibold">Reason (10–500 characters)</label>
        <textarea id="reject-reason" value={reason} onChange={event => setReason(event.target.value)} maxLength={500} rows={4} className="mt-2 w-full rounded-xl border border-borderMuted p-3 text-sm outline-none focus:border-primary" placeholder="Tell us why this order cannot be fulfilled."/>
        <div className="mt-4 flex justify-end gap-2"><button onClick={() => setRejecting(null)} className="min-h-10 rounded-xl px-4 text-sm font-semibold text-slateText-secondary">Keep order</button><button onClick={reject} disabled={reason.trim().length < 10 || busyOrderId === rejecting.id} className="min-h-10 rounded-xl bg-rose-600 px-4 text-sm font-semibold text-white disabled:opacity-50">Confirm rejection</button></div>
      </section>
    </div>}
    {pickupCode && <div className="fixed inset-0 z-[60] grid place-items-center bg-slate-950/50 p-4"><section role="dialog" aria-modal="true" aria-labelledby="pickup-code-title" className="w-full max-w-sm rounded-2xl bg-white p-6 text-center shadow-2xl"><h3 id="pickup-code-title" className="text-lg font-bold">Partner-to-rider handover</h3><p className="mt-2 text-sm text-slateText-secondary">Share this short-lived code with the rider physically collecting order {pickupCode.orderId.slice(0, 8)}. Do not send it to anyone else.</p><p className="my-5 font-mono text-4xl font-extrabold tracking-[.3em] text-primary">{pickupCode.code}</p><p className="text-xs text-slateText-secondary">Expires in {pickupCode.expires} seconds</p><button onClick={() => setPickupCode(null)} className="mt-5 min-h-11 w-full rounded-xl bg-primary px-4 font-semibold text-white">Close and clear code</button></section></div>}
  </section>;
}

function Metric({ label, value, tone }: { label: string; value: number; tone: 'blue' | 'amber' | 'teal' }) {
  const color = tone === 'blue' ? 'bg-blue-50 text-blue-800' : tone === 'amber' ? 'bg-amber-50 text-amber-800' : 'bg-teal-50 text-teal-800';
  return <div className={`rounded-2xl border border-borderMuted p-4 ${color}`}><p className="text-xs font-semibold">{label}</p><p className="mt-1 text-2xl font-bold">{value}</p></div>;
}

function StatusPill({ status }: { status: string }) {
  const tone = status === 'placed' ? 'bg-amber-100 text-amber-800' : status === 'rejected' || status === 'cancelled' ? 'bg-rose-100 text-rose-800' : status === 'ready_for_pickup' ? 'bg-teal-100 text-teal-800' : 'bg-blue-100 text-blue-800';
  return <span className={`rounded-full px-2.5 py-1 text-[11px] font-semibold ${tone}`}>{statusLabel[status] || status}</span>;
}

function ActionButton({ children, disabled, onClick, tone }: { children: React.ReactNode; disabled?: boolean; onClick: () => void; tone: 'primary' | 'danger' }) {
  return <button onClick={onClick} disabled={disabled} className={`flex min-h-11 w-full items-center justify-center gap-2 rounded-xl px-3 text-sm font-semibold text-white disabled:cursor-wait disabled:opacity-50 ${tone === 'primary' ? 'bg-primary hover:bg-blue-800' : 'bg-rose-600 hover:bg-rose-700'}`}>{children}</button>;
}
