'use client';

import React, { useState } from 'react';
import {
  FileCheck2,
  Building,
  MapPin,
  Phone,
  Search,
  Filter,
  CheckCircle2,
  XCircle,
  Eye,
  Award,
  Sparkles,
} from 'lucide-react';
import { KYCSubmission, KYC_SUBMISSIONS } from '@/lib/adminData';
import { KYCReviewModal } from './KYCReviewModal';
import { Business } from '@/lib/api';

interface VerificationQueueViewProps {
  apiPendingList: Business[];
  onApproveBusiness: (id: string) => Promise<void>;
  onVerifyBusiness: (id: string) => Promise<void>;
  onRejectBusiness: (id: string, reason: string) => Promise<void>;
}

export const VerificationQueueView: React.FC<VerificationQueueViewProps> = ({
  apiPendingList,
  onApproveBusiness,
  onVerifyBusiness,
  onRejectBusiness,
}) => {
  const [submissions, setSubmissions] = useState<KYCSubmission[]>(KYC_SUBMISSIONS);
  const [selectedSubmission, setSelectedSubmission] = useState<KYCSubmission | null>(null);
  const [cityFilter, setCityFilter] = useState<string>('All');
  const [searchQuery, setSearchQuery] = useState('');
  const [actionLoadingId, setActionLoadingId] = useState<string | null>(null);

  // Filter submissions
  const filteredSubmissions = submissions.filter((sub) => {
    const matchesCity = cityFilter === 'All' || sub.city.toLowerCase() === cityFilter.toLowerCase();
    const matchesSearch =
      sub.businessName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      sub.ownerName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      sub.documentNumber.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesCity && matchesSearch;
  });

  async function handleApprove(submissionId: string, businessId: string) {
    setActionLoadingId(businessId);
    try {
      await onVerifyBusiness(businessId);
      await onApproveBusiness(businessId);
      setSubmissions((prev) =>
        prev.map((s) => (s.id === submissionId ? { ...s, status: 'verified' } : s))
      );
    } finally {
      setActionLoadingId(null);
    }
  }

  async function handleReject(submissionId: string, businessId: string, reason: string) {
    setActionLoadingId(businessId);
    try {
      await onRejectBusiness(businessId, reason);
      setSubmissions((prev) =>
        prev.map((s) => (s.id === submissionId ? { ...s, status: 'rejected' } : s))
      );
    } finally {
      setActionLoadingId(null);
    }
  }

  return (
    <div className="space-y-6">
      {/* Header & Controls */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-xl font-bold text-[#172033]">Merchant &amp; Listing Verification Queue</h2>
            <span className="rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-bold text-amber-800">
              {filteredSubmissions.filter((s) => s.status === 'pending').length} Pending Review
            </span>
          </div>
          <p className="text-xs text-[#667085] mt-1">
            Validate trade licenses, GSTIN registrations, and physical storefront geotags before listing activation
          </p>
        </div>

        {/* Filter Chips */}
        <div className="flex items-center gap-2">
          {['All', 'Bhubaneswar', 'Cuttack', 'Puri'].map((city) => (
            <button
              key={city}
              onClick={() => setCityFilter(city)}
              className={`rounded-lg px-3 py-1.5 text-xs font-medium transition-all ${
                cityFilter === city
                  ? 'bg-[#2457D6] text-white font-semibold shadow-xs'
                  : 'bg-white border border-[#D0D5DD] text-[#344054] hover:bg-[#F9FAFB]'
              }`}
            >
              {city}
            </button>
          ))}
        </div>
      </div>

      {/* Search Input Bar */}
      <div className="flex items-center rounded-xl border border-[#E4E7EC] bg-white px-3.5 py-2 shadow-xs">
        <Search className="h-4 w-4 text-[#98A2B3] mr-2" />
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Search by store name, owner name, or license number..."
          className="w-full text-xs text-[#172033] placeholder-[#98A2B3] focus:outline-none"
        />
      </div>

      {/* Verification Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {filteredSubmissions.map((sub) => {
          const isPending = sub.status === 'pending';
          const isVerified = sub.status === 'verified';
          const isRejected = sub.status === 'rejected';

          return (
            <div
              key={sub.id}
              className={`rounded-2xl border bg-white p-5 shadow-xs transition-all ${
                isPending
                  ? 'border-[#E4E7EC] hover:border-[#2457D6]/40'
                  : isVerified
                  ? 'border-emerald-200 bg-emerald-50/20'
                  : 'border-rose-200 bg-rose-50/20'
              }`}
            >
              <div className="flex items-start justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-bold text-[#172033]">{sub.businessName}</span>
                    <span
                      className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${
                        sub.city === 'Puri'
                          ? 'bg-amber-100 text-amber-800'
                          : sub.city === 'Cuttack'
                          ? 'bg-teal-100 text-teal-800'
                          : 'bg-blue-100 text-blue-800'
                      }`}
                    >
                      {sub.city}
                    </span>
                  </div>
                  <div className="mt-1 flex items-center gap-2 text-xs text-[#667085]">
                    <Building className="h-3.5 w-3.5" />
                    <span>{sub.category}</span>
                    <span>•</span>
                    <MapPin className="h-3.5 w-3.5 text-[#0F766E]" />
                    <span>{sub.locality}</span>
                  </div>
                </div>

                <span
                  className={`rounded-full px-2.5 py-0.5 text-xs font-bold ${
                    isPending
                      ? 'bg-amber-100 text-amber-800'
                      : isVerified
                      ? 'bg-emerald-100 text-emerald-800'
                      : 'bg-rose-100 text-rose-800'
                  }`}
                >
                  {sub.status.toUpperCase()}
                </span>
              </div>

              {/* Document Summary Box */}
              <div className="mt-4 rounded-xl border border-[#E4E7EC] bg-[#F7F8FA] p-3 text-xs">
                <div className="flex items-center justify-between">
                  <span className="font-semibold text-[#344054] flex items-center gap-1.5">
                    <Award className="h-4 w-4 text-[#2457D6]" />
                    {sub.documentType}
                  </span>
                  <span className="font-mono text-[11px] font-bold text-[#172033]">
                    {sub.documentNumber}
                  </span>
                </div>
                <div className="mt-2 text-[11px] text-[#667085]">
                  <span>Issuer: {sub.issuer}</span>
                  <span className="mx-2">•</span>
                  <span>Owner: {sub.ownerName} ({sub.ownerPhone})</span>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="mt-4 flex items-center justify-between pt-2 border-t border-[#F2F4F7]">
                <button
                  onClick={() => setSelectedSubmission(sub)}
                  className="flex items-center gap-1 text-xs font-semibold text-[#2457D6] hover:underline"
                >
                  <Eye className="h-3.5 w-3.5" /> Review Full KYC Documents →
                </button>

                {isPending && (
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => handleReject(sub.id, sub.businessId, 'Incomplete documentation')}
                      disabled={actionLoadingId === sub.businessId}
                      className="rounded-lg border border-[#D0D5DD] px-3 py-1.5 text-xs font-semibold text-rose-700 hover:bg-rose-50 transition-colors"
                    >
                      Reject
                    </button>
                    <button
                      onClick={() => handleApprove(sub.id, sub.businessId)}
                      disabled={actionLoadingId === sub.businessId}
                      className="flex items-center gap-1 rounded-lg bg-[#2457D6] px-3.5 py-1.5 text-xs font-bold text-white shadow-xs hover:bg-[#1E40AF] transition-colors"
                    >
                      <CheckCircle2 className="h-3.5 w-3.5" />
                      {actionLoadingId === sub.businessId ? 'Saving...' : 'Approve'}
                    </button>
                  </div>
                )}

                {isVerified && (
                  <span className="flex items-center gap-1 text-xs font-semibold text-emerald-600">
                    <CheckCircle2 className="h-4 w-4" /> Verified &amp; Live on Platform
                  </span>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* KYC Document Review Modal */}
      {selectedSubmission && (
        <KYCReviewModal
          submission={selectedSubmission}
          isOpen={true}
          onClose={() => setSelectedSubmission(null)}
          onApprove={handleApprove}
          onReject={handleReject}
        />
      )}
    </div>
  );
};
