'use client';

import { ArrowUpRight, CalendarClock, Package, RefreshCw, Wrench } from 'lucide-react';
import type { Business, OperatingHoursDay, ServiceRequest } from '../lib/types';

export function OverviewCards({ business, requests, productCount, serviceCount, hours, updatedAt, onNavigateTab }: {
  business: Business;
  requests: ServiceRequest[];
  productCount: number;
  serviceCount: number;
  hours: OperatingHoursDay[];
  updatedAt: Date | null;
  onNavigateTab: (tab: string) => void;
}) {
  const today = new Date().toDateString();
  const todayRequests = requests.filter(r => new Date(r.createdAt).toDateString() === today).length;
  const pending = requests.filter(r => r.status === 'requested').length;
  const completed = requests.filter(r => r.status === 'completed').length;
  const stats = [
    { label: 'Requests today', value: todayRequests, helper: 'Received today', icon: CalendarClock, tone: 'from-blue-600 to-indigo-600' },
    { label: 'Needs attention', value: pending, helper: pending ? 'Awaiting your response' : 'No pending requests', icon: RefreshCw, tone: 'from-amber-500 to-orange-500' },
    { label: 'Products', value: productCount, helper: 'Catalog records', icon: Package, tone: 'from-teal-600 to-emerald-500' },
    { label: 'Services', value: serviceCount, helper: `${completed} requests completed`, icon: Wrench, tone: 'from-violet-600 to-fuchsia-500' },
  ];
  const recent = requests.slice(0, 5);
  const todayHours = hours[new Date().getDay() === 0 ? 6 : new Date().getDay() - 1];

  return <div className="space-y-6">
    <section className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-[#173F9F] via-[#2457D6] to-[#168B87] p-6 text-white shadow-xl shadow-blue-900/10 sm:p-8">
      <div className="relative z-10 max-w-2xl"><p className="text-xs font-semibold uppercase tracking-[.18em] text-blue-100">Merchant workspace</p><h2 className="mt-2 text-2xl font-bold tracking-tight sm:text-3xl">Welcome back. Your store, at a glance.</h2><p className="mt-2 text-sm text-blue-50">Live operational data for {business.name} in {business.city}.</p><button onClick={() => onNavigateTab('requests')} className="mt-5 inline-flex min-h-11 items-center gap-2 rounded-xl bg-white px-4 text-sm font-semibold text-blue-800 shadow hover:bg-blue-50">Review requests <ArrowUpRight size={16}/></button></div>
      <div aria-hidden="true" className="absolute -right-10 -top-20 h-72 w-72 rounded-full border-[40px] border-white/10"/><div aria-hidden="true" className="absolute -bottom-28 right-28 h-64 w-64 rounded-full border-[28px] border-teal-200/10"/>
    </section>
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{stats.map(({ label, value, helper, icon: Icon, tone }) => <article key={label} className="overflow-hidden rounded-2xl border border-borderMuted bg-surface shadow-card"><div className={`h-1.5 bg-gradient-to-r ${tone}`}/><div className="p-5"><div className="flex items-start justify-between"><div><p className="text-sm font-medium text-slateText-secondary">{label}</p><p className="mt-2 text-3xl font-bold tracking-tight text-slateText-main">{value}</p></div><span className={`grid h-11 w-11 place-items-center rounded-xl bg-gradient-to-br ${tone} text-white shadow-md`}><Icon size={19}/></span></div><p className="mt-3 text-xs text-slateText-muted">{helper}</p></div></article>)}</div>
    <div className="grid gap-5 xl:grid-cols-[1.35fr_.9fr]">
      <section className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-card"><div className="flex items-center justify-between border-b border-borderMuted pb-4"><div><h3 className="font-bold text-slateText-main">Recent customer requests</h3><p className="mt-1 text-xs text-slateText-secondary">Latest records from your merchant account</p></div><button onClick={() => onNavigateTab('requests')} className="text-sm font-semibold text-primary hover:underline">View all</button></div>
        {recent.length === 0 ? <div className="py-10 text-center"><CalendarClock className="mx-auto text-slate-300"/><p className="mt-3 text-sm font-semibold text-slateText-main">No customer requests yet</p><p className="mt-1 text-xs text-slateText-secondary">New requests will appear here when customers contact this business.</p></div> : <div className="divide-y divide-borderMuted">{recent.map(r => <div key={r.id} className="flex items-center justify-between gap-4 py-3"><div className="min-w-0"><p className="truncate text-sm font-semibold text-slateText-main">{r.serviceName}</p><p className="mt-1 truncate text-xs text-slateText-secondary">{r.customerName} · {new Date(r.createdAt).toLocaleString()}</p></div><span className="shrink-0 rounded-full bg-blue-50 px-2.5 py-1 text-xs font-semibold capitalize text-blue-700">{r.status.replace('_', ' ')}</span></div>)}</div>}
      </section>
      <section className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-card"><div className="flex items-center justify-between"><div><h3 className="font-bold text-slateText-main">Store readiness</h3><p className="mt-1 text-xs text-slateText-secondary">Current profile and availability</p></div><span className={`rounded-full px-3 py-1 text-xs font-semibold ${business.isVerified ? 'bg-emerald-50 text-emerald-700' : 'bg-amber-50 text-amber-800'}`}>{business.isVerified ? 'Approved' : 'Under review'}</span></div>
        <dl className="mt-5 space-y-3 text-sm"><div className="flex justify-between gap-4 border-b border-borderMuted pb-3"><dt className="text-slateText-secondary">Category</dt><dd className="text-right font-semibold text-slateText-main">{business.category}</dd></div><div className="flex justify-between gap-4 border-b border-borderMuted pb-3"><dt className="text-slateText-secondary">Service coverage</dt><dd className="text-right font-semibold text-slateText-main">{business.serviceRadiusKm} km</dd></div><div className="flex justify-between gap-4 border-b border-borderMuted pb-3"><dt className="text-slateText-secondary">Today’s hours</dt><dd className="text-right font-semibold text-slateText-main">{todayHours?.isOpen ? `${todayHours.openTime} – ${todayHours.closeTime}` : 'Closed'}</dd></div><div className="flex justify-between gap-4"><dt className="text-slateText-secondary">Request availability</dt><dd className="text-right font-semibold text-slateText-main">{business.acceptsRequests ? 'Accepting' : 'Paused'}</dd></div></dl>
        <div className="mt-5 flex items-center justify-between rounded-xl bg-slate-50 px-3 py-2 text-xs text-slateText-secondary"><span>Last synchronized</span><span>{updatedAt ? updatedAt.toLocaleTimeString() : 'Loading'}</span></div>
      </section>
    </div>
  </div>;
}
