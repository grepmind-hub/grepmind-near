'use client';

import React, { useMemo, useState } from 'react';
import { Building2, FileText, MapPin, Phone, Search, ShieldCheck } from 'lucide-react';
import type { Business } from '@/lib/api';

interface VerificationQueueViewProps {
  apiPendingList: Business[];
  onViewDetails: (id: string) => void;
}

export const VerificationQueueView: React.FC<VerificationQueueViewProps> = ({ apiPendingList, onViewDetails }) => {
  const [city, setCity] = useState('All');
  const [query, setQuery] = useState('');
  const filtered = useMemo(() => apiPendingList.filter((item) => {
    const matchesCity = city === 'All' || item.city?.toLowerCase() === city.toLowerCase();
    const text = `${item.name} ${item.category_name ?? item.category_slug} ${item.address_text} ${item.owner_phone ?? ''}`.toLowerCase();
    return matchesCity && text.includes(query.toLowerCase());
  }), [apiPendingList, city, query]);

  return (
    <section className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div><p className="text-xs font-semibold uppercase tracking-[.16em] text-[#2457D6]">Merchant governance</p><h1 className="mt-1 text-2xl font-bold tracking-tight text-[#172033]">Listing verification</h1><p className="mt-1 text-sm text-[#667085]">Review submitted listing details before approval. No external license or KYC documents are stored in the current platform.</p></div>
        <span className="rounded-full border border-amber-200 bg-amber-50 px-3 py-1.5 text-xs font-semibold text-amber-800">{filtered.length} records in queue</span>
      </div>
      <div className="flex flex-wrap items-center gap-3 rounded-2xl border border-[#E4EAF2] bg-white p-3 shadow-sm">
        <div className="relative min-w-[220px] flex-1"><Search className="absolute left-3 top-3 h-4 w-4 text-[#98A2B3]"/><input aria-label="Search listings" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search name, category, address or phone" className="h-10 w-full rounded-xl border border-[#E4E7EC] bg-[#FAFBFD] pl-9 pr-3 text-sm outline-none focus:border-blue-300 focus:ring-2 focus:ring-blue-100" /></div>
        <div className="flex gap-1 rounded-xl bg-[#F3F6FA] p-1">{['All', 'Cuttack', 'Jajpur'].map((item) => <button key={item} onClick={() => setCity(item)} className={`min-h-9 rounded-lg px-3 text-xs font-semibold ${city === item ? 'bg-white text-[#2457D6] shadow-sm' : 'text-[#667085]'}`}>{item}</button>)}</div>
      </div>
      {filtered.length === 0 ? <div className="rounded-2xl border border-dashed border-[#D0D9E5] bg-white px-6 py-14 text-center"><ShieldCheck className="mx-auto h-8 w-8 text-[#98A2B3]"/><h2 className="mt-3 font-semibold text-[#172033]">No listings need review</h2><p className="mt-1 text-sm text-[#667085]">The live API returned no pending business records for this filter.</p></div> :
        <div className="grid gap-4 xl:grid-cols-2">{filtered.map((item) => <article key={item.id} className="rounded-2xl border border-[#E4EAF2] bg-white p-5 shadow-[0_4px_18px_-14px_rgba(23,32,51,.35)]">
          <div className="flex items-start justify-between gap-4"><div className="flex min-w-0 items-start gap-3"><span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-blue-50 text-[#2457D6]"><Building2 className="h-5 w-5"/></span><div className="min-w-0"><h2 className="truncate font-semibold text-[#172033]">{item.name}</h2><p className="mt-0.5 text-sm text-[#667085]">{item.category_name || item.category_slug}</p></div></div><span className="rounded-full bg-amber-50 px-2.5 py-1 text-[11px] font-semibold capitalize text-amber-800">{item.status} · {item.verification_status}</span></div>
          <div className="mt-4 space-y-2 text-sm text-[#475467]"><p className="flex gap-2"><MapPin className="mt-0.5 h-4 w-4 shrink-0 text-[#0F766E]"/><span>{item.address_text}{item.city ? `, ${item.city}` : ''}</span></p>{item.phone_e164 && <p className="flex gap-2"><Phone className="h-4 w-4 text-[#667085]"/>{item.phone_e164}</p>}{item.owner_phone && <p className="text-xs text-[#667085]">Owner account: {item.owner_phone}</p>}</div>
          <div className="mt-4 flex justify-end border-t border-[#F2F4F7] pt-4"><button onClick={() => onViewDetails(item.id)} className="inline-flex min-h-10 items-center gap-2 rounded-xl bg-teal-800 px-4 text-sm font-semibold text-white hover:bg-teal-900"><FileText className="h-4 w-4" aria-hidden />View details</button></div>
        </article>)}</div>}
    </section>
  );
};
