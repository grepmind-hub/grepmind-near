'use strict';
'use client';

import React from 'react';
import { LayoutDashboard, CalendarClock, ShoppingBag, Clock, Users, BarChart3, Settings, HelpCircle, ShieldCheck } from 'lucide-react';

interface SidebarProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
  pendingRequestsCount: number;
}

export const Sidebar: React.FC<SidebarProps> = ({
  activeTab,
  onTabChange,
  pendingRequestsCount,
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
        <div className="rounded-2xl border border-borderMuted bg-slate-50 p-4">
          <div className="flex items-center space-x-2 text-primary font-bold text-xs">
            <ShieldCheck className="h-4 w-4" />
            <span>Verified Merchant</span>
          </div>
          <p className="mt-1 text-[11px] text-slateText-secondary leading-relaxed">
            Your storefront credentials and location are verified by Grepmind Near moderators.
          </p>
          <div className="mt-3 flex items-center justify-between">
            <span className="text-[10px] font-semibold text-slateText-muted">Audit Score</span>
            <span className="text-xs font-bold text-emerald-600">98 / 100</span>
          </div>
          <div className="mt-1.5 h-1.5 w-full rounded-full bg-slate-200">
            <div className="h-1.5 rounded-full bg-emerald-500 w-[98%]" />
          </div>
        </div>
      </div>

      {/* Footer Support & Settings */}
      <div className="border-t border-borderMuted pt-4 space-y-1">
        <button className="flex w-full items-center space-x-3 rounded-xl px-3.5 py-2 text-xs font-semibold text-slateText-secondary hover:bg-slate-50 hover:text-slateText-main">
          <Settings className="h-4 w-4 text-slateText-muted" />
          <span>Account Settings</span>
        </button>
        <button className="flex w-full items-center space-x-3 rounded-xl px-3.5 py-2 text-xs font-semibold text-slateText-secondary hover:bg-slate-50 hover:text-slateText-main">
          <HelpCircle className="h-4 w-4 text-slateText-muted" />
          <span>Merchant Support</span>
        </button>
      </div>
    </aside>
  );
};
