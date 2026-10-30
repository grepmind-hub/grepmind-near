'use strict';
'use client';

import React from 'react';
import { ShoppingBag, IndianRupee, Eye, Sparkles, ArrowUpRight, Plus, MapPin, Calendar, Clock } from 'lucide-react';
import { Business } from '../lib/types';

interface OverviewCardsProps {
  business: Business;
  pendingRequestsCount: number;
  totalProductsCount: number;
  onNavigateTab: (tab: string) => void;
}

export const OverviewCards: React.FC<OverviewCardsProps> = ({
  business,
  pendingRequestsCount,
  totalProductsCount,
  onNavigateTab,
}) => {
  const stats = [
    {
      label: "Today's Orders & Requests",
      value: '12',
      change: '+18% vs yesterday',
      isPositive: true,
      icon: ShoppingBag,
      color: 'text-blue-600 bg-blue-50',
    },
    {
      label: "Estimated Revenue",
      value: '₹3,240',
      change: '+24% this week',
      isPositive: true,
      icon: IndianRupee,
      color: 'text-emerald-600 bg-emerald-50',
    },
    {
      label: 'Store Impressions & Views',
      value: '342',
      change: '+45 searches',
      isPositive: true,
      icon: Eye,
      color: 'text-indigo-600 bg-indigo-50',
    },
    {
      label: 'Pending Service Bookings',
      value: pendingRequestsCount.toString(),
      change: pendingRequestsCount > 0 ? 'Action required' : 'All clear',
      isPositive: pendingRequestsCount === 0,
      icon: Calendar,
      color: 'text-amber-600 bg-amber-50',
    },
  ];

  return (
    <div className="space-y-6">
      {/* AI Insight Smart Banner (Matching reference kit) */}
      <div className="relative overflow-hidden rounded-2xl border border-primary/20 bg-gradient-to-r from-primary/10 via-primary/5 to-transparent p-5">
        <div className="flex items-start justify-between">
          <div className="flex items-start space-x-3.5">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary text-white shadow-sm">
              <Sparkles className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center space-x-2">
                <h4 className="text-sm font-bold text-slateText-main">AI Discovery Insight</h4>
                <span className="rounded-full bg-primary text-white px-2 py-0.5 text-[10px] font-bold">
                  Recommended
                </span>
              </div>
              <p className="mt-1 text-xs text-slateText-secondary max-w-2xl leading-relaxed">
                Customer searches for <strong>AC jet cleaning & wiring checks</strong> surged by 42% in {business.locality} this week.
                Publish a 15% promotional discount on your electrical packages to capture local monsoon demand!
              </p>
            </div>
          </div>
          <button
            onClick={() => onNavigateTab('catalog')}
            className="flex items-center space-x-1.5 rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white shadow-sm hover:bg-primary-dark transition-colors"
          >
            <span>Create Offer</span>
            <ArrowUpRight className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>

      {/* 4 Metric Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {stats.map((stat, i) => {
          const Icon = stat.icon;
          return (
            <div
              key={i}
              className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-card hover:shadow-cardHover transition-shadow"
            >
              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold text-slateText-secondary">{stat.label}</span>
                <div className={`flex h-9 w-9 items-center justify-center rounded-xl ${stat.color}`}>
                  <Icon className="h-4 w-4" />
                </div>
              </div>
              <div className="mt-3 flex items-baseline justify-between">
                <span className="text-2xl font-black tracking-tight text-slateText-main">
                  {stat.value}
                </span>
                <span
                  className={`text-[11px] font-bold ${
                    stat.isPositive ? 'text-emerald-600' : 'text-amber-600'
                  }`}
                >
                  {stat.change}
                </span>
              </div>
            </div>
          );
        })}
      </div>

      {/* Quick Actions & Store Summary */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Store Highlights Card */}
        <div className="lg:col-span-2 rounded-2xl border border-borderMuted bg-surface p-6 shadow-card">
          <div className="flex items-center justify-between border-b border-borderMuted pb-4">
            <div>
              <h3 className="text-sm font-bold text-slateText-main">Active Store Profile</h3>
              <p className="text-xs text-slateText-secondary">Public presence on Grepmind Near mobile app</p>
            </div>
            <span className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-bold text-emerald-700 border border-emerald-200">
              Live in {business.city}
            </span>
          </div>

          <div className="mt-4 grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="rounded-xl bg-background p-3.5">
              <span className="text-[11px] font-semibold text-slateText-secondary">Delivery / Service Radius</span>
              <div className="mt-1 flex items-center space-x-1.5 text-sm font-bold text-slateText-main">
                <MapPin className="h-4 w-4 text-primary" />
                <span>{business.serviceRadiusKm} km coverage</span>
              </div>
            </div>
            <div className="rounded-xl bg-background p-3.5">
              <span className="text-[11px] font-semibold text-slateText-secondary">Operating Schedule</span>
              <div className="mt-1 flex items-center space-x-1.5 text-sm font-bold text-slateText-main">
                <Clock className="h-4 w-4 text-emerald-600" />
                <span>8:00 AM – 9:00 PM</span>
              </div>
            </div>
            <div className="rounded-xl bg-background p-3.5">
              <span className="text-[11px] font-semibold text-slateText-secondary">Catalog Items</span>
              <div className="mt-1 flex items-center space-x-1.5 text-sm font-bold text-slateText-main">
                <ShoppingBag className="h-4 w-4 text-indigo-600" />
                <span>{totalProductsCount} Products Listed</span>
              </div>
            </div>
          </div>
        </div>

        {/* Quick Shortcuts */}
        <div className="rounded-2xl border border-borderMuted bg-surface p-6 shadow-card flex flex-col justify-between">
          <div>
            <h3 className="text-sm font-bold text-slateText-main">Quick Actions</h3>
            <p className="text-xs text-slateText-secondary">Frequently used management tools</p>
          </div>

          <div className="mt-4 space-y-2.5">
            <button
              onClick={() => onNavigateTab('catalog')}
              className="flex w-full items-center justify-between rounded-xl border border-borderMuted bg-background px-4 py-2.5 text-xs font-semibold text-slateText-main hover:bg-slate-50 transition-colors"
            >
              <div className="flex items-center space-x-2.5">
                <Plus className="h-4 w-4 text-primary" />
                <span>Add New Catalog Item</span>
              </div>
              <span className="text-[10px] text-slateText-muted">Product / Service</span>
            </button>

            <button
              onClick={() => onNavigateTab('requests')}
              className="flex w-full items-center justify-between rounded-xl border border-borderMuted bg-background px-4 py-2.5 text-xs font-semibold text-slateText-main hover:bg-slate-50 transition-colors"
            >
              <div className="flex items-center space-x-2.5">
                <Calendar className="h-4 w-4 text-amber-600" />
                <span>Review Customer Bookings</span>
              </div>
              {pendingRequestsCount > 0 && (
                <span className="rounded-full bg-amber-500 text-white px-2 py-0.5 text-[10px] font-bold">
                  {pendingRequestsCount} new
                </span>
              )}
            </button>

            <button
              onClick={() => onNavigateTab('hours')}
              className="flex w-full items-center justify-between rounded-xl border border-borderMuted bg-background px-4 py-2.5 text-xs font-semibold text-slateText-main hover:bg-slate-50 transition-colors"
            >
              <div className="flex items-center space-x-2.5">
                <MapPin className="h-4 w-4 text-emerald-600" />
                <span>Adjust Radius & Localities</span>
              </div>
              <span className="text-[10px] text-slateText-muted">{business.serviceRadiusKm} km</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
