'use client';

import { useCallback, useEffect, useState } from 'react';
import { api } from '@/lib/api';

type GrantRequest = {
  id: string;
  target_user_id: string;
  permission: 'finance.read' | 'finance.post';
  requested_by: string;
  reason: string;
  status: 'pending' | 'approved' | 'rejected';
  decided_by?: string;
  decision_reason?: string;
  created_at: string;
};

const card = 'rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-sm';

export function FinanceAccessGrantPanel() {
  const [rows, setRows] = useState<GrantRequest[]>([]);
  const [target, setTarget] = useState('');
  const [permission, setPermission] = useState<'finance.read' | 'finance.post'>('finance.read');
  const [reason, setReason] = useState('');
  const [decisionReasons, setDecisionReasons] = useState<Record<string, string>>({});
  const [error, setError] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [forbidden, setForbidden] = useState(false);

  const load = useCallback(async () => {
    try {
      const response = await api.get('/admin/finance/access-grants');
      setRows(response.data?.data ?? []);
      setForbidden(false);
      setError('');
    } catch (e: any) {
      setForbidden(e?.response?.status === 403);
      setError(e?.response?.data?.error?.message ?? 'Finance access requests could not be loaded.');
    }
  }, []);
  useEffect(() => { void load(); }, [load]);

  // This surface is for finance.configure actors only. Users with ordinary
  // finance.read/post access should not see an access-denied panel in Finance.
  if (forbidden) return null;

  async function submitRequest(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError(''); setNote('');
    try {
      await api.post('/admin/finance/access-grant-requests', { target_user_id: target.trim(), permission, reason: reason.trim() });
      setTarget(''); setReason(''); setNote('Request submitted. A different Finance administrator must approve it.');
      await load();
    } catch (e: any) { setError(e?.response?.data?.error?.message ?? 'Finance access request was not accepted.'); }
    finally { setBusy(false); }
  }

  async function decide(id: string, decision: 'approve' | 'reject') {
    const decision_reason = (decisionReasons[id] ?? '').trim();
    if (decision_reason.length < 10) { setError('Enter a decision reason of at least 10 characters.'); return; }
    setBusy(true); setError(''); setNote('');
    try {
      await api.post(`/admin/finance/access-grant-requests/${id}/decision`, { decision, reason: decision_reason });
      setNote(`Access request ${decision === 'approve' ? 'approved' : 'rejected'} and audited.`);
      await load();
    } catch (e: any) { setError(e?.response?.data?.error?.message ?? 'Finance access decision was not accepted.'); }
    finally { setBusy(false); }
  }

  return <article className={card}>
    <h2 className="font-bold">Finance access · two-person control</h2>
    <p className="mt-1 text-xs text-[#667085]">Only `finance.read` and `finance.post` can be requested here. The requester and approver must be different active Finance administrators. No `finance.configure` or `finance.reverse` grants can be issued from this panel.</p>
    {error && <p role="alert" className="mt-3 rounded-lg bg-rose-50 p-3 text-sm text-rose-800">{error}</p>}
    {note && <p role="status" className="mt-3 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-800">{note}</p>}
    {!forbidden && <form onSubmit={submitRequest} className="mt-4 grid gap-3 sm:grid-cols-3">
      <label className="text-xs font-semibold">Target Admin user ID<input required value={target} onChange={e=>setTarget(e.target.value)} className="mt-1 min-h-10 w-full rounded-lg border p-2" placeholder="UUID"/></label>
      <label className="text-xs font-semibold">Permission<select value={permission} onChange={e=>setPermission(e.target.value as 'finance.read'|'finance.post')} className="mt-1 min-h-10 w-full rounded-lg border bg-white p-2"><option value="finance.read">finance.read</option><option value="finance.post">finance.post</option></select></label>
      <label className="text-xs font-semibold">Request reason<input required minLength={10} maxLength={500} value={reason} onChange={e=>setReason(e.target.value)} className="mt-1 min-h-10 w-full rounded-lg border p-2" placeholder="Why is this access needed?"/></label>
      <button disabled={busy} className="min-h-10 rounded-[14px] bg-[#123D36] px-4 text-sm font-semibold text-white hover:bg-[#0c2924] disabled:opacity-50 sm:col-span-3">Submit access request</button>
    </form>}
    <div className="mt-4 space-y-3">
      {rows.map(row=><div key={row.id} className="rounded-xl border p-3">
        <div className="flex flex-wrap justify-between gap-2 text-sm"><strong>{row.permission} · {row.target_user_id}</strong><span className="rounded-full bg-slate-100 px-2 py-1 text-xs capitalize">{row.status}</span></div>
        <p className="mt-1 text-xs text-[#667085]">Requested by {row.requested_by} · {row.reason}</p>
        {row.status==='pending' && <div className="mt-2 flex flex-wrap gap-2"><input aria-label={`Decision reason ${row.id}`} minLength={10} maxLength={500} value={decisionReasons[row.id]??''} onChange={e=>setDecisionReasons({...decisionReasons,[row.id]:e.target.value})} className="min-h-9 min-w-64 flex-1 rounded-lg border p-2 text-xs" placeholder="Independent decision reason (10+ chars)"/>{(['approve','reject'] as const).map(action=><button key={action} disabled={busy||decisionReasons[row.id]?.trim().length<10} onClick={()=>void decide(row.id,action)} className="min-h-9 rounded-lg border px-3 text-xs font-bold disabled:opacity-50">{action}</button>)}</div>}
        {row.status!=='pending' && <p className="mt-1 text-xs text-[#667085]">Decided by {row.decided_by} · {row.decision_reason}</p>}
      </div>)}
      {!forbidden && rows.length===0 && <p className="text-sm text-[#667085]">No finance access requests.</p>}
    </div>
  </article>;
}
