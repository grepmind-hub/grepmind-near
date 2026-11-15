'use client';

import { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, BadgeIndianRupee, RefreshCw, ShieldCheck } from 'lucide-react';
import { api } from '@/lib/api';

type Overview = { rider_user_id: string; rider_name: string; completed_deliveries: number; unpriced_deliveries: number; total_recorded_minor: string; currency: string };
type LedgerEntry = { id: string; rider_user_id: string; rider_name: string; delivery_job_id?: string; order_id?: string; entry_type: string; amount_minor: string | null; currency: string; effective_at: string; reason?: string; policy_version?: number; locality?: string };
type Policy = { id: string; policy_key: string; version: number; locality?: string; currency: string; fixed_amount_minor: string; status: string; is_synthetic: boolean; effective_from: string };
type Reconciliation = { delivery_job_id: string; reference_code: string; execution_state: string; discrepancy: string };
type AuditRow = { id: string; rider_name: string; actor_name: string; event_type: string; reason?: string; created_at: string };
type Locality = { locality_id: string; name: string; district: string };

function money(value: string | null, currency = 'INR') {
  if (value === null) return 'Unpriced';
  if (!/^-?\d+$/.test(value)) return 'Invalid amount';
  const negative = value.startsWith('-');
  const digits = (negative ? value.slice(1) : value).replace(/^0+(?=\d)/, '');
  const whole = digits.length > 2 ? digits.slice(0, -2) : '0';
  const fraction = digits.length > 1 ? digits.slice(-2) : digits.padStart(2, '0');
  const grouped = whole.length > 3 ? `${whole.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ',')},${whole.slice(-3)}` : whole;
  return `${negative ? '−' : ''}${currency} ${grouped}.${fraction}`;
}

