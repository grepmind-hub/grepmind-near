import Link from 'next/link';
import { orderReferencePattern } from '@/lib/finance-display';

export type FinanceReturn = 'finance-overview' | 'cod-finance' | 'merchant-finance' | 'reconciliation-queue';

export function FinanceOrderLink({ reference, orderId, from, refundStatus }: {
  reference?: string | null;
  orderId?: string | null;
  from: FinanceReturn;
  refundStatus?: string;
}) {
  const key = [reference, orderId].find((value) => value && orderReferencePattern.test(value));
  if (!key) return <span>Reference unavailable</span>;
  const query = new URLSearchParams({ from });
  if (refundStatus) query.set('refund_status', refundStatus);
  return <Link
    className="break-all font-semibold text-[#2457D6] underline decoration-blue-200 underline-offset-2 hover:decoration-current"
    href={`/dashboard/payment-tracking/${encodeURIComponent(key)}?${query}`}
  >{key === reference ? reference : 'View order by ID'}</Link>;
}
