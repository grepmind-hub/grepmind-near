'use client';

import { isAxiosError } from 'axios';
import Link from 'next/link';
import { useEffect, useState, type FormEvent } from 'react';
import { api } from '@/lib/api';

type View = 'needs_action' | 'history';
type Entry = {
  id: string;
  order_id: string;
  reference_code: string;
  attempt_id: string;
  attempt_number: number;
  attempt_status: string;
  outcome: string | null;
  amount_minor: number;
  currency: string;
  recorded_at: string;
  actor_id?: string;
  actor_name?: string;
};
export type RelatedAttempt = Pick<Entry, 'attempt_id' | 'attempt_number' | 'reference_code'>;
type Filters = { status: string; outcome: string; reference: string; from: string; to: string };
type Selection = { view: View; filters: Filters; cursors: string[]; related?: RelatedAttempt };
type Queue = { data: Entry[]; meta: { next_cursor?: string } };
type Result = { request: Selection; data: Queue } | { request: Selection; error: string };

const emptyFilters: Filters = { status: '', outcome: '', reference: '', from: '', to: '' };
const statuses = ['initialized', 'session_created', 'pending', 'succeeded', 'failed', 'expired', 'reconciliation_required'];
const outcomes = ['matched', 'missing_webhook', 'late_success', 'amount_mismatch', 'currency_mismatch', 'unknown_reference', 'provider_unavailable'];
const inputClass = 'min-h-11 w-full rounded-xl border border-[#D0D5DD] bg-white px-3 text-[#344054]';
const buttonClass = 'min-h-11 rounded-xl border border-[#D0D5DD] bg-white px-4 text-sm font-semibold text-[#2457D6] disabled:opacity-60';
const label = (value: string) => value.replaceAll('_', ' ');
const amount = (row: Entry) => new Intl.NumberFormat('en-IN', {
  style: 'currency', currency: row.currency,
}).format(row.amount_minor / 100);

