'use client';

import React from 'react';
import { ArrowUpRight, Building2, ClipboardList, FileWarning, ShieldCheck, ShoppingBag, Tag, UsersRound } from 'lucide-react';
import type { Stats } from '@/lib/api';

interface GraphicalMetricsViewProps {
  stats: Stats | null;
  selectedCity: string;
  selectedRange: '7d' | '14d' | '30d';
  onNavigateTab: (tab: 'verification' | 'businesses' | 'reports') => void;
}

const number = new Intl.NumberFormat('en-IN');

export const GraphicalMetricsView: React.FC<GraphicalMetricsViewProps> = ({ stats, selectedCity, selectedRange, onNavigateTab }) => {
  if (!stats) return null;
  const cards = [
    { title: 'Approved listings', value: stats.active_listings, note: 'Current directory', icon: Building2, tone: 'blue' as const, action: () => onNavigateTab('businesses') },
    { title: 'Awaiting verification', value: stats.pending_verifications, note: 'Needs moderation', icon: ShieldCheck, tone: 'amber' as const, action: () => onNavigateTab('verification') },
    { title: 'Platform-wide open reports', value: stats.reported_listings, note: 'Customer reports', icon: FileWarning, tone: 'rose' as const, action: () => onNavigateTab('reports') },
    { title: 'Offers for review', value: stats.pending_offers, note: 'Draft or pending', icon: Tag, tone: 'teal' as const },
  ];
  const activity = [
    { label: 'Business claims awaiting review', value: stats.pending_claims, icon: UsersRound },
    { label: `Service requests · last ${selectedRange}`, value: stats.service_requests, icon: ClipboardList },
    { label: `Customer orders · last ${selectedRange}`, value: stats.customer_orders, icon: ShoppingBag },
    { label: 'Active user accounts', value: stats.active_accounts, icon: UsersRound },
    { label: `Notification events · last ${selectedRange}`, value: stats.notification_events, icon: FileWarning },
  ];
  const toneStyle = {
    blue: 'bg-blue-50 text-[#2457D6]',
    amber: 'bg-amber-50 text-amber-700',
    rose: 'bg-rose-50 text-rose-700',
    teal: 'bg-teal-50 text-teal-700',
  };

  return (
    <section className="space-y-6 pb-10">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[.16em] text-[#2457D6]">Platform overview</p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#172033] md:text-3xl">Operations at a glance</h1>
          <p className="mt-1 text-sm text-[#667085]">Live records from the Grepmind Near platform database.</p>
        </div>
        <div className="flex items-center gap-2 rounded-full border border-[#DCE5F2] bg-white px-3 py-2 text-xs font-medium text-[#475467] shadow-sm">
          <span className="h-2 w-2 rounded-full bg-emerald-500" />
          {selectedCity === 'All Cities' ? 'Cuttack + Jajpur' : selectedCity} · {selectedRange}
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map(({ title, value, note, icon: Icon, tone, action }) => (
          <button key={title} onClick={action} disabled={!action} className={`group rounded-2xl border border-[#E4EAF2] bg-white p-5 text-left shadow-[0_4px_18px_-14px_rgba(23,32,51,.35)] transition-all ${action ? 'hover:-translate-y-0.5 hover:border-blue-200 hover:shadow-md' : 'cursor-default'}`}>
            <div className="flex items-start justify-between">
              <span className={`flex h-10 w-10 items-center justify-center rounded-xl ${toneStyle[tone]}`}><Icon className="h-5 w-5" /></span>
              {action && <ArrowUpRight className="h-4 w-4 text-[#98A2B3] transition-colors group-hover:text-[#2457D6]" />}
            </div>
            <p className="mt-5 text-sm font-medium text-[#667085]">{title}</p>
            <div className="mt-1 flex items-baseline gap-2"><span className="text-3xl font-bold tracking-tight text-[#172033]">{number.format(value)}</span><span className="text-xs text-[#98A2B3]">records</span></div>
            <p className="mt-2 text-xs text-[#98A2B3]">{note}</p>
          </button>
        ))}
      </div>

      <div className="grid gap-6 lg:grid-cols-[1.4fr_1fr]">
        <div className="rounded-2xl border border-[#E4EAF2] bg-white p-6 shadow-[0_4px_18px_-14px_rgba(23,32,51,.35)]">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[#F1F5FF] text-[#2457D6]"><ClipboardList className="h-5 w-5" /></div>
            <div><h2 className="font-semibold text-[#172033]">Recent platform activity</h2><p className="text-xs text-[#667085]">Operational totals for the selected period</p></div>
          </div>
          <div className="mt-5 divide-y divide-[#F2F4F7]">
            {activity.map(({ label, value, icon: Icon }) => <div key={label} className="flex items-center justify-between gap-3 py-4"><div className="flex items-center gap-3"><Icon className="h-4 w-4 text-[#667085]" /><span className="text-sm text-[#475467]">{label}</span></div><strong className="text-sm tabular-nums text-[#172033]">{number.format(value)}</strong></div>)}
          </div>
        </div>
        <div className="rounded-2xl border border-blue-100 bg-gradient-to-br from-[#F5F8FF] to-white p-6 shadow-[0_4px_18px_-14px_rgba(23,32,51,.35)]">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-white text-[#2457D6] shadow-sm"><ShieldCheck className="h-5 w-5" /></div>
          <h2 className="mt-4 font-semibold text-[#172033]">Trustworthy reporting</h2>
          <p className="mt-2 text-sm leading-6 text-[#667085]">Counts are queried from live records. Revenue, ratings, SLA, dispatch time, and search demand are not shown because those measurements are not currently backed by production data.</p>
          <div className="mt-4 flex items-center gap-2 text-xs font-medium text-[#0F766E]"><span className="h-2 w-2 rounded-full bg-[#0F766E]" />No demonstration metrics</div>
        </div>
      </div>
    </section>
  );
};
