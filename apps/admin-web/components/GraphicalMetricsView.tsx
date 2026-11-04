'use client';

import React from 'react';
import { ArrowUpRight, Building2, ClipboardList, FileWarning, ShieldCheck, ShoppingBag, Tag, UsersRound, Activity, TrendingUp } from 'lucide-react';
import type { AdminTrends, Stats } from '@/lib/api';

interface GraphicalMetricsViewProps {
  stats: Stats | null;
  trends: AdminTrends | null;
  selectedCity: string;
  selectedRange: '7d' | '14d' | '30d';
  updatedAt: Date | null;
  metricsError: string | null;
  onNavigateTab: (tab: 'verification' | 'businesses' | 'reports') => void;
}

const number = new Intl.NumberFormat('en-IN');
const chartWidth = 720;
const chartHeight = 190;

function makePath(values: number[], closeToBaseline = false) {
  if (!values.length) return '';
  const max = Math.max(1, ...values);
  const xStep = (chartWidth - 44) / Math.max(1, values.length - 1);
  const points = values.map((value, index) => ({
    x: 22 + index * xStep,
    y: chartHeight - 24 - (value / max) * (chartHeight - 54),
  }));
  const line = points.map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x.toFixed(1)} ${point.y.toFixed(1)}`).join(' ');
  return closeToBaseline ? `${line} L ${points.at(-1)!.x.toFixed(1)} ${chartHeight - 24} L ${points[0].x.toFixed(1)} ${chartHeight - 24} Z` : line;
}

function TrendPanel({ title, subtitle, values, tone, gradient, dates }: { title: string; subtitle: string; values: number[]; tone: string; gradient: string; dates: string[] }) {
  const total = values.reduce((sum, value) => sum + value, 0);
  const last = values.at(-1) ?? 0;
  const max = Math.max(1, ...values);
  return (
    <article className="overflow-hidden rounded-3xl border border-slate-200/80 bg-white shadow-[0_18px_50px_-38px_rgba(20,30,60,.45)]">
      <div className="flex items-start justify-between gap-3 p-5"><div><h2 className="text-sm font-semibold text-slate-800">{title}</h2><p className="mt-1 text-xs text-slate-500">{subtitle}</p></div><span className={`rounded-xl p-2.5 ${tone}`}><TrendingUp className="h-4 w-4" /></span></div>
      <div className="flex items-end justify-between px-5"><div><span className="text-3xl font-bold tracking-tight text-slate-900">{number.format(total)}</span><span className="ml-2 text-xs text-slate-400">in range</span></div><div className="text-right"><span className="block text-lg font-bold text-slate-700">{number.format(last)}</span><span className="text-[10px] uppercase tracking-wide text-slate-400">today</span></div></div>
      {total === 0 ? <div className="mx-5 mb-5 mt-4 flex h-36 items-center justify-center rounded-2xl bg-slate-50 text-xs text-slate-400">No records in this period</div> : <div className="px-3 pt-4"><svg viewBox={`0 0 ${chartWidth} ${chartHeight}`} role="img" aria-label={`${title} daily trend chart`} className="h-40 w-full overflow-visible"><defs><linearGradient id={gradient} x1="0" x2="0" y1="0" y2="1"><stop offset="0%" stopColor="currentColor" stopOpacity=".24" /><stop offset="100%" stopColor="currentColor" stopOpacity=".01" /></linearGradient></defs><path d={`M 22 ${chartHeight - 24} H ${chartWidth - 22}`} stroke="#E8EDF5" strokeWidth="1" /><path d={`M 22 18 V ${chartHeight - 24}`} stroke="#F0F3F8" strokeWidth="1" />{values.length > 1 ? <><path d={makePath(values, true)} className={`${tone.split(' ')[1]}`} fill={`url(#${gradient})`} stroke="none" /><path d={makePath(values)} fill="none" className={tone.split(' ')[1]} stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />{values.map((value, index) => { const x = 22 + index * ((chartWidth - 44) / (values.length - 1)); const y = chartHeight - 24 - (value / max) * (chartHeight - 54); return <circle key={`${dates[index]}-${index}`} cx={x} cy={y} r="4" fill="white" className={tone.split(' ')[1]} stroke="currentColor" strokeWidth="2"><title>{dates[index]}: {value}</title></circle>; })}</> : <text x="30" y="80" fill="#94A3B8" fontSize="12">Not enough dates to draw a trend</text>}</svg><div className="flex justify-between px-2 pb-4 text-[10px] text-slate-400"><span>{dates[0] ? new Date(`${dates[0]}T00:00:00`).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : ''}</span><span>{dates[Math.floor(dates.length / 2)] ? new Date(`${dates[Math.floor(dates.length / 2)]}T00:00:00`).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : ''}</span><span>{dates.at(-1) ? new Date(`${dates.at(-1)}T00:00:00`).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : ''}</span></div></div>}
      <div className="flex items-center justify-between border-t border-slate-100 bg-gradient-to-r from-slate-50/80 to-white px-5 py-3 text-[11px] text-slate-500"><span>Daily records · Asia/Kolkata</span><span>Peak {number.format(max)}</span></div>
    </article>
  );
}

