'use client';

import { useState } from 'react';
import { CalendarDays, Plus, Trash2, Tag } from 'lucide-react';
import type { MerchantOffer } from '../lib/types';

export function OffersManager({ offers, onCreate, onDelete }: {
  offers: MerchantOffer[];
  onCreate: (input: { title: string; description: string; starts_at: string; ends_at: string; discount_percent?: number }) => void;
  onDelete: (offer: MerchantOffer) => void;
}) {
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [discount, setDiscount] = useState('');
  const [startsAt, setStartsAt] = useState('');
  const [endsAt, setEndsAt] = useState('');

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    onCreate({ title, description, starts_at: new Date(startsAt).toISOString(), ends_at: new Date(endsAt).toISOString(), discount_percent: discount ? Number(discount) : undefined });
    setOpen(false); setTitle(''); setDescription(''); setDiscount(''); setStartsAt(''); setEndsAt('');
  };

  return <section className="space-y-5">
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-borderMuted bg-surface p-5 shadow-card">
      <div><h2 className="text-lg font-bold text-slateText-main">Offers & promotions</h2><p className="mt-1 text-sm text-slateText-secondary">Create and track offers submitted for moderation.</p></div>
      <button onClick={() => setOpen(true)} className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-primary px-4 text-sm font-semibold text-white shadow-sm hover:bg-primary-dark"><Plus size={17}/> Create offer</button>
    </div>
    {offers.length === 0 ? <div className="rounded-2xl border border-dashed border-borderMuted bg-surface p-12 text-center"><Tag className="mx-auto text-primary"/><h3 className="mt-3 font-semibold text-slateText-main">No offers yet</h3><p className="mt-1 text-sm text-slateText-secondary">Offers you create will appear here with their moderation status.</p></div> :
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">{offers.map((offer) => <article key={offer.id} className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-card">
        <div className="flex items-start justify-between gap-3"><div><span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${offer.status === 'approved' ? 'bg-emerald-50 text-emerald-700' : offer.status === 'rejected' ? 'bg-rose-50 text-rose-700' : 'bg-amber-50 text-amber-700'}`}>{offer.status}</span><h3 className="mt-3 text-base font-bold text-slateText-main">{offer.title}</h3></div><button aria-label={`Delete ${offer.title}`} onClick={() => onDelete(offer)} className="rounded-lg p-2 text-slateText-muted hover:bg-rose-50 hover:text-rose-600"><Trash2 size={16}/></button></div>
        {offer.description && <p className="mt-2 text-sm text-slateText-secondary">{offer.description}</p>}
        <div className="mt-4 flex items-center gap-2 border-t border-borderMuted pt-3 text-xs text-slateText-secondary"><CalendarDays size={15}/><span>{new Date(offer.starts_at).toLocaleDateString()} – {new Date(offer.ends_at).toLocaleDateString()}</span></div>
        {offer.discount_percent !== undefined && <p className="mt-3 inline-flex rounded-lg bg-blue-50 px-3 py-1.5 text-sm font-bold text-primary">{offer.discount_percent}% off</p>}
      </article>)}</div>}
    {open && <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/45 p-4"><form onSubmit={submit} className="w-full max-w-lg space-y-4 rounded-2xl border border-borderMuted bg-surface p-6 shadow-2xl">
      <div><h3 className="text-lg font-bold text-slateText-main">Create an offer</h3><p className="mt-1 text-sm text-slateText-secondary">New offers are submitted as pending for review.</p></div>
      <label className="block text-sm font-medium text-slateText-main">Title<input required minLength={2} maxLength={100} value={title} onChange={e => setTitle(e.target.value)} className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3 py-2.5"/></label>
      <label className="block text-sm font-medium text-slateText-main">Description<textarea maxLength={2000} value={description} onChange={e => setDescription(e.target.value)} className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3 py-2.5"/></label>
      <div className="grid gap-3 sm:grid-cols-3"><label className="text-sm font-medium">Discount %<input type="number" min="0" max="100" value={discount} onChange={e => setDiscount(e.target.value)} className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3 py-2.5"/></label><label className="text-sm font-medium">Starts<input required type="datetime-local" value={startsAt} onChange={e => setStartsAt(e.target.value)} className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3 py-2.5"/></label><label className="text-sm font-medium">Ends<input required type="datetime-local" value={endsAt} onChange={e => setEndsAt(e.target.value)} className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3 py-2.5"/></label></div>
      <div className="flex justify-end gap-2"><button type="button" onClick={() => setOpen(false)} className="min-h-11 rounded-xl border border-borderMuted px-4 text-sm font-semibold">Cancel</button><button className="min-h-11 rounded-xl bg-primary px-4 text-sm font-semibold text-white">Submit offer</button></div>
    </form></div>}
  </section>;
}