export function RiderEarningsView() {
  const [overview, setOverview] = useState<Overview[]>([]);
  const [entries, setEntries] = useState<LedgerEntry[]>([]);
  const [policies, setPolicies] = useState<Policy[]>([]);
  const [flags, setFlags] = useState<Reconciliation[]>([]);
  const [audit, setAudit] = useState<AuditRow[]>([]);
  const [localities, setLocalities] = useState<Locality[]>([]);
  const [localityID, setLocalityID] = useState('');
  const [showAdjustment, setShowAdjustment] = useState(false);
  const [adjustment, setAdjustment] = useState({ rider: '', job: '', amount: '', reason: '' });
  const [actionError, setActionError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [from, setFrom] = useState(() => new Date(Date.now() - 30 * 86400000).toISOString());
  const [to] = useState(() => new Date(Date.now() + 60000).toISOString());

  const refresh = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const range = { from, to, ...(localityID ? { locality_id: localityID } : {}) };
      const [o, e, p, r, a, l] = await Promise.all([
        api.get<{ data: Overview[] }>('/admin/rider-earnings/overview', { params: range }),
        api.get<{ data: LedgerEntry[] }>('/admin/rider-earnings/entries', { params: { ...range, limit: 100 } }),
        api.get<{ data: Policy[] }>('/admin/rider-earnings/policies'),
        api.get<{ data: Reconciliation[] }>('/admin/rider-earnings/reconciliation'),
        api.get<{ data: AuditRow[] }>('/admin/rider-earnings/audit', { params: { limit: 50 } }),
        api.get<{ data: Locality[] }>('/admin/rider-earnings/localities'),
      ]);
      setOverview(o.data.data ?? []); setEntries(e.data.data ?? []); setPolicies(p.data.data ?? []); setFlags(r.data.data ?? []); setAudit(a.data.data ?? []); setLocalities(l.data.data ?? []);
    } catch (e: any) {
      setOverview([]); setEntries([]); setPolicies([]); setFlags([]); setAudit([]);
      setError(e?.response?.status === 403 ? 'Earnings data is restricted to the primary superadmin.' : 'Financial records could not be loaded. No totals are shown as zero.');
    } finally { setLoading(false); }
  }, [from, to, localityID]);
  useEffect(() => { void refresh(); }, [refresh]);

  const currencies = [...new Set(overview.map(row => row.currency))];
  const total = currencies.length > 1 ? 'Multiple currencies' : money(overview.reduce((sum, row) => sum + BigInt(row.total_recorded_minor || '0'), BigInt(0)).toString(), currencies[0] ?? 'INR');
  const completed = overview.reduce((sum, row) => sum + Number(row.completed_deliveries || 0), 0);
  const unpriced = overview.reduce((sum, row) => sum + Number(row.unpriced_deliveries || 0), 0);

  async function submitAdjustment() {
    setActionError(null);
    const minor = Number(adjustment.amount);
    if (!adjustment.rider || !Number.isSafeInteger(minor) || minor === 0 || adjustment.reason.trim().length < 10) { setActionError('Enter a rider UUID, non-zero integer minor-unit amount, and a reason of at least 10 characters.'); return; }
    try {
      await api.post('/admin/rider-earnings/adjustments', { rider_user_id: adjustment.rider.trim(), ...(adjustment.job.trim() ? { delivery_job_id: adjustment.job.trim() } : {}), amount_minor: minor, currency: 'INR', reason: adjustment.reason.trim(), idempotency_key: crypto.randomUUID() });
      setShowAdjustment(false); setAdjustment({ rider: '', job: '', amount: '', reason: '' }); await refresh();
    } catch (e: any) { setActionError(e?.response?.data?.error?.message ?? 'Adjustment was not recorded.'); }
  }

  async function reverse(row: LedgerEntry) {
    const reason = window.prompt(`Reverse delivery earning for ${row.rider_name}. Enter a reason (10–500 characters):`);
    if (!reason || reason.trim().length < 10) return;
    setActionError(null);
    try { await api.post(`/admin/rider-earnings/entries/${row.id}/reverse`, { reason: reason.trim(), idempotency_key: `reverse:${row.id}` }); await refresh(); }
    catch (e: any) { setActionError(e?.response?.data?.error?.message ?? 'Reversal was not recorded.'); }
  }

  return <section className="space-y-6">
    <header className="flex flex-wrap items-center justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wider text-[#123D36]">Rider operations · finance controls</p><h1 className="mt-1 text-2xl font-bold text-[#172033]">Rider earnings ledger</h1><p className="mt-1 text-sm text-[#667085]">Append-only compensation records. Payouts and settlement are disabled.</p></div><button onClick={() => void refresh()} className="inline-flex min-h-11 items-center gap-2 rounded-[14px] border bg-white px-4 text-sm font-semibold hover:bg-slate-50"><RefreshCw size={16}/> Refresh</button></header>
    {error && <div role="alert" className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">{error}</div>}
    <div className="grid gap-4 md:grid-cols-3">
      <Metric title="Recorded compensation" value={loading ? 'Loading…' : total} icon={<BadgeIndianRupee size={19}/>} />
      <Metric title="Completed deliveries" value={loading ? 'Loading…' : completed.toLocaleString()} icon={<ShieldCheck size={19}/>} />
      <Metric title="Awaiting policy review" value={loading ? 'Loading…' : unpriced.toLocaleString()} icon={<AlertTriangle size={19}/>} />
    </div>
    {actionError && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">{actionError}</div>}
    <div className="flex flex-wrap items-end justify-between gap-3 rounded-2xl border bg-white p-4"><div className="flex flex-wrap items-end gap-3"><label className="text-xs font-semibold text-slate-600">From<input aria-label="From date" type="date" value={from.slice(0,10)} onChange={e => setFrom(new Date(`${e.target.value}T00:00:00.000Z`).toISOString())} className="mt-1 block min-h-10 rounded-lg border px-3 text-sm"/></label><label className="text-xs font-semibold text-slate-600">Locality<select aria-label="Filter by locality" value={localityID} onChange={e=>setLocalityID(e.target.value)} className="mt-1 block min-h-10 rounded-lg border px-3 text-sm"><option value="">All localities</option>{localities.map(x=><option key={x.locality_id} value={x.locality_id}>{x.name}, {x.district}</option>)}</select></label><p className="pb-2 text-xs text-slate-500">Through now · timestamps UTC</p></div><button onClick={() => setShowAdjustment(v => !v)} className="min-h-10 rounded-[14px] bg-[#123D36] px-4 text-sm font-semibold text-white hover:bg-[#0c2924]">Record adjustment</button></div>
    {showAdjustment && <Panel title="Append an audited adjustment"><div className="grid gap-3 p-4 md:grid-cols-2"><label className="text-xs font-semibold">Rider user UUID<input className="mt-1 min-h-10 w-full rounded-lg border px-3 font-mono text-sm" value={adjustment.rider} onChange={e=>setAdjustment({...adjustment,rider:e.target.value})}/></label><label className="text-xs font-semibold">Related delivered job UUID (optional)<input className="mt-1 min-h-10 w-full rounded-lg border px-3 font-mono text-sm" value={adjustment.job} onChange={e=>setAdjustment({...adjustment,job:e.target.value})}/></label><label className="text-xs font-semibold">INR amount in paise (positive or negative)<input inputMode="numeric" className="mt-1 min-h-10 w-full rounded-lg border px-3 text-sm" value={adjustment.amount} onChange={e=>setAdjustment({...adjustment,amount:e.target.value})}/></label><label className="text-xs font-semibold">Reason<input className="mt-1 min-h-10 w-full rounded-lg border px-3 text-sm" value={adjustment.reason} onChange={e=>setAdjustment({...adjustment,reason:e.target.value})}/></label><div className="flex gap-2 md:col-span-2"><button onClick={()=>void submitAdjustment()} className="min-h-10 rounded-[14px] bg-[#123D36] px-4 text-sm font-semibold text-white hover:bg-[#0c2924]">Append adjustment</button><button onClick={()=>setShowAdjustment(false)} className="min-h-10 rounded-[14px] border px-4 text-sm">Cancel</button></div></div></Panel>}
    <div className="grid gap-5 xl:grid-cols-2">
      <Panel title="Rider overview">{loading ? <p className="p-5 text-sm text-slate-500">Loading earnings…</p> : overview.length === 0 ? <Empty error={!!error}/> : <div className="divide-y">{overview.map(row => <div key={`${row.rider_user_id}:${row.currency}`} className="flex items-center justify-between gap-4 p-4"><div className="min-w-0"><p className="truncate font-semibold text-slate-900">{row.rider_name} · {row.currency}</p><p className="text-xs text-slate-500">{row.completed_deliveries} completed · {row.unpriced_deliveries} unpriced</p></div><b className="shrink-0 text-slate-900">{money(row.total_recorded_minor,row.currency)}</b></div>)}</div>}</Panel>
      <Panel title="Compensation policy registry">{loading ? <p className="p-5 text-sm text-slate-500">Loading policy metadata…</p> : policies.length === 0 ? <Empty error={!!error} text="No compensation policies configured. Production posting remains disabled."/> : <div className="divide-y">{policies.map(p => <div key={p.id} className="p-4"><div className="flex justify-between gap-2"><b>{p.policy_key} · v{p.version}</b><span className="rounded-full bg-slate-100 px-2 py-1 text-xs">{p.status}{p.is_synthetic ? ' · synthetic QA' : ''}</span></div><p className="mt-1 text-sm text-slate-600">{p.locality ?? 'Global'} · {money(p.fixed_amount_minor,p.currency)} per completed delivery</p><p className="text-xs text-slate-500">Effective {new Date(p.effective_from).toLocaleString()}</p></div>)}</div>}</Panel>
    </div>
    <Panel title="Unresolved reconciliation exceptions">{loading ? <p className="p-5 text-sm text-slate-500">Checking ledger consistency…</p> : flags.length === 0 ? <Empty error={!!error} text="No discrepancies found in the checked delivery records."/> : <div className="divide-y">{flags.map(row => <div key={row.delivery_job_id} className="flex flex-wrap justify-between gap-2 p-4 text-sm"><span className="font-semibold">{row.reference_code} · {row.execution_state}</span><span className="text-amber-800">{row.discrepancy.replaceAll('_',' ')}</span></div>)}</div>}</Panel>
    <Panel title="Ledger and adjustment history">{loading ? <p className="p-5 text-sm text-slate-500">Loading ledger…</p> : entries.length === 0 ? <Empty error={!!error}/> : <div className="overflow-x-auto"><table className="w-full min-w-[850px] text-left text-sm"><thead className="bg-slate-50 text-xs uppercase text-slate-500"><tr><th className="p-3">Date</th><th className="p-3">Rider</th><th className="p-3">Entry</th><th className="p-3">Delivery job</th><th className="p-3">Reason</th><th className="p-3 text-right">Amount</th><th className="p-3">Action</th></tr></thead><tbody className="divide-y">{entries.map(row => <tr key={row.id}><td className="p-3">{new Date(row.effective_at).toLocaleString()}</td><td className="p-3">{row.rider_name}</td><td className="p-3">{row.entry_type.replaceAll('_',' ')}</td><td className="p-3 font-mono text-xs">{row.delivery_job_id?.slice(0,8) ?? '—'}</td><td className="max-w-60 truncate p-3 text-slate-500">{row.reason ?? '—'}</td><td className="p-3 text-right font-semibold">{money(row.amount_minor,row.currency)}</td><td className="p-3">{row.entry_type==='delivery_earning'&&<button onClick={()=>void reverse(row)} className="rounded-lg border px-2 py-1 text-xs font-semibold text-rose-700">Reverse</button>}</td></tr>)}</tbody></table></div>}</Panel>
    <Panel title="Immutable audit history">{loading ? <p className="p-5 text-sm text-slate-500">Loading audit history…</p> : audit.length===0 ? <Empty error={!!error} text="No adjustment or ledger audit events."/> : <div className="divide-y">{audit.map(row=><div key={row.id} className="flex flex-wrap justify-between gap-2 p-4 text-sm"><span><b>{row.event_type.replaceAll('_',' ')}</b> · {row.rider_name} · by {row.actor_name}</span><span className="text-slate-500">{row.reason ?? 'System-recorded delivery event'} · {new Date(row.created_at).toLocaleString()}</span></div>)}</div>}</Panel>
    <p className="text-xs text-slate-500">Financial reports and policy records are restricted to the primary superadmin. Adjustments/reversals are append-only API operations requiring an audited reason; this view does not expose a balance editor or payout controls.</p>
  </section>;
}

function Metric({title,value,icon}:{title:string;value:string;icon:React.ReactNode}) { return <div className="rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-sm"><div className="flex items-center justify-between text-sm text-slate-500"><span>{title}</span><span className="text-[#16A085]">{icon}</span></div><p className="mt-3 text-2xl font-bold text-[#172033]">{value}</p></div>; }
function Panel({title,children}:{title:string;children:React.ReactNode}) { return <div className="overflow-hidden rounded-2xl border border-[#E4E7EC] bg-white shadow-sm"><h2 className="border-b px-5 py-4 font-semibold text-[#172033]">{title}</h2>{children}</div>; }
function Empty({error,text='No ledger entries for this period.'}:{error:boolean;text?:string}) { return <div className="p-8 text-center text-sm text-slate-500">{error?'Data unavailable. Retry after restoring Admin API access.':text}</div>; }
