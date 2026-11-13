'use client';

import { useCallback, useEffect, useState } from 'react';
import { AlertCircle, RefreshCw, WalletCards } from 'lucide-react';
import { fetchMerchantFinanceOverview, fetchMerchantFinancePayables, fetchMerchantFinanceSettlements, MerchantApiError, MerchantFinanceOverview, MerchantPayableRow, MerchantSettlementRow } from '../lib/api';

const money = (minor: number, currency = 'INR') => new Intl.NumberFormat('en-IN', { style: 'currency', currency }).format(Number(minor || 0) / 100);
const card = 'rounded-2xl border border-borderMuted bg-white p-5 shadow-card';

export function MerchantFinanceView({ businessId }: { businessId: string }) {
  const [overview, setOverview] = useState<MerchantFinanceOverview | null>(null);
  const [payables, setPayables] = useState<MerchantPayableRow[]>([]);
  const [settlements, setSettlements] = useState<MerchantSettlementRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const [summary, payableRows, settlementRows] = await Promise.all([
        fetchMerchantFinanceOverview(businessId), fetchMerchantFinancePayables(businessId), fetchMerchantFinanceSettlements(businessId),
      ]);
      setOverview(summary); setPayables(payableRows); setSettlements(settlementRows);
    } catch (e) {
      setOverview(null); setPayables([]); setSettlements([]);
      setError(e instanceof MerchantApiError && e.status === 503
        ? 'Merchant financial reporting is not enabled for this environment yet.'
        : e instanceof MerchantApiError && e.status === 404
          ? 'This account does not have access to this business financial view.'
          : e instanceof Error ? e.message : 'Financial records could not be loaded.');
    } finally { setLoading(false); }
  }, [businessId]);
  useEffect(() => { void load(); }, [load]);

  return <section aria-label="Merchant financial overview" className="space-y-5">
    <header className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-[.14em] text-teal-700">Merchant finance</p><h2 className="mt-1 text-2xl font-bold">Payables & settlement history</h2><p className="mt-1 text-sm text-slateText-secondary">Read-only reporting for this business, based on approved policy snapshots.</p></div><button onClick={() => void load()} disabled={loading} className="inline-flex min-h-11 items-center gap-2 rounded-xl border border-borderMuted bg-white px-4 text-sm font-semibold"><RefreshCw size={16} className={loading ? 'animate-spin' : ''}/>Refresh</button></header>
    <div className="rounded-xl border border-blue-200 bg-blue-50 p-4 text-sm text-blue-950"><strong>Settlement simulation only.</strong> Displayed payable is not a promise of payment or proof of available funds. Simulated batches do not transfer money. Commission and tax treatment follow only independently approved policy records.</div>
    {error && <div role="alert" className="flex items-start gap-2 rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800"><AlertCircle size={18} className="mt-0.5 shrink-0"/>{error}</div>}
    {loading ? <div className={card}>Loading financial records…</div> : !error && overview && <>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{[
        ['Customer order gross', overview.customer_gross_minor], ['Partner supply basis', overview.partner_gross_minor],
        ['Commission clearing', overview.commission_minor], ['Pending payable', overview.pending_payable_minor],
        ['Simulated / reconciled settlements', overview.simulated_settlement_minor],
      ].map(([label, value]) => <article key={String(label)} className={card}><div className="flex items-center justify-between"><p className="text-sm text-slateText-secondary">{label}</p><WalletCards size={16} className="text-primary"/></div><p className="mt-2 text-2xl font-bold">{money(Number(value), overview.currency)}</p><p className="mt-2 text-xs text-slateText-muted">Derived from server records.</p></article>)}</div>
      <article className={card}><h3 className="font-bold">Order-level payable history</h3><div className="mt-4 overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr className="border-b text-xs text-slateText-muted"><th className="pb-2">Order</th><th>Payment source</th><th>Supply basis</th><th>Commission</th><th>Net payable</th><th>Status</th></tr></thead><tbody>{payables.map(p=><tr key={p.id} className="border-b last:border-0"><td className="py-3 font-semibold">{p.reference_code}<p className="font-normal text-xs text-slateText-muted">{new Date(p.created_at).toLocaleDateString()}</p></td><td>{p.payment_source.replaceAll('_',' ')}</td><td>{money(p.partner_gross_minor,p.currency)}</td><td>{money(p.commission_minor,p.currency)}</td><td className="font-semibold">{money(p.net_payable_minor,p.currency)}</td><td className="capitalize">{p.state}</td></tr>)}</tbody></table>{payables.length===0&&<p className="py-5 text-sm text-slateText-secondary">No payable records are available for this business.</p>}</div></article>
      <article className={card}><h3 className="font-bold">Settlement simulation history</h3><div className="mt-3 space-y-3">{settlements.map(s=><div key={s.id} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-borderMuted p-4"><div><p className="font-semibold">{money(s.simulated_net_minor,s.currency)} <span className="ml-2 rounded-full bg-blue-50 px-2 py-1 text-xs capitalize text-blue-800">{s.status}</span></p><p className="mt-1 text-xs text-slateText-secondary">Period {s.period_start} – {s.period_end} · {s.funding_mode.replaceAll('_',' ')}</p><p className="mt-1 text-xs text-slateText-muted">{s.disclosure}</p></div><p className="text-xs text-slateText-muted">Created {new Date(s.created_at).toLocaleDateString()}</p></div>)}{settlements.length===0&&<p className="py-4 text-sm text-slateText-secondary">No settlement simulations have been recorded.</p>}</div></article>
    </>}
  </section>;
}
