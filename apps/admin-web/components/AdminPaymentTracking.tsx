'use client';

import { isAxiosError } from 'axios';
import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react';
import { api } from '@/lib/api';
import type { RelatedAttempt } from '@/components/AdminReconciliationQueue';
import { financeAmount, financeStatus as label, orderReferencePattern, paymentClassification } from '@/lib/finance-display';

type Amount = { amount_minor: number; currency: string };
type Tracking = {
  order: Amount & { id: string; reference_code: string; status: string; payment_status: string; payment_method: string | null };
  intent: (Amount & { id: string; status: string }) | null;
  attempts: (Amount & { id: string; attempt_number: number; provider: string; status: string; capture_posted?: boolean; updated_at: string })[];
  reconciliation: { id: string; attempt_id: string; attempt_number: number; outcome: string; provider_status: string | null; created_at: string }[];
  refunds?: (Amount & { id: string; attempt_number: number; provider: string; status: string; created_at: string })[];
  more_refunds?: boolean;
  more_attempts: boolean;
  more_reconciliation_events: boolean;
};

type Lookup =
  | { kind: 'idle' | 'loading' }
  | { kind: 'error'; message: string }
  | { kind: 'success'; data: Tracking };

const card = 'min-w-0 rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-sm';
const date = (value: string) => new Date(value).toLocaleString();
const money = (value: Amount) =>
  financeAmount(value.amount_minor, value.currency);

