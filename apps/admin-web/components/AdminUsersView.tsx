'use client';

import React, { useState } from 'react';
import {
  ShieldCheck,
  UserPlus,
  Trash2,
  Lock,
  CheckCircle2,
  AlertTriangle,
  KeyRound,
  Phone,
  Calendar,
  X,
} from 'lucide-react';
import { AdminUser } from '@/lib/api';

interface AdminUsersViewProps {
  admins: AdminUser[];
  onAddAdmin: (phone: string, name: string) => Promise<void>;
  onRevokeAdmin: (userId: string) => Promise<void>;
}

export const AdminUsersView: React.FC<AdminUsersViewProps> = ({
  admins,
  onAddAdmin,
  onRevokeAdmin,
}) => {
  const [showAddModal, setShowAddModal] = useState(false);
  const [phone, setPhone] = useState('+91 ');
  const [name, setName] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [actionLoadingId, setActionLoadingId] = useState<string | null>(null);

  async function handleAddSubmit(e: React.FormEvent) {
    e.preventDefault();
    const cleanPhone = phone.trim().replace(/\s+/g, '');
    if (!cleanPhone.startsWith('+91') || cleanPhone.length < 13) {
      alert('Please enter a valid 10-digit mobile number with +91 country code (e.g., +919876543210).');
      return;
    }
    if (!name.trim()) {
      alert('Please enter the administrator name or operational title.');
      return;
    }

    setIsSubmitting(true);
    try {
      await onAddAdmin(cleanPhone, name.trim());
      setShowAddModal(false);
      setPhone('+91 ');
      setName('');
    } catch {
      alert('Failed to add platform administrator.');
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleRevoke(userId: string, adminPhone: string) {
    if (adminPhone === '+910000000000') {
      alert('The primary platform superadmin (+91 00000 00000) cannot be revoked.');
      return;
    }
    if (!confirm(`Are you sure you want to revoke platform administration permissions from ${adminPhone}?`)) {
      return;
    }

    setActionLoadingId(userId);
    try {
      await onRevokeAdmin(userId);
    } finally {
      setActionLoadingId(null);
    }
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-xl font-bold text-[#172033]">Platform Administrators &amp; Permissions</h2>
            <span className="rounded-full bg-emerald-100 px-2.5 py-0.5 text-xs font-bold text-emerald-800">
              {admins.length} Active Admins
            </span>
          </div>
          <p className="text-xs text-[#667085] mt-0.5">
            Manage who has administrative access to moderate listings, verify KYC, and resolve consumer disputes
          </p>
        </div>

        <button
          onClick={() => setShowAddModal(true)}
          className="flex items-center gap-1.5 rounded-xl bg-[#2457D6] px-4 py-2 text-xs font-bold text-white shadow-xs hover:bg-[#1E40AF] transition-all active:scale-95"
        >
          <UserPlus className="h-4 w-4" /> Add Platform Admin
        </button>
      </div>

      {/* Security & Access Hierarchy Notice */}
      <div className="rounded-2xl border border-blue-200 bg-blue-50/60 p-4 text-xs text-[#172033]">
        <div className="flex items-start gap-3">
          <div className="rounded-xl bg-[#2457D6] p-2 text-white">
            <KeyRound className="h-4 w-4" />
          </div>
          <div className="space-y-1">
            <span className="font-bold text-sm text-[#2457D6]">Role-Based Access Control (RBAC) Architecture</span>
            <p className="text-[#475467] leading-relaxed">
              Administrative permissions are backed by the PostgreSQL <code className="bg-white/80 px-1 py-0.5 rounded font-mono text-[11px]">user_roles</code> table (<code className="font-mono text-[11px]">role = &apos;admin&apos;</code>) and verified cryptographically on every request via Go REST API <code className="bg-white/80 px-1 py-0.5 rounded font-mono text-[11px]">requireAdmin</code> middleware.
            </p>
          </div>
        </div>
      </div>

      {/* Admins Table */}
      <div className="rounded-2xl border border-[#E4E7EC] bg-white shadow-xs overflow-hidden">
        <table className="w-full text-left border-collapse text-xs">
          <thead>
            <tr className="border-b border-[#E4E7EC] bg-[#F7F8FA] text-[#667085] font-semibold">
              <th className="py-3 px-4">Administrator</th>
              <th className="py-3 px-4">Mobile Number (Phone OTP ID)</th>
              <th className="py-3 px-4">Security Role</th>
              <th className="py-3 px-4">Granted On</th>
              <th className="py-3 px-4 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[#F2F4F7]">
            {admins.map((admin) => {
              const isSuperadmin = admin.phone_e164 === '+910000000000';

              return (
                <tr key={admin.id} className="hover:bg-[#FAFAFA] transition-colors">
                  <td className="py-3.5 px-4 font-bold text-[#172033]">
                    <div className="flex items-center gap-2">
                      <div className="flex h-7 w-7 items-center justify-center rounded-full bg-[#0F766E] text-[10px] font-bold text-white">
                        {admin.display_name.slice(0, 2).toUpperCase()}
                      </div>
                      <div>
                        <span>{admin.display_name}</span>
                        {isSuperadmin && (
                          <span className="ml-2 rounded-full bg-[#E3EEFF] px-2 py-0.2 text-[9px] font-bold text-[#2457D6]">
                            ROOT SUPERADMIN
                          </span>
                        )}
                      </div>
                    </div>
                  </td>
                  <td className="py-3.5 px-4 font-mono font-semibold text-[#344054]">
                    {admin.phone_e164}
                  </td>
                  <td className="py-3.5 px-4">
                    <span className="rounded-md bg-emerald-50 border border-emerald-200 px-2 py-0.5 font-mono text-[10px] font-bold text-emerald-800">
                      ADMIN / MODERATOR
                    </span>
                  </td>
                  <td className="py-3.5 px-4 text-[#667085]">
                    {new Date(admin.created_at).toLocaleDateString()}
                  </td>
                  <td className="py-3.5 px-4 text-right">
                    {isSuperadmin ? (
                      <span className="text-[11px] font-semibold text-gray-400 italic">Protected</span>
                    ) : (
                      <button
                        onClick={() => handleRevoke(admin.id, admin.phone_e164)}
                        disabled={actionLoadingId === admin.id}
                        className="rounded-lg border border-rose-200 bg-rose-50 px-2.5 py-1 text-[11px] font-bold text-rose-700 hover:bg-rose-100 transition-colors"
                      >
                        {actionLoadingId === admin.id ? 'Revoking...' : 'Revoke Admin'}
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Add Admin Modal */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs animate-in fade-in duration-200">
          <div className="relative w-full max-w-md rounded-2xl bg-white shadow-2xl border border-[#E4E7EC] overflow-hidden">
            <div className="flex items-center justify-between border-b border-[#E4E7EC] px-6 py-4 bg-[#F7F8FA]">
              <div className="flex items-center gap-2">
                <ShieldCheck className="h-5 w-5 text-[#2457D6]" />
                <h3 className="text-sm font-bold text-[#172033]">Add Platform Administrator</h3>
              </div>
              <button onClick={() => setShowAddModal(false)} className="text-[#667085] hover:text-[#172033]">
                <X className="h-4 w-4" />
              </button>
            </div>

            <form onSubmit={handleAddSubmit} className="p-6 space-y-4">
              <div>
                <label className="text-xs font-semibold text-[#344054] block mb-1">
                  Full Name / Operational Title:
                </label>
                <input
                  type="text"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g., Regional Operations Lead - Cuttack & Puri"
                  required
                  className="w-full rounded-xl border border-[#D0D5DD] px-3.5 py-2 text-xs text-[#172033] focus:outline-none focus:ring-1 focus:ring-[#2457D6]"
                />
              </div>

              <div>
                <label className="text-xs font-semibold text-[#344054] block mb-1">
                  Mobile Number (E.164 with +91):
                </label>
                <input
                  type="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="+91 98765 43210"
                  required
                  className="w-full rounded-xl border border-[#D0D5DD] px-3.5 py-2 text-xs font-mono text-[#172033] focus:outline-none focus:ring-1 focus:ring-[#2457D6]"
                />
                <p className="text-[10px] text-[#667085] mt-1">
                  The admin will use this mobile number to log in via secure passwordless Phone OTP.
                </p>
              </div>

              <div className="rounded-xl border border-[#E4E7EC] bg-[#F7F8FA] p-3 text-xs text-[#475467]">
                <span className="font-bold text-[#172033]">Assigned Privileges:</span>
                <ul className="list-disc list-inside mt-1 space-y-0.5 text-[11px] text-[#667085]">
                  <li>Review &amp; approve merchant KYC &amp; licenses</li>
                  <li>Moderate discount offers &amp; consumer complaints</li>
                  <li>Access platform analytics across Bhubaneswar, Cuttack, Puri</li>
                </ul>
              </div>

              <div className="flex items-center justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setShowAddModal(false)}
                  disabled={isSubmitting}
                  className="rounded-xl border border-[#D0D5DD] px-4 py-2 text-xs font-semibold text-[#344054] hover:bg-[#F9FAFB]"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="rounded-xl bg-[#2457D6] px-5 py-2 text-xs font-bold text-white shadow-xs hover:bg-[#1E40AF]"
                >
                  {isSubmitting ? 'Granting...' : 'Grant Admin Permissions'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
