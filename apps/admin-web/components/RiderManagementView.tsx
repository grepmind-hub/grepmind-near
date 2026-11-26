'use client';

import { useCallback, useEffect, useState } from 'react';
import {
  Bike,
  Check,
  Download,
  FileImage,
  Printer,
  RefreshCw,
  Search,
  ShieldBan,
  UserCheck,
  UserPlus,
  UserRoundCheck,
  X,
} from 'lucide-react';
import { api } from '@/lib/api';

type RiderRow = {
  id: string;
  rider_code?: string;
  user_id: string;
  display_name: string;
  phone_e164: string;
  vehicle_type: string;
  vehicle_details: string;
  address?: string;
  onboarding_source?: string;
  field_executive_code?: string;
  field_executive_name?: string;
  is_online?: boolean;
  availability_expires_at?: string | null;
  status: string;
  review_notes?: string | null;
  submitted_at?: string | null;
};

type RiderDetail = RiderRow & {
  localities: { locality_id: string; name: string; district: string; status: string }[];
  documents: {
    id: string;
    code: string;
    label: string;
    content_type: string;
    size_bytes: number;
    review_status: string;
    rejection_reason?: string | null;
  }[];
};

type Requirement = {
  id?: string;
  code: string;
  label: string;
  vehicle_type: string;
  is_required: boolean;
  is_active: boolean;
};

