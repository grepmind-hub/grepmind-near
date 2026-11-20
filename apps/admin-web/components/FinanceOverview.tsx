'use client';

import { isAxiosError } from 'axios';
import { useEffect, useId, useState, type ReactNode } from 'react';
import { api } from '@/lib/api';
import { FinanceOrderLink } from '@/components/FinanceOrderLink';
import { financeAmount as money, financeStatus as label, paymentClassification, refundStatuses, settlementClassification } from '@/lib/finance-display';
import type { AdminTab } from '@/components/AdminSidebar';

type FinanceRow = { id: string; currency: string };
type Refund = FinanceRow & { order_id: string; reference_code?: string; provider?: string; amount_minor: number; status: string };
type Payable = FinanceRow & { order_id?: string; reference_code: string; merchant_name: string; net_payable_minor: number; payment_source: string };
type Remittance = FinanceRow & { submission_reference: string; rider_name: string; amount_minor: number; state: string; sandbox_verified?: boolean };
type Settlement = FinanceRow & { merchant_name: string; simulated_net_minor: number; status: string; funding_mode?: string; simulated_at?: string | null };

type SectionState<Row> =
  | { kind: 'error'; message: string }
  | { kind: 'ready'; rows: Row[] };

function FinanceSection<Row extends FinanceRow>({
  title, path, empty, columns, cells, controls, limit, refresh,
}: {
  title: string;
  path: string;
  empty: string;
  columns: string[];
  cells: (row: Row) => ReactNode[];
  controls?: ReactNode;
  limit: number;
  refresh: number;
}) {
  const headingId = useId();
  const [result, setResult] = useState<{ path: string; refresh: number; state: SectionState<Row> }>();
  const state = result?.path === path && result.refresh === refresh ? result.state : { kind: 'loading' } as const;

  useEffect(() => {
    const request = new AbortController();
    const publish = (state: SectionState<Row>) => {
      if (!request.signal.aborted) setResult({ path, refresh, state });
    };
    void api.get<{ data: Row[] | null }>(path, { signal: request.signal })
      .then(({ data }) => {
        if (data?.data !== null && !Array.isArray(data?.data)) {
          publish({ kind: 'error', message: 'The server returned an unexpected response. Refresh to try again.' });
          return;
        }
        publish({ kind: 'ready', rows: data.data ?? [] });
      })
      .catch((error: unknown) => {
        if (request.signal.aborted) return;
        const status = isAxiosError(error) ? error.response?.status : undefined;
        const message = status === 403
          ? 'Active Platform Admin access is required.'
          : status === 503
            ? 'These records are unavailable in this environment.'
            : 'These records could not be loaded. Refresh to try again.';
        publish({ kind: 'error', message });
      });
    return () => request.abort();
  }, [path, refresh]);

  return (
    <section aria-labelledby={headingId} className="min-w-0 rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-sm">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <h2 id={headingId} className="font-bold text-[#172033]">{title}</h2>
        {controls}
      </div>
      {state.kind === 'loading' && <p role="status" className="text-sm text-[#667085]">Loading {title.toLowerCase()}…</p>}
      {state.kind === 'error' && <p role="alert" className="text-sm text-rose-800">{state.message}</p>}
      {state.kind === 'ready' && (state.rows.length === 0
        ? <p className="text-sm text-[#667085]">{empty}</p>
        : <>
          <div className="overflow-x-auto">
            <table aria-labelledby={headingId} className="w-full text-left text-sm">
              <thead className="border-b border-[#E4E7EC] text-xs text-[#667085]">
                <tr>{columns.map((column) => <th key={column} scope="col" className="whitespace-nowrap px-2 pb-2">{column}</th>)}</tr>
              </thead>
              <tbody>{state.rows.slice(0, limit).map((row) => (
                <tr key={row.id} className="border-b border-[#EAECF0] last:border-0">
                  {cells(row).map((cell, index) => <td key={columns[index]} className="px-2 py-3 align-top text-[#344054]">{cell}</td>)}
                </tr>
              ))}</tbody>
            </table>
          </div>
          {state.rows.length >= limit && <p className="mt-3 text-xs text-[#667085]">Showing up to {limit} records.</p>}
        </>)}
    </section>
  );
}

