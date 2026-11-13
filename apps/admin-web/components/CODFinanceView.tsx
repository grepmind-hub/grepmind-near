'use client';

import { useCallback, useEffect, useState } from 'react';
import { api } from '@/lib/api';

type Remittance = {
  id: string;
  rider_user_id: string;
  rider_name: string;
  amount_minor: number;
  currency: string;
  submission_reference: string;
  state: string;
  submitted_at: string;
  verification_reason?: string | null;
};
type Collection = {
  id: string;
  order_id: string;
  reference_code: string;
  rider_name: string;
  amount_minor: number;
  currency: string;
  collected_at: string;
  financial_journal_id: string;
};

export function CODFinanceView() {
  const [collections, setCollections] = useState<Collection[]>([]);
  const [remittances, setRemittances] = useState<Remittance[]>([]);
  const [audit, setAudit] = useState<Record<string, unknown>[]>([]);
  const [issues, setIssues] = useState<Record<string, unknown>[]>([]);
  const [reason, setReason] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const [collectionResponse, remittanceResponse, auditResponse, reconciliationResponse] = await Promise.all([
        api.get('/admin/cod/collections'), api.get('/admin/cod/remittances'), api.get('/admin/cod/audit'), api.get('/admin/cod/reconcile'),
      ]);
      setCollections(collectionResponse.data?.data ?? []);
      setRemittances(remittanceResponse.data?.data ?? []);
      setAudit(auditResponse.data?.data ?? []);
      setIssues(reconciliationResponse.data?.data?.issues ?? []);
    } catch (e: any) {
      setError(e?.response?.status === 403
        ? 'Your account does not have the approved finance.read grant.'
        : e?.response?.status === 503
          ? 'Synthetic COD finance is disabled for this API environment.'
          : 'COD finance data could not be loaded. Retry to read current server state.');
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function review(item: Remittance, decision: 'verify' | 'dispute' | 'reject') {
    const note = (reason[item.id] ?? '').trim();
    if (note.length < 5 || busy) return;
    setBusy(item.id); setError(null);
    try {
      await api.post(`/admin/cod/remittances/${item.id}/review`, { decision, reason: note });
      setReason((current) => ({ ...current, [item.id]: '' }));
      await load();
    } catch (e: any) {
      setError(e?.response?.data?.error?.message ?? 'Finance review was not accepted. Refresh before retrying.');
    } finally { setBusy(null); }
  }

  const money = (minor: number) => `₹${(minor / 100).toFixed(2)}`;
  const card = 'rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-sm';
  return <section className="space-y-5" aria-label="COD finance operations">
    <header className="flex flex-wrap items-start justify-between gap-3">
      <div><p className="text-xs font-bold uppercase tracking-[.14em] text-[#0F766E]">Synthetic QA only</p><h1 className="mt-1 text-2xl font-bold text-[#172033]">COD cash accountability</h1><p className="mt-1 text-sm text-[#667085]">Collections, rider remittance claims, reconciliation exceptions and immutable review history.</p></div>
      <button onClick={() => void load()} disabled={loading} className="min-h-11 rounded-xl border border-[#D0D5DD] px-4 text-sm font-semibold text-[#344054] disabled:opacity-50">{loading ? 'Refreshing…' : 'Refresh data'}</button>
    </header>
    <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950">No physical cash is handled here. Submitted remittances are claims until finance verifies them. Rider cash liabilities are separate from earnings; payouts, COD production mode and merchant settlements are disabled.</div>
    {error && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">{error}</div>}
    {loading ? <div className={card}>Loading finance records…</div> : error && !collections.length && !remittances.length ? null : <>
      <div className="grid gap-4 lg:grid-cols-2">
        <div className={card}><h2 className="font-bold">Synthetic collections</h2><div className="mt-4 overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr className="border-b text-xs text-[#667085]"><th className="pb-2">Order</th><th className="pb-2">Rider</th><th className="pb-2">Amount</th><th className="pb-2">Journal</th></tr></thead><tbody>{collections.map((c) => <tr key={c.id} className="border-b last:border-0"><td className="py-3 font-semibold">{c.reference_code}</td><td>{c.rider_name}</td><td>{money(c.amount_minor)}</td><td className="max-w-28 truncate font-mono text-xs">{c.financial_journal_id}</td></tr>)}</tbody></table>{collections.length === 0 && <p className="py-4 text-sm text-[#667085]">No synthetic COD collections recorded.</p>}</div></div>
        <div className={card}><h2 className="font-bold">Rider remittances</h2><div className="mt-4 space-y-3">{remittances.map((r) => <article key={r.id} className="rounded-xl border border-[#EAECF0] p-4"><div className="flex flex-wrap justify-between gap-2"><div><p className="font-semibold">{r.rider_name} · {money(r.amount_minor)}</p><p className="text-xs text-[#667085]">{r.submission_reference} · {r.submitted_at}</p></div><span className="h-fit rounded-full bg-[#F2F4F7] px-3 py-1 text-xs font-semibold capitalize">{r.state}</span></div>{r.state === 'submitted' && <><textarea aria-label={`Review reason for ${r.submission_reference}`} value={reason[r.id] ?? ''} onChange={(e) => setReason((current) => ({ ...current, [r.id]: e.target.value }))} maxLength={300} rows={2} className="mt-3 min-h-16 w-full rounded-lg border border-[#D0D5DD] p-2 text-sm" placeholder="Required finance review reason (5–300 characters)"/><div className="mt-2 flex flex-wrap gap-2">{(['verify','dispute','reject'] as const).map((action) => <button key={action} onClick={() => void review(r, action)} disabled={busy === r.id || (reason[r.id]?.trim().length ?? 0) < 5} className={`min-h-10 rounded-lg px-3 text-xs font-bold capitalize disabled:opacity-50 ${action === 'verify' ? 'bg-[#2457D6] text-white' : 'border border-[#D0D5DD] text-[#344054]'}`}>{busy === r.id ? 'Saving…' : action}</button>)}</div></>}</article>)}{remittances.length === 0 && <p className="py-4 text-sm text-[#667085]">No remittance submissions.</p>}</div></div>
      </div>
      <div className={card}><h2 className="font-bold">Reconciliation exceptions</h2><p className="mt-1 text-xs text-[#667085]">Read-only detection. This view never repairs financial records automatically.</p>{issues.length ? <ul className="mt-3 space-y-2">{issues.map((issue, i) => <li key={`${String(issue.issue)}-${i}`} className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm"><strong>{String(issue.issue).replaceAll('_',' ')}</strong> · {String(issue.reference_code ?? issue.order_id ?? 'Reference unavailable')}</li>)}</ul> : <p className="mt-3 text-sm text-emerald-700">No reconciliation exceptions detected.</p>}</div>
      <details className={card}><summary className="cursor-pointer font-bold">Audit history ({audit.length})</summary><div className="mt-3 max-h-80 space-y-2 overflow-auto">{audit.map((event, i) => <div key={String(event.id ?? i)} className="border-b py-2 text-xs"><strong>{String(event.event_type)}</strong> · {String(event.reason)} · {String(event.created_at)}</div>)}</div></details>
    </>}
  </section>;
}
