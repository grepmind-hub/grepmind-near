'use client';

import React, { useState } from 'react';
import {
  X,
  ShieldCheck,
  CheckCircle2,
  AlertTriangle,
  Building,
  MapPin,
  Phone,
  FileText,
  Calendar,
  Award,
  ExternalLink,
  Lock,
} from 'lucide-react';
import { KYCSubmission } from '@/lib/adminData';

interface KYCReviewModalProps {
  submission: KYCSubmission;
  isOpen: boolean;
  onClose: () => void;
  onApprove: (id: string, bizId: string) => Promise<void>;
  onReject: (id: string, bizId: string, reason: string) => Promise<void>;
}

export const KYCReviewModal: React.FC<KYCReviewModalProps> = ({
  submission,
  isOpen,
  onClose,
  onApprove,
  onReject,
}) => {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [showRejectBox, setShowRejectBox] = useState(false);

  if (!isOpen) return null;

  async function handleApproveClick() {
    setIsSubmitting(true);
    try {
      await onApprove(submission.id, submission.businessId);
      onClose();
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleRejectClick() {
    if (!rejectReason.trim()) {
      alert('Please enter a rejection reason.');
      return;
    }
    setIsSubmitting(true);
    try {
      await onReject(submission.id, submission.businessId, rejectReason);
      onClose();
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs animate-in fade-in duration-200">
      <div className="relative w-full max-w-2xl rounded-2xl bg-white shadow-2xl border border-[#E4E7EC] overflow-hidden flex flex-col max-h-[90vh]">
        {/* Modal Header */}
        <div className="flex items-center justify-between border-b border-[#E4E7EC] px-6 py-4 bg-[#F7F8FA]">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-tr from-[#1E40AF] to-[#2457D6] text-white shadow-xs">
              <ShieldCheck className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-base font-bold text-[#172033]">KYC &amp; Trade License Review</h3>
                <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-800">
                  PENDING REVIEW
                </span>
              </div>
              <p className="text-xs text-[#667085]">
                Verification case #{submission.id} • {submission.city} Zone
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-[#667085] hover:bg-gray-200 transition-colors"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Modal Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {/* Business & Owner Profile */}
          <div className="rounded-xl border border-[#E4E7EC] bg-[#FAFAFA] p-4">
            <div className="flex items-start justify-between">
              <div>
                <h4 className="text-base font-bold text-[#172033]">{submission.businessName}</h4>
                <div className="mt-1 flex flex-wrap items-center gap-3 text-xs text-[#667085]">
                  <span className="flex items-center gap-1">
                    <Building className="h-3.5 w-3.5 text-[#2457D6]" /> {submission.category}
                  </span>
                  <span className="flex items-center gap-1">
                    <MapPin className="h-3.5 w-3.5 text-[#0F766E]" /> {submission.locality}, {submission.city}
                  </span>
                  <span className="flex items-center gap-1">
                    <Phone className="h-3.5 w-3.5 text-gray-500" /> {submission.ownerPhone}
                  </span>
                </div>
              </div>
              <span className="rounded-md bg-white border border-[#D0D5DD] px-2 py-1 text-xs font-semibold text-[#344054]">
                Owner: {submission.ownerName}
              </span>
            </div>
          </div>

          {/* Document Verification Certificate Card */}
          <div className="rounded-xl border-2 border-[#2457D6]/20 bg-gradient-to-br from-[#F0F5FF] to-white p-5 space-y-4">
            <div className="flex items-center justify-between border-b border-[#2457D6]/15 pb-3">
              <div className="flex items-center gap-2">
                <Award className="h-5 w-5 text-[#2457D6]" />
                <span className="font-bold text-sm text-[#172033]">{submission.documentType}</span>
              </div>
              <span className="text-xs font-semibold text-[#0F766E] bg-emerald-50 border border-emerald-200 px-2.5 py-0.5 rounded-full flex items-center gap-1">
                <CheckCircle2 className="h-3 w-3" /> Digital Registry Matched
              </span>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs">
              <div>
                <span className="text-[#667085] block">License / Reg Number:</span>
                <span className="font-mono font-bold text-sm text-[#172033]">{submission.documentNumber}</span>
              </div>

              {submission.gstin && (
                <div>
                  <span className="text-[#667085] block">GSTIN:</span>
                  <span className="font-mono font-bold text-sm text-[#172033]">{submission.gstin}</span>
                </div>
              )}

              <div>
                <span className="text-[#667085] block">Issuing Authority:</span>
                <span className="font-semibold text-[#172033]">{submission.issuer}</span>
              </div>

              <div>
                <span className="text-[#667085] block">Validity:</span>
                <span className="font-semibold text-[#172033]">{submission.validUntil}</span>
              </div>
            </div>

            <div className="rounded-lg bg-white border border-[#E4E7EC] p-3 text-xs text-[#475467]">
              <span className="font-bold text-[#172033]">Moderator Note:</span> {submission.notes}
            </div>
          </div>

          {/* Verification Checklist */}
          <div>
            <h5 className="text-xs font-bold uppercase tracking-wider text-[#667085] mb-2.5">
              Automated &amp; Physical Compliance Checks
            </h5>
            <div className="space-y-2">
              <div className="flex items-center justify-between rounded-lg border border-emerald-200 bg-emerald-50/50 p-2.5 text-xs">
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                  <span className="font-medium text-[#172033]">Phone OTP &amp; Identity Verification</span>
                </div>
                <span className="text-emerald-700 font-bold">100% Passed</span>
              </div>

              <div className="flex items-center justify-between rounded-lg border border-emerald-200 bg-emerald-50/50 p-2.5 text-xs">
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                  <span className="font-medium text-[#172033]">Physical Store GPS Geotag Lock</span>
                </div>
                <span className="text-emerald-700 font-bold">Verified within 15m</span>
              </div>

              <div className="flex items-center justify-between rounded-lg border border-emerald-200 bg-emerald-50/50 p-2.5 text-xs">
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                  <span className="font-medium text-[#172033]">State Business Registry Validated</span>
                </div>
                <span className="text-emerald-700 font-bold">Active &amp; In Good Standing</span>
              </div>
            </div>
          </div>

          {/* Rejection input box if triggered */}
          {showRejectBox && (
            <div className="rounded-xl border border-rose-300 bg-rose-50 p-3 space-y-2">
              <label className="text-xs font-bold text-rose-800">Reason for Rejection / Re-upload Request:</label>
              <textarea
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                placeholder="e.g., Incomplete trade license document, expired certificate, or blurry shop photograph."
                className="w-full rounded-lg border border-rose-300 bg-white p-2 text-xs text-[#172033] focus:outline-none focus:ring-1 focus:ring-rose-500"
                rows={2}
              />
            </div>
          )}
        </div>

        {/* Modal Footer with Action Buttons */}
        <div className="flex items-center justify-between border-t border-[#E4E7EC] px-6 py-4 bg-[#F7F8FA]">
          <div className="flex items-center gap-2">
            {!showRejectBox ? (
              <button
                onClick={() => setShowRejectBox(true)}
                disabled={isSubmitting}
                className="rounded-xl border border-rose-300 bg-white px-3.5 py-2 text-xs font-semibold text-rose-700 hover:bg-rose-50 transition-colors"
              >
                Reject Listing
              </button>
            ) : (
              <button
                onClick={handleRejectClick}
                disabled={isSubmitting}
                className="rounded-xl bg-rose-600 px-4 py-2 text-xs font-bold text-white hover:bg-rose-700 transition-colors"
              >
                {isSubmitting ? 'Submitting...' : 'Confirm Rejection'}
              </button>
            )}
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={onClose}
              disabled={isSubmitting}
              className="rounded-xl border border-[#D0D5DD] bg-white px-4 py-2 text-xs font-semibold text-[#344054] hover:bg-[#F9FAFB] transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={handleApproveClick}
              disabled={isSubmitting}
              className="flex items-center gap-1.5 rounded-xl bg-[#2457D6] px-5 py-2 text-xs font-bold text-white shadow-xs hover:bg-[#1E40AF] transition-colors active:scale-95 disabled:opacity-50"
            >
              <CheckCircle2 className="h-4 w-4" />
              {isSubmitting ? 'Verifying...' : 'Approve & Grant Verified Badge'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
