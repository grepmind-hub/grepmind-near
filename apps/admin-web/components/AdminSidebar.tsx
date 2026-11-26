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
  UserRoundCheck,
  Activity,
  PackageSearch,
  Bike,
  Truck,
  WalletCards,
  Banknote,
} from 'lucide-react';

export type AdminTab =
  | 'overview'
  | 'verification'
  | 'businesses'
  | 'claims'
  | 'reports'
  | 'offers'
  | 'audit-logs'
  | 'listing-activity'
  | 'admin-users'
  | 'service-locations'
  | 'platform-catalog'
  | 'riders'
  | 'dispatch'
  | 'rider-earnings'
  | 'finance-overview'
  | 'payment-tracking'
  | 'reconciliation-queue'
  | 'cod-finance'
  | 'merchant-finance';

interface AdminSidebarProps {
  hideOnNarrow?: boolean;
  currentTab: AdminTab;
  onSelectTab: (tab: AdminTab) => void;
  pendingCount: number;
  reportsCount: number;
  offersCount: number;
}

export const AdminSidebar: React.FC<AdminSidebarProps> = ({
  currentTab,
  hideOnNarrow = false,
  onSelectTab,
  pendingCount,
  reportsCount,
  offersCount,
}) => {
  const navItems = [
    {
      id: 'overview' as AdminTab,
      label: 'Dashboard',
      description: 'Live analytics & trends',
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
      id: 'claims' as AdminTab,
      label: 'Ownership claims',
      description: 'Review merchant claims',
      icon: UserRoundCheck,
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
      id: 'listing-activity' as AdminTab,
      label: 'Listing Activity',
      description: 'Who submitted new listings',
      icon: Activity,
      badge: null,
    },
    {
      id: 'admin-users' as AdminTab,
      label: 'Admins & Access',
      description: 'Permissions & security',
      icon: ShieldCheck,
      badge: null,
    },
    {
      id: 'service-locations' as AdminTab,
      label: 'Service Areas & PINs',
      description: 'Coverage & capabilities',
      icon: MapPin,
      badge: null,
    },
    {
      id: 'platform-catalog' as AdminTab,
      label: 'Platform Catalog',
      description: 'Products & fulfillment partners',
      icon: PackageSearch,
      badge: null,
    },
    {
      id: 'riders' as AdminTab,
      label: 'Rider Management',
      description: 'Applications & approvals',
      icon: Bike,
      badge: null,
    },
    {
      id: 'dispatch' as AdminTab,
      label: 'Delivery Dispatch',
      description: 'Jobs, offers & exceptions',
      icon: Truck,
      badge: null,
    },
    {
      id: 'rider-earnings' as AdminTab,
      label: 'Rider earnings',
      description: 'Ledger & reconciliation',
      icon: WalletCards,
      badge: null,
    },
    {
      id: 'finance-overview' as AdminTab,
      label: 'Finance overview',
      description: 'Refunds, payables & remittances',
      icon: BarChart3,
      badge: null,
    },
    {
      id: 'payment-tracking' as AdminTab,
      label: 'Payment tracking',
      description: 'Order attempts & reconciliation',
      icon: Banknote,
      badge: null,
    },
    {
      id: 'reconciliation-queue' as AdminTab,
      label: 'Reconciliation queue',
      description: 'Attempts & recorded exceptions',
      icon: FileCheck2,
      badge: null,
    },
    {
      id: 'cod-finance' as AdminTab,
      label: 'COD accountability',
      description: 'Synthetic remittance review',
      icon: Banknote,
      badge: null,
    },
    {
      id: 'merchant-finance' as AdminTab,
      label: 'Merchant settlements',
      description: 'Payables, commission & simulation',
      icon: WalletCards,
      badge: null,
    },
  ];
  const merchantPortalUrl = process.env.NEXT_PUBLIC_MERCHANT_PORTAL_URL || '/merchant/';

  return (
    <aside className={`w-64 shrink-0 overflow-y-auto border-r border-[#E4E7EC] bg-white flex-col justify-between py-4 ${hideOnNarrow ? 'hidden xl:flex' : 'flex'}`}>
      <div>
        <div className="px-4 mb-4 pb-3 border-b border-[#E4E7EC] flex items-center gap-2.5">
          <svg width="34" height="34" viewBox="0 0 64 64" fill="none" aria-label="Abashyaka logo" className="shrink-0">
            <rect width="64" height="64" rx="16" fill="#00545B" />
            <path d="M32 14L19 50" stroke="#FFFFFF" strokeWidth="6.5" strokeLinecap="round" />
            <path d="M32 14L45 50" stroke="#FFFFFF" strokeWidth="6.5" strokeLinecap="round" />
            <path d="M23.5 39H40.5" stroke="#FF8A00" strokeWidth="5.2" strokeLinecap="round" />
          </svg>
          <div>
            <div className="text-sm font-extrabold tracking-tight text-[#00545B]">Abashyaka</div>
            <div className="text-[11px] font-medium text-[#667085]">Admin Console</div>
          </div>
        </div>

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
                    ? 'bg-[#123D36] text-white shadow-xs'
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
                        ? 'bg-white text-[#123D36] border-white/40'
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
          </div>
          <a
            href={merchantPortalUrl}
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
