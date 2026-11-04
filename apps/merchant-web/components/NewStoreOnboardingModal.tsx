'use client';

import { useEffect, useState } from 'react';
import { AlertCircle, Loader2, MapPin, Store, UploadCloud } from 'lucide-react';
import { createMerchantBusiness, merchantApi, uploadMediaFile } from '../lib/api';

type Category = { slug: string; name: string };
type Day = { weekday: number; opens_at: string; closes_at: string; is_closed: boolean };
const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

export function NewStoreOnboardingModal({ userPhone, onStoreCreated, onCancel }: { userPhone: string; onStoreCreated: () => Promise<void> | void; onCancel: () => void }) {
  const [categories, setCategories] = useState<Category[]>([]);
  const [name, setName] = useState(''); const [description, setDescription] = useState(''); const [categorySlug, setCategorySlug] = useState('');
  const [locality, setLocality] = useState(''); const [city, setCity] = useState(''); const [address, setAddress] = useState(''); const [postalCode, setPostalCode] = useState('');
  const [coordinates, setCoordinates] = useState<{ latitude: number; longitude: number } | null>(null); const [coverPhoto, setCoverPhoto] = useState('');
  const [hours, setHours] = useState<Day[]>(dayNames.map((_, weekday) => ({ weekday, opens_at: '', closes_at: '', is_closed: true })));
  const [error, setError] = useState(''); const [saving, setSaving] = useState(false);

  useEffect(() => { void merchantApi<Category[]>('/categories').then(setCategories).catch(() => setError('Unable to load business categories. Please retry.')); }, []);
  const useLocation = () => {
    if (!navigator.geolocation) { setError('This browser does not provide location access.'); return; }
    navigator.geolocation.getCurrentPosition(position => { setCoordinates({ latitude: position.coords.latitude, longitude: position.coords.longitude }); setError(''); }, () => setError('Location access was unavailable. Enable location permission and retry.'), { enableHighAccuracy: true, timeout: 15000 });
  };
  const updateDay = (index: number, changes: Partial<Day>) => setHours(prev => prev.map((day, i) => i === index ? { ...day, ...changes } : day));
  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault(); setError('');
    if (!coordinates) { setError('Capture the storefront location before submitting.'); return; }
    if (hours.some(day => !day.is_closed && (!day.opens_at || !day.closes_at))) { setError('Choose opening and closing times for every open day.'); return; }
    setSaving(true);
    try {
      await createMerchantBusiness({ name, description, category_slug: categorySlug, phone_e164: userPhone.replace(/\s/g, ''), whatsapp_e164: userPhone.replace(/\s/g, ''), address_text: address, locality, city, postal_code: postalCode, ...coordinates, cover_photo_url: coverPhoto, hours: hours.map(day => ({ ...day, opens_at: day.is_closed ? null : `${day.opens_at}:00`, closes_at: day.is_closed ? null : `${day.closes_at}:00` })) });
      await onStoreCreated();
    } catch (e) { setError(e instanceof Error ? e.message : 'The business could not be registered.'); }
    finally { setSaving(false); }
  };

  return <div className="fixed inset-0 z-50 overflow-y-auto bg-slate-950/55 p-3 backdrop-blur-sm sm:p-6"><div className="mx-auto my-3 w-full max-w-3xl overflow-hidden rounded-3xl border border-white/60 bg-surface shadow-2xl">
    <div className="bg-gradient-to-r from-[#173F9F] via-[#2457D6] to-[#168B87] p-6 text-white"><div className="flex items-center gap-3"><span className="grid h-12 w-12 place-items-center rounded-2xl bg-white/15"><Store/></span><div><h1 className="text-xl font-bold">Register your business</h1><p className="mt-1 text-sm text-blue-50">Create a real listing for {userPhone}. It will be submitted for review.</p></div></div></div>
    <form onSubmit={handleSubmit} className="max-h-[calc(100vh-150px)] space-y-5 overflow-y-auto p-5 sm:p-7">
      {error && <div role="alert" className="flex gap-2 rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800"><AlertCircle size={17} className="shrink-0"/>{error}</div>}
      <div className="grid gap-4 sm:grid-cols-2"><label className="text-sm font-semibold">Business name<input required minLength={2} maxLength={100} value={name} onChange={e => setName(e.target.value)} className="mt-1.5 min-h-11 w-full rounded-xl border border-borderMuted bg-background px-3"/></label><label className="text-sm font-semibold">Category<select required value={categorySlug} onChange={e => setCategorySlug(e.target.value)} className="mt-1.5 min-h-11 w-full rounded-xl border border-borderMuted bg-background px-3"><option value="">Choose a category</option>{categories.map(category => <option key={category.slug} value={category.slug}>{category.name}</option>)}</select></label>
      <label className="text-sm font-semibold">City<select required value={city} onChange={e => setCity(e.target.value)} className="mt-1.5 min-h-11 w-full rounded-xl border border-borderMuted bg-background px-3"><option value="">Select Cuttack or Jajpur</option><option value="Cuttack">Cuttack</option><option value="Jajpur">Jajpur</option></select></label><label className="text-sm font-semibold">Locality<input required value={locality} onChange={e => setLocality(e.target.value)} className="mt-1.5 min-h-11 w-full rounded-xl border border-borderMuted bg-background px-3"/></label>
      <label className="text-sm font-semibold sm:col-span-2">Street address<input required minLength={5} maxLength={240} value={address} onChange={e => setAddress(e.target.value)} className="mt-1.5 min-h-11 w-full rounded-xl border border-borderMuted bg-background px-3"/></label><label className="text-sm font-semibold">PIN code<input required inputMode="numeric" pattern="[0-9]{6}" maxLength={6} value={postalCode} onChange={e => setPostalCode(e.target.value)} className="mt-1.5 min-h-11 w-full rounded-xl border border-borderMuted bg-background px-3"/></label><label className="text-sm font-semibold">Business description<textarea maxLength={2000} value={description} onChange={e => setDescription(e.target.value)} className="mt-1.5 min-h-11 w-full rounded-xl border border-borderMuted bg-background px-3 py-2"/></label></div>
      <div className="rounded-2xl border border-borderMuted bg-blue-50/50 p-4"><div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="font-semibold">Business map pin</h2><p className="mt-1 text-xs text-slateText-secondary">GPS is used to verify the listing city and show the store nearby.</p>{coordinates && <p className="mt-2 text-xs font-medium text-emerald-700">Location captured · {coordinates.latitude.toFixed(5)}, {coordinates.longitude.toFixed(5)}</p>}</div><button type="button" onClick={useLocation} className="inline-flex min-h-11 items-center gap-2 rounded-xl border border-primary/20 bg-white px-4 text-sm font-semibold text-primary"><MapPin size={16}/>Use current location</button></div></div>
      <div className="rounded-2xl border border-borderMuted p-4"><h2 className="font-semibold">Weekly operating hours · Asia/Kolkata</h2><div className="mt-3 grid gap-2">{hours.map((day, index) => <div key={day.weekday} className="grid items-center gap-2 sm:grid-cols-[120px_1fr] sm:gap-4"><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!day.is_closed} onChange={e => updateDay(index, { is_closed: !e.target.checked, opens_at: e.target.checked ? '09:00' : '', closes_at: e.target.checked ? '18:00' : '' })}/>{dayNames[index]}</label>{day.is_closed ? <span className="text-sm text-slateText-muted">Closed</span> : <div className="flex items-center gap-2"><input required type="time" value={day.opens_at} onChange={e => updateDay(index, { opens_at: e.target.value })} className="min-h-10 rounded-lg border border-borderMuted px-2"/><span>to</span><input required type="time" value={day.closes_at} onChange={e => updateDay(index, { closes_at: e.target.value })} className="min-h-10 rounded-lg border border-borderMuted px-2"/></div>}</div>)}</div></div>
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-borderMuted p-4"><div><p className="text-sm font-semibold">Storefront photo (optional)</p><p className="mt-1 text-xs text-slateText-secondary">Upload an image owned by this account.</p></div><label className="inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-xl border border-borderMuted bg-white px-4 text-sm font-semibold"><UploadCloud size={16}/> {coverPhoto ? 'Photo added' : 'Upload photo'}<input type="file" accept="image/png,image/jpeg,image/webp" className="hidden" onChange={async e => { const file=e.target.files?.[0]; if(!file)return; try { const media=await uploadMediaFile(file,'storefront'); setCoverPhoto(media.url); setError(''); } catch(err) { setError(err instanceof Error ? err.message : 'Upload failed.'); } }}/></label></div>
      <div className="flex justify-end gap-3 border-t border-borderMuted pt-4"><button type="button" onClick={onCancel} className="min-h-11 rounded-xl border border-borderMuted px-4 text-sm font-semibold">Sign out</button><button disabled={saving || !categories.length} className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-primary px-5 text-sm font-semibold text-white shadow-sm hover:bg-primary-dark disabled:opacity-60">{saving && <Loader2 size={16} className="animate-spin"/>}{saving ? 'Submitting…' : 'Submit for review'}</button></div>
    </form>
  </div></div>;
}
