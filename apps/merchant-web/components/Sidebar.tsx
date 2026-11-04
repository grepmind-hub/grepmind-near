'use strict';
'use client';

import React from 'react';
import { LayoutDashboard, CalendarClock, ShoppingBag, Clock, Users, BarChart3, BadgePercent, ShieldCheck } from 'lucide-react';

interface SidebarProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
  pendingRequestsCount: number;
  verificationStatus: string;
}

export const Sidebar: React.FC<SidebarProps> = ({
  activeTab,
  onTabChange,
  pendingRequestsCount,
  verificationStatus,
}) => {
  const menuItems = [
    {
      id: 'overview',
      label: 'Dashboard Overview',
      icon: LayoutDashboard,
    },
    {
      id: 'requests',
      label: 'Service Requests',
      icon: CalendarClock,
      badge: pendingRequestsCount > 0 ? pendingRequestsCount : undefined,
    },
    {
      id: 'catalog',
      label: 'Catalog & Inventory',
      icon: ShoppingBag,
    },
    {
      id: 'hours',
      label: 'Hours & Coverage',
      icon: Clock,
    },
    {
      id: 'team',
      label: 'Team & Staff',
      icon: Users,
    },
    { id: 'offers', label: 'Offers & Promotions', icon: BadgePercent },
    {
      id: 'analytics',
      label: 'Store Analytics',
      icon: BarChart3,
    },
  ];

  return (
    <aside className="w-64 shrink-0 border-r border-borderMuted bg-surface p-4 flex flex-col justify-between h-[calc(100vh-4rem)]">
      <div className="space-y-6">
        {/* Navigation Items */}
        <div className="space-y-1">
          <div className="px-3 pb-2 text-[11px] font-bold text-slateText-muted uppercase tracking-wider">
            Workspace Hub
          </div>
          {menuItems.map((item) => {
            const Icon = item.icon;
            const isActive = activeTab === item.id;
            return (
              <button
                key={item.id}
                onClick={() => onTabChange(item.id)}
                className={`flex w-full items-center justify-between rounded-xl px-3.5 py-2.5 text-xs font-semibold transition-all ${
                  isActive
                    ? 'bg-primary text-white shadow-sm'
                    : 'text-slateText-secondary hover:bg-slate-50 hover:text-slateText-main'
                }`}
              >
                <div className="flex items-center space-x-3">
                  <Icon className={`h-4 w-4 ${isActive ? 'text-white' : 'text-slateText-muted'}`} />
                  <span>{item.label}</span>
                </div>
                {item.badge !== undefined && (
                  <span
                    className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${
                      isActive ? 'bg-white text-primary' : 'bg-primary text-white'
                    }`}
                  >
                    {item.badge}
                  </span>
                )}
              </button>
            );
          })}
        </div>

        {/* Verification Status Card */}
        <div className="rounded-2xl border border-borderMuted bg-gradient-to-br from-blue-50 to-teal-50 p-4">
          <div className="flex items-center space-x-2 text-primary font-bold text-xs">
            <ShieldCheck className="h-4 w-4" />
            <span>Listing review</span>
          </div>
          <p className="mt-1 text-[11px] text-slateText-secondary leading-relaxed">
            Current status: <strong className="capitalize">{verificationStatus.replace('_', ' ')}</strong>.
          </p>
        </div>
      </div>

      <p className="border-t border-borderMuted pt-4 px-3 text-[11px] text-slateText-muted">Secure merchant workspace</p>
    </aside>
  );
};
