'use client';

import { useMemo, useState } from 'react';
import { Activity, Building2, CalendarClock, MapPin, RefreshCw, UsersRound } from 'lucide-react';
import type { ListingActivity } from '@/lib/api';

interface ListingActivityViewProps {
  items: ListingActivity[];
  range: string;
  loading: boolean;
  error: string | null;
  updatedAt: Date | null;
  onRefresh: () => void;
}

export function ListingActivityView({ items, range, loading, error, updatedAt, onRefresh }: ListingActivityViewProps) {
  const [search, setSearch] = useState('');
  const accounts = useMemo(() => {
    const grouped = new Map<string, { id: string; name: string; phone: string; count: number; latest: string }>();
    for (const item of items) {
      const row = grouped.get(item.user_id) ?? { id: item.user_id, name: item.display_name || 'Account name not set', phone: item.phone_e164, count: 0, latest: item.created_at };
      row.count += 1;
      if (item.created_at > row.latest) row.latest = item.created_at;
      grouped.set(item.user_id, row);
    }
    return Array.from(grouped.values()).sort((a, b) => b.count - a.count || b.latest.localeCompare(a.latest));
  }, [items]);
  const filteredItems = items.filter((item) => `${item.business_name} ${item.phone_e164} ${item.display_name} ${item.category} ${item.city}`.toLowerCase().includes(search.toLowerCase()));
  const totalAccounts = accounts.length;

  return (
    <section className="space-y-6 pb-10">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div><p className="text-xs font-semibold uppercase tracking-[.16em] text-teal-700">People & listings</p><h1 className="mt-1 text-2xl font-bold tracking-tight text-[#172033] md:text-3xl">Team listing activity</h1><p className="mt-1 text-sm text-[#667085]">New listings grouped by the verified account that submitted them.</p></div>
        <button onClick={onRefresh} disabled={loading} className="inline-flex min-h-11 items-center gap-2 rounded-xl border border-teal-100 bg-white px-4 text-sm font-semibold text-teal-800 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md disabled:opacity-60"><RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />Refresh activity</button>
      </header>
      <div className="grid gap-4 sm:grid-cols-3">
        <div className="rounded-3xl border border-blue-100 bg-gradient-to-br from-blue-600 via-blue-600 to-indigo-700 p-5 text-white shadow-lg shadow-blue-200/60"><div className="flex items-center justify-between"><Building2 className="h-5 w-5" /><span className="rounded-full bg-white/15 px-2.5 py-1 text-[11px] font-semibold">{range}</span></div><div className="mt-5 text-3xl font-bold tabular-nums">{items.length}</div><div className="mt-1 text-sm text-blue-100">Recorded listing submissions</div></div>
        <div className="rounded-3xl border border-violet-100 bg-gradient-to-br from-white to-violet-50 p-5 shadow-sm"><div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-violet-600 text-white shadow-md shadow-violet-200"><UsersRound className="h-5 w-5" /></div><div className="mt-5 text-3xl font-bold tabular-nums text-[#172033]">{totalAccounts}</div><div className="mt-1 text-sm text-[#667085]">Accounts with submissions</div></div>
        <div className="rounded-3xl border border-teal-100 bg-gradient-to-br from-white to-teal-50 p-5 shadow-sm"><div className="flex h-10 w-10 items-center justify-center rounded-2xl bg-teal-600 text-white shadow-md shadow-teal-200"><Activity className="h-5 w-5" /></div><div className="mt-5 text-sm font-semibold text-[#172033]">Account-level attribution</div><div className="mt-1 text-xs leading-5 text-[#667085]">New events are recorded with the authenticated account ID and mobile number.</div></div>
      </div>
      <div className="rounded-3xl border border-[#E3E8F4] bg-white shadow-[0_20px_60px_-40px_rgba(23,32,51,.35)]">
        <div className="flex flex-col gap-3 border-b border-slate-100 p-5 md:flex-row md:items-center md:justify-between"><div><h2 className="font-semibold text-[#172033]">Submissions by account</h2><p className="text-xs text-[#667085]">Counts reflect recorded listing creation events in the selected range.</p></div><div className="flex items-center gap-2 rounded-xl border border-slate-200 bg-slate-50 px-3"><span className="text-xs text-slate-400">Search</span><input value={search} onChange={(event) => setSearch(event.target.value)} className="min-h-10 w-52 bg-transparent text-sm outline-none" placeholder="Name, phone, listing…" /></div></div>
        {error ? <div role="alert" className="m-5 rounded-2xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">{error}</div> : null}
        {!error && loading ? <div className="animate-pulse p-8 text-center text-sm text-slate-500">Loading verified creation events…</div> : null}
        {!error && !loading && items.length === 0 ? <div className="p-12 text-center"><CalendarClock className="mx-auto h-8 w-8 text-slate-300" /><h3 className="mt-3 font-semibold text-slate-700">No recorded listing submissions</h3><p className="mt-1 text-sm text-slate-500">New merchant registrations will appear here with the submitting account.</p></div> : null}
        {!error && !loading && items.length > 0 ? <div className="overflow-x-auto"><table className="w-full min-w-[780px] text-left text-sm"><thead className="bg-slate-50 text-[11px] uppercase tracking-wide text-slate-500"><tr><th className="px-5 py-3">Account</th><th className="px-5 py-3">User ID</th><th className="px-5 py-3">Submissions</th><th className="px-5 py-3">Latest listing</th></tr></thead><tbody className="divide-y divide-slate-100">{accounts.map((account) => <tr key={account.id} className="hover:bg-blue-50/30"><td className="px-5 py-4"><div className="font-semibold text-slate-800">{account.name}</div><div className="mt-0.5 font-mono text-xs text-slate-500">{account.phone}</div></td><td className="px-5 py-4 font-mono text-[11px] text-slate-500">{account.id}</td><td className="px-5 py-4"><span className="inline-flex rounded-full bg-blue-50 px-3 py-1 font-bold text-blue-700">{account.count}</span></td><td className="px-5 py-4 text-xs text-slate-600">{new Date(account.latest).toLocaleString()}</td></tr>)}</tbody></table></div> : null}
      </div>
      {!error && !loading && filteredItems.length > 0 ? <div className="rounded-3xl border border-[#E3E8F4] bg-white p-5 shadow-sm"><div className="mb-4 flex items-center justify-between"><div><h2 className="font-semibold text-[#172033]">Listing details</h2><p className="text-xs text-[#667085]">Individual records in {range}.</p></div><span className="rounded-full bg-teal-50 px-3 py-1 text-xs font-semibold text-teal-800">{filteredItems.length} entries</span></div><div className="grid gap-3 md:grid-cols-2">{filteredItems.map((item) => <article key={item.id} className="rounded-2xl border border-slate-100 bg-gradient-to-br from-white to-slate-50 p-4"><div className="flex items-start justify-between gap-3"><div><h3 className="font-semibold text-slate-800">{item.business_name}</h3><p className="mt-1 text-xs text-slate-500">{item.category} · <span className="capitalize">{item.status.replaceAll('_', ' ')}</span></p></div><span className="rounded-lg bg-indigo-50 px-2.5 py-1 text-[11px] font-semibold text-indigo-700">{item.city}</span></div><div className="mt-3 flex items-center justify-between border-t border-slate-100 pt-3 text-xs"><span className="flex items-center gap-1.5 text-slate-600"><MapPin className="h-3.5 w-3.5 text-teal-600" />{item.display_name || item.phone_e164}</span><time className="text-slate-500">{new Date(item.created_at).toLocaleDateString()}</time></div></article>)}</div></div> : null}
      <p className="rounded-2xl border border-amber-100 bg-amber-50 px-4 py-3 text-xs leading-5 text-amber-900">Attribution identifies the account that submitted the listing. It cannot identify a separate staff member who assisted unless that person used their own verified account for submission. Older listings without a recorded creation event are not backfilled or guessed.</p>
      {updatedAt ? <p className="text-right text-[11px] text-slate-400">Updated {updatedAt.toLocaleTimeString()}</p> : null}
    </section>
  );
}
