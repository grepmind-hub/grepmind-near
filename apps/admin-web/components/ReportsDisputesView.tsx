'use client';

import React, { useState } from 'react';
import { ShieldAlert, CheckCircle2, XCircle, AlertTriangle, User, MessageSquare } from 'lucide-react';
import { Report } from '@/lib/api';

interface ReportsDisputesViewProps {
  reports: Report[];
  onResolveReport: (id: string, resolution: 'action_taken' | 'dismissed', reason: string) => Promise<void>;
}

export const ReportsDisputesView: React.FC<ReportsDisputesViewProps> = ({
  reports,
  onResolveReport,
}) => {
  const [actionLoadingId, setActionLoadingId] = useState<string | null>(null);

  async function handleAction(id: string, resolution: 'action_taken' | 'dismissed') {
    const reason = prompt(
      `Enter resolution notes for this ticket (${resolution}):`,
      resolution === 'action_taken'
        ? 'Merchant issued warning and corrected storefront details'
        : 'Reviewed and dismissed as invalid inquiry'
    );
    if (!reason) return;

    setActionLoadingId(id);
    try {
      await onResolveReport(id, resolution, reason);
    } finally {
      setActionLoadingId(null);
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-bold text-[#172033]">Consumer Reports &amp; Disputes</h2>
        <p className="text-xs text-[#667085] mt-0.5">
          Review customer inquiries, address inaccuracies, price disparities, or conduct reports
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {reports.length === 0 ? (
          <div className="col-span-2 rounded-2xl border border-[#E4E7EC] bg-white p-12 text-center text-xs text-[#667085]">
            <CheckCircle2 className="mx-auto h-8 w-8 text-emerald-500 mb-2" />
            <p className="font-semibold text-sm text-[#172033]">Zero Open Disputes</p>
            <p className="mt-1">All consumer reports have been addressed and resolved.</p>
          </div>
        ) : (
          reports.map((rep) => (
            <div
              key={rep.id}
              className="rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-xs space-y-4"
            >
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-2">
                  <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-rose-50 text-rose-600">
                    <ShieldAlert className="h-4 w-4" />
                  </div>
                  <div>
                    <span className="text-xs font-bold text-[#172033] capitalize">
                      {rep.target_type} Dispute
                    </span>
                    <div className="text-[11px] text-[#667085]">
                      Reporter: {rep.reporter_phone || 'Customer'}
                    </div>
                  </div>
                </div>

                <span
                  className={`rounded-full px-2.5 py-0.5 text-xs font-bold ${
                    rep.status === 'open'
                      ? 'bg-rose-100 text-rose-800'
                      : 'bg-emerald-100 text-emerald-800'
                  }`}
                >
                  {rep.status.toUpperCase()}
                </span>
              </div>

              <div className="rounded-xl border border-rose-100 bg-rose-50/50 p-3 text-xs text-[#172033]">
                <span className="font-bold text-rose-900 block mb-1">Issue Details:</span>
                {rep.reason}
              </div>

              {rep.status === 'open' && (
                <div className="flex items-center justify-end gap-2 pt-2 border-t border-[#F2F4F7]">
                  <button
                    onClick={() => handleAction(rep.id, 'dismissed')}
                    disabled={actionLoadingId === rep.id}
                    className="rounded-lg border border-[#D0D5DD] px-3 py-1.5 text-xs font-semibold text-[#475467] hover:bg-gray-50"
                  >
                    Dismiss
                  </button>
                  <button
                    onClick={() => handleAction(rep.id, 'action_taken')}
                    disabled={actionLoadingId === rep.id}
                    className="rounded-lg bg-[#2457D6] px-3.5 py-1.5 text-xs font-bold text-white hover:bg-[#1E40AF]"
                  >
                    {actionLoadingId === rep.id ? 'Saving...' : 'Resolve & Warn Merchant'}
                  </button>
                </div>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
};