export function AdminReconciliationQueue({ onExit, initialRelated }: { onExit: () => void; initialRelated?: RelatedAttempt }) {
  const [selection, setSelection] = useState<Selection>({
    view: initialRelated ? 'history' : 'needs_action', filters: emptyFilters, cursors: [''], related: initialRelated,
  });
  const [draft, setDraft] = useState(emptyFilters);
  const [result, setResult] = useState<Result>();
  const current = result?.request === selection ? result : undefined;
  const queue = current && 'data' in current ? current.data : undefined;
  const history = selection.view === 'history';
  const title = history ? 'Recorded history' : 'Needs action';

  useEffect(() => {
    const controller = new AbortController();
    const params = new URLSearchParams({ view: selection.view });
    for (const [name, value] of Object.entries(selection.filters)) {
      if (value) params.set(name, value);
    }
    const before = selection.cursors.at(-1);
    if (before) params.set('before', before);
    if (selection.related) params.set('attempt_id', selection.related.attempt_id);
    void api.get<Queue>('/admin/payments/reconciliation-queue', {
      params, signal: controller.signal,
    }).then(({ data }) => {
      if (!controller.signal.aborted) setResult({ request: selection, data });
    }).catch((error: unknown) => {
      if (controller.signal.aborted) return;
      const status = isAxiosError(error) ? error.response?.status : undefined;
      const message = status === 403
        ? 'Active Platform Admin access is required.'
        : status === 400
          ? 'Check the selected filters and date range.'
          : 'The reconciliation queue could not be loaded. Refresh to try again.';
      setResult({ request: selection, error: message });
    });
    return () => controller.abort();
  }, [selection]);

  function changeView(view: View, related?: RelatedAttempt) {
    setDraft(emptyFilters);
    setSelection({ view, filters: emptyFilters, cursors: [''], related });
  }

  function applyFilters(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSelection({ ...selection, filters: { ...draft, reference: draft.reference.trim() }, cursors: [''] });
  }

  return <section className="min-w-0 space-y-4" aria-label="Payment reconciliation queue">
    <button type="button" onClick={onExit} className={`${buttonClass} xl:hidden`}>Back to Admin dashboard</button>
    <header className="flex flex-wrap items-center justify-between gap-3">
      <h1 className="text-2xl font-bold text-[#172033]">Payment reconciliation queue</h1>
      <button type="button" onClick={() => setSelection({ ...selection, cursors: [''] })} className={buttonClass}>Refresh queue</button>
    </header>
    <nav className="flex flex-wrap gap-2" aria-label="Reconciliation views">
      {(['needs_action', 'history'] as const).map((view) => (
        <button type="button" key={view} aria-pressed={selection.view === view} onClick={() => changeView(view)}
          className={`${buttonClass} aria-pressed:border-[#2457D6] aria-pressed:bg-blue-50`}>
          {view === 'needs_action' ? 'Needs action' : 'Recorded history'}
        </button>
      ))}
    </nav>
    {selection.related && <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-blue-50 px-4 py-2 text-sm text-[#172033]">
      <p>History for <strong>{selection.related.reference_code} · attempt #{selection.related.attempt_number}</strong></p>
      <button type="button" onClick={() => changeView('history')} className={buttonClass}>Show all history</button>
    </div>}
    <form onSubmit={applyFilters} className="grid grid-cols-2 gap-3 rounded-2xl border border-[#E4E7EC] bg-white p-4 xl:grid-cols-3">
      <label className="col-span-2 min-w-0 text-sm font-medium sm:col-span-1">Order reference or UUID
        <input className={inputClass} maxLength={64} value={draft.reference}
          onChange={(event) => setDraft({ ...draft, reference: event.target.value })} />
      </label>
      {history && <label className="min-w-0 text-sm font-medium">Attempt status
        <select className={inputClass} value={draft.status} onChange={(event) => setDraft({ ...draft, status: event.target.value })}>
          <option value="">All statuses</option>
          {statuses.map((status) => <option key={status} value={status}>{label(status)}</option>)}
        </select>
      </label>}
      <label className="min-w-0 text-sm font-medium">Outcome
        <select className={inputClass} value={draft.outcome} onChange={(event) => setDraft({ ...draft, outcome: event.target.value })}>
          <option value="">All outcomes</option>
          {outcomes.filter((outcome) => history || outcome !== 'matched').map((outcome) => (
            <option key={outcome} value={outcome}>{label(outcome)}</option>
          ))}
        </select>
      </label>
      <label className="min-w-0 text-sm font-medium">From date (UTC)
        <input type="date" className={inputClass} value={draft.from} onChange={(event) => setDraft({ ...draft, from: event.target.value })} />
      </label>
      <label className="min-w-0 text-sm font-medium">To date (UTC)
        <input type="date" className={inputClass} value={draft.to} min={draft.from || undefined}
          onChange={(event) => setDraft({ ...draft, to: event.target.value })} />
      </label>
      <div className="col-span-2 flex flex-wrap items-end gap-2 sm:col-span-1">
        <button type="submit" className={buttonClass}>Apply filters</button>
        <button type="button" className={buttonClass} onClick={() => {
          setDraft(emptyFilters);
          setSelection({ ...selection, filters: emptyFilters, cursors: [''] });
        }}>Clear filters</button>
      </div>
    </form>
    <h2 className="font-bold text-[#172033]">{title}</h2>
    {!current && <p role="status" className="text-sm text-[#667085]">Loading reconciliation records…</p>}
    {current && 'error' in current && <p role="alert" className="rounded-xl bg-rose-50 p-4 text-sm text-rose-800">{current.error}</p>}
    {queue && <div className="min-w-0 rounded-2xl border border-[#E4E7EC] bg-white p-4 shadow-sm">
      {queue.data.length === 0 ? (
        <p className="text-sm text-[#667085]">{history ? 'No recorded events match these filters.' : 'No attempts requiring reconciliation match these filters.'}</p>
      ) : <div className="overflow-x-auto" tabIndex={0} role="region" aria-label={`${title} table scroll area`}>
        <table aria-label={title} className="w-full text-left text-sm text-[#344054]">
          <thead>
            <tr className="border-b border-[#E4E7EC] text-xs text-[#667085]">
              {['Order', 'Outcome', 'Current attempt status', 'Amount', 'Recorded', ...(history ? ['Actor'] : ['History'])].map((column) => (
                <th key={column} scope="col" className="px-2 pb-2">{column}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {queue.data.map((row) => (
              <tr key={row.id} className="border-b border-[#EAECF0] last:border-0">
                <td className="px-2 py-3">
                  <Link className="inline-flex min-h-11 items-center whitespace-nowrap font-semibold text-[#2457D6] hover:underline"
                    href={`/dashboard/payment-tracking/${encodeURIComponent(row.order_id)}`}>
                    {row.reference_code}
                  </Link>
                  <span className="block text-xs text-[#667085]">Attempt #{row.attempt_number}</span>
                </td>
                <td className="px-2 py-3">{row.outcome ? label(row.outcome) : '—'}</td>
                <td className="px-2 py-3">{label(row.attempt_status)}</td>
                <td className="whitespace-nowrap px-2 py-3">{amount(row)}</td>
                <td className="px-2 py-3"><time dateTime={row.recorded_at}>{new Date(row.recorded_at).toLocaleString()}</time></td>
                <td className="px-2 py-3">{history ? (
                  row.actor_name ?? row.actor_id ?? '—'
                ) : <button type="button" className={buttonClass} onClick={() => changeView('history', row)}>View history</button>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>}
    </div>}
    <nav className="flex flex-wrap items-center gap-3" aria-label="Reconciliation pagination">
      <button type="button" className={buttonClass} disabled={selection.cursors.length === 1}
        onClick={() => setSelection({ ...selection, cursors: selection.cursors.slice(0, -1) })}>Previous page</button>
      <span className="text-sm text-[#667085]">Page {selection.cursors.length}</span>
      <button type="button" className={buttonClass} disabled={!queue?.meta.next_cursor}
        onClick={() => {
          const cursor = queue?.meta.next_cursor;
          if (cursor) setSelection({ ...selection, cursors: [...selection.cursors, cursor] });
        }}>Next page</button>
    </nav>
  </section>;
}