export const GraphicalMetricsView: React.FC<GraphicalMetricsViewProps> = ({ stats, trends, selectedCity, selectedRange, updatedAt, metricsError, onNavigateTab }) => {
  if (!stats) return null;
  const cards = [
    { title: 'Approved listings', value: stats.active_listings, note: 'Current directory', icon: Building2, tone: 'from-blue-600 to-indigo-600', action: () => onNavigateTab('businesses') },
    { title: 'Awaiting verification', value: stats.pending_verifications, note: 'Needs moderation', icon: ShieldCheck, tone: 'from-amber-500 to-orange-500', action: () => onNavigateTab('verification') },
    { title: 'Open reports', value: stats.reported_listings, note: 'Customer reports', icon: FileWarning, tone: 'from-rose-500 to-pink-600', action: () => onNavigateTab('reports') },
    { title: 'Offers for review', value: stats.pending_offers, note: 'Draft or pending', icon: Tag, tone: 'from-teal-500 to-cyan-600', action: undefined },
  ];
  const dates = trends?.series.map((point) => point.date) ?? [];
  const chartSeries = [
    { title: 'New listings', subtitle: 'Businesses submitted each day', values: trends?.series.map((point) => point.new_listings) ?? [], tone: 'bg-blue-50 text-blue-600', gradient: 'listingsFill' },
    { title: 'Service requests', subtitle: 'Customer requests created each day', values: trends?.series.map((point) => point.service_requests) ?? [], tone: 'bg-teal-50 text-teal-700', gradient: 'requestsFill' },
    { title: 'Customer orders', subtitle: 'Orders and reservations each day', values: trends?.series.map((point) => point.customer_orders) ?? [], tone: 'bg-violet-50 text-violet-700', gradient: 'ordersFill' },
  ];
  const categoryMax = Math.max(1, ...(trends?.categories.map((item) => item.count) ?? []));
  const activity = [
    { label: `Service requests · ${selectedRange}`, value: stats.service_requests, icon: ClipboardList, color: 'text-teal-700 bg-teal-50' },
    { label: `Customer orders · ${selectedRange}`, value: stats.customer_orders, icon: ShoppingBag, color: 'text-violet-700 bg-violet-50' },
    { label: 'Active user accounts', value: stats.active_accounts, icon: UsersRound, color: 'text-blue-700 bg-blue-50' },
    { label: `Notification events · ${selectedRange}`, value: stats.notification_events, icon: Activity, color: 'text-amber-700 bg-amber-50' },
  ];

  return (
    <section className="space-y-6 pb-10">
      <div className="relative overflow-hidden rounded-[28px] bg-gradient-to-r from-[#142852] via-[#254FD1] to-[#4B65E8] p-6 text-white shadow-[0_24px_70px_-36px_rgba(36,87,214,.65)] md:p-8"><div className="pointer-events-none absolute -right-16 -top-24 h-72 w-72 rounded-full border-[36px] border-white/10" /><div className="pointer-events-none absolute right-28 top-16 h-28 w-28 rounded-full bg-cyan-300/15 blur-2xl" /><div className="relative flex flex-wrap items-end justify-between gap-4"><div><p className="text-xs font-bold uppercase tracking-[.2em] text-blue-100">Executive command center</p><h1 className="mt-2 text-3xl font-bold tracking-tight md:text-4xl">Platform pulse</h1><p className="mt-2 max-w-xl text-sm leading-6 text-blue-100">Operational signals from live Grepmind Near records, refreshed automatically while this view is open.</p></div><div className="flex items-center gap-2 rounded-2xl border border-white/15 bg-white/10 px-4 py-3 backdrop-blur"><span className="relative flex h-2.5 w-2.5"><span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-300 opacity-75" /><span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-emerald-300" /></span><div><div className="text-sm font-semibold">Live database view</div><div className="text-[11px] text-blue-100">{selectedCity === 'All Cities' ? 'Cuttack + Jajpur' : selectedCity} · {selectedRange}</div></div></div></div></div>
      {metricsError ? <div role="alert" className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">Latest refresh failed. Showing the last successfully loaded data.</div> : null}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">{cards.map(({ title, value, note, icon: Icon, tone, action }) => <button key={title} onClick={action} disabled={!action} className={`group relative overflow-hidden rounded-3xl border border-slate-200/70 bg-white p-5 text-left shadow-[0_14px_36px_-28px_rgba(20,30,60,.5)] transition duration-200 ${action ? 'hover:-translate-y-1 hover:shadow-xl' : 'cursor-default'}`}><div className={`absolute inset-x-0 top-0 h-1 bg-gradient-to-r ${tone}`} /><div className="flex items-start justify-between"><span className={`flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br ${tone} text-white shadow-lg`}><Icon className="h-5 w-5" /></span>{action && <ArrowUpRight className="h-4 w-4 text-slate-400 transition group-hover:text-blue-600" />}</div><p className="mt-5 text-sm font-medium text-slate-500">{title}</p><div className="mt-1 flex items-baseline gap-2"><span className="text-3xl font-bold tracking-tight text-slate-900">{number.format(value)}</span><span className="text-xs text-slate-400">records</span></div><p className="mt-2 text-xs text-slate-400">{note}</p></button>)}</div>
      <div className="flex flex-wrap items-center justify-between gap-2"><div><h2 className="text-lg font-bold text-slate-900">Trend intelligence</h2><p className="text-xs text-slate-500">Daily counts grouped in Asia/Kolkata for the selected range.</p></div><span className="rounded-full border border-slate-200 bg-white px-3 py-1.5 text-[10px] font-semibold uppercase tracking-wide text-slate-500">Auto refresh · 30 sec</span></div>
      <div className="grid gap-4 xl:grid-cols-3">{chartSeries.map((series) => <TrendPanel key={series.title} {...series} dates={dates} />)}</div>
      <div className="grid gap-5 xl:grid-cols-[1.3fr_1fr]">
        <article className="rounded-3xl border border-slate-200/80 bg-white p-5 shadow-[0_18px_50px_-38px_rgba(20,30,60,.45)]"><div className="flex items-center justify-between"><div><h2 className="font-semibold text-slate-800">Category mix</h2><p className="mt-1 text-xs text-slate-500">New listings by category in the selected period.</p></div><span className="rounded-xl bg-gradient-to-br from-fuchsia-500 to-violet-600 p-2.5 text-white shadow-md"><Tag className="h-4 w-4" /></span></div>{!trends?.categories.length ? <div className="mt-5 rounded-2xl bg-slate-50 px-4 py-10 text-center text-xs text-slate-400">No listing category records in this period</div> : <div className="mt-5 space-y-4">{trends.categories.map((item, index) => <div key={item.category}><div className="mb-1.5 flex justify-between gap-4 text-xs"><span className="font-medium text-slate-700">{item.category}</span><span className="font-bold tabular-nums text-slate-800">{number.format(item.count)}</span></div><div className="h-2.5 overflow-hidden rounded-full bg-slate-100"><div className={`h-full rounded-full ${['bg-gradient-to-r from-blue-500 to-indigo-500', 'bg-gradient-to-r from-teal-400 to-emerald-500', 'bg-gradient-to-r from-violet-500 to-fuchsia-500', 'bg-gradient-to-r from-amber-400 to-orange-500'][index % 4]}`} style={{ width: `${Math.max(4, (item.count / categoryMax) * 100)}%` }} /></div></div>)}</div>}</article>
        <article className="rounded-3xl border border-slate-200/80 bg-white p-5 shadow-[0_18px_50px_-38px_rgba(20,30,60,.45)]"><div className="flex items-center justify-between"><div><h2 className="font-semibold text-slate-800">Operational signals</h2><p className="mt-1 text-xs text-slate-500">Current totals from the selected time window.</p></div><span className="rounded-xl bg-gradient-to-br from-cyan-500 to-teal-600 p-2.5 text-white shadow-md"><Activity className="h-4 w-4" /></span></div><div className="mt-3 divide-y divide-slate-100">{activity.map(({ label, value, icon: Icon, color }) => <div key={label} className="flex items-center justify-between gap-3 py-3"><div className="flex items-center gap-3"><span className={`flex h-9 w-9 items-center justify-center rounded-xl ${color}`}><Icon className="h-4 w-4" /></span><span className="text-xs text-slate-600">{label}</span></div><strong className="text-sm tabular-nums text-slate-900">{number.format(value)}</strong></div>)}</div><div className="mt-3 rounded-2xl border border-blue-100 bg-gradient-to-r from-blue-50 to-violet-50 p-3 text-[11px] leading-5 text-slate-600">Revenue, ratings, SLA, and search demand are omitted because those measurements are not backed by current production records.</div></article>
      </div>
      <p className="text-right text-[11px] text-slate-400">{updatedAt ? `Data refreshed ${updatedAt.toLocaleTimeString()}` : 'Waiting for first data refresh'} · Source: Grepmind Near PostgreSQL</p>
    </section>
  );
};
