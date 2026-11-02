'use client';

import React from 'react';
import {
  BarChart3,
  ShieldAlert,
  ShieldCheck,
  Building2,
  FileCheck2,
  Tag,
  History,
  TrendingUp,
  MapPin,
  ExternalLink,
} from 'lucide-react';

export type AdminTab =
  | 'overview'
  | 'verification'
  | 'businesses'
  | 'reports'
  | 'offers'
  | 'audit-logs'
  | 'admin-users';

interface AdminSidebarProps {
  currentTab: AdminTab;
  onSelectTab: (tab: AdminTab) => void;
  pendingCount: number;
  reportsCount: number;
  offersCount: number;
}

export const AdminSidebar: React.FC<AdminSidebarProps> = ({
  currentTab,
  onSelectTab,
  pendingCount,
  reportsCount,
  offersCount,
}) => {
  const navItems = [
    {
      id: 'overview' as AdminTab,
      label: 'Analytics & Trends',
      description: 'Charts, GMV, and SLAs',
      icon: BarChart3,
      badge: null,
    },
    {
      id: 'verification' as AdminTab,
      label: 'Listing Verification',
      description: 'Review KYC & licenses',
      icon: FileCheck2,
      badge: pendingCount > 0 ? pendingCount : null,
      badgeColor: 'bg-amber-100 text-amber-800 border-amber-300',
    },
    {
      id: 'businesses' as AdminTab,
      label: 'Merchant Registry',
      description: 'All stores & status',
      icon: Building2,
      badge: null,
    },
    {
      id: 'reports' as AdminTab,
      label: 'Reports & Disputes',
      description: 'Consumer complaints',
      icon: ShieldAlert,
      badge: reportsCount > 0 ? reportsCount : null,
      badgeColor: 'bg-rose-100 text-rose-800 border-rose-300',
    },
    {
      id: 'offers' as AdminTab,
      label: 'Offers & Promos',
      description: 'Banner moderation',
      icon: Tag,
      badge: offersCount > 0 ? offersCount : null,
      badgeColor: 'bg-blue-100 text-blue-800 border-blue-300',
    },
    {
      id: 'audit-logs' as AdminTab,
      label: 'Audit Trail',
      description: 'Compliance history',
      icon: History,
      badge: null,
    },
    {
      id: 'admin-users' as AdminTab,
      label: 'Admins & Access',
      description: 'Permissions & security',
      icon: ShieldCheck,
      badge: null,
    },
  ];

  return (
    <aside className="w-64 shrink-0 border-r border-[#E4E7EC] bg-white flex flex-col justify-between py-4">
      <div>
        <div className="px-5 mb-3">
          <p className="text-[11px] font-bold uppercase tracking-wider text-[#98A2B3]">
            Operations &amp; Governance
          </p>
        </div>

        <nav className="space-y-1 px-3">
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = currentTab === item.id;

            return (
              <button
                key={item.id}
                onClick={() => onSelectTab(item.id)}
                className={`group flex w-full items-center justify-between rounded-xl px-3.5 py-2.5 text-left text-sm font-medium transition-all ${
                  isActive
                    ? 'bg-[#2457D6] text-white shadow-xs'
                    : 'text-[#475467] hover:bg-[#F2F4F7] hover:text-[#172033]'
                }`}
              >
                <div className="flex items-center gap-3">
                  <Icon
                    className={`h-4.5 w-4.5 transition-colors ${
                      isActive ? 'text-white' : 'text-[#667085] group-hover:text-[#172033]'
                    }`}
                  />
                  <div>
                    <span className="block leading-tight">{item.label}</span>
                    <span
                      className={`block text-[11px] font-normal leading-none mt-0.5 ${
                        isActive ? 'text-white/80' : 'text-[#98A2B3]'
                      }`}
                    >
                      {item.description}
                    </span>
                  </div>
                </div>

                {item.badge !== null && (
                  <span
                    className={`ml-2 rounded-full border px-2 py-0.5 text-[11px] font-bold ${
                      isActive
                        ? 'bg-white text-[#2457D6] border-white/40'
                        : item.badgeColor || 'bg-gray-100 text-gray-700'
                    }`}
                  >
                    {item.badge}
                  </span>
                )}
              </button>
            );
          })}
        </nav>
      </div>

      {/* Bottom Hub Summary */}
      <div className="px-4">
        <div className="rounded-xl border border-[#E4E7EC] bg-[#F7F8FA] p-3.5 text-xs">
          <div className="flex items-center gap-1.5 text-xs font-semibold text-[#172033]">
            <MapPin className="h-3.5 w-3.5 text-[#0F766E]" />
            Active Coverage Zones
          </div>
          <div className="mt-2 space-y-1 text-[11px] text-[#667085]">
            <div className="flex justify-between">
              <span>Cuttack</span>
              <span>Supported</span>
            </div>
            <div className="flex justify-between">
              <span>Jajpur</span>
              <span>Supported</span>
            </div>
            <div className="flex justify-between">
              <span>Counts</span>
              <span>See live registry</span>
            </div>
            <div className="flex justify-between">
            </div>
          </div>
          <a
            href="http://localhost/merchant/"
            target="_blank"
            rel="noreferrer"
            className="mt-3 flex items-center justify-center gap-1.5 rounded-lg border border-[#D0D5DD] bg-white py-1.5 text-[11px] font-medium text-[#344054] hover:bg-[#F9FAFB]"
          >
            Open Merchant Portal <ExternalLink className="h-3 w-3" />
          </a>
        </div>
      </div>
    </aside>
  );
};
