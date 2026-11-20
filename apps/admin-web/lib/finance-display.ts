export const orderReferencePattern = /^[a-z0-9][a-z0-9-]{0,63}$/i;
export const refundStatuses = ['requested', 'approved', 'processing', 'succeeded', 'failed', 'rejected', 'reconciliation_required'];

const amountFormat = new Intl.NumberFormat('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export function financeAmount(amountMinor: number, currency: string) {
  return currency === 'INR'
    ? `₹${amountFormat.format(amountMinor / 100)}`
    : `${currency} ${amountFormat.format(amountMinor / 100)}`;
}

export function financeStatus(value: string | null) {
  return value ? value[0].toUpperCase() + value.slice(1).replaceAll('_', ' ') : 'Unavailable';
}

export function paymentClassification(provider?: string) {
  return provider === 'grepmind_sandbox' ? 'Sandbox' : 'Classification unavailable';
}

export function settlementClassification(mode?: string, simulatedAt?: string | null) {
  if (mode !== 'synthetic_qa_pool' && mode !== 'verified_cod_remittance') return 'Classification unavailable';
  return simulatedAt ? 'Simulated' : 'Simulation only';
}