type FieldExecutiveRow = {
  id: string;
  user_id: string;
  executive_code: string;
  display_name: string;
  phone_e164: string;
  is_active: boolean;
  onboarded_riders_count: number;
  onboarded_merchants_count: number;
};

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export function RiderManagementView() {
  const [rows, setRows] = useState<RiderRow[]>([]);
  const [selected, setSelected] = useState<RiderDetail | null>(null);
  const [requirements, setRequirements] = useState<Requirement[]>([]);
  const [fieldExecutives, setFieldExecutives] = useState<FieldExecutiveRow[]>([]);
  const [filter, setFilter] = useState('submitted');
  const [sourceFilter, setSourceFilter] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [approvedLocalities, setApprovedLocalities] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [reason, setReason] = useState('');
  const [newRequirement, setNewRequirement] = useState({
    code: '',
    label: '',
    vehicle_type: 'any',
    is_required: false,
    is_active: true,
  });
  const [newExec, setNewExec] = useState({ phone_e164: '', display_name: '' });

  const refresh = useCallback(async () => {
    try {
      const [list, reqs, execs] = await Promise.all([
        api.get<{ data: RiderRow[] }>('/admin/rider-applications', { params: { status: filter } }),
        api.get<{ data: Requirement[] }>('/admin/rider-document-requirements'),
        api.get<{ data: FieldExecutiveRow[] }>('/admin/field-executives').catch(() => ({ data: { data: [] } })),
      ]);
      setRows(list.data.data ?? []);
      setRequirements(reqs.data.data ?? []);
      setFieldExecutives(execs.data.data ?? []);
      setError(null);
    } catch {
      setError('Rider records could not be loaded. Retry after checking Admin API access.');
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => {
    const timer = window.setTimeout(() => void refresh(), 0);
    return () => window.clearTimeout(timer);
  }, [refresh]);

  async function open(row: RiderRow) {
    try {
      const res = await api.get<{ data: RiderDetail }>(`/admin/rider-applications/${row.id}`);
      setSelected(res.data.data);
      setApprovedLocalities(
        res.data.data.localities.filter((x) => x.status === 'requested').map((x) => x.locality_id),
      );
      setReason('');
    } catch {
      setError('Rider application details could not be loaded.');
    }
  }

  async function decision(value: 'under_review' | 'changes_requested' | 'approved' | 'rejected') {
    if (!selected) return;
    if ((value === 'changes_requested' || value === 'rejected') && reason.trim().length < 10) {
      setError('Enter a review reason of at least 10 characters.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await api.post(`/admin/rider-applications/${selected.id}/review`, {
        decision: value,
        reason,
        approved_locality_ids: value === 'approved' ? approvedLocalities : [],
      });
      setSelected(null);
      await refresh();
    } catch (e: unknown) {
      const msg =
        (e as { response?: { data?: { error?: { message?: string } } } })?.response?.data?.error?.message ??
        'The review decision was not saved.';
      setError(msg);
    } finally {
      setBusy(false);
    }
  }

  async function reviewDocument(id: string, status: 'accepted' | 'rejected') {
    const why = status === 'rejected' ? window.prompt('Reason for rejection (10–500 characters)') ?? '' : '';
    if (status === 'rejected' && why.trim().length < 10) return;
    setBusy(true);
    try {
      await api.post(`/admin/rider-documents/${id}/review`, { status, reason: why });
      if (selected) await open(selected);
      await refresh();
    } catch {
      setError('Document review could not be saved.');
    } finally {
      setBusy(false);
    }
  }

  async function showDocument(id: string) {
    try {
      const result = await api.get<Blob>(`/admin/rider-documents/${id}/content`, { responseType: 'blob' });
      const url = URL.createObjectURL(result.data);
      const tab = window.open(url, '_blank', 'noopener,noreferrer');
      if (!tab) URL.revokeObjectURL(url);
      else window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
    } catch {
      setError('Private rider document could not be opened.');
    }
  }

  async function riderAction(kind: 'suspend' | 'reactivate') {
    if (!selected) return;
    let why = '';
    if (kind === 'suspend') {
      why = window.prompt('Suspension reason (10–500 characters)') ?? '';
      if (why.trim().length < 10) return;
    }
    setBusy(true);
    try {
      await api.post(`/admin/riders/${selected.id}/${kind}`, kind === 'suspend' ? { reason: why } : {});
      setSelected(null);
      await refresh();
    } catch {
      setError(`Rider ${kind} was not confirmed.`);
    } finally {
      setBusy(false);
    }
  }

  async function saveRequirement() {
    setBusy(true);
    setError(null);
    try {
      await api.post('/admin/rider-document-requirements', newRequirement);
      setNewRequirement({ code: '', label: '', vehicle_type: 'any', is_required: false, is_active: true });
      await refresh();
    } catch (e: unknown) {
      const msg =
        (e as { response?: { data?: { error?: { message?: string } } } })?.response?.data?.error?.message ??
        'Requirement update failed. Only the primary superadmin can change this configurable checklist.';
      setError(msg);
    } finally {
      setBusy(false);
    }
  }

  async function grantFieldExecutive() {
    setBusy(true);
    setError(null);
    try {
      await api.post('/admin/field-executives', newExec);
      setNewExec({ phone_e164: '', display_name: '' });
      await refresh();
    } catch (e: unknown) {
      const msg =
        (e as { response?: { data?: { error?: { message?: string } } } })?.response?.data?.error?.message ??
        'Could not grant Field Executive designation.';
      setError(msg);
    } finally {
      setBusy(false);
    }
  }

  async function revokeFieldExecutive(id: string) {
    setBusy(true);
    setError(null);
    try {
      await api.post(`/admin/field-executives/${id}/revoke`);
      await refresh();
    } catch {
      setError('Could not revoke Field Executive.');
    } finally {
      setBusy(false);
    }
  }

  function printOrExportRider(detail: RiderDetail, mode: 'print' | 'pdf') {
    const win = window.open('', '_blank', 'width=900,height=720');
    if (!win) {
      setError('Allow popups to print or export the Rider summary.');
      return;
    }
    const onboardedBy =
      detail.onboarding_source === 'field_executive'
        ? `Field Executive (${detail.field_executive_code || 'AFE'} · ${detail.field_executive_name || ''})`
        : 'Self-Registered';
    const docRows =
      detail.documents.length === 0
        ? '<tr><td colspan="3">No documents uploaded</td></tr>'
        : detail.documents
            .map(
              (d) =>
                `<tr><td>${escapeHtml(d.label)}</td><td>${escapeHtml(d.content_type)}</td><td>${escapeHtml(d.review_status.toUpperCase())}</td></tr>`,
            )
            .join('');
    const locRows = detail.localities
      .map((l) => `<li>${escapeHtml(l.name)}, ${escapeHtml(l.district)} (${escapeHtml(l.status)})</li>`)
      .join('');

    win.document.write(`<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Abashyaka Rider Profile · ${escapeHtml(detail.rider_code || detail.display_name)}</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; color: #172033; padding: 32px; max-width: 820px; margin: auto; }
    header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #00545B; padding-bottom: 14px; margin-bottom: 20px; }
    .brand { font-size: 20px; font-weight: 800; color: #00545B; }
    .badge { background: #E6F7F7; color: #00545B; padding: 4px 10px; border-radius: 8px; font-weight: 700; font-size: 13px; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 18px; }
    .box { border: 1px solid #E4E7EC; border-radius: 10px; padding: 12px; }
    .label { font-size: 11px; text-transform: uppercase; color: #667085; font-weight: 700; }
    .val { font-size: 14px; font-weight: 600; margin-top: 4px; }
    table { width: 100%; border-collapse: collapse; margin-top: 8px; }
    th, td { border: 1px solid #E4E7EC; padding: 8px 10px; text-align: left; font-size: 13px; }
    th { background: #F7F8FA; }
    .note { margin-top: 24px; font-size: 11px; color: #667085; }
  </style>
</head>
<body>
  <header>
    <div>
      <div class="brand">Abashyaka · Rider Application Summary</div>
      <div style="font-size:12px;color:#667085;">${mode === 'pdf' ? 'Use Save as PDF in the print dialog' : 'Official Admin Printout'}</div>
    </div>
    <div class="badge">${escapeHtml(detail.rider_code || 'AR-PENDING')}</div>
  </header>
  <div class="grid">
    <div class="box"><div class="label">Full Name</div><div class="val">${escapeHtml(detail.display_name)}</div></div>
    <div class="box"><div class="label">Phone</div><div class="val">${escapeHtml(detail.phone_e164)}</div></div>
    <div class="box"><div class="label">Application Status</div><div class="val">${escapeHtml(detail.status.toUpperCase())}</div></div>
    <div class="box"><div class="label">Live Availability</div><div class="val">${detail.is_online ? 'ONLINE' : 'OFFLINE'}</div></div>
    <div class="box"><div class="label">Vehicle</div><div class="val">${escapeHtml(detail.vehicle_type.replaceAll('_', ' '))}${detail.vehicle_details ? ' · ' + escapeHtml(detail.vehicle_details) : ''}</div></div>
    <div class="box"><div class="label">Onboarded Via</div><div class="val">${escapeHtml(onboardedBy)}</div></div>
  </div>
  <div class="box" style="margin-bottom:18px;">
    <div class="label">Complete Residential Address</div>
    <div class="val">${escapeHtml(detail.address || 'Not provided')}</div>
  </div>
  <div class="box" style="margin-bottom:18px;">
    <div class="label">Requested Service Localities</div>
    <ul>${locRows || '<li>None</li>'}</ul>
  </div>
  <div class="box">
    <div class="label">Verification Documents</div>
    <table><thead><tr><th>Document</th><th>Format</th><th>Review Status</th></tr></thead><tbody>${docRows}</tbody></table>
  </div>
  <p class="note">Generated from Abashyaka Admin Portal · ${new Date().toISOString()}</p>
  <script>window.onload = function(){ window.print(); };</script>
</body>
</html>`);
    win.document.close();
  }

  const filteredRows = rows.filter((r) => {
    const src = r.onboarding_source || 'self';
    if (sourceFilter !== 'all' && src !== sourceFilter) return false;
    const q = searchQuery.trim().toLowerCase();
    if (!q) return true;
    return (
      r.display_name.toLowerCase().includes(q) ||
      r.phone_e164.toLowerCase().includes(q) ||
      (r.rider_code && r.rider_code.toLowerCase().includes(q)) ||
      (r.address && r.address.toLowerCase().includes(q)) ||
      (r.field_executive_code && r.field_executive_code.toLowerCase().includes(q)) ||
      (r.field_executive_name && r.field_executive_name.toLowerCase().includes(q))
    );
  });

  return (
    <section className="space-y-6">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-xs font-bold uppercase tracking-wider text-[#0F766E]">People &amp; safety</p>
          <h1 className="mt-1 text-2xl font-bold text-[#172033]">Rider management</h1>
          <p className="mt-1 text-sm text-[#667085]">
            Review rider applications, live Online/Offline availability, Field Executive attribution, and approved areas.
          </p>
        </div>
        <button
          onClick={() => void refresh()}
          className="inline-flex min-h-11 items-center gap-2 rounded-xl border bg-white px-4 text-sm font-semibold"
        >
          <RefreshCw size={16} /> Refresh
        </button>
      </header>

      {error && (
        <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">
          {error}
        </div>
      )}

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_350px]">
        {/* Rider Applications Table */}
        <div className="overflow-hidden rounded-2xl border border-[#E4E7EC] bg-white shadow-sm">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b p-4">
            <div className="flex items-center gap-2">
              <h2 className="font-semibold text-[#172033]">Rider applications</h2>
              <span className="rounded-full bg-[#EBF0FF] px-2.5 py-0.5 text-xs font-semibold text-[#2457D6]">
                {filteredRows.length}
              </span>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <div className="flex items-center rounded-lg border border-[#D0D5DD] bg-white px-2.5 py-1.5">
                <Search size={14} className="mr-1.5 text-[#98A2B3]" />
                <input
                  type="text"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Search AR-1000, name, address, AFE-1000..."
                  className="w-52 text-xs text-[#172033] placeholder-[#98A2B3] focus:outline-none"
                />
              </div>
              <select
                aria-label="Filter onboarding source"
                className="min-h-9 rounded-lg border px-2.5 text-xs font-medium"
                value={sourceFilter}
                onChange={(e) => setSourceFilter(e.target.value)}
              >
                <option value="all">All Sources</option>
                <option value="self">Self-Registered</option>
                <option value="field_executive">Field Executive (AFE)</option>
              </select>
              <select
                aria-label="Filter rider applications"
                className="min-h-9 rounded-lg border px-2.5 text-xs font-medium capitalize"
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
              >
                {['submitted', 'under_review', 'changes_requested', 'approved', 'rejected', 'suspended', 'draft'].map(
                  (x) => (
                    <option key={x} value={x}>
                      {x.replaceAll('_', ' ')}
                    </option>
                  ),
                )}
              </select>
            </div>
          </div>

          {loading ? (
            <p className="p-8 text-sm text-[#667085]">Loading riders…</p>
          ) : filteredRows.length === 0 ? (
            <div className="p-10 text-center text-sm text-[#667085]">No rider applications in this view.</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-left text-xs">
                <thead>
                  <tr className="border-b border-[#E4E7EC] bg-[#F7F8FA] font-semibold text-[#667085]">
                    <th className="px-4 py-3">Rider ID</th>
                    <th className="px-4 py-3">Rider &amp; Phone</th>
                    <th className="px-4 py-3">Availability</th>
                    <th className="px-4 py-3">Vehicle</th>
                    <th className="px-4 py-3">Address</th>
                    <th className="px-4 py-3">Onboarded Via</th>
                    <th className="px-4 py-3">Status</th>
                    <th className="px-4 py-3 text-right">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[#F2F4F7]">
                  {filteredRows.map((row) => (
                    <tr key={row.id} className="hover:bg-slate-50">
                      <td className="whitespace-nowrap px-4 py-3 font-mono font-bold text-[#0F766E]">
                        {row.rider_code || '—'}
                      </td>
                      <td className="px-4 py-3">
                        <div className="font-semibold text-[#172033]">{row.display_name}</div>
                        <div className="text-[11px] text-[#667085]">{row.phone_e164}</div>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3">
                        <span
                          className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11px] font-bold ${
                            row.is_online
                              ? 'bg-emerald-50 text-emerald-700 border border-emerald-200'
                              : 'bg-slate-100 text-slate-600'
                          }`}
                        >
                          <span
                            className={`h-2 w-2 rounded-full ${row.is_online ? 'bg-emerald-500' : 'bg-slate-400'}`}
                          />
                          {row.is_online ? 'Online' : 'Offline'}
                        </span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 capitalize text-[#344054]">
                        {row.vehicle_type.replaceAll('_', ' ')}
                      </td>
                      <td className="max-w-[200px] truncate px-4 py-3 text-[#667085]" title={row.address || ''}>
                        {row.address || '—'}
                      </td>
                      <td className="px-4 py-3">
                        {row.onboarding_source === 'field_executive' ? (
                          <div>
                            <span className="inline-block rounded-full border border-teal-200 bg-teal-50 px-2 py-0.5 text-[10px] font-bold text-teal-800">
                              {row.field_executive_code || 'AFE'}
                            </span>
                            {row.field_executive_name && (
                              <div className="mt-0.5 text-[11px] text-[#667085]">{row.field_executive_name}</div>
                            )}
                          </div>
                        ) : (
                          <span className="inline-block rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-semibold text-slate-700">
                            Self
                          </span>
                        )}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3">
                        <span className="rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-semibold capitalize">
                          {row.status.replaceAll('_', ' ')}
                        </span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right">
                        <button
                          onClick={() => void open(row)}
                          className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-1.5 text-xs font-semibold text-blue-700 hover:bg-blue-100"
                        >
                          Review
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Right Rail: Verification Checklist & Field Executives (AFE-1000) */}
        <div className="space-y-5">
          <div className="rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-sm">
            <div className="flex items-center gap-2">
              <UserCheck size={18} className="text-[#0F766E]" />
              <h2 className="font-semibold text-[#172033]">Field Executives (AFE-1000)</h2>
            </div>
            <p className="mt-1.5 text-xs leading-5 text-[#667085]">
              Admin-only designation to track who onboarded each Rider and Merchant.
            </p>
            <div className="mt-3 space-y-2">
              <input
                className="min-h-10 w-full rounded-lg border px-3 text-xs"
                placeholder="User phone (+91...)"
                value={newExec.phone_e164}
                onChange={(e) => setNewExec({ ...newExec, phone_e164: e.target.value })}
              />
              <input
                className="min-h-10 w-full rounded-lg border px-3 text-xs"
                placeholder="Executive name (optional)"
                value={newExec.display_name}
                onChange={(e) => setNewExec({ ...newExec, display_name: e.target.value })}
              />
              <button
                disabled={busy || !newExec.phone_e164.trim()}
                onClick={() => void grantFieldExecutive()}
                className="inline-flex min-h-10 w-full items-center justify-center gap-1.5 rounded-lg bg-[#0F766E] px-3 text-xs font-semibold text-white disabled:opacity-50"
              >
                <UserPlus size={14} /> Grant AFE-1000 Designation
              </button>
            </div>
            <div className="mt-4 max-h-56 space-y-2 overflow-y-auto">
              {fieldExecutives.length === 0 ? (
                <p className="text-xs text-[#667085]">No Field Executives assigned yet.</p>
              ) : (
                fieldExecutives.map((fe) => (
                  <div key={fe.id} className="rounded-xl border border-[#E4E7EC] bg-slate-50 p-3 text-xs">
                    <div className="flex items-center justify-between gap-2">
                      <span className="font-mono font-bold text-[#0F766E]">{fe.executive_code}</span>
                      <span
                        className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${
                          fe.is_active ? 'bg-emerald-100 text-emerald-800' : 'bg-slate-200 text-slate-600'
                        }`}
                      >
                        {fe.is_active ? 'Active' : 'Revoked'}
                      </span>
                    </div>
                    <div className="mt-1 font-semibold text-[#172033]">{fe.display_name}</div>
                    <div className="text-[11px] text-[#667085]">{fe.phone_e164}</div>
                    <div className="mt-1.5 flex items-center justify-between text-[11px] text-[#344054]">
                      <span>
                        Riders: <b>{fe.onboarded_riders_count}</b> · Merchants: <b>{fe.onboarded_merchants_count}</b>
                      </span>
                      {fe.is_active && (
                        <button
                          disabled={busy}
                          onClick={() => void revokeFieldExecutive(fe.id)}
                          className="font-semibold text-rose-700 hover:underline"
                        >
                          Revoke
                        </button>
                      )}
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>

          <div className="rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-sm">
            <div className="flex items-center gap-2">
              <FileImage size={18} className="text-blue-700" />
              <h2 className="font-semibold">Verification checklist</h2>
            </div>
            <p className="mt-2 text-xs leading-5 text-[#667085]">
              Configurable after appropriate legal review. Changes require primary superadmin.
            </p>
            <div className="mt-4 space-y-2">
              {requirements.map((r) => (
                <div key={r.id ?? r.code} className="rounded-lg bg-slate-50 p-3 text-sm">
                  <b>{r.label}</b>
                  <div className="text-xs text-[#667085]">
                    {r.vehicle_type} · {r.is_required ? 'Required' : 'Optional'}
                  </div>
                </div>
              ))}
            </div>
            <div className="mt-5 space-y-2 border-t pt-4">
              <input
                className="min-h-10 w-full rounded-lg border px-3 text-sm"
                placeholder="Requirement code (e.g. aadhaar)"
                value={newRequirement.code}
                onChange={(e) => setNewRequirement({ ...newRequirement, code: e.target.value })}
              />
              <input
                className="min-h-10 w-full rounded-lg border px-3 text-sm"
                placeholder="Display label (e.g. Aadhaar Card)"
                value={newRequirement.label}
                onChange={(e) => setNewRequirement({ ...newRequirement, label: e.target.value })}
              />
              <select
                className="min-h-10 w-full rounded-lg border px-3 text-sm"
                value={newRequirement.vehicle_type}
                onChange={(e) => setNewRequirement({ ...newRequirement, vehicle_type: e.target.value })}
              >
                {['any', 'bicycle', 'two_wheeler', 'three_wheeler', 'other'].map((x) => (
                  <option key={x}>{x}</option>
                ))}
              </select>
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={newRequirement.is_required}
                  onChange={(e) => setNewRequirement({ ...newRequirement, is_required: e.target.checked })}
                />
                Required for selected vehicle
              </label>
              <button
                disabled={busy || !newRequirement.code || !newRequirement.label}
                onClick={() => void saveRequirement()}
                className="min-h-10 w-full rounded-lg bg-[#2457D6] px-3 text-sm font-semibold text-white disabled:opacity-50"
              >
                Save verification rule
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Rider Review Modal with Print & Export PDF */}
      {selected && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Rider application review"
          className="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/40 p-0 sm:items-center sm:p-5"
        >
          <div className="max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-t-3xl bg-white p-5 shadow-2xl sm:rounded-3xl sm:p-7">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <div className="flex items-center gap-2">
                  <p className="text-xs font-bold uppercase tracking-wider text-[#0F766E]">Application review</p>
                  {selected.rider_code && (
                    <span className="rounded-md bg-teal-50 px-2 py-0.5 font-mono text-xs font-bold text-[#0F766E]">
                      {selected.rider_code}
                    </span>
                  )}
                  <span
                    className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold ${
                      selected.is_online ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-600'
                    }`}
                  >
                    <Bike size={12} /> {selected.is_online ? 'Online' : 'Offline'}
                  </span>
                </div>
                <h2 className="mt-1 text-xl font-bold">{selected.display_name}</h2>
                <p className="text-sm text-[#667085]">
                  {selected.phone_e164} · {selected.vehicle_type.replaceAll('_', ' ')}
                  {selected.vehicle_details ? ` · ${selected.vehicle_details}` : ''}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => printOrExportRider(selected, 'print')}
                  className="inline-flex min-h-9 items-center gap-1.5 rounded-lg border px-3 text-xs font-semibold text-[#344054] hover:bg-slate-50"
                >
                  <Printer size={14} /> Print
                </button>
                <button
                  onClick={() => printOrExportRider(selected, 'pdf')}
                  className="inline-flex min-h-9 items-center gap-1.5 rounded-lg bg-[#0F766E] px-3 text-xs font-semibold text-white hover:bg-[#0D635C]"
                >
                  <Download size={14} /> Export PDF
                </button>
                <button
                  aria-label="Close review"
                  onClick={() => setSelected(null)}
                  className="rounded-lg p-2 hover:bg-slate-100"
                >
                  <X size={20} />
                </button>
              </div>
            </div>

            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              <div className="rounded-xl border bg-slate-50/70 p-3.5 text-sm">
                <div className="text-xs font-bold uppercase text-[#667085]">Complete Address</div>
                <div className="mt-1 font-medium text-[#172033]">{selected.address || 'Not provided'}</div>
              </div>
              <div className="rounded-xl border bg-slate-50/70 p-3.5 text-sm">
                <div className="text-xs font-bold uppercase text-[#667085]">Onboarded Via</div>
                <div className="mt-1 font-medium text-[#172033]">
                  {selected.onboarding_source === 'field_executive'
                    ? `Field Executive · ${selected.field_executive_code || 'AFE'} (${selected.field_executive_name || ''})`
                    : 'Self-Registered'}
                </div>
              </div>
            </div>

            <div className="mt-4 grid gap-4 md:grid-cols-2">
              <div className="rounded-xl border p-4">
                <h3 className="font-semibold">Requested service areas</h3>
                {selected.localities.map((x) => (
                  <div key={x.locality_id} className="mt-2 flex justify-between text-sm">
                    <span>
                      {x.name}, {x.district}
                    </span>
                    <span className="text-[#667085]">{x.status}</span>
                  </div>
                ))}
              </div>
              <div className="rounded-xl border p-4">
                <h3 className="font-semibold">Verification documents</h3>
                {selected.documents.length === 0 ? (
                  <p className="mt-2 text-sm text-[#667085]">No documents uploaded.</p>
                ) : (
                  selected.documents.map((d) => (
                    <div key={d.id} className="mt-3 rounded-lg bg-slate-50 p-3">
                      <div className="flex justify-between gap-2">
                        <b className="text-sm">{d.label}</b>
                        <span className="text-xs">{d.review_status}</span>
                      </div>
                      <div className="mt-2 flex flex-wrap gap-2">
                        <button
                          onClick={() => void showDocument(d.id)}
                          className="min-h-9 rounded-lg border bg-white px-3 text-xs font-semibold"
                        >
                          View private file
                        </button>
                        {d.review_status === 'pending' && (
                          <>
                            <button
                              disabled={busy}
                              onClick={() => void reviewDocument(d.id, 'accepted')}
                              className="min-h-9 rounded-lg bg-emerald-600 px-3 text-xs font-semibold text-white"
                            >
                              <Check size={14} />
                            </button>
                            <button
                              disabled={busy}
                              onClick={() => void reviewDocument(d.id, 'rejected')}
                              className="min-h-9 rounded-lg bg-rose-600 px-3 text-xs font-semibold text-white"
                            >
                              <X size={14} />
                            </button>
                          </>
                        )}
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>

            <label className="mt-5 block text-sm font-medium">
              Review reason (required for changes or rejection)
              <textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                maxLength={500}
                rows={3}
                className="mt-1 w-full rounded-xl border p-3"
                placeholder="Explain the requested change or decision"
              />
            </label>

            <div className="mt-5 flex flex-wrap gap-2">
              {['submitted', 'under_review', 'changes_requested'].includes(selected.status) && (
                <>
                  <button
                    disabled={busy}
                    onClick={() => void decision('under_review')}
                    className="min-h-11 rounded-xl border px-4 text-sm font-semibold"
                  >
                    Mark under review
                  </button>
                  <button
                    disabled={busy}
                    onClick={() => void decision('changes_requested')}
                    className="min-h-11 rounded-xl border border-amber-300 bg-amber-50 px-4 text-sm font-semibold text-amber-800"
                  >
                    Request changes
                  </button>
                  <button
                    disabled={busy}
                    onClick={() => void decision('rejected')}
                    className="min-h-11 rounded-xl border border-rose-300 bg-rose-50 px-4 text-sm font-semibold text-rose-800"
                  >
                    Reject
                  </button>
                  <button
                    disabled={busy}
                    onClick={() => void decision('approved')}
                    className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-[#2457D6] px-4 text-sm font-semibold text-white"
                  >
                    <UserRoundCheck size={16} />
                    Approve &amp; grant requested areas
                  </button>
                </>
              )}
              {selected.status === 'approved' && (
                <button
                  disabled={busy}
                  onClick={() => void riderAction('suspend')}
                  className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-rose-700 px-4 text-sm font-semibold text-white"
                >
                  <ShieldBan size={16} />
                  Suspend
                </button>
              )}
              {selected.status === 'suspended' && (
                <button
                  disabled={busy}
                  onClick={() => void riderAction('reactivate')}
                  className="min-h-11 rounded-xl bg-emerald-700 px-4 text-sm font-semibold text-white"
                >
                  Reactivate
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
