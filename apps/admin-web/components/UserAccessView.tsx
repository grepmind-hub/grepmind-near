'use client';

import { useMemo, useState, type FormEvent } from 'react';
import { KeyRound, Search, ShieldAlert, ShieldCheck, UserRoundPlus, Save, LockKeyhole } from 'lucide-react';
import type { UserAccessRecord } from '@/lib/api';

const roleOptions = [
  { id: 'admin', label: 'Admin', hint: 'Platform operations' },
  { id: 'merchant', label: 'Merchant', hint: 'Business workspace' },
  { id: 'customer', label: 'Customer', hint: 'Discovery and bookings' },
  { id: 'professional', label: 'Professional', hint: 'Service provider profile' },
] as const;

interface UserAccessViewProps {
  users: UserAccessRecord[];
  canManageRoles: boolean;
  loading: boolean;
  error: string | null;
  onRefresh: () => void;
  onSave: (phone: string, name: string, roles: string[]) => Promise<void>;
}

export function UserAccessView({ users, canManageRoles, loading, error, onRefresh, onSave }: UserAccessViewProps) {
  const [query, setQuery] = useState('');
  const [drafts, setDrafts] = useState<Record<string, string[]>>({});
  const [savingId, setSavingId] = useState<string | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [phone, setPhone] = useState('+91');
  const [name, setName] = useState('');
  const [newRoles, setNewRoles] = useState<string[]>(['customer']);
  const [message, setMessage] = useState<string | null>(null);
  const visible = useMemo(() => users.filter((user) => `${user.phone_e164} ${user.display_name} ${user.roles.join(' ')}`.toLowerCase().includes(query.toLowerCase())), [users, query]);

  function currentRoles(user: UserAccessRecord) { return drafts[user.id] ?? user.roles; }
  function toggleRole(target: string[], role: string, checked: boolean) { return checked ? Array.from(new Set([...target, role])) : target.filter((item) => item !== role); }

  async function saveExisting(user: UserAccessRecord) {
    const roles = currentRoles(user);
    if (!canManageRoles || roles.length === 0) return;
    setSavingId(user.id); setMessage(null);
    try { await onSave(user.phone_e164, user.display_name, roles); setDrafts((state) => { const next = { ...state }; delete next[user.id]; return next; }); setMessage(`Saved access for ${user.phone_e164}. Existing sessions were revoked.`); }
    catch { setMessage(`Could not save access for ${user.phone_e164}.`); }
    finally { setSavingId(null); }
  }

  async function addAccount(event: FormEvent) {
    event.preventDefault();
    const normalizedPhone = phone.replace(/\s+/g, '');
    if (!/^\+91[6-9]\d{9}$/.test(normalizedPhone) || newRoles.length === 0) return;
    setSavingId('new'); setMessage(null);
    try { await onSave(normalizedPhone, name.trim(), newRoles); setShowAdd(false); setPhone('+91'); setName(''); setNewRoles(['customer']); setMessage(`Access saved for ${normalizedPhone}.`); }
    catch { setMessage(`Could not create or update ${normalizedPhone}.`); }
    finally { setSavingId(null); }
  }

  return (
    <section className="space-y-6 pb-10">
      <header className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-xs font-semibold uppercase tracking-[.16em] text-indigo-700">Identity & permissions</p><h1 className="mt-1 text-2xl font-bold tracking-tight text-[#172033] md:text-3xl">User access control</h1><p className="mt-1 text-sm text-[#667085]">Assign platform roles to verified user accounts.</p></div><button disabled={!canManageRoles} onClick={() => setShowAdd(true)} className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-gradient-to-r from-indigo-600 to-blue-600 px-4 text-sm font-semibold text-white shadow-lg shadow-indigo-200 transition hover:-translate-y-0.5 hover:shadow-xl disabled:cursor-not-allowed disabled:opacity-50"><UserRoundPlus className="h-4 w-4" />Add account access</button></header>
      {!canManageRoles ? <div className="flex gap-3 rounded-2xl border border-amber-200 bg-gradient-to-r from-amber-50 to-white p-4 text-sm text-amber-900"><LockKeyhole className="mt-0.5 h-5 w-5 shrink-0" /><div><strong>Read-only access</strong><p className="mt-1 text-xs leading-5">Only the protected primary superadmin can change platform roles. This session can review the account directory.</p></div></div> : <div className="flex gap-3 rounded-2xl border border-blue-100 bg-gradient-to-r from-blue-50 via-white to-violet-50 p-4 text-sm text-slate-700"><ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-blue-700" /><div><strong>Protected role administration</strong><p className="mt-1 text-xs leading-5">Role changes are audited and revoke the account’s existing sessions, so the next API request reflects its new access immediately.</p></div></div>}
      {message ? <div role="status" className="rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700 shadow-sm">{message}</div> : null}
      {error ? <div role="alert" className="rounded-2xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">{error}</div> : null}
      <div className="overflow-hidden rounded-3xl border border-[#E3E8F4] bg-white shadow-[0_20px_60px_-40px_rgba(23,32,51,.35)]"><div className="flex flex-col justify-between gap-3 border-b border-slate-100 bg-gradient-to-r from-indigo-50/70 via-white to-teal-50/50 p-5 sm:flex-row sm:items-center"><div><h2 className="font-semibold text-[#172033]">Accounts & assigned roles</h2><p className="text-xs text-[#667085]">Newest {users.length} accounts returned by the protected API.</p></div><div className="flex min-h-10 items-center gap-2 rounded-xl border border-slate-200 bg-white px-3"><Search className="h-4 w-4 text-slate-400" /><input value={query} onChange={(event) => setQuery(event.target.value)} aria-label="Search user accounts" className="w-56 bg-transparent text-sm outline-none" placeholder="Search name or mobile" /></div></div>
        {!error && loading ? <div className="animate-pulse p-8 text-center text-sm text-slate-500">Loading user access…</div> : null}
        {!error && !loading && visible.length === 0 ? <div className="p-12 text-center text-sm text-slate-500">No accounts match this search.</div> : null}
        {!error && !loading && visible.length > 0 ? <div className="divide-y divide-slate-100">{visible.map((user) => { const roles = currentRoles(user); const protectedRoot = user.phone_e164 === '+910000000000'; const dirty = Boolean(drafts[user.id]); return <article key={user.id} className="grid gap-5 p-5 xl:grid-cols-[minmax(220px,.8fr)_minmax(500px,1.8fr)_auto] xl:items-center"><div className="min-w-0"><div className="flex items-center gap-2"><span className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-indigo-600 to-blue-500 text-white shadow-md"><KeyRound className="h-4 w-4" /></span><div className="min-w-0"><h3 className="truncate text-sm font-semibold text-slate-800">{user.display_name || 'Name not set'}</h3><p className="font-mono text-xs text-slate-500">{user.phone_e164}</p></div></div><p className="mt-2 break-all font-mono text-[10px] text-slate-400">{user.id}</p>{protectedRoot ? <span className="mt-2 inline-flex items-center gap-1 rounded-full bg-amber-50 px-2.5 py-1 text-[10px] font-bold text-amber-800"><ShieldAlert className="h-3 w-3" />Protected root account</span> : null}</div><div className="grid grid-cols-2 gap-2 sm:grid-cols-4">{roleOptions.map((option) => <label key={option.id} className={`flex min-h-14 cursor-pointer items-start gap-2 rounded-xl border p-2.5 transition ${roles.includes(option.id) ? 'border-blue-200 bg-gradient-to-br from-blue-50 to-indigo-50' : 'border-slate-200 bg-white hover:bg-slate-50'} ${(protectedRoot || !canManageRoles) ? 'cursor-not-allowed opacity-60' : ''}`}><input type="checkbox" checked={roles.includes(option.id)} disabled={protectedRoot || !canManageRoles} onChange={(event) => setDrafts((state) => ({ ...state, [user.id]: toggleRole(roles, option.id, event.target.checked) }))} className="mt-0.5 h-4 w-4 accent-blue-600" /><span><span className="block text-xs font-semibold text-slate-800">{option.label}</span><span className="mt-0.5 block text-[10px] leading-4 text-slate-500">{option.hint}</span></span></label>)}</div><div className="flex items-center justify-end gap-2">{dirty ? <button disabled={!canManageRoles || roles.length === 0 || savingId === user.id} onClick={() => void saveExisting(user)} className="inline-flex min-h-10 items-center gap-2 rounded-xl bg-indigo-600 px-3 text-xs font-bold text-white shadow-sm hover:bg-indigo-700 disabled:opacity-50"><Save className="h-3.5 w-3.5" />{savingId === user.id ? 'Saving…' : 'Save roles'}</button> : <span className="text-[10px] font-semibold uppercase tracking-wide text-slate-400">{user.status}</span>}</div></article>; })}</div> : null}
      </div>

      {showAdd ? <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-sm"><form onSubmit={addAccount} className="w-full max-w-xl rounded-3xl border border-white/70 bg-white p-6 shadow-2xl"><div className="flex items-center gap-3"><div className="rounded-2xl bg-gradient-to-br from-indigo-600 to-blue-600 p-3 text-white"><UserRoundPlus className="h-5 w-5" /></div><div><h2 className="text-lg font-bold text-slate-900">Assign user roles</h2><p className="text-xs text-slate-500">Creates an account record when the mobile number is new.</p></div></div><label className="mt-5 block text-xs font-semibold text-slate-700">Indian mobile number</label><input value={phone} onChange={(event) => setPhone(event.target.value)} placeholder="+919876543210" className="mt-1 min-h-11 w-full rounded-xl border border-slate-200 px-3 text-sm outline-none focus:border-indigo-400 focus:ring-4 focus:ring-indigo-100" /><label className="mt-4 block text-xs font-semibold text-slate-700">Display name</label><input value={name} onChange={(event) => setName(event.target.value)} maxLength={120} className="mt-1 min-h-11 w-full rounded-xl border border-slate-200 px-3 text-sm outline-none focus:border-indigo-400 focus:ring-4 focus:ring-indigo-100" /><div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">{roleOptions.map((option) => <label key={option.id} className="flex min-h-12 items-center gap-2 rounded-xl border border-slate-200 px-3 text-xs font-semibold text-slate-700"><input type="checkbox" checked={newRoles.includes(option.id)} onChange={(event) => setNewRoles((roles) => toggleRole(roles, option.id, event.target.checked))} className="h-4 w-4 accent-indigo-600" />{option.label}</label>)}</div><div className="mt-6 flex justify-end gap-2"><button type="button" onClick={() => setShowAdd(false)} className="min-h-10 rounded-xl border border-slate-200 px-4 text-sm font-semibold text-slate-600">Cancel</button><button type="submit" disabled={savingId === 'new' || newRoles.length === 0} className="min-h-10 rounded-xl bg-gradient-to-r from-indigo-600 to-blue-600 px-4 text-sm font-semibold text-white shadow-md disabled:opacity-50">{savingId === 'new' ? 'Saving…' : 'Save account access'}</button></div></form></div> : null}
    </section>
  );
}
