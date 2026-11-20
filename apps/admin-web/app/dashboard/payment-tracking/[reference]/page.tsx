import { AdminPortalClient } from '@/components/AdminPortalClient';
import { refundStatuses } from '@/lib/finance-display';

export default async function PaymentTrackingRoute({ params, searchParams }: {
  params: Promise<{ reference: string }>;
  searchParams: Promise<{ from?: string | string[]; refund_status?: string | string[] }>;
}) {
  const [{ reference }, { from, refund_status }] = await Promise.all([params, searchParams]);
  const source = from === 'finance-overview' || from === 'merchant-finance' || from === 'cod-finance' ? from : 'reconciliation-queue';
  const refundStatus = typeof refund_status === 'string' && refundStatuses.includes(refund_status) ? refund_status : 'requested';
  return <AdminPortalClient initialTab="payment-tracking" initialPaymentOrder={reference}
    financeReturn={source} initialRefundStatus={refundStatus} />;
}
