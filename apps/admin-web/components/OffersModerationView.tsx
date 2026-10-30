'use client';

import React, { useState } from 'react';
import { Tag, CheckCircle2, XCircle, Clock, Percent } from 'lucide-react';
import { Offer } from '@/lib/api';

interface OffersModerationViewProps {
  offers: Offer[];
  onApprove: (id: string) => Promise<void>;
  onReject: (id: string) => Promise<void>;
}

export const OffersModerationView: React.FC<OffersModerationViewProps> = ({
  offers,
  onApprove,
  onReject,
}) => {
  const [actionLoadingId, setActionLoadingId] = useState<string | null>(null);

  async function handleApprove(id: string) {
    setActionLoadingId(id);
    try {
      await onApprove(id);
    } finally {
      setActionLoadingId(null);
    }
  }

  async function handleReject(id: string) {
    setActionLoadingId(id);
    try {
      await onReject(id);
    } finally {
      setActionLoadingId(null);
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-bold text-[#172033]">Promotions &amp; Offer Moderation</h2>
        <p className="text-xs text-[#667085] mt-0.5">
          Review discount banners, seasonal festival specials, and indicative promotional coupons
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {offers.length === 0 ? (
          <div className="col-span-2 rounded-2xl border border-[#E4E7EC] bg-white p-12 text-center text-xs text-[#667085]">
            <CheckCircle2 className="mx-auto h-8 w-8 text-emerald-500 mb-2" />
            <p className="font-semibold text-sm text-[#172033]">All Offers Moderated</p>
            <p className="mt-1">Zero pending promotional banners in queue.</p>
          </div>
        ) : (
          offers.map((offer) => (
            <div
              key={offer.id}
              className="rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-xs space-y-4"
            >
              <div className="flex items-start justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-bold text-[#172033]">{offer.title}</span>
                    {offer.discount_percent && (
                      <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-[10px] font-bold text-emerald-800">
                        {offer.discount_percent}% OFF
                      </span>
                    )}
                  </div>
                  <div className="text-xs text-[#667085] mt-1">
                    Store: {offer.business_name || 'Partner Merchant'}
                  </div>
                </div>

                <span
                  className={`rounded-full px-2.5 py-0.5 text-xs font-bold ${
                    offer.status === 'pending'
                      ? 'bg-amber-100 text-amber-800'
                      : offer.status === 'approved'
                      ? 'bg-emerald-100 text-emerald-800'
                      : 'bg-rose-100 text-rose-800'
                  }`}
                >
                  {offer.status.toUpperCase()}
                </span>
              </div>

              {offer.description && (
                <div className="rounded-xl border border-[#E4E7EC] bg-[#F7F8FA] p-3 text-xs text-[#475467]">
                  {offer.description}
                </div>
              )}

              <div className="flex items-center justify-between text-[11px] text-[#667085] pt-2 border-t border-[#F2F4F7]">
                <span>Valid: {new Date(offer.starts_at).toLocaleDateString()} - {new Date(offer.ends_at).toLocaleDateString()}</span>

                {offer.status === 'pending' && (
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => handleReject(offer.id)}
                      disabled={actionLoadingId === offer.id}
                      className="rounded-lg border border-[#D0D5DD] px-3 py-1.5 text-xs font-semibold text-rose-700 hover:bg-rose-50"
                    >
                      Reject
                    </button>
                    <button
                      onClick={() => handleApprove(offer.id)}
                      disabled={actionLoadingId === offer.id}
                      className="rounded-lg bg-[#2457D6] px-3.5 py-1.5 text-xs font-bold text-white hover:bg-[#1E40AF]"
                    >
                      {actionLoadingId === offer.id ? 'Saving...' : 'Approve Banner'}
                    </button>
                  </div>
                )}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
