'use client';

import { useEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { Building2, Check, Clock3, MapPin, Printer, Store, X } from 'lucide-react';
import { getBusinessApplication, getBusinessStorefront, type BusinessApplication } from '@/lib/api';

const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const enterpriseTypes = { retail: 'Retail shop & showroom', service_pro: 'Skilled trade & professional', food: 'Food, dining & cafe', wellness: 'Salon, spa & wellness' };
const operatingModes = { store_only: 'Walk-in only', home_only: 'On-site visits', both: 'Store & on-site' };
const formatDate = new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Kolkata' });

function Field({ label, children }: { label: string; children: ReactNode }) {
  return <div className="min-w-0"><dt className="text-xs font-medium text-slate-600">{label}</dt><dd className="mt-0.5 break-words text-sm font-semibold text-slate-900">{children ?? 'Not provided'}</dd></div>;
}

function Section({ title, icon, children }: { title: string; icon: ReactNode; children: ReactNode }) {
  return <section className="application-section rounded-2xl border border-slate-200 bg-white p-5"><h3 className="mb-4 flex items-center gap-2 text-sm font-bold text-slate-900">{icon}{title}</h3>{children}</section>;
}

type Props = {
  id: string;
  onClose: () => void;
  onDecision: (item: BusinessApplication, action: 'approve' | 'reject', reason: string) => Promise<boolean>;
};

export function MerchantApplicationDrawer({ id, onClose, onDecision }: Props) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [record, setRecord] = useState<BusinessApplication | null>(null);
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [photo, setPhoto] = useState<{ url?: string; failed?: boolean } | null>(null);
  const [action, setAction] = useState<'approve' | 'reject'>('approve');
  const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false);
  const [decisionError, setDecisionError] = useState(false);

  useEffect(() => {
    const dialog = dialogRef.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    let photoUrl: string | undefined;
    async function load() {
      let application: BusinessApplication;
      try {
        application = await getBusinessApplication(id, controller.signal);
      } catch {
        if (!controller.signal.aborted) setFailed(true);
        return;
      }
      if (controller.signal.aborted) return;
      setRecord(application);
      if (!application.has_storefront_photo) return;
      try {
        const blob = await getBusinessStorefront(id, controller.signal);
        if (controller.signal.aborted) return;
        photoUrl = URL.createObjectURL(blob);
        setPhoto({ url: photoUrl });
      } catch {
        if (!controller.signal.aborted) setPhoto({ failed: true });
      }
    }
    void load();
    return () => {
      controller.abort();
      if (photoUrl) URL.revokeObjectURL(photoUrl);
    };
  }, [id, attempt]);

  function reload() {
    setFailed(false);
    setPhoto(null);
    setRecord(null);
    setAttempt((count) => count + 1);
  }

  async function decide() {
    if (!record || saving || reason.trim().length < (action === 'approve' ? 8 : 1)) return;
    setSaving(true);
    setDecisionError(false);
    try {
      if (await onDecision(record, action, reason.trim())) onClose();
      else setDecisionError(true);
    } catch {
      setDecisionError(true);
    } finally {
      setSaving(false);
    }
  }

  async function printApplication() {
    const photoElement = dialogRef.current?.querySelector('img');
    if (photoElement) await photoElement.decode().catch(() => undefined);
    if (!dialogRef.current?.open) return;
    const previousTitle = document.title;
    document.title = `Merchant Application - ${record?.name ?? id}`;
    try { window.print(); } finally { document.title = previousTitle; }
  }

  const details = record?.application;
  const alreadyApproved = record?.status === 'approved';
  const reviewable = record && (['pending', 'pending_review', 'draft'].includes(record.status) || (alreadyApproved && record.verification_status === 'pending'));
  const approvalLabel = alreadyApproved ? 'Verify listing' : 'Verify & approve';
  return createPortal(
    <dialog ref={dialogRef} aria-labelledby="merchant-application-title" onCancel={(event) => { event.preventDefault(); if (!saving) onClose(); }}
      className="merchant-application-dialog fixed inset-y-0 left-auto right-0 m-0 h-[100dvh] max-h-none w-full max-w-4xl overflow-y-auto bg-slate-50 text-left text-slate-900 shadow-2xl backdrop:bg-slate-950/45">
      <header className="sticky top-0 z-10 flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-white px-5 py-4 sm:px-8">
        <div><p className="text-xs font-semibold text-teal-800">Abashyaka · Admin review</p><h2 id="merchant-application-title" className="mt-1 text-xl font-bold">Merchant application</h2></div>
        <div className="application-controls flex items-center gap-2">
          <button type="button" onClick={() => void printApplication()} disabled={!record || (record.has_storefront_photo && !photo)} className="inline-flex min-h-10 items-center gap-2 rounded-xl border border-slate-200 px-3 text-sm font-semibold hover:bg-slate-50 disabled:opacity-50"><Printer className="h-4 w-4" aria-hidden />Print / Save PDF</button>
          <button type="button" onClick={onClose} disabled={saving} aria-label="Close application" className="grid h-10 w-10 place-items-center rounded-xl text-slate-600 hover:bg-slate-100 disabled:opacity-50"><X className="h-5 w-5" aria-hidden /></button>
        </div>
      </header>
      {!record && <div className="p-8 text-sm text-slate-600">{failed ? <div role="alert">Could not load the application. <button type="button" onClick={reload} className="font-semibold text-teal-800 underline">Retry</button></div> : <p role="status">Loading application…</p>}</div>}
      {record && <div className="application-content space-y-4 px-5 py-5 sm:px-8">
        <div className="application-section rounded-2xl border border-teal-100 bg-gradient-to-br from-teal-50 to-white p-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div><h3 className="break-words text-2xl font-bold tracking-tight">{record.name}</h3><p className="mt-1 text-sm text-slate-600">{record.category_name || record.category_slug} · {record.locality || record.city || 'Area unavailable'}</p></div>
            <span className="rounded-full border border-slate-200 bg-white px-3 py-1 text-xs font-semibold capitalize text-slate-700">{record.status.replaceAll('_', ' ')}</span>
          </div>
          <dl className="mt-4 grid gap-3 sm:grid-cols-3">
            <Field label="Application reference">GN-{record.id.slice(0, 8).toUpperCase()}</Field>
            <Field label="Submitted (IST)">{formatDate.format(new Date(record.created_at))}</Field>
            <Field label="Verification">{record.verification_status.replaceAll('_', ' ')}</Field>
          </dl>
        </div>

        <div className="application-columns grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.75fr)]">
          <Section title="Business and contact" icon={<Building2 className="h-4 w-4 text-teal-700" aria-hidden />}>
            <dl className="grid grid-cols-2 gap-4">
              <Field label="Owner name">{details?.owner_name || record.owner_name}</Field>
              <Field label="Enterprise type">{details && enterpriseTypes[details.enterprise_type]}</Field>
              <Field label="Business phone">{record.phone_e164}</Field>
              <Field label="WhatsApp">{record.whatsapp_e164}</Field>
              <Field label="Owner account phone">{record.owner_phone}</Field>
              <Field label="Business email">{details?.email}</Field>
              <Field label="GSTIN / Business PAN">{details?.no_gst ? 'Local artisan / No GST' : details?.tax_id}</Field>
              <div className="col-span-2 whitespace-pre-wrap"><Field label="Description">{record.description || null}</Field></div>
            </dl>
          </Section>
          <Section title="Storefront photo" icon={<Store className="h-4 w-4 text-teal-700" aria-hidden />}>
            {photo?.url && !photo.failed ? (
              // eslint-disable-next-line @next/next/no-img-element -- Authenticated object URL owned by this drawer.
              <img src={photo.url} alt={`Storefront of ${record.name}`} onError={() => setPhoto({ failed: true })} className="application-photo w-full rounded-xl bg-slate-50 object-contain" />
            ) : <p className="grid min-h-32 place-items-center rounded-xl border border-dashed border-slate-200 px-4 text-center text-sm text-slate-600">{photo?.failed ? 'The storefront photo could not be loaded.' : record.has_storefront_photo ? 'Loading storefront photo…' : 'No storefront photo was submitted.'}</p>}
          </Section>
        </div>

        <div className="application-columns grid gap-4 sm:grid-cols-2">
          <Section title="Storefront location" icon={<MapPin className="h-4 w-4 text-teal-700" aria-hidden />}>
            <dl className="grid grid-cols-2 gap-4">
              <div className="col-span-2"><Field label="Street address and landmark">{record.address_text}</Field></div>
              <Field label="Locality">{record.locality}</Field>
              <Field label="City / district">{record.city}</Field>
              <Field label="Postal PIN">{record.postal_code}</Field>
              <Field label="GPS coordinates">{record.latitude !== null && record.longitude !== null ? `${record.latitude.toFixed(6)}, ${record.longitude.toFixed(6)}` : null}</Field>
            </dl>
          </Section>
          <Section title="Operations" icon={<Clock3 className="h-4 w-4 text-teal-700" aria-hidden />}>
            <dl className="grid grid-cols-2 gap-4">
              <Field label="Operating mode">{details && operatingModes[details.operating_mode]}</Field>
              <Field label="Requested service radius">{details ? `${details.service_radius_km} km` : null}</Field>
            </dl>
            <h4 className="mt-5 text-xs font-semibold text-slate-700">Operating hours ({record.time_zone})</h4>
            {record.hours.length ? <dl className="mt-2 divide-y divide-slate-100 text-sm">{record.hours.map((hour) => (
              <div key={hour.weekday} className="flex justify-between gap-3 py-1"><dt>{weekdays[hour.weekday]}</dt><dd className="font-medium">{hour.is_closed ? 'Closed' : `${hour.opens_at}–${hour.closes_at}`}</dd></div>
            ))}</dl> : <p className="mt-2 text-sm text-slate-600">No hours were recorded.</p>}
          </Section>
        </div>
        {!details && <p className="rounded-xl bg-slate-100 p-3 text-sm text-slate-700">This application was submitted before additional registration fields were recorded.</p>}
        {reviewable && <form className="application-controls space-y-3 rounded-2xl border border-slate-200 bg-white p-5" onSubmit={(event) => { event.preventDefault(); void decide(); }}>
          <h3 className="text-sm font-bold">Review decision</h3>
          <label className="block text-sm font-medium">Decision<select value={action} onChange={(event) => { setAction(event.target.value === 'reject' ? 'reject' : 'approve'); setReason(''); }} disabled={saving} className="ml-2 rounded-lg border border-slate-300 px-2 py-1"><option value="approve">{approvalLabel}</option><option value="reject">Reject</option></select></label>
          <label htmlFor="application-reason" className="block text-sm font-medium">{action === 'approve' ? 'Offline evidence reference' : 'Rejection reason'}</label>
          <textarea id="application-reason" rows={2} maxLength={400} required minLength={action === 'approve' ? 8 : 1} value={reason} onChange={(event) => setReason(event.target.value)} disabled={saving} className="w-full rounded-xl border border-slate-300 p-3 text-sm" />
          {action === 'approve' && <p className="text-xs text-slate-600">Record the reference to the evidence you reviewed offline. Keep sensitive document numbers out of this note.</p>}
          {decisionError && <p role="alert" className="text-sm text-rose-700">The decision could not be confirmed. Reload the application to check its current status before retrying.</p>}
          <div className="flex flex-wrap justify-end gap-2">
            {decisionError && <button type="button" onClick={() => { setDecisionError(false); reload(); }} className="rounded-xl border border-slate-200 px-4 py-2 text-sm font-semibold">Reload application</button>}
            <button type="submit" disabled={saving || decisionError || reason.trim().length < (action === 'approve' ? 8 : 1)} className={`inline-flex min-h-10 items-center gap-2 rounded-xl px-4 text-sm font-semibold text-white disabled:opacity-50 ${action === 'approve' ? 'bg-teal-800' : 'bg-rose-700'}`}>{action === 'approve' && <Check className="h-4 w-4" aria-hidden />}{saving ? 'Saving…' : action === 'approve' ? approvalLabel : 'Reject application'}</button>
          </div>
        </form>}
      </div>}
    </dialog>, document.body,
  );
}
