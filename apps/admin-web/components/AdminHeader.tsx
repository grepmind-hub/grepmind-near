'use client';

import React from 'react';
import { ShieldCheck, Activity, RefreshCw, LogOut, Bell, Sparkles } from 'lucide-react';

interface AdminHeaderProps {
  selectedCity: string;
  onSelectCity: (city: string) => void;
  selectedRange: '7d' | '14d' | '30d';
  onSelectRange: (range: '7d' | '14d' | '30d') => void;
  isRefreshing: boolean;
  onRefresh: () => void;
  onSignOut: () => void;
}

export const AdminHeader: React.FC<AdminHeaderProps> = ({
  selectedCity,
  onSelectCity,
  selectedRange,
  onSelectRange,
  isRefreshing,
  onRefresh,
  onSignOut,
}) => {
  return (
    <header className="sticky top-0 z-30 flex h-16 w-full items-center justify-between border-b border-[#E4E7EC] bg-white/95 px-6 backdrop-blur-sm shadow-xs">
      {/* Left: Branding & System Status */}
      <div className="flex items-center gap-4">
        <div className="flex items-center gap-2.5">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-tr from-[#1E40AF] to-[#2457D6] text-white shadow-xs">
            <ShieldCheck className="h-5 w-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="text-base font-bold tracking-tight text-[#172033]">Grepmind Near</span>
              <span className="rounded-full bg-[#E3EEFF] px-2 py-0.5 text-[10px] font-semibold text-[#2457D6]">
                ADMIN
              </span>
            </div>
            <p className="text-[11px] font-medium text-[#667085]">Odisha Central Operations Hub</p>
          </div>
        </div>

        {/* Live Service Health Pill */}
        <div className="hidden items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50/70 px-3 py-1 lg:flex">
          <span className="relative flex h-2 w-2">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75"></span>
            <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-500"></span>
          </span>
          <span className="text-xs font-medium text-emerald-800">
            Platform Operational • 14ms latency
          </span>
        </div>
      </div>

      {/* Center/Right: Interactive Filters & Admin Identity */}
      <div className="flex items-center gap-3">
        {/* City Filter Switcher */}
        <div className="flex items-center rounded-lg border border-[#E4E7EC] bg-[#F7F8FA] p-0.5 text-xs font-medium">
          {['All Cities', 'Cuttack', 'Jajpur'].map((city) => (
            <button
              key={city}
              onClick={() => onSelectCity(city)}
              className={`rounded-md px-2.5 py-1 transition-all ${
                selectedCity === city
                  ? 'bg-white font-semibold text-[#2457D6] shadow-xs'
                  : 'text-[#667085] hover:text-[#172033]'
              }`}
            >
              {city}
            </button>
          ))}
        </div>

        {/* Time Range Selector */}
        <div className="hidden sm:flex items-center rounded-lg border border-[#E4E7EC] bg-[#F7F8FA] p-0.5 text-xs font-medium">
          {(['7d', '14d', '30d'] as const).map((range) => (
            <button
              key={range}
              onClick={() => onSelectRange(range)}
              className={`rounded-md px-2.5 py-1 transition-all ${
                selectedRange === range
                  ? 'bg-[#2457D6] font-semibold text-white shadow-xs'
                  : 'text-[#667085] hover:text-[#172033]'
              }`}
            >
              {range.toUpperCase()}
            </button>
          ))}
        </div>

        {/* Refresh Button */}
        <button
          onClick={onRefresh}
          disabled={isRefreshing}
          title="Refresh real-time data from Go REST API"
          className="flex h-9 w-9 items-center justify-center rounded-lg border border-[#E4E7EC] text-[#667085] transition-all hover:bg-[#F2F4F7] hover:text-[#172033] active:scale-95 disabled:opacity-50"
        >
          <RefreshCw className={`h-4 w-4 ${isRefreshing ? 'animate-spin text-[#2457D6]' : ''}`} />
        </button>

        {/* Admin Identity Card */}
        <div className="flex items-center gap-3 border-l border-[#E4E7EC] pl-3">
          <div className="flex items-center gap-2">
            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-[#0F766E] text-xs font-bold text-white shadow-xs">
              AD
            </div>
            <div className="hidden md:block text-left">
              <div className="flex items-center gap-1.5">
                <span className="text-xs font-semibold text-[#172033]">Platform Admin</span>
                <span className="rounded bg-[#0F766E]/10 px-1.5 py-0.2 text-[9px] font-bold text-[#0F766E]">
                  SUPERUSER
                </span>
              </div>
              <div className="text-[10px] text-[#667085]">+91 00000 00000</div>
            </div>
          </div>

          <button
            onClick={onSignOut}
            title="Sign out of Admin Session"
            className="flex h-8 w-8 items-center justify-center rounded-lg text-[#667085] transition-colors hover:bg-rose-50 hover:text-rose-600"
          >
            <LogOut className="h-4 w-4" />
          </button>
        </div>
      </div>
    </header>
  );
};
