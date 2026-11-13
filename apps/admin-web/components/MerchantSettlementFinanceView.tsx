'use client';

import { useCallback, useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { FinanceAccessGrantPanel } from '@/components/FinanceAccessGrantPanel';

type Row = Record<string, any>;
const money = (minor: number) => `₹${(Number(minor || 0) / 100).toFixed(2)}`;
const card = 'rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-sm';

export function MerchantSettlementFinanceView() {
  const [policies, setPolicies] = useState<Row[]>([]);
  const [eligible, setEligible] = useState<Row[]>([]);
  const [payables, setPayables] = useState<Row[]>([]);
  const [batches, setBatches] = useState<Row[]>([]);
  const [adjustments, setAdjustments] = useState<Row[]>([]);
  const [exceptions, setExceptions] = useState<Row[]>([]);
  const [selected, setSelected] = useState<Record<string, boolean>>({});
  const [policyForm, setPolicyForm] = useState({ policy_key: '', version: '1', business_id: '', vertical: 'food', commission_type: 'percentage_bps', percentage_bps: '', fixed_minor: '', effective_from: new Date().toISOString().slice(0, 16) });
  const [poolForm, setPoolForm] = useState({ order_id: '', amount_minor: '', funding_reference: '', reason: '' });
  const [reason, setReason] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const [p, e, a, b, adj, ex] = await Promise.all([
        api.get('/admin/finance/commission-policies'), api.get('/admin/finance/eligible-orders'),
        api.get('/admin/finance/payables'), api.get('/admin/finance/settlements'),
        api.get('/admin/finance/payable-adjustments'), api.get('/admin/finance/reconciliation-exceptions'),
      ]);
      setPolicies(p.data?.data ?? []); setEligible(e.data?.data ?? []); setPayables(a.data?.data ?? []);
      setBatches(b.data?.data ?? []); setAdjustments(adj.data?.data ?? []); setExceptions(ex.data?.data ?? []);
    } catch (e: any) {
      setError(e?.response?.data?.error?.message ?? (e?.response?.status === 403
        ? 'Your finance.read grant is required for these records.'
        : e?.response?.status === 503 ? 'Settlement simulation is disabled. Verify the isolated QA feature flags.'
          : 'Merchant finance data could not be loaded from the API. No totals are estimated locally.'));
    } finally { setLoading(false); }
  }, []);
  useEffect(() => { void load(); }, [load]);

  async function mutate(key: string, action: () => Promise<unknown>, success: string) {
    setBusy(key); setError(null); setNotice(null);
    try { await action(); setNotice(success); await load(); }
    catch (e: any) { setError(e?.response?.data?.error?.message ?? 'Finance action was not accepted. Refresh before retrying.'); }
    finally { setBusy(null); }
  }
  async function createPolicy() {
    const body: Row = { ...policyForm, version: Number(policyForm.version), effective_from: new Date(policyForm.effective_from).toISOString(), effective_until: null };
    if (policyForm.business_id.trim()) body.business_id = policyForm.business_id.trim(); else delete body.business_id;
    if (body.commission_type === 'percentage_bps') { body.percentage_bps = Number(policyForm.percentage_bps); delete body.fixed_minor; }
    else { body.fixed_minor = Number(policyForm.fixed_minor); delete body.percentage_bps; }
    await mutate('policy', () => api.post('/admin/finance/commission-policies', body), 'Draft policy created. It is not active until an independent finance reviewer approves it.');
  }
  async function accrue(order: Row) {
    await mutate(`accrue-${order.order_id}`, () => api.post(`/admin/finance/orders/${order.order_id}/accrue-payable`, {}), 'Immutable payable snapshot accrued from server records.');
  }
  async function reviewPolicy(id: string, decision: 'approve' | 'reject') {
    const note = (reason[id] || '').trim();
    if (note.length < 5) { setError('Provide a review reason of at least five characters.'); return; }
    await mutate(`policy-${id}`, () => api.post(`/admin/finance/commission-policies/${id}/decision`, { decision, reason: note }), `Policy ${decision === 'approve' ? 'approved' : 'rejected'}.`);
  }
  async function createPool() {
    const body = { ...poolForm, amount_minor: Number(poolForm.amount_minor) };
    await mutate('pool', () => api.post('/admin/finance/qa-funding-pools', body), 'Synthetic QA pool recorded; it does not represent provider-settled funds.');
    setPoolForm({ order_id: '', amount_minor: '', funding_reference: '', reason: '' });
  }
  async function createBatch() {
    const ids = Object.keys(selected).filter(id => selected[id]);
    if (!ids.length) { setError('Select at least one unallocated payable.'); return; }
    const dates = ids.map(id => String(payables.find(p => p.id === id)?.created_at ?? '').slice(0, 10)).filter(Boolean).sort();
    const start = dates[0], end = dates[dates.length - 1];
    if (!start || !end) { setError('Selected payable period could not be determined from API data.'); return; }
    await mutate('batch', () => api.post('/admin/finance/settlements', { payable_ids: ids, period_start: start, period_end: end, idempotency_key: crypto.randomUUID() }), 'Settlement simulation draft created. No transfer occurred.');
    setSelected({});
  }
  async function transition(id: string, action: 'review' | 'approve' | 'simulate' | 'reconcile') {
    const note = (reason[id] || '').trim();
    if (note.length < 5) { setError('Provide a finance reason of at least five characters.'); return; }
    if (action === 'simulate' && !window.confirm('Simulate this settlement in the QA ledger? This does not transfer funds.')) return;
    await mutate(`${action}-${id}`, () => api.post(`/admin/finance/settlements/${id}/${action}`, { reason: note }), action === 'simulate' ? 'Settlement simulation recorded; no payout was made.' : `Settlement batch ${action}d.`);
  }
  async function decideAdjustment(id: string, decision: 'approve' | 'reject') {
    const note = (reason[id] || '').trim(); if (note.length < 5) { setError('Provide an adjustment review reason.'); return; }
    await mutate(`adjust-${id}`, () => api.post(`/admin/finance/payable-adjustments/${id}/review`, { decision, reason: note }), `Adjustment ${decision === 'approve' ? 'approved' : 'rejected'}.`);
  }
  async function reconcile() {
    await mutate('reconcile', () => api.post('/admin/finance/reconcile', {}), 'Read-only reconciliation completed. Detected exceptions are listed below; no automatic repairs were made.');
  }

  return <section className="space-y-5" aria-label="Merchant payable and settlement simulation">
    <header className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-[.14em] text-[#0F766E]">Finance operations · isolated QA</p><h1 className="mt-1 text-2xl font-bold text-[#172033]">Merchant payables & settlement simulation</h1><p className="mt-1 text-sm text-[#667085]">Versioned commission snapshots, verified funding eligibility, simulated batches and reconciliation.</p></div><div className="flex gap-2"><button onClick={() => void reconcile()} disabled={busy !== null} className="min-h-11 rounded-xl border border-[#D0D5DD] px-4 text-sm font-semibold">Run reconciliation</button><button onClick={() => void load()} disabled={loading} className="min-h-11 rounded-xl bg-[#2457D6] px-4 text-sm font-semibold text-white">{loading ? 'Refreshing…' : 'Refresh data'}</button></div></header>
    <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950"><strong>Simulation only.</strong> No bank or gateway funds are transferred. Commission, tax and supplier terms require approved contracts; no production rate or tax is assumed. UPI capture is not provider settlement. COD requires verified rider remittance. Real payout, COD and live settlement flags remain disabled.</div>
    {error && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">{error}</div>}{notice && <div role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">{notice}</div>}
    {loading ? <div className={card}>Loading authoritative finance records…</div> : !error && <>
      <div className="grid gap-4 xl:grid-cols-2">
        <article className={card}><h2 className="font-bold">Commission policy versions</h2><p className="mt-1 text-xs text-[#667085]">Drafts never affect calculations. Approvals require a different finance principal.</p><form onSubmit={e => { e.preventDefault(); void createPolicy(); }} className="mt-4 grid gap-3 sm:grid-cols-2">
          <label className="text-xs font-semibold">Policy key<input required maxLength={100} value={policyForm.policy_key} onChange={e => setPolicyForm({...policyForm,policy_key:e.target.value})} className="mt-1 min-h-10 w-full rounded-lg border p-2 text-sm" placeholder="e.g. qa-food-v1"/></label>
          <label className="text-xs font-semibold">Version<input required type="number" min="1" value={policyForm.version} onChange={e => setPolicyForm({...policyForm,version:e.target.value})} className="mt-1 min-h-10 w-full rounded-lg border p-2 text-sm"/></label>
          <label className="text-xs font-semibold">Vertical<select value={policyForm.vertical} onChange={e => setPolicyForm({...policyForm,vertical:e.target.value})} className="mt-1 min-h-10 w-full rounded-lg border bg-white p-2 text-sm"><option value="food">Food</option><option value="grocery">Grocery</option></select></label>
          <label className="text-xs font-semibold">Merchant UUID (optional)<input value={policyForm.business_id} onChange={e => setPolicyForm({...policyForm,business_id:e.target.value})} className="mt-1 min-h-10 w-full rounded-lg border p-2 text-sm" placeholder="Blank means vertical scope"/></label>
          <label className="text-xs font-semibold">Calculation<input disabled value="Partner supply price" className="mt-1 min-h-10 w-full rounded-lg border bg-slate-50 p-2 text-sm"/></label>
          <label className="text-xs font-semibold">Commission type<select value={policyForm.commission_type} onChange={e => setPolicyForm({...policyForm,commission_type:e.target.value})} className="mt-1 min-h-10 w-full rounded-lg border bg-white p-2 text-sm"><option value="percentage_bps">Percentage basis points</option><option value="fixed_minor">Fixed paise per order</option></select></label>
          {policyForm.commission_type === 'percentage_bps' ? <label className="text-xs font-semibold">Rate (basis points)<input required type="number" min="0" max="10000" value={policyForm.percentage_bps} onChange={e => setPolicyForm({...policyForm,percentage_bps:e.target.value})} className="mt-1 min-h-10 w-full rounded-lg border p-2 text-sm"/></label> : <label className="text-xs font-semibold">Fixed amount (paise)<input required type="number" min="0" value={policyForm.fixed_minor} onChange={e => setPolicyForm({...policyForm,fixed_minor:e.target.value})} className="mt-1 min-h-10 w-full rounded-lg border p-2 text-sm"/></label>}
          <label className="text-xs font-semibold">Effective from<input required type="datetime-local" value={policyForm.effective_from} onChange={e => setPolicyForm({...policyForm,effective_from:e.target.value})} className="mt-1 min-h-10 w-full rounded-lg border p-2 text-sm"/></label>
          <button disabled={busy!==null} className="min-h-10 self-end rounded-lg bg-[#2457D6] px-4 text-sm font-semibold text-white disabled:opacity-50">Save draft policy</button>
        </form><div className="mt-4 space-y-2">{policies.map(p=><div key={p.id} className="rounded-xl border p-3"><div className="flex flex-wrap justify-between gap-2 text-sm"><strong>{p.policy_key} v{p.version} · {p.vertical}</strong><span className="rounded-full bg-slate-100 px-2 py-1 text-xs font-semibold capitalize">{p.status}</span></div><p className="mt-1 text-xs text-[#667085]">{p.business_id || 'All merchants'} · {p.commission_type==='percentage_bps' ? `${(Number(p.percentage_bps)/100).toFixed(2)}%` : money(Number(p.fixed_minor))} · effective {p.effective_from}</p>{p.status==='draft'&&<><input aria-label={`Policy review reason ${p.id}`} value={reason[p.id]||''} onChange={e=>setReason({...reason,[p.id]:e.target.value})} className="mt-2 min-h-9 w-full rounded-lg border p-2 text-xs" placeholder="Independent review reason"/><div className="mt-2 flex gap-2"><button disabled={busy!==null||!reason[p.id]?.trim()} onClick={()=>void reviewPolicy(p.id,'approve')} className="min-h-9 rounded-lg bg-emerald-700 px-3 text-xs font-bold text-white disabled:opacity-50">Approve</button><button disabled={busy!==null||!reason[p.id]?.trim()} onClick={()=>void reviewPolicy(p.id,'reject')} className="min-h-9 rounded-lg border px-3 text-xs font-bold disabled:opacity-50">Reject</button></div></>}</div>)}{policies.length===0&&<p className="py-3 text-sm text-[#667085]">No policy versions. There is no default commission.</p>}</div></article>
        <article className={card}><h2 className="font-bold">Eligible delivered orders</h2><p className="mt-1 text-xs text-[#667085]">Only server-verified sandbox captures or synthetic COD collections appear. Full order-time supply snapshots are required for accrual.</p><div className="mt-4 space-y-3">{eligible.map(o=><div key={o.order_id} className="rounded-xl border p-3"><div className="flex flex-wrap justify-between gap-2"><div><strong className="text-sm">{o.reference_code} · {o.merchant_name}</strong><p className="mt-1 text-xs text-[#667085]">{o.payment_method} · customer {money(o.customer_gross_minor)} · partner supply {money(o.partner_supply_minor)}</p><p className="text-xs text-[#667085]">priced items {o.priced_item_count}/{o.item_count}</p></div><button disabled={busy!==null||o.priced_item_count!==o.item_count} onClick={()=>void accrue(o)} className="min-h-10 rounded-lg bg-[#2457D6] px-3 text-xs font-bold text-white disabled:opacity-50">Accrue payable</button></div></div>)}{eligible.length===0&&<p className="py-3 text-sm text-[#667085]">No delivered, verified orders are currently eligible.</p>}</div></article>
      </div>
      <article className={card}><div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="font-bold">Payable snapshots</h2><p className="mt-1 text-xs text-[#667085]">Immutable order-time calculations. Merchant amounts are not settlement-fund availability.</p></div><button onClick={()=>void createBatch()} disabled={busy!==null||!Object.values(selected).some(Boolean)} className="min-h-10 rounded-lg bg-[#2457D6] px-4 text-sm font-bold text-white disabled:opacity-50">Create simulated batch</button></div><div className="mt-4 overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr className="border-b text-xs text-[#667085]"><th className="pb-2">Select</th><th>Order / merchant</th><th>Customer gross</th><th>Supply</th><th>Commission</th><th>Net payable</th><th>Funding</th></tr></thead><tbody>{payables.map(p=><tr key={p.id} className="border-b last:border-0"><td><input type="checkbox" aria-label={`Select payable ${p.reference_code}`} checked={!!selected[p.id]} disabled={p.allocation_state==='allocated'} onChange={e=>setSelected({...selected,[p.id]:e.target.checked})}/></td><td className="py-3"><strong>{p.reference_code}</strong><p className="text-xs text-[#667085]">{p.merchant_name}</p></td><td>{money(p.customer_gross_minor)}</td><td>{money(p.partner_gross_minor)}</td><td>{money(p.commission_minor)}</td><td className="font-semibold">{money(p.net_payable_minor)}</td><td>{p.allocation_state}</td></tr>)}</tbody></table>{payables.length===0&&<p className="py-4 text-sm text-[#667085]">No payable snapshots yet.</p>}</div></article>
      <div className="grid gap-4 xl:grid-cols-2"><article className={card}><h2 className="font-bold">Synthetic UPI funding pool</h2><p className="mt-1 text-xs text-[#667085]">Explicit QA value only; cannot exceed a verified sandbox capture net of successful refunds.</p><form onSubmit={e=>{e.preventDefault();void createPool();}} className="mt-3 grid gap-2 sm:grid-cols-2"><input required value={poolForm.order_id} onChange={e=>setPoolForm({...poolForm,order_id:e.target.value})} className="min-h-10 rounded-lg border p-2 text-xs" placeholder="Order UUID"/><input required type="number" min="1" value={poolForm.amount_minor} onChange={e=>setPoolForm({...poolForm,amount_minor:e.target.value})} className="min-h-10 rounded-lg border p-2 text-xs" placeholder="Amount in paise"/><input required minLength={8} value={poolForm.funding_reference} onChange={e=>setPoolForm({...poolForm,funding_reference:e.target.value})} className="min-h-10 rounded-lg border p-2 text-xs" placeholder="QA funding reference"/><input required minLength={10} value={poolForm.reason} onChange={e=>setPoolForm({...poolForm,reason:e.target.value})} className="min-h-10 rounded-lg border p-2 text-xs" placeholder="Reason (10+ chars)"/><button disabled={busy!==null} className="min-h-10 rounded-lg border border-amber-400 bg-amber-50 px-3 text-xs font-bold text-amber-950 sm:col-span-2">Record synthetic pool</button></form></article>
        <article className={card}><h2 className="font-bold">Settlement batches</h2><div className="mt-3 space-y-3">{batches.map(b=><div key={b.id} className="rounded-xl border p-3"><div className="flex flex-wrap justify-between gap-2"><strong className="text-sm">{b.merchant_name} · {money(b.simulated_net_minor)}</strong><span className="rounded-full bg-blue-50 px-2 py-1 text-xs font-semibold capitalize">{b.status}</span></div><p className="mt-1 text-xs text-[#667085]">{b.funding_mode} · {b.disclosure}</p><input aria-label={`Settlement reason ${b.id}`} value={reason[b.id]||''} onChange={e=>setReason({...reason,[b.id]:e.target.value})} className="mt-2 min-h-9 w-full rounded-lg border p-2 text-xs" placeholder="Finance action reason"/><div className="mt-2 flex flex-wrap gap-2">{(['review','approve','simulate','reconcile'] as const).map(action=>{const expected=({draft:'review',reviewed:'approve',approved:'simulate',simulated:'reconcile'} as Record<string,string>)[b.status];return expected===action?<button key={action} onClick={()=>void transition(b.id,action)} disabled={busy!==null||!reason[b.id]?.trim()} className="min-h-9 rounded-lg bg-[#2457D6] px-3 text-xs font-bold text-white disabled:opacity-50">{action}</button>:null;})}</div></div>)}{batches.length===0&&<p className="py-3 text-sm text-[#667085]">No simulated settlement batches.</p>}</div></article></div>
      <div className="grid gap-4 xl:grid-cols-2"><article className={card}><h2 className="font-bold">Payable adjustments</h2><div className="mt-3 space-y-2">{adjustments.map(a=><div key={a.id} className="rounded-xl border p-3 text-sm"><div className="flex justify-between gap-2"><strong>{a.merchant_name} · {money(a.amount_minor)} {a.adjustment_type}</strong><span className="text-xs capitalize">{a.status}</span></div><p className="mt-1 text-xs text-[#667085]">{a.reason_code} · {a.created_at}</p>{a.status==='requested'&&<><input value={reason[a.id]||''} onChange={e=>setReason({...reason,[a.id]:e.target.value})} className="mt-2 min-h-9 w-full rounded border p-2 text-xs" placeholder="Independent review reason"/><div className="mt-2 flex gap-2">{(['approve','reject'] as const).map(decision=><button key={decision} onClick={()=>void decideAdjustment(a.id,decision)} disabled={busy!==null||!reason[a.id]?.trim()} className="min-h-9 rounded-lg border px-3 text-xs font-bold disabled:opacity-50">{decision}</button>)}</div></>}</div>)}{adjustments.length===0&&<p className="py-3 text-sm text-[#667085]">No adjustment requests.</p>}</div></article>
        <article className={card}><h2 className="font-bold">Reconciliation exceptions</h2><div className="mt-3 space-y-2">{exceptions.map(x=><div key={x.id} className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm"><strong>{String(x.issue_code).replaceAll('_',' ')}</strong><p className="mt-1 text-xs">{x.details}</p></div>)}{exceptions.length===0&&<p className="py-3 text-sm text-emerald-700">No persisted reconciliation exceptions.</p>}</div></article></div>
      <FinanceAccessGrantPanel />
    </>}
  </section>;
}
