'use client';

import React, { useState } from 'react';
import { 
  Users, 
  UserPlus, 
  ShieldCheck, 
  Shield, 
  Phone, 
  Calendar, 
  Trash2, 
  CheckCircle2, 
  AlertCircle,
  X,
  Search,
  KeyRound,
  Wrench,
  Store
} from 'lucide-react';
import { Business, TeamMember } from '../lib/types';

interface TeamManagerProps {
  business: Business;
  team: TeamMember[];
  onAddMember: (member: Omit<TeamMember, 'id' | 'businessId' | 'createdAt'>) => void;
  onRevokeMember: (memberId: string) => void;
}

export const TeamManager: React.FC<TeamManagerProps> = ({
  business,
  team,
  onAddMember,
  onRevokeMember,
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedRoleFilter, setSelectedRoleFilter] = useState<'all' | 'owner' | 'manager' | 'staff'>('all');
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [memberToRevoke, setMemberToRevoke] = useState<TeamMember | null>(null);

  // Add form state
  const [formName, setFormName] = useState('');
  const [formPhone, setFormPhone] = useState('');
  const [formRole, setFormRole] = useState<'manager' | 'staff'>('manager');
  const [formError, setFormError] = useState('');

  const filteredTeam = team.filter((member) => {
    const matchesSearch = 
      member.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      member.phone.includes(searchQuery);
    const matchesRole = selectedRoleFilter === 'all' || member.role === selectedRoleFilter;
    return matchesSearch && matchesRole;
  });

  const handleOpenAdd = () => {
    setFormName('');
    setFormPhone('+91 ');
    setFormRole('manager');
    setFormError('');
    setIsAddModalOpen(true);
  };

  const handleSaveMember = (e: React.FormEvent) => {
    e.preventDefault();
    const cleanPhone = formPhone.trim();
    if (!cleanPhone || cleanPhone.length < 10) {
      setFormError('Please enter a valid mobile number with country code (e.g., +91 9861000005).');
      return;
    }
    if (!formName.trim()) {
      setFormError('Please enter the team member’s display name.');
      return;
    }

    onAddMember({
      userId: `user-${Date.now()}`,
      name: formName.trim(),
      phone: cleanPhone,
      role: formRole,
      status: 'active',
    });

    setIsAddModalOpen(false);
  };

  const handleConfirmRevoke = () => {
    if (memberToRevoke) {
      onRevokeMember(memberToRevoke.id);
      setMemberToRevoke(null);
    }
  };

  return (
    <div className="space-y-6">
      {/* 1. Header & Actions */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <div className="flex items-center space-x-2">
            <h2 className="text-xl font-bold text-slateText-main">Team & Staff Access</h2>
            <span className="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-bold text-primary">
              {team.length} {team.length === 1 ? 'Member' : 'Members'}
            </span>
          </div>
          <p className="text-xs text-slateText-secondary mt-0.5">
            Manage roles and delegate store bookings, catalog, and operating hours for {business.name}.
          </p>
        </div>

        <button
          onClick={handleOpenAdd}
          className="inline-flex items-center space-x-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white shadow-sm hover:bg-primary/90 transition-all active:scale-[0.98]"
        >
          <UserPlus className="h-4 w-4" />
          <span>+ Add Team Member</span>
        </button>
      </div>

      {/* 2. Permission Levels Explainer Banner */}
      <div className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-sm">
        <h3 className="text-xs font-bold uppercase tracking-wider text-slateText-muted mb-3 flex items-center space-x-1.5">
          <KeyRound className="h-3.5 w-3.5 text-primary" />
          <span>Access Level Hierarchy</span>
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3.5">
          <div className="rounded-xl border border-blue-100 bg-blue-50/50 p-3.5">
            <div className="flex items-center space-x-2">
              <span className="flex h-6 w-6 items-center justify-center rounded-lg bg-blue-600 text-white text-xs font-bold">
                1
              </span>
              <span className="text-xs font-bold text-blue-900">Store Owner</span>
            </div>
            <p className="text-[11px] text-blue-800/80 mt-1.5 leading-relaxed">
              Full administrative authority. Can invite/revoke managers and staff, view payouts, and update store profile.
            </p>
          </div>

          <div className="rounded-xl border border-teal-100 bg-teal-50/50 p-3.5">
            <div className="flex items-center space-x-2">
              <span className="flex h-6 w-6 items-center justify-center rounded-lg bg-teal-700 text-white text-xs font-bold">
                2
              </span>
              <span className="text-xs font-bold text-teal-900">Store Manager</span>
            </div>
            <p className="text-[11px] text-teal-800/80 mt-1.5 leading-relaxed">
              Operational control. Can accept/reschedule service requests, update catalog prices/stock, and adjust operating hours.
            </p>
          </div>

          <div className="rounded-xl border border-amber-100 bg-amber-50/50 p-3.5">
            <div className="flex items-center space-x-2">
              <span className="flex h-6 w-6 items-center justify-center rounded-lg bg-amber-600 text-white text-xs font-bold">
                3
              </span>
              <span className="text-xs font-bold text-amber-900">Staff / Technician</span>
            </div>
            <p className="text-[11px] text-amber-800/80 mt-1.5 leading-relaxed">
              Field execution. Can view customer requests, update dispatch status (*En Route*, *In Progress*, *Completed*), and call customers.
            </p>
          </div>
        </div>
      </div>

      {/* 3. Search & Filter Bar */}
      <div className="flex flex-col sm:flex-row items-center justify-between gap-3">
        <div className="relative w-full sm:w-80">
          <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-slateText-muted" />
          <input
            type="text"
            placeholder="Search by name or mobile number..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full rounded-xl border border-borderMuted bg-background pl-9 pr-3.5 py-2 text-xs text-slateText-main placeholder:text-slateText-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          />
        </div>

        <div className="flex items-center space-x-1.5 self-start sm:self-auto overflow-x-auto w-full sm:w-auto">
          {(['all', 'owner', 'manager', 'staff'] as const).map((role) => (
            <button
              key={role}
              onClick={() => setSelectedRoleFilter(role)}
              className={`rounded-lg px-3 py-1.5 text-xs font-semibold capitalize transition-all ${
                selectedRoleFilter === role
                  ? 'bg-slateText-main text-white'
                  : 'bg-surface border border-borderMuted text-slateText-secondary hover:bg-slate-50'
              }`}
            >
              {role === 'all' ? 'All Roles' : role}
            </button>
          ))}
        </div>
      </div>

      {/* 4. Team Members List */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filteredTeam.map((member) => {
          const isOwner = member.role === 'owner';
          const isManager = member.role === 'manager';

          return (
            <div
              key={member.id}
              className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-card hover:shadow-cardHover transition-all flex flex-col justify-between"
            >
              <div>
                {/* Top Badge Strip */}
                <div className="flex items-center justify-between">
                  <span
                    className={`inline-flex items-center space-x-1 rounded-full px-2.5 py-0.5 text-[11px] font-bold border ${
                      isOwner
                        ? 'bg-blue-50 text-blue-700 border-blue-200'
                        : isManager
                        ? 'bg-teal-50 text-teal-700 border-teal-200'
                        : 'bg-amber-50 text-amber-800 border-amber-200'
                    }`}
                  >
                    {isOwner ? (
                      <ShieldCheck className="h-3 w-3" />
                    ) : isManager ? (
                      <Store className="h-3 w-3" />
                    ) : (
                      <Wrench className="h-3 w-3" />
                    )}
                    <span className="capitalize">{member.role}</span>
                  </span>

                  <span className="flex items-center space-x-1 text-[11px] font-semibold text-emerald-700">
                    <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse" />
                    <span className="capitalize">{member.status}</span>
                  </span>
                </div>

                {/* Member Profile Info */}
                <div className="mt-4 flex items-center space-x-3.5">
                  <div
                    className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl text-sm font-black text-white ${
                      isOwner
                        ? 'bg-gradient-to-tr from-blue-700 to-indigo-600'
                        : isManager
                        ? 'bg-gradient-to-tr from-teal-700 to-emerald-600'
                        : 'bg-gradient-to-tr from-slate-700 to-slate-900'
                    }`}
                  >
                    {member.name.charAt(0).toUpperCase()}
                  </div>

                  <div className="min-w-0 flex-1">
                    <h4 className="text-sm font-bold text-slateText-main truncate">
                      {member.name}
                    </h4>
                    <div className="mt-0.5 flex items-center space-x-1.5 text-xs text-slateText-secondary">
                      <Phone className="h-3 w-3 text-slateText-muted" />
                      <a
                        href={`tel:${member.phone}`}
                        className="hover:text-primary hover:underline font-medium"
                      >
                        {member.phone}
                      </a>
                    </div>
                  </div>
                </div>

                {/* Role Details */}
                <div className="mt-4 rounded-xl bg-background p-2.5 text-[11px] text-slateText-secondary space-y-1">
                  <div className="flex items-center justify-between text-slateText-muted">
                    <span>Access Granted</span>
                    <span>{member.createdAt}</span>
                  </div>
                  <div className="text-slateText-main font-medium">
                    {isOwner
                      ? 'Full store administrative authority'
                      : isManager
                      ? 'Service booking & catalog management'
                      : 'Request dispatch & customer coordination'}
                  </div>
                </div>
              </div>

              {/* Bottom Action */}
              <div className="mt-4 pt-3 border-t border-borderMuted flex items-center justify-between">
                <span className="text-[10px] text-slateText-muted">
                  {isOwner ? 'Protected Owner Account' : 'Delegated Access'}
                </span>

                {isOwner ? (
                  <span className="text-xs font-bold text-primary flex items-center space-x-1">
                    <ShieldCheck className="h-3.5 w-3.5" />
                    <span>Primary</span>
                  </span>
                ) : (
                  <button
                    onClick={() => setMemberToRevoke(member)}
                    className="inline-flex items-center space-x-1 text-xs font-semibold text-rose-600 hover:text-rose-700 transition-colors"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                    <span>Revoke</span>
                  </button>
                )}
              </div>
            </div>
          );
        })}

        {filteredTeam.length === 0 && (
          <div className="col-span-full rounded-2xl border border-dashed border-borderMuted bg-surface p-10 text-center">
            <Users className="mx-auto h-8 w-8 text-slateText-muted mb-2" />
            <p className="text-sm font-bold text-slateText-main">No team members found</p>
            <p className="text-xs text-slateText-secondary mt-1">
              Try adjusting your search query or role filters.
            </p>
          </div>
        )}
      </div>

      {/* 5. "+ Add Team Member" Modal Dialog */}
      {isAddModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 backdrop-blur-sm p-4">
          <div className="relative w-full max-w-lg rounded-2xl bg-surface p-6 shadow-2xl border border-borderMuted">
            <button
              onClick={() => setIsAddModalOpen(false)}
              className="absolute right-4 top-4 rounded-lg p-1 text-slateText-muted hover:bg-slate-100 hover:text-slateText-main"
            >
              <X className="h-4 w-4" />
            </button>

            <div className="flex items-center space-x-2.5 mb-4">
              <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/10 text-primary">
                <UserPlus className="h-5 w-5" />
              </div>
              <div>
                <h3 className="text-base font-bold text-slateText-main">Add Team Member</h3>
                <p className="text-xs text-slateText-secondary">
                  Grant store management access via passwordless phone OTP
                </p>
              </div>
            </div>

            {formError && (
              <div className="mb-4 flex items-center space-x-2 rounded-xl bg-rose-50 border border-rose-200 p-3 text-xs text-rose-700">
                <AlertCircle className="h-4 w-4 shrink-0" />
                <span>{formError}</span>
              </div>
            )}

            <form onSubmit={handleSaveMember} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slateText-main mb-1">
                  Full Display Name *
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Rakesh Mohapatra"
                  value={formName}
                  onChange={(e) => setFormName(e.target.value)}
                  className="w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2.5 text-xs text-slateText-main placeholder:text-slateText-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slateText-main mb-1">
                  Mobile Number (E.164) *
                </label>
                <input
                  type="tel"
                  required
                  placeholder="+91 9861000005"
                  value={formPhone}
                  onChange={(e) => setFormPhone(e.target.value)}
                  className="w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2.5 text-xs font-mono text-slateText-main placeholder:text-slateText-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
                />
                <span className="text-[11px] text-slateText-muted mt-1 block">
                  The member will log into this workspace using this mobile number via secure SMS OTP.
                </span>
              </div>

              <div>
                <label className="block text-xs font-bold text-slateText-main mb-2">
                  Select Access Role *
                </label>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div
                    onClick={() => setFormRole('manager')}
                    className={`cursor-pointer rounded-xl border p-3.5 transition-all ${
                      formRole === 'manager'
                        ? 'border-teal-500 bg-teal-50/50 ring-1 ring-teal-500'
                        : 'border-borderMuted bg-background hover:bg-slate-50'
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center space-x-1.5">
                        <Store className="h-4 w-4 text-teal-700" />
                        <span className="text-xs font-bold text-teal-900">Store Manager</span>
                      </div>
                      {formRole === 'manager' && (
                        <CheckCircle2 className="h-4 w-4 text-teal-600" />
                      )}
                    </div>
                    <p className="text-[11px] text-slateText-secondary mt-1.5">
                      Can accept customer bookings, adjust hours, and add/edit catalog products.
                    </p>
                  </div>

                  <div
                    onClick={() => setFormRole('staff')}
                    className={`cursor-pointer rounded-xl border p-3.5 transition-all ${
                      formRole === 'staff'
                        ? 'border-amber-500 bg-amber-50/50 ring-1 ring-amber-500'
                        : 'border-borderMuted bg-background hover:bg-slate-50'
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center space-x-1.5">
                        <Wrench className="h-4 w-4 text-amber-700" />
                        <span className="text-xs font-bold text-amber-900">Staff / Tech</span>
                      </div>
                      {formRole === 'staff' && (
                        <CheckCircle2 className="h-4 w-4 text-amber-600" />
                      )}
                    </div>
                    <p className="text-[11px] text-slateText-secondary mt-1.5">
                      Can view incoming requests and update real-time dispatch progress.
                    </p>
                  </div>
                </div>
              </div>

              <div className="mt-6 pt-4 border-t border-borderMuted flex items-center justify-end space-x-2.5">
                <button
                  type="button"
                  onClick={() => setIsAddModalOpen(false)}
                  className="rounded-xl border border-borderMuted px-4 py-2.5 text-xs font-semibold text-slateText-main hover:bg-slate-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="rounded-xl bg-primary px-5 py-2.5 text-xs font-bold text-white hover:bg-primary/90 shadow-sm"
                >
                  Grant Access
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* 6. Revoke Confirmation Modal Dialog */}
      {memberToRevoke && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 backdrop-blur-sm p-4">
          <div className="relative w-full max-w-md rounded-2xl bg-surface p-6 shadow-2xl border border-borderMuted">
            <div className="flex items-center space-x-3 text-rose-600 mb-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-rose-100">
                <AlertCircle className="h-5 w-5" />
              </div>
              <div>
                <h3 className="text-base font-bold text-slateText-main">Revoke Team Access?</h3>
                <p className="text-xs text-slateText-secondary">This action takes effect immediately</p>
              </div>
            </div>

            <p className="text-xs text-slateText-secondary leading-relaxed mb-6">
              Are you sure you want to revoke access for <strong className="text-slateText-main">{memberToRevoke.name}</strong> ({memberToRevoke.phone})? They will immediately lose access to manage {business.name}.
            </p>

            <div className="flex items-center justify-end space-x-2.5">
              <button
                onClick={() => setMemberToRevoke(null)}
                className="rounded-xl border border-borderMuted px-4 py-2.5 text-xs font-semibold text-slateText-main hover:bg-slate-50"
              >
                Keep Access
              </button>
              <button
                onClick={handleConfirmRevoke}
                className="rounded-xl bg-rose-600 px-4 py-2.5 text-xs font-bold text-white hover:bg-rose-700 shadow-sm"
              >
                Yes, Revoke Access
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
