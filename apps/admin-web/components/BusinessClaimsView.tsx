'use client';

import { useState, type FormEvent } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { BusinessClaim } from '@/lib/api';
import { Check, ClipboardCheck, RefreshCw, ShieldAlert, X } from 'lucide-react';

interface BusinessClaimsViewProps {
  claims: BusinessClaim[];
  isLoading: boolean;
  error: string | null;
  actionId: string | null;
  onRetry: () => void;
  onDecision: (claim: BusinessClaim, decision: 'approve' | 'reject', note: string) => Promise<void>;
}

export function BusinessClaimsView({ claims, isLoading, error, actionId, onRetry, onDecision }: BusinessClaimsViewProps) {
  const [decision, setDecision] = useState<{ claim: BusinessClaim; kind: 'approve' | 'reject' } | null>(null);
  const [note, setNote] = useState('');
  const [submitting, setSubmitting] = useState(false);

  async function submitDecision(event: FormEvent) {
    event.preventDefault();
    if (!decision || note.trim().length < (decision.kind === 'approve' ? 10 : 5)) return;
    setSubmitting(true);
    try {
      await onDecision(decision.claim, decision.kind, note.trim());
      setDecision(null);
      setNote('');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="space-y-6 pb-10">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[.16em] text-[#6D4AFF]">Trust & ownership</p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#172033] md:text-3xl">Ownership claims</h1>
          <p className="mt-1 text-sm text-[#667085]">Review claimant details and evidence before transferring a listing.</p>
        </div>
        <div className="flex items-center gap-2 rounded-2xl border border-violet-100 bg-gradient-to-br from-violet-50 to-white px-4 py-3 shadow-sm">
          <ClipboardCheck className="h-5 w-5 text-violet-600" />
          <div><div className="text-xl font-bold text-[#172033]">{claims.length}</div><div className="text-[11px] text-[#667085]">pending review</div></div>
        </div>
      </header>

      <div className="overflow-hidden rounded-3xl border border-[#E3E8F4] bg-white shadow-[0_20px_60px_-40px_rgba(23,32,51,.35)]">
        <div className="flex items-start gap-3 border-b border-violet-100 bg-gradient-to-r from-violet-50 via-white to-blue-50 px-5 py-4">
          <div className="rounded-xl bg-violet-600 p-2 text-white shadow-lg shadow-violet-200"><ShieldAlert className="h-4 w-4" /></div>
          <div><h2 className="font-semibold text-[#172033]">Transfer review queue</h2><p className="text-xs text-[#667085]">Approval updates business ownership and records the decision in the audit trail.</p></div>
        </div>
        <div className="p-5">
          {error ? <div role="alert" className="rounded-2xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">{error}<button onClick={onRetry} className="ml-2 inline-flex min-h-10 items-center gap-1 font-semibold underline"><RefreshCw className="h-3.5 w-3.5" />Retry</button></div> : null}
          {!error && isLoading ? <div className="animate-pulse rounded-2xl bg-slate-100 p-8 text-center text-sm text-slate-500">Loading claim records…</div> : null}
          {!error && !isLoading && claims.length === 0 ? <div className="rounded-2xl border border-dashed border-[#CBD5E1] bg-slate-50/70 px-6 py-12 text-center"><div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-emerald-100 text-emerald-700"><Check className="h-6 w-6" /></div><h3 className="mt-3 font-semibold text-[#172033]">All caught up</h3><p className="mt-1 text-sm text-[#667085]">There are no pending ownership requests.</p></div> : null}
          {!error && !isLoading && claims.length > 0 ? <div className="space-y-3">{claims.map((claim) => <article key={claim.id} className="rounded-2xl border border-[#E5EAF3] bg-white p-4 transition hover:border-violet-200 hover:shadow-md"><div className="flex flex-col justify-between gap-4 xl:flex-row xl:items-start"><div className="min-w-0 flex-1"><div className="flex flex-wrap items-center gap-2"><h3 className="text-base font-semibold text-[#172033]">{claim.business_name}</h3><Badge variant="outline" className="border-blue-100 bg-blue-50 text-blue-700">{claim.category}</Badge><Badge variant="outline" className="border-teal-100 bg-teal-50 text-teal-700">{claim.city}</Badge></div><p className="mt-1 text-sm text-[#667085]">{claim.address}{claim.locality ? ` · ${claim.locality}` : ''}</p><div className="mt-4 grid gap-3 rounded-xl bg-gradient-to-br from-slate-50 to-violet-50/50 p-4 sm:grid-cols-2"><div><div className="text-[10px] font-bold uppercase tracking-wider text-[#98A2B3]">Claimant</div><p className="mt-1 text-sm font-semibold text-[#344054]">{claim.claimant_name || 'Name not set'}</p><p className="text-xs text-[#667085]">{claim.claimant_phone}</p></div><div><div className="text-[10px] font-bold uppercase tracking-wider text-[#98A2B3]">Submitted</div><p className="mt-1 text-sm text-[#344054]">{new Date(claim.created_at).toLocaleString()}</p></div><div className="sm:col-span-2"><div className="text-[10px] font-bold uppercase tracking-wider text-[#98A2B3]">Claim statement</div><p className="mt-1 whitespace-pre-wrap text-sm leading-6 text-[#475467]">{claim.message}</p></div></div></div><div className="flex shrink-0 gap-2 xl:flex-col"><Button className="min-h-11 bg-gradient-to-r from-emerald-600 to-teal-600 text-white shadow-md shadow-emerald-100 hover:from-emerald-700 hover:to-teal-700" disabled={actionId === claim.id} onClick={() => { setDecision({ claim, kind: 'approve' }); setNote(''); }}><Check className="mr-1 h-4 w-4" />Approve transfer</Button><Button variant="outline" className="min-h-11 border-rose-200 text-rose-700 hover:bg-rose-50" disabled={actionId === claim.id} onClick={() => { setDecision({ claim, kind: 'reject' }); setNote(''); }}><X className="mr-1 h-4 w-4" />Reject claim</Button></div></div></article>)}</div> : null}
        </div>
      </div>

      {decision ? <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-sm"><form onSubmit={submitDecision} className="w-full max-w-lg rounded-3xl border border-white/70 bg-white p-6 shadow-2xl"><div className="flex items-start justify-between"><div><p className="text-xs font-semibold uppercase tracking-wider text-violet-600">{decision.kind === 'approve' ? 'Ownership transfer' : 'Claim review'}</p><h2 className="mt-1 text-xl font-bold text-[#172033]">{decision.kind === 'approve' ? 'Approve claim?' : 'Reject claim?'}</h2><p className="mt-1 text-sm text-[#667085]">{decision.claim.business_name}</p></div><button type="button" aria-label="Close review dialog" onClick={() => setDecision(null)} className="flex h-10 w-10 items-center justify-center rounded-xl text-slate-500 hover:bg-slate-100"><X className="h-5 w-5" /></button></div><label htmlFor="claim-note" className="mt-5 block text-sm font-semibold text-[#344054]">{decision.kind === 'approve' ? 'Evidence reviewed' : 'Reason for rejection'}</label><textarea id="claim-note" value={note} onChange={(event) => setNote(event.target.value)} minLength={decision.kind === 'approve' ? 10 : 5} maxLength={1000} required rows={4} className="mt-2 w-full rounded-2xl border border-slate-200 p-3 text-sm outline-none transition focus:border-violet-400 focus:ring-4 focus:ring-violet-100" placeholder={decision.kind === 'approve' ? 'Describe the identity and ownership evidence checked…' : 'Explain what is missing or invalid…'} /><div className="mt-5 flex justify-end gap-2"><Button type="button" variant="outline" onClick={() => setDecision(null)}>Cancel</Button><Button type="submit" disabled={submitting || note.trim().length < (decision.kind === 'approve' ? 10 : 5)} className={decision.kind === 'approve' ? 'bg-violet-600 hover:bg-violet-700' : 'bg-rose-600 hover:bg-rose-700'}>{submitting ? 'Saving…' : 'Confirm decision'}</Button></div></form></div> : null}
    </section>
  );
}
