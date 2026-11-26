'use client';

import React, { useState } from 'react';
import {
  Building2,
  MapPin,
  Phone,
  Search,
  CheckCircle2,
  Clock,
  ExternalLink,
  ShieldCheck,
} from 'lucide-react';
import { Business } from '@/lib/api';

interface BusinessesRegistryViewProps {
  businesses: Business[];
  onViewDetails: (id: string) => void;
}

export const BusinessesRegistryView: React.FC<BusinessesRegistryViewProps> = ({
  businesses,
  onViewDetails,
}) => {
  const [cityFilter, setCityFilter] = useState('All');
  const [statusFilter, setStatusFilter] = useState('All');
  const [sourceFilter, setSourceFilter] = useState('All');
  const [searchQuery, setSearchQuery] = useState('');

  const filtered = businesses.filter((b) => {
    const bCity = (b.city || '').toLowerCase();
    const bAddr = (b.address_text || '').toLowerCase();
    const targetCity = cityFilter.toLowerCase();
    const matchesCity = cityFilter === 'All' || bCity.includes(targetCity) || bAddr.includes(targetCity);
    const matchesStatus = statusFilter === 'All' || b.status.toLowerCase() === statusFilter.toLowerCase();
    const source = b.onboarding_source || 'self';
    const matchesSource = sourceFilter === 'All' || source === sourceFilter;
    const q = searchQuery.toLowerCase();
    const matchesSearch =
      b.name.toLowerCase().includes(q) ||
      (b.merchant_code && b.merchant_code.toLowerCase().includes(q)) ||
      (b.category_name && b.category_name.toLowerCase().includes(q)) ||
      (b.address_text && b.address_text.toLowerCase().includes(q)) ||
      (b.field_executive_code && b.field_executive_code.toLowerCase().includes(q)) ||
      (b.field_executive_name && b.field_executive_name.toLowerCase().includes(q));
    return matchesCity && matchesStatus && matchesSource && matchesSearch;
  });

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-xl font-bold text-[#172033]">Platform Merchant Registry</h2>
            <span className="rounded-full bg-[#EBF0FF] px-2.5 py-0.5 text-xs font-semibold text-[#2457D6]">
              {filtered.length} of {businesses.length}
            </span>
          </div>
          <p className="text-xs text-[#667085] mt-0.5">
            Full directory of retail storefronts and service professionals across Odisha
          </p>
        </div>

        {/* City Filter Pills */}
        <div className="flex items-center gap-2">
          {['All', 'Cuttack', 'Jajpur'].map((city) => (
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

      {/* Filter and Search Bar */}
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="flex flex-1 items-center rounded-xl border border-[#E4E7EC] bg-white px-3.5 py-2 shadow-xs">
          <Search className="h-4 w-4 text-[#98A2B3] mr-2" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search by AM-1000 ID, name, category, address, or AFE-1000..."
            className="w-full text-xs text-[#172033] placeholder-[#98A2B3] focus:outline-none"
          />
        </div>

        {/* Status Dropdown */}
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-xl border border-[#E4E7EC] bg-white px-3 py-2 text-xs font-medium text-[#344054] shadow-xs focus:outline-none"
        >
          <option value="All">All Statuses</option>
          <option value="approved">Approved &amp; Live</option>
          <option value="pending">Pending Verification</option>
          <option value="rejected">Rejected</option>
        </select>

        {/* Onboarded Via Dropdown */}
        <select
          value={sourceFilter}
          onChange={(e) => setSourceFilter(e.target.value)}
          className="rounded-xl border border-[#E4E7EC] bg-white px-3 py-2 text-xs font-medium text-[#344054] shadow-xs focus:outline-none"
        >
          <option value="All">All Sources</option>
          <option value="self">Self-Registered</option>
          <option value="field_executive">Field Executive (AFE)</option>
        </select>
      </div>

      {/* Table */}
      <div className="rounded-2xl border border-[#E4E7EC] bg-white shadow-xs overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse text-xs">
            <thead>
              <tr className="border-b border-[#E4E7EC] bg-[#F7F8FA] text-[#667085] font-semibold">
                <th className="py-3 px-4">Merchant ID</th>
                <th className="py-3 px-4">Business / Pro</th>
                <th className="py-3 px-4">Category</th>
                <th className="py-3 px-4">City / Locality</th>
                <th className="py-3 px-4">Onboarded Via</th>
                <th className="py-3 px-4">Listing Status</th>
                <th className="py-3 px-4">Verification</th>
                <th className="py-3 px-4 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#F2F4F7]">
              {filtered.map((biz) => (
                <tr key={biz.id} className="hover:bg-[#FAFAFA] transition-colors">
                  <td className="py-3 px-4 font-mono font-bold text-[#0F766E] whitespace-nowrap">
                    {biz.merchant_code || '—'}
                  </td>
                  <td className="py-3 px-4">
                    <div className="font-bold text-[#172033]">{biz.name}</div>
                    <div className="text-[11px] text-[#667085] flex items-center gap-1.5 mt-0.5">
                      <Phone className="h-3 w-3" /> {biz.owner_phone || biz.phone_e164 || 'Unlisted'}
                    </div>
                  </td>
                  <td className="py-3 px-4 text-[#344054]">
                    {biz.category_name || biz.category_slug}
                  </td>
                  <td className="py-3 px-4">
                    <div className="font-medium text-[#172033]">{biz.city || 'Odisha'}</div>
                    <div className="text-[11px] text-[#667085] truncate max-w-xs">{biz.address_text}</div>
                  </td>
                  <td className="py-3 px-4">
                    {biz.onboarding_source === 'field_executive' ? (
                      <div>
                        <span className="inline-block rounded-full bg-teal-50 border border-teal-200 px-2 py-0.5 text-[10px] font-bold text-teal-800">
                          {biz.field_executive_code || 'AFE'}
                        </span>
                        {biz.field_executive_name && (
                          <div className="text-[11px] text-[#667085] mt-0.5">{biz.field_executive_name}</div>
                        )}
                      </div>
                    ) : (
                      <span className="inline-block rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-semibold text-slate-700">
                        Self
                      </span>
                    )}
                  </td>
                  <td className="py-3 px-4">
                    <span
                      className={`inline-block rounded-full px-2 py-0.5 text-[10px] font-bold ${
                        biz.status === 'approved'
                          ? 'bg-emerald-100 text-emerald-800'
                          : biz.status === 'pending'
                          ? 'bg-amber-100 text-amber-800'
                          : 'bg-gray-100 text-gray-700'
                      }`}
                    >
                      {biz.status.toUpperCase()}
                    </span>
                  </td>
                  <td className="py-3 px-4">
                    <span
                      className={`inline-flex items-center gap-1 text-[11px] font-semibold ${
                        biz.verification_status === 'verified'
                          ? 'text-emerald-700'
                          : biz.verification_status === 'pending'
                          ? 'text-amber-700'
                          : 'text-gray-500'
                      }`}
                    >
                      <ShieldCheck className="h-3.5 w-3.5" />
                      {biz.verification_status.toUpperCase()}
                    </span>
                  </td>
                  <td className="py-3 px-4 text-right">
                    <button onClick={() => onViewDetails(biz.id)} className="rounded-lg border border-teal-200 px-2.5 py-1.5 text-xs font-semibold text-teal-800 hover:bg-teal-50">View details</button>
                    {biz.status === 'approved' && (
                      <span className="text-[11px] font-semibold text-emerald-600 flex items-center justify-end gap-1">
                        <CheckCircle2 className="h-3.5 w-3.5" /> Active
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
