'use client';

import { useEffect, useState } from 'react';
import { CheckCircle2, Clock3, MapPin, Save, ShieldCheck, Zap } from 'lucide-react';
import type { Business, OperatingHoursDay } from '../lib/types';

interface HoursCoverageManagerProps {
  business: Business;
  hours: OperatingHoursDay[];
  onSaveHours: (hours: OperatingHoursDay[]) => Promise<void> | void;
  onSaveRadius: (radius: number) => Promise<void> | void;
}

export const HoursCoverageManager = ({ business, hours, onSaveHours, onSaveRadius }: HoursCoverageManagerProps) => {
  const [schedule, setSchedule] = useState(hours);
  const [radius, setRadius] = useState(business.serviceRadiusKm || 5);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  useEffect(() => { setSchedule(hours); }, [hours]);
  useEffect(() => { setRadius(business.serviceRadiusKm || 5); }, [business.id, business.serviceRadiusKm]);

  const change = (index: number, update: Partial<OperatingHoursDay>) => setSchedule(current => current.map((day, i) => i === index ? { ...day, ...update } : day));
  const save = async () => {
    setSaving(true); setSaved(false); setSaveError(null);
    try {
      if (schedule.some(day => day.isOpen && (!day.openTime || !day.closeTime || day.openTime === day.closeTime))) {
        setSaveError('Choose valid, different opening and closing times for every open day.');
        return;
      }
      await onSaveHours(schedule);
      await onSaveRadius(radius);
      setSaved(true);
      window.setTimeout(() => setSaved(false), 2500);
    } catch (error) {
      setSaveError(error instanceof Error ? error.message : 'The schedule could not be saved. Try again.');
    } finally { setSaving(false); }
  };

  return <div className="grid gap-5 xl:grid-cols-[minmax(0,1.6fr)_minmax(300px,.8fr)]">
    <section className="overflow-hidden rounded-2xl border border-borderMuted bg-surface shadow-card">
      <div className="flex items-center justify-between border-b border-borderMuted bg-gradient-to-r from-blue-50 to-white px-5 py-4">
        <div className="flex items-center gap-3"><span className="grid h-10 w-10 place-items-center rounded-xl bg-primary text-white"><Clock3 size={19}/></span><div><h2 className="font-bold text-slateText-main">Weekly opening hours</h2><p className="text-xs text-slateText-secondary">Times are saved in Asia/Kolkata.</p></div></div>
        <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-semibold text-primary">IST · UTC+05:30</span>
      </div>
      <div className="divide-y divide-borderMuted px-5">
        {schedule.map((day, index) => <div key={day.day} className="grid gap-3 py-4 sm:grid-cols-[130px_1fr] sm:items-center">
          <div className="flex items-center gap-3"><button type="button" aria-label={`${day.isOpen ? 'Close' : 'Open'} ${day.day}`} aria-pressed={day.isOpen} onClick={() => change(index, { isOpen: !day.isOpen })} className={`relative h-6 w-11 rounded-full transition ${day.isOpen ? 'bg-primary' : 'bg-slate-300'}`}><span className={`absolute top-1 h-4 w-4 rounded-full bg-white shadow transition-all ${day.isOpen ? 'left-6' : 'left-1'}`}/></button><span className="text-sm font-semibold text-slateText-main">{day.day}</span></div>
          {day.isOpen ? <div className="flex items-center gap-2"><input aria-label={`${day.day} opens`} type="time" value={day.openTime} onChange={e => change(index, { openTime: e.target.value })} className="min-h-11 rounded-xl border border-borderMuted bg-background px-3 text-sm"/><span className="text-slateText-muted">to</span><input aria-label={`${day.day} closes`} type="time" value={day.closeTime} onChange={e => change(index, { closeTime: e.target.value })} className="min-h-11 rounded-xl border border-borderMuted bg-background px-3 text-sm"/></div> : <span className="text-sm text-slateText-muted">Closed</span>}
        </div>)}
      </div>
    </section>
    <div className="space-y-5">
      <section className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-card">
        <div className="flex items-center gap-3"><span className="grid h-10 w-10 place-items-center rounded-xl bg-teal-50 text-teal-700"><MapPin size={19}/></span><div><h2 className="font-bold text-slateText-main">Service coverage</h2><p className="text-xs text-slateText-secondary">Used to match nearby requests.</p></div></div>
        <div className="mt-6 flex items-baseline justify-between"><span className="text-sm text-slateText-secondary">Radius</span><strong className="text-2xl font-black text-primary">{radius} km</strong></div>
        <input aria-label="Service radius in kilometers" type="range" min="1" max="50" value={radius} onChange={e => setRadius(Number(e.target.value))} className="mt-3 w-full accent-primary"/>
        <div className="mt-1 flex justify-between text-xs text-slateText-muted"><span>1 km</span><span>50 km</span></div>
        <div className="mt-4 rounded-xl bg-blue-50/70 p-3 text-xs text-blue-900"><MapPin size={14} className="mr-1 inline"/>{business.locality}, {business.city}</div>
      </section>
      <section className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-card">
        <div className="flex items-start gap-3"><span className={`grid h-10 w-10 shrink-0 place-items-center rounded-xl ${business.acceptsRequests ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-600'}`}><Zap size={18}/></span><div><h2 className="font-bold text-slateText-main">Request availability</h2><p className="mt-1 text-xs leading-relaxed text-slateText-secondary">{business.acceptsRequests ? 'Customers can currently send service requests.' : 'New service requests are paused for this business.'}</p></div></div>
        <p className="mt-4 flex items-center gap-2 text-xs text-slateText-secondary"><ShieldCheck size={15} className="text-primary"/>Availability updates are stored on your business profile.</p>
      </section>
      {saveError && <p role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-700">{saveError}</p>}
      <button onClick={save} disabled={saving} className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl bg-primary px-4 text-sm font-semibold text-white shadow-sm hover:bg-primary-dark disabled:opacity-60">{saved ? <CheckCircle2 size={17}/> : <Save size={17}/>} {saving ? 'Saving…' : saved ? 'Saved successfully' : 'Save schedule & coverage'}</button>
    </div>
  </div>;
};