export function FinanceOverview({ onSelectTab, refundStatus, onRefundStatusChange }: {
  onSelectTab: (tab: AdminTab) => void;
  refundStatus: string;
  onRefundStatusChange: (value: string) => void;
}) {
  const [refresh, setRefresh] = useState(0);
  const buttonClass = 'min-h-11 rounded-xl border border-[#D0D5DD] px-3 text-sm font-semibold text-[#2457D6] hover:bg-blue-50';
  const status = (value: string) => <span className="inline-block rounded-full bg-[#F2F4F7] px-2 py-1 text-xs font-semibold ">{label(value)}</span>;

  return (
    <div className="space-y-5">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl font-bold text-[#172033]">Finance overview</h1>
        <button type="button" className={`${buttonClass} xl:hidden`} onClick={() => onSelectTab('overview')}>Back to Admin dashboard</button>
        <button type="button" className={buttonClass} onClick={() => setRefresh((value) => value + 1)}>Refresh finance data</button>
      </header>
      <p className="text-sm text-[#475467]">Recent recorded activity by finance workflow. Open an order to review its individual payment attempts, refunds and reconciliation events.</p>
      <div className="grid gap-4 2xl:grid-cols-2">
        <FinanceSection<Refund>
          title="Refunds" path={`/admin/payments/refunds?status=${refundStatus}&limit=10`}
          empty="No refunds with this status." columns={['Order', 'Amount', 'Status', 'Classification']}
          cells={(row) => [<FinanceOrderLink key="order" reference={row.reference_code} orderId={row.order_id} from="finance-overview" refundStatus={refundStatus} />, money(row.amount_minor, row.currency), status(row.status), paymentClassification(row.provider)]}
          refresh={refresh} limit={10}
          controls={<label className="flex items-center gap-2 text-sm text-[#344054]">Refund status
            <select value={refundStatus} onChange={(event) => onRefundStatusChange(event.target.value)} className="min-h-11 rounded-xl border border-[#D0D5DD] bg-white px-2">
              {refundStatuses.map((value) => <option key={value} value={value}>{label(value)}</option>)}
            </select>
          </label>}
        />
        <FinanceSection<Payable>
          title="Posted merchant payables" path="/admin/finance/payables?limit=10"
          empty="No posted merchant payables." columns={['Order', 'Merchant', 'Net payable', 'Payment source', 'Classification']}
          cells={(row) => [<FinanceOrderLink key="order" reference={row.reference_code} orderId={row.order_id} from="finance-overview" refundStatus={refundStatus} />,
            row.merchant_name, money(row.net_payable_minor, row.currency), status(row.payment_source),
            ['sandbox_upi_capture', 'synthetic_cod_collection'].includes(row.payment_source) ? 'Sandbox' : 'Classification unavailable']}
          refresh={refresh} limit={10}
          controls={<button type="button" className={buttonClass} onClick={() => onSelectTab('merchant-finance')}>Open merchant payables</button>}
        />
        <FinanceSection<Remittance>
          title="COD remittances" path="/admin/cod/remittances"
          empty="No COD remittances recorded." columns={['Reference', 'Rider', 'Amount', 'Status', 'Classification']}
          cells={(row) => [row.submission_reference, row.rider_name, money(row.amount_minor, row.currency), status(row.state), row.sandbox_verified ? 'Sandbox' : 'Classification unavailable']}
          refresh={refresh} limit={10}
          controls={<button type="button" className={buttonClass} onClick={() => onSelectTab('cod-finance')}>Open COD accountability</button>}
        />
        <FinanceSection<Settlement>
          title="Merchant settlement simulations" path="/admin/finance/settlements"
          empty="No merchant settlement batches." columns={['Merchant', 'Net amount', 'Status', 'Classification']}
          cells={(row) => [row.merchant_name, money(row.simulated_net_minor, row.currency), status(row.status), settlementClassification(row.funding_mode, row.simulated_at)]}
          refresh={refresh} limit={10}
          controls={<button type="button" className={buttonClass} onClick={() => onSelectTab('merchant-finance')}>Open merchant settlements</button>}
        />
      </div>
    </div>
  );
}
