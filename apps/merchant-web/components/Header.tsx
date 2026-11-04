'use strict';
'use client';

import React, { useState } from 'react';
import { Business, MerchantSession } from '../lib/types';
import { RealtimeNotification } from '../lib/api';
import { Store, ChevronDown, CheckCircle2, Clock, Bell, User, MapPin, LogOut, Check, Sparkles } from 'lucide-react';

interface HeaderProps {
  businesses: Business[];
  currentBusiness: Business;
  session?: MerchantSession | null;
  notifications?: RealtimeNotification[];
  onSelectBusiness: (biz: Business) => void;
  onToggleStoreStatus: () => void;
  onLogout?: () => void;
  onSelectNotification?: (notif: RealtimeNotification) => void;
}

export const Header: React.FC<HeaderProps> = ({
  businesses,
  currentBusiness,
  session,
  notifications = [],
  onSelectBusiness,
  onToggleStoreStatus,
  onLogout,
  onSelectNotification,
}) => {
  const [showNotifDropdown, setShowNotifDropdown] = useState(false);
  const unreadCount = notifications.filter((n) => !n.is_read).length;

  return (
    <header className="sticky top-0 z-30 flex h-16 w-full items-center justify-between border-b border-borderMuted bg-surface px-6 shadow-sm">
      {/* Brand & Workspace Title */}
      <div className="flex items-center space-x-6">
        <div className="flex items-center space-x-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary text-white shadow-md">
            <Store className="h-5 w-5" />
          </div>
          <div>
            <div className="flex items-center space-x-2">
              <span className="text-lg font-bold tracking-tight text-slateText-main">Grepmind Near</span>
              <span className="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary">
                Merchant
              </span>
            </div>
            <p className="text-xs text-slateText-secondary">Storefront & Trade Management</p>
          </div>
        </div>

        {/* Business Selector Dropdown */}
        <div className="relative group">
          <button className="flex items-center space-x-3 rounded-xl border border-borderMuted bg-background px-3.5 py-2 hover:bg-slate-50 transition-colors">
            <div className="text-left">
              <div className="flex items-center space-x-2">
                <span className="text-xs font-bold text-slateText-main max-w-[180px] truncate">
                  {currentBusiness.name}
                </span>
                {currentBusiness.isVerified && (
                  <CheckCircle2 className="h-3.5 w-3.5 text-primary" />
                )}
              </div>
              <div className="flex items-center space-x-1 text-[11px] text-slateText-secondary">
                <MapPin className="h-3 w-3 text-slateText-muted" />
                <span>{currentBusiness.locality}, {currentBusiness.city}</span>
              </div>
            </div>
            <ChevronDown className="h-4 w-4 text-slateText-muted group-hover:text-slateText-main transition-transform group-hover:rotate-180" />
          </button>

          {/* Selector Popover */}
          <div className="absolute left-0 mt-2 hidden w-72 rounded-2xl border border-borderMuted bg-surface p-2 shadow-xl group-hover:block z-50">
            <div className="px-3 py-2 text-xs font-bold text-slateText-muted uppercase tracking-wider">
              Your Managed Outlets ({businesses.length})
            </div>
            {businesses.map((biz) => (
              <button
                key={biz.id}
                onClick={() => onSelectBusiness(biz)}
                className={`flex w-full items-center justify-between rounded-xl px-3 py-2.5 text-left text-xs transition-colors ${
                  biz.id === currentBusiness.id
                    ? 'bg-primary/10 text-primary font-semibold'
                    : 'text-slateText-main hover:bg-slate-50'
                }`}
              >
                <div>
                  <div className="font-bold">{biz.name}</div>
                  <div className="text-[11px] text-slateText-secondary">{biz.city} • {biz.category}</div>
                </div>
                {biz.id === currentBusiness.id && (
                  <span className="h-2 w-2 rounded-full bg-primary" />
                )}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Right Actions: Store Status Toggle & Account */}
      <div className="flex items-center space-x-4">
        {/* Open / Closed Toggle Switch */}
        <div className="flex items-center space-x-2.5 rounded-xl border border-borderMuted bg-background px-3.5 py-1.5">
          <div className="flex items-center space-x-1.5">
            <span
              className={`h-2.5 w-2.5 rounded-full ${
                currentBusiness.isOpen ? 'bg-emerald-500 animate-pulse' : 'bg-rose-500'
              }`}
            />
            <span className="text-xs font-semibold text-slateText-main">
              {currentBusiness.isOpen ? 'Accepting Orders' : 'Store Paused'}
            </span>
          </div>
          <button
            onClick={onToggleStoreStatus}
            disabled={!currentBusiness.isVerified}
            aria-label={currentBusiness.isVerified ? 'Toggle service request availability' : 'Availability is disabled until listing approval'}
            className={`relative inline-flex h-5 w-9 shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 ${
              currentBusiness.isOpen ? 'bg-emerald-500' : 'bg-slate-300'
            }`}
          >
            <span
              className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow-lg ring-0 transition duration-200 ease-in-out ${
                currentBusiness.isOpen ? 'translate-x-4' : 'translate-x-0'
              }`}
            />
          </button>
        </div>

        {/* Real-Time Notification Bell with Dropdown */}
        <div className="relative">
          <button
            onClick={() => setShowNotifDropdown(!showNotifDropdown)}
            title="Notifications & Live Alerts"
            className="relative flex h-9 w-9 items-center justify-center rounded-xl border border-borderMuted hover:bg-slate-50 text-slateText-main transition-colors"
          >
            <Bell className="h-4 w-4" />
            {unreadCount > 0 ? (
              <span className="absolute -top-1 -right-1 flex h-4 min-w-[16px] px-1 items-center justify-center rounded-full bg-rose-500 text-[9px] font-bold text-white shadow animate-pulse">
                {unreadCount}
              </span>
            ) : (
              <span className="absolute top-1.5 right-1.5 h-2 w-2 rounded-full bg-primary" />
            )}
          </button>

          {showNotifDropdown && (
            <div className="absolute right-0 mt-2 w-80 rounded-2xl border border-borderMuted bg-surface p-3 shadow-2xl z-50 animate-in fade-in slide-in-from-top-2 duration-150">
              <div className="flex items-center justify-between border-b border-borderMuted pb-2 mb-2">
                <div className="flex items-center space-x-1.5">
                  <Sparkles className="h-3.5 w-3.5 text-primary" />
                  <span className="text-xs font-bold text-slateText-main">Live Store Alerts</span>
                </div>
                <span className="text-[10px] bg-primary/10 text-primary font-bold px-2 py-0.5 rounded-full">
                  {unreadCount} Unread
                </span>
              </div>

              <div className="max-h-72 overflow-y-auto space-y-2">
                {notifications.length === 0 ? (
                  <div className="py-6 text-center text-xs text-slateText-muted">
                    No notifications yet.
                  </div>
                ) : (
                  notifications.slice(0, 6).map((n) => (
                    <div
                      key={n.id}
                      onClick={() => {
                        onSelectNotification?.(n);
                        setShowNotifDropdown(false);
                      }}
                      className={`cursor-pointer rounded-xl p-2.5 transition-colors border ${
                        !n.is_read
                          ? 'bg-primary/5 border-primary/20 hover:bg-primary/10'
                          : 'bg-background border-borderMuted hover:bg-slate-50'
                      }`}
                    >
                      <div className="flex items-start justify-between">
                        <span className="text-xs font-bold text-slateText-main leading-tight">
                          {n.title}
                        </span>
                        {!n.is_read && (
                          <span className="h-2 w-2 rounded-full bg-rose-500 shrink-0 ml-1 mt-0.5" />
                        )}
                      </div>
                      <p className="text-[11px] text-slateText-secondary mt-1 line-clamp-2">
                        {n.body}
                      </p>
                      <div className="text-[9px] text-slateText-muted mt-1.5 font-mono">
                        {new Date(n.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>
          )}
        </div>

        {/* Merchant Avatar & Sign Out */}
        <div className="flex items-center space-x-3 border-l border-borderMuted pl-4">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/10 text-primary font-bold text-xs border border-primary/20">
            {session?.name ? session.name.charAt(0).toUpperCase() : 'M'}
          </div>
          <div className="hidden md:block text-left">
            <div className="text-xs font-bold text-slateText-main truncate max-w-[130px]">
              {session?.name || 'Store Proprietor'}
            </div>
            <div className="text-[10px] font-bold text-primary capitalize flex items-center space-x-1">
              <span>{session?.role || 'owner'}</span>
              <span className="text-slateText-muted">•</span>
              <span className="text-slateText-muted font-mono">{session?.phone?.slice(-5) || ''}</span>
            </div>
          </div>

          {onLogout && (
            <button
              onClick={onLogout}
              title="Sign Out of Merchant Workspace"
              className="flex h-8 w-8 items-center justify-center rounded-lg border border-borderMuted text-slateText-secondary hover:bg-rose-50 hover:text-rose-600 hover:border-rose-200 transition-colors ml-1"
            >
              <LogOut className="h-3.5 w-3.5" />
            </button>
          )}
        </div>
      </div>
    </header>
  );
};