function HistoryTable({
  title, columns, rows, empty, truncated,
}: {
  title: string;
  columns: string[];
  rows: { id: string; cells: ReactNode[] }[];
  empty: string;
  truncated: boolean;
}) {
  return <section aria-label={title} className={card}>
    <h2 className="font-bold text-[#172033]">{title}</h2>
    {rows.length > 0 ? (
      <div className="mt-4 overflow-x-auto">
        <table aria-label={title} className="w-full text-left text-sm text-[#344054]">
          <thead>
            <tr className="border-b border-[#E4E7EC] text-xs text-[#667085]">
              {columns.map((column) => <th key={column} scope="col" className="whitespace-nowrap p-2">{column}</th>)}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.id} className="border-b border-[#EAECF0] last:border-0">
                {row.cells.map((cell, index) => <td key={columns[index]} className="px-2 py-3">{cell}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    ) : <p className="mt-3 text-sm text-[#667085]">{empty}</p>}
    {truncated && <p className="mt-3 text-sm text-[#667085]">Showing the {rows.length} most recent records.</p>}
  </section>;
}

async function lookupOrder(reference: string, signal: AbortSignal): Promise<Lookup> {
  try {
    const response = await api.get<{ data: Tracking }>(`/admin/payments/orders/${encodeURIComponent(reference)}`, { signal });
    return { kind: 'success', data: response.data.data };
  } catch (error: unknown) {
    const status = isAxiosError(error) ? error.response?.status : undefined;
    let message = 'Payment tracking could not be loaded. Try again.';
    if (status === 403) message = 'Active Platform Admin access is required.';
    if (status === 404) message = 'No order matches that reference.';
    if (status === 400) message = 'Enter a valid order reference or UUID.';
    return { kind: 'error', message };
  }
}

export function AdminPaymentTracking({ initialReference = '', onViewHistory }: {
  initialReference?: string;
  onViewHistory: (attempt: RelatedAttempt | undefined, order: string) => void;
}) {
  const [query, setQuery] = useState(initialReference);
  const [lookup, setLookup] = useState<Lookup>({ kind: initialReference ? 'loading' : 'idle' });
  const requestRef = useRef<AbortController | null>(null);

  const load = useCallback((reference: string) => {
    requestRef.current?.abort();
    const request = new AbortController();
    requestRef.current = request;
    void lookupOrder(reference, request.signal).then((result) => {
      if (!request.signal.aborted) setLookup(result);
    });
  }, []);

  useEffect(() => {
    if (initialReference) load(initialReference);
    return () => requestRef.current?.abort();
  }, [initialReference, load]);

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const reference = query.trim();
    if (!orderReferencePattern.test(reference)) {
      requestRef.current?.abort();
      setLookup({ kind: 'error', message: 'Enter a valid order reference or UUID.' });
      return;
    }
    setLookup({ kind: 'loading' });
    load(reference);
  }

  const data = lookup.kind === 'success' ? lookup.data : null;

  const historyButton = (attempt: { id: string; attempt_number: number }, order: Tracking['order']) =>
    <button type="button" className="min-h-11 text-left font-semibold text-[#2457D6] underline underline-offset-2"
      onClick={() => onViewHistory({ attempt_id: attempt.id, attempt_number: attempt.attempt_number, reference_code: order.reference_code }, order.id)}>
      History for attempt #{attempt.attempt_number}
    </button>;

  return <div className="min-w-0 space-y-5">
    <h1 className="text-2xl font-bold text-[#172033]">Payment tracking</h1>
    <form onSubmit={submit} className={`flex flex-wrap items-end gap-3 ${card}`}>
      <label className="min-w-0 flex-1 text-sm font-semibold text-[#344054]">
        Order reference or UUID
        <input
          className="mt-2 min-h-11 w-full rounded-xl border border-[#D0D5DD] px-3 font-normal"
          type="text" maxLength={64} required value={query} autoComplete="off"
          onChange={(event) => setQuery(event.target.value)}
        />
      </label>
      <button type="submit" className="min-h-11 rounded-xl bg-[#2457D6] px-4 text-sm font-semibold text-white disabled:opacity-60" disabled={lookup.kind === 'loading'}>
        Look up order
      </button>
    </form>
    {lookup.kind === 'idle' && <p className="text-sm text-[#667085]">Enter an exact order reference or UUID to view its payment records.</p>}
    {lookup.kind === 'loading' && <p role="status" className="text-sm text-[#667085]">Loading payment history…</p>}
    {lookup.kind === 'error' && <p role="alert" className="rounded-xl bg-rose-50 p-4 text-sm text-rose-800">{lookup.message}</p>}
    {data && <>
      <section aria-label="Order payment summary" className={card}>
        <h2 className="font-bold text-[#172033]">{data.order.reference_code}</h2>
        <dl className="mt-4 grid grid-cols-2 gap-4 text-sm sm:grid-cols-3 lg:grid-cols-5">
          {[
            ['Order total', money(data.order)],
            ['Order status', label(data.order.status)],
            ['Payment status', label(data.order.payment_status)],
            ['Payment method', label(data.order.payment_method)],
            ['Payment intent', data.intent ? label(data.intent.status) : 'None recorded'],
          ].map(([name, value]) => <div key={name}><dt className="text-[#667085]">{name}</dt><dd className="mt-1 font-semibold text-[#172033]">{value}</dd></div>)}
        </dl>
      </section>
      <HistoryTable
        title="Payment attempts" columns={['Attempt', 'Provider', 'Amount', 'Status', 'Sandbox capture', 'Updated', 'History']}
        rows={data.attempts.map((attempt) => ({
          id: attempt.id,
          cells: [
            <div key="identity"><strong>#{attempt.attempt_number}</strong><code className="mt-1 block max-w-40 break-all text-xs text-[#667085]">{attempt.id}</code></div>,
            <div key="provider">{label(attempt.provider)}<span className="block text-xs text-[#667085]">{paymentClassification(attempt.provider)}</span></div>,
            money(attempt), label(attempt.status),
            attempt.capture_posted ? 'Posted' : attempt.provider === 'grepmind_sandbox' && attempt.capture_posted === false ? 'No posted capture' : 'Unavailable',
            date(attempt.updated_at), historyButton(attempt, data.order),
          ],
        }))}
        empty="No payment attempts recorded for this order." truncated={data.more_attempts}
      />
      <HistoryTable
        title="Refunds" columns={['Attempt', 'Amount', 'Status', 'Classification', 'Requested']}
        rows={(data.refunds ?? []).map((refund) => ({
          id: refund.id,
          cells: [`#${refund.attempt_number}`, money(refund), label(refund.status), paymentClassification(refund.provider), date(refund.created_at)],
        }))}
        empty={data.refunds ? 'No refunds recorded for this order.' : 'Refund records are unavailable.'} truncated={Boolean(data.more_refunds)}
      />
      <HistoryTable
        title="Reconciliation history" columns={['Attempt', 'Outcome', 'Provider status', 'Recorded', 'History']}
        rows={data.reconciliation.map((event) => ({
          id: event.id,
          cells: [`#${event.attempt_number}`, label(event.outcome), label(event.provider_status), date(event.created_at),
            historyButton({ id: event.attempt_id, attempt_number: event.attempt_number }, data.order)],
        }))}
        empty="No reconciliation events recorded for this order." truncated={data.more_reconciliation_events}
      />
      <button type="button" className="min-h-11 rounded-xl border border-[#D0D5DD] bg-white px-4 text-sm font-semibold text-[#2457D6]"
        onClick={() => onViewHistory(undefined, data.order.id)}>Open reconciliation queue</button>
    </>}
  </div>;
}
