'use client';

import React, { useState } from 'react';
import {
  TrendingUp,
  ArrowUpRight,
  ArrowDownRight,
  Users,
  ShieldCheck,
  Clock,
  IndianRupee,
  MapPin,
  Flame,
  CheckCircle2,
  Calendar,
  Layers,
  Sparkles,
} from 'lucide-react';
import {
  PLATFORM_KPIS,
  DAILY_TRENDS,
  CITY_ANALYTICS,
  CATEGORY_DEMAND,
  HOURLY_TRENDS,
  UNSERVED_DEMAND_ALERTS,
  DailyTrendPoint,
  CityAnalytics,
} from '@/lib/adminData';

interface GraphicalMetricsViewProps {
  selectedCity: string;
  selectedRange: '7d' | '14d' | '30d';
  onNavigateTab: (tab: 'verification' | 'businesses' | 'reports') => void;
}

export const GraphicalMetricsView: React.FC<GraphicalMetricsViewProps> = ({
  selectedCity,
  selectedRange,
  onNavigateTab,
}) => {
  const [hoveredTrend, setHoveredTrend] = useState<DailyTrendPoint | null>(null);
  const [cityMetricType, setCityMetricType] = useState<'requests' | 'gmv'>('requests');
  const [hoveredCategory, setHoveredCategory] = useState<string | null>(null);

  if (DAILY_TRENDS.length === 0) return <section className="rounded-2xl border bg-white p-8"><h2 className="text-lg font-semibold">Analytics unavailable</h2><p>Live analytics are not connected yet. No sample metrics are displayed.</p></section>;

  // Filter trends based on selected range
  const daysSlice = selectedRange === '7d' ? 7 : selectedRange === '14d' ? 14 : DAILY_TRENDS.length;
  const filteredTrends = DAILY_TRENDS.slice(-daysSlice);

  // Filter city analytics
  const filteredCities =
    selectedCity === 'All Cities'
      ? CITY_ANALYTICS
      : CITY_ANALYTICS.filter((c) => c.city.toLowerCase() === selectedCity.toLowerCase());

  // Max value for area chart scaling
  const maxRequests = Math.max(...filteredTrends.map((d) => d.totalRequests)) * 1.15;

  return (
    <div className="space-y-6 pb-12">
      {/* ------------------------------------------------------------- */}
      {/* Section 1: Executive KPI Cards */}
      {/* ------------------------------------------------------------- */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* KPI 1: Platform GMV */}
        <div className="rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-xs hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between text-xs text-[#667085]">
            <span className="font-semibold uppercase tracking-wider text-[11px] text-[#475467]">
              Platform GMV
            </span>
            <span className="flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-bold text-emerald-700">
              <ArrowUpRight className="h-3 w-3" /> +{PLATFORM_KPIS.totalGmvGrowth}%
            </span>
          </div>
          <div className="mt-3 flex items-baseline gap-1">
            <span className="text-3xl font-extrabold tracking-tight text-[#172033]">
              ₹{(PLATFORM_KPIS.totalGmv / 100000).toFixed(2)}
            </span>
            <span className="text-sm font-semibold text-[#667085]">Lakhs</span>
          </div>
          <div className="mt-3 flex items-center justify-between text-xs text-[#667085]">
            <span>Across Cuttack and Jajpur</span>
            <span className="font-semibold text-emerald-600">30-day run rate</span>
          </div>
        </div>

        {/* KPI 2: Active Verified Listings & Queue */}
        <div className="rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-xs hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between text-xs text-[#667085]">
            <span className="font-semibold uppercase tracking-wider text-[11px] text-[#475467]">
              Storefronts &amp; Pros
            </span>
            <button
              onClick={() => onNavigateTab('verification')}
              className="flex items-center gap-1 rounded-full bg-amber-50 px-2 py-0.5 text-xs font-bold text-amber-700 hover:bg-amber-100 transition-colors"
            >
              <ShieldCheck className="h-3 w-3" /> {PLATFORM_KPIS.pendingVerificationCount} Pending
            </button>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-3xl font-extrabold tracking-tight text-[#172033]">
              {PLATFORM_KPIS.activeListingsCount}
            </span>
            <span className="text-xs font-medium text-emerald-600">Active &amp; Verified</span>
          </div>
          <div className="mt-3 flex items-center justify-between text-xs text-[#667085]">
            <span>Review pending applications</span>
            <span
              onClick={() => onNavigateTab('verification')}
              className="cursor-pointer font-semibold text-[#2457D6] hover:underline"
            >
              Review queue →
            </span>
          </div>
        </div>

        {/* KPI 3: Request Volume & Fulfillment Rate */}
        <div className="rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-xs hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between text-xs text-[#667085]">
            <span className="font-semibold uppercase tracking-wider text-[11px] text-[#475467]">
              Service Requests
            </span>
            <span className="flex items-center gap-1 rounded-full bg-blue-50 px-2 py-0.5 text-xs font-bold text-[#2457D6]">
              {PLATFORM_KPIS.fulfillmentRatePct}% SLA
            </span>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-3xl font-extrabold tracking-tight text-[#172033]">
              {(PLATFORM_KPIS.totalRequestsCount / 1000).toFixed(1)}k
            </span>
            <span className="text-xs font-medium text-emerald-600">Completed jobs</span>
          </div>
          <div className="mt-3 flex items-center justify-between text-xs text-[#667085]">
            <span>Low cancel rate: 4.8%</span>
            <span className="font-semibold text-emerald-600">93.8% fulfilled</span>
          </div>
        </div>

        {/* KPI 4: Dispatch Speed & Rating */}
        <div className="rounded-2xl border border-[#E4E7EC] bg-white p-5 shadow-xs hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between text-xs text-[#667085]">
            <span className="font-semibold uppercase tracking-wider text-[11px] text-[#475467]">
              Dispatch &amp; Quality
            </span>
            <span className="flex items-center gap-1 rounded-full bg-purple-50 px-2 py-0.5 text-xs font-bold text-purple-700">
              ★ {PLATFORM_KPIS.customerSatisfactionScore}
            </span>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-3xl font-extrabold tracking-tight text-[#172033]">
              {PLATFORM_KPIS.avgDispatchMins}
            </span>
            <span className="text-xs font-semibold text-[#667085]">mins avg arrival</span>
          </div>
          <div className="mt-3 flex items-center justify-between text-xs text-[#667085]">
            <span>Fastest: Patia &amp; Badambadi</span>
            <span className="font-semibold text-emerald-600">Target &lt; 20m</span>
          </div>
        </div>
      </div>

      {/* ------------------------------------------------------------- */}
      {/* Section 2: Main Area Chart (Request Trends & Fulfillment) */}
      {/* ------------------------------------------------------------- */}
      <div className="rounded-2xl border border-[#E4E7EC] bg-white p-6 shadow-xs">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-base font-bold text-[#172033]">Daily Service Demand &amp; Completion Trends</h3>
              <span className="rounded-md bg-[#2457D6]/10 px-2 py-0.5 text-xs font-semibold text-[#2457D6]">
                {filteredTrends.length} Days View
              </span>
            </div>
            <p className="text-xs text-[#667085] mt-0.5">
              Tracking customer search-to-completion pipeline across Cuttack and Jajpur
            </p>
          </div>

          {/* Interactive Chart Legend */}
          <div className="flex items-center gap-4 text-xs font-medium">
            <div className="flex items-center gap-1.5">
              <span className="h-3 w-3 rounded-full bg-[#2457D6]"></span>
              <span className="text-[#344054]">Total Inquiries</span>
            </div>
            <div className="flex items-center gap-1.5">
              <span className="h-3 w-3 rounded-full bg-[#0F766E]"></span>
              <span className="text-[#344054]">Jobs Fulfilled</span>
            </div>
            <div className="flex items-center gap-1.5">
              <span className="h-3 w-3 rounded-full bg-[#F43F5E]"></span>
              <span className="text-[#344054]">Cancelled / Unserved</span>
            </div>
          </div>
        </div>

        {/* Interactive SVG Multi-Series Area Chart */}
        <div className="relative mt-6 h-64 w-full">
          <svg className="h-full w-full overflow-visible" preserveAspectRatio="none" viewBox="0 0 700 220">
            <defs>
              <linearGradient id="gradientTotal" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#2457D6" stopOpacity="0.25" />
                <stop offset="100%" stopColor="#2457D6" stopOpacity="0.00" />
              </linearGradient>
              <linearGradient id="gradientFulfilled" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#0F766E" stopOpacity="0.30" />
                <stop offset="100%" stopColor="#0F766E" stopOpacity="0.00" />
              </linearGradient>
            </defs>

            {/* Background Grid Lines */}
            {[0, 50, 100, 150, 200].map((y) => (
              <line
                key={y}
                x1="0"
                y1={y}
                x2="700"
                y2={y}
                stroke="#F2F4F7"
                strokeWidth="1"
                strokeDasharray="4 4"
              />
            ))}

            {/* Total Requests Area & Line */}
            {(() => {
              const points = filteredTrends.map((d, i) => {
                const x = (i / (filteredTrends.length - 1)) * 680 + 10;
                const y = 200 - (d.totalRequests / maxRequests) * 190;
                return { x, y, data: d };
              });

              const pathTotal = points.reduce((acc, p, i) => `${acc} ${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`, '');
              const areaTotal = `${pathTotal} L ${points[points.length - 1].x} 200 L ${points[0].x} 200 Z`;

              // Fulfilled Line
              const pointsFulfilled = filteredTrends.map((d, i) => {
                const x = (i / (filteredTrends.length - 1)) * 680 + 10;
                const y = 200 - (d.fulfilled / maxRequests) * 190;
                return { x, y };
              });
              const pathFulfilled = pointsFulfilled.reduce((acc, p, i) => `${acc} ${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`, '');
              const areaFulfilled = `${pathFulfilled} L ${pointsFulfilled[pointsFulfilled.length - 1].x} 200 L ${pointsFulfilled[0].x} 200 Z`;

              return (
                <g>
                  {/* Total Area Fill */}
                  <path d={areaTotal} fill="url(#gradientTotal)" />
                  {/* Fulfilled Area Fill */}
                  <path d={areaFulfilled} fill="url(#gradientFulfilled)" />

                  {/* Lines */}
                  <path d={pathTotal} fill="none" stroke="#2457D6" strokeWidth="2.5" strokeLinecap="round" />
                  <path d={pathFulfilled} fill="none" stroke="#0F766E" strokeWidth="2.5" strokeLinecap="round" />

                  {/* Interactive Dots */}
                  {points.map((p, i) => (
                    <g
                      key={i}
                      className="cursor-pointer"
                      onMouseEnter={() => setHoveredTrend(p.data)}
                      onMouseLeave={() => setHoveredTrend(null)}
                    >
                      <circle
                        cx={p.x}
                        cy={p.y}
                        r="4"
                        fill="#2457D6"
                        stroke="#FFFFFF"
                        strokeWidth="2"
                        className="transition-all hover:r-6"
                      />
                      <circle
                        cx={pointsFulfilled[i].x}
                        cy={pointsFulfilled[i].y}
                        r="3.5"
                        fill="#0F766E"
                        stroke="#FFFFFF"
                        strokeWidth="2"
                      />
                    </g>
                  ))}
                </g>
              );
            })()}
          </svg>

          {/* Dynamic Hover Tooltip */}
          {hoveredTrend && (
            <div className="absolute top-2 right-4 rounded-xl border border-[#D0D5DD] bg-white/95 p-3.5 shadow-lg backdrop-blur-sm text-xs">
              <div className="flex items-center gap-2 border-b border-[#E4E7EC] pb-1.5 font-bold text-[#172033]">
                <Calendar className="h-3.5 w-3.5 text-[#2457D6]" />
                {hoveredTrend.date} ({hoveredTrend.label})
              </div>
              <div className="mt-2 space-y-1">
                <div className="flex justify-between gap-6">
                  <span className="text-[#667085]">Total Requests:</span>
                  <span className="font-bold text-[#2457D6]">{hoveredTrend.totalRequests}</span>
                </div>
                <div className="flex justify-between gap-6">
                  <span className="text-[#667085]">Fulfilled Jobs:</span>
                  <span className="font-bold text-[#0F766E]">{hoveredTrend.fulfilled} ({((hoveredTrend.fulfilled / hoveredTrend.totalRequests) * 100).toFixed(1)}%)</span>
                </div>
                <div className="flex justify-between gap-6">
                  <span className="text-[#667085]">Daily Volume:</span>
                  <span className="font-bold text-[#172033]">₹{hoveredTrend.gmvAmount.toLocaleString()}</span>
                </div>
                <div className="flex justify-between gap-6">
                  <span className="text-[#667085]">Avg Dispatch Time:</span>
                  <span className="font-bold text-emerald-600">{hoveredTrend.avgSlaMins} mins</span>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* X-Axis Date Labels */}
        <div className="mt-2 flex justify-between px-2 text-[11px] font-medium text-[#98A2B3]">
          {filteredTrends.map((d, i) => (
            <span key={i} className="hidden sm:inline-block">
              {d.label}
            </span>
          ))}
          <span className="sm:hidden font-semibold text-[#2457D6]">{filteredTrends[filteredTrends.length - 1].label}</span>
        </div>
      </div>

      {/* ------------------------------------------------------------- */}
      {/* Section 3: Dual Charts (City Market Share + Category Donut) */}
      {/* ------------------------------------------------------------- */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Chart 2: Comparative City Analysis (2 Cols) */}
        <div className="lg:col-span-2 rounded-2xl border border-[#E4E7EC] bg-white p-6 shadow-xs">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div>
              <h3 className="text-base font-bold text-[#172033]">Regional Activity &amp; Market Distribution</h3>
              <p className="text-xs text-[#667085]">
                Direct comparison between Cuttack and Jajpur
              </p>
            </div>

            {/* Metric Switcher */}
            <div className="flex items-center rounded-lg border border-[#E4E7EC] bg-[#F7F8FA] p-0.5 text-xs font-medium">
              <button
                onClick={() => setCityMetricType('requests')}
                className={`rounded-md px-3 py-1 transition-all ${
                  cityMetricType === 'requests'
                    ? 'bg-white font-semibold text-[#2457D6] shadow-xs'
                    : 'text-[#667085]'
                }`}
              >
                Requests Volume
              </button>
              <button
                onClick={() => setCityMetricType('gmv')}
                className={`rounded-md px-3 py-1 transition-all ${
                  cityMetricType === 'gmv'
                    ? 'bg-white font-semibold text-[#0F766E] shadow-xs'
                    : 'text-[#667085]'
                }`}
              >
                GMV Revenue (₹)
              </button>
            </div>
          </div>

          {/* Grouped Comparative Bars */}
          <div className="mt-6 space-y-4">
            {CITY_ANALYTICS.map((cityData) => {
              const maxVal = cityMetricType === 'requests' ? 5500 : 1000000;
              const currentVal =
                cityMetricType === 'requests' ? cityData.totalRequests : cityData.gmvAmount;
              const fillPct = Math.min(100, Math.round((currentVal / maxVal) * 100));

              return (
                <div key={cityData.city} className="rounded-xl border border-[#F2F4F7] p-3 hover:bg-[#FAFAFA] transition-colors">
                  <div className="flex items-center justify-between text-xs font-semibold">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-bold text-[#172033]">{cityData.city}</span>
                      <span className="rounded-full bg-gray-100 px-2 py-0.2 text-[10px] text-[#475467]">
                        {cityData.activeListings} Active Stores
                      </span>
                      {cityData.pendingListings > 0 && (
                        <span className="rounded-full bg-amber-50 px-2 py-0.2 text-[10px] font-bold text-amber-700">
                          {cityData.pendingListings} Pending Review
                        </span>
                      )}
                    </div>
                    <div className="text-right">
                      <span className="font-bold text-[#172033]">
                        {cityMetricType === 'requests'
                          ? `${cityData.totalRequests.toLocaleString()} requests`
                          : `₹${(cityData.gmvAmount / 100000).toFixed(2)} Lakhs`}
                      </span>
                      <span className="ml-2 text-xs font-semibold text-emerald-600">
                        {cityData.fulfillmentRate}% fulfilled
                      </span>
                    </div>
                  </div>

                  {/* Progress bar */}
                  <div className="mt-2.5 h-3 w-full rounded-full bg-[#EAECF0] overflow-hidden flex">
                    <div
                      className={`h-full rounded-full transition-all duration-700 ${
                        cityData.city === 'Cuttack'
                          ? 'bg-[#2457D6]'
                          : 'bg-[#0F766E]'
                      }`}
                      style={{ width: `${fillPct}%` }}
                    />
                  </div>

                  <div className="mt-2 flex items-center justify-between text-[11px] text-[#667085]">
                    <span>Top Hubs: {cityData.topLocalities.slice(0, 3).join(', ')}</span>
                    <span className="text-amber-700 font-medium">
                      {cityData.unservedQueriesCount} unserved search spikes
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Chart 3: Category Demand Donut / Breakdown (1 Col) */}
        <div className="rounded-2xl border border-[#E4E7EC] bg-white p-6 shadow-xs flex flex-col justify-between">
          <div>
            <h3 className="text-base font-bold text-[#172033]">Category Volume Share</h3>
            <p className="text-xs text-[#667085]">Distribution of inquiries by trade</p>

            {/* Circular Graphic Visualization */}
            <div className="relative mt-6 flex items-center justify-center">
              <svg className="h-44 w-44 -rotate-90" viewBox="0 0 100 100">
                {(() => {
                  let accumulated = 0;
                  return CATEGORY_DEMAND.map((cat, idx) => {
                    const strokeDasharray = `${cat.sharePct} ${100 - cat.sharePct}`;
                    const strokeDashoffset = -accumulated;
                    accumulated += cat.sharePct;

                    return (
                      <circle
                        key={idx}
                        cx="50"
                        cy="50"
                        r="36"
                        fill="transparent"
                        stroke={cat.color}
                        strokeWidth="14"
                        strokeDasharray={strokeDasharray}
                        strokeDashoffset={strokeDashoffset}
                        className="transition-all duration-500 hover:opacity-80 cursor-pointer"
                        onMouseEnter={() => setHoveredCategory(cat.name)}
                        onMouseLeave={() => setHoveredCategory(null)}
                      />
                    );
                  });
                })()}
              </svg>

              {/* Donut Center Display */}
              <div className="absolute flex flex-col items-center justify-center text-center">
                <span className="text-xl font-extrabold text-[#172033]">10.3k</span>
                <span className="text-[10px] font-semibold text-[#667085] uppercase">
                  {hoveredCategory || 'Requests'}
                </span>
              </div>
            </div>

            {/* Segment Legends */}
            <div className="mt-6 space-y-2">
              {CATEGORY_DEMAND.map((cat) => (
                <div
                  key={cat.slug}
                  onMouseEnter={() => setHoveredCategory(cat.name)}
                  onMouseLeave={() => setHoveredCategory(null)}
                  className={`flex items-center justify-between text-xs py-1 px-1.5 rounded-lg transition-colors ${
                    hoveredCategory === cat.name ? 'bg-[#F2F4F7]' : ''
                  }`}
                >
                  <div className="flex items-center gap-2">
                    <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: cat.color }} />
                    <span className="text-[#344054] font-medium">{cat.name}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-[#172033]">{cat.sharePct}%</span>
                    <span className="text-[11px] text-[#98A2B3]">₹{cat.avgTicket} avg</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* ------------------------------------------------------------- */}
      {/* Section 4: Diurnal Hourly Booking Histogram & Unserved Demand */}
      {/* ------------------------------------------------------------- */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Hourly Peak Histogram (2 Cols) */}
        <div className="lg:col-span-2 rounded-2xl border border-[#E4E7EC] bg-white p-6 shadow-xs">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-base font-bold text-[#172033]">Peak Hourly Booking Distribution</h3>
              <p className="text-xs text-[#667085]">
                Customer dispatch volume throughout operating hours (08:00 - 22:00)
              </p>
            </div>
            <div className="flex items-center gap-2 text-xs font-semibold text-emerald-700 bg-emerald-50 px-2.5 py-1 rounded-full">
              <Clock className="h-3.5 w-3.5" /> Prime Surge: 17:00 - 19:30
            </div>
          </div>

          <div className="mt-6 flex h-44 items-end gap-2 pt-6">
            {HOURLY_TRENDS.map((h, i) => {
              const maxHour = 140;
              const heightPct = Math.round((h.requests / maxHour) * 100);
              const isPeak = h.requests > 100;

              return (
                <div key={i} className="group relative flex-1 flex flex-col items-center h-full justify-end">
                  {/* Tooltip */}
                  <div className="absolute -top-10 opacity-0 group-hover:opacity-100 transition-opacity bg-gray-900 text-white rounded-md px-2 py-1 text-[10px] pointer-events-none whitespace-nowrap shadow-md z-10">
                    {h.hour}: {h.requests} requests ({h.slaMins}m SLA)
                  </div>

                  <div
                    className={`w-full rounded-t-md transition-all duration-500 ${
                      isPeak
                        ? 'bg-gradient-to-t from-[#1E40AF] to-[#2457D6]'
                        : 'bg-[#D0D5DD] group-hover:bg-[#98A2B3]'
                    }`}
                    style={{ height: `${heightPct}%` }}
                  />
                  <span className="mt-2 text-[10px] text-[#667085] rotate-45 origin-left">
                    {h.hour.split(':')[0]}h
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Unserved Demand Alerts (Expansion Heatmap Radar) (1 Col) */}
        <div className="rounded-2xl border border-[#E4E7EC] bg-gradient-to-br from-amber-50/50 to-orange-50/20 p-6 shadow-xs flex flex-col justify-between">
          <div>
            <div className="flex items-center gap-2 text-amber-900">
              <Flame className="h-4.5 w-4.5 text-amber-600 animate-bounce" />
              <h3 className="text-base font-bold">Unserved Demand Radar</h3>
            </div>
            <p className="text-xs text-[#667085] mt-1">
              Top customer searches with zero matched local providers (High-priority merchant recruitment zones)
            </p>

            <div className="mt-4 space-y-3">
              {UNSERVED_DEMAND_ALERTS.map((alert) => (
                <div
                  key={alert.id}
                  className="rounded-xl border border-amber-200/80 bg-white p-3 shadow-2xs hover:border-amber-400 transition-colors"
                >
                  <div className="flex items-start justify-between">
                    <div>
                      <div className="flex items-center gap-1.5 text-xs font-bold text-[#172033]">
                        <MapPin className="h-3.5 w-3.5 text-amber-600" />
                        {alert.city} • {alert.locality}
                      </div>
                      <p className="mt-1 text-xs font-medium text-[#475467]">
                        &ldquo;{alert.query}&rdquo;
                      </p>
                    </div>
                    <span className="rounded-md bg-amber-100 px-1.5 py-0.5 text-[10px] font-bold text-amber-800">
                      +{alert.growthPct}%
                    </span>
                  </div>

                  <div className="mt-2.5 flex items-center justify-between text-[11px] text-[#667085] border-t border-[#F2F4F7] pt-2">
                    <span>{alert.searchCount} customer searches</span>
                    <button
                      onClick={() => onNavigateTab('verification')}
                      className="font-semibold text-[#2457D6] hover:underline"
                    >
                      Invite Pros →
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="mt-4 rounded-xl bg-amber-100/60 p-3 text-xs text-amber-900">
            <span className="font-bold">Expansion Advisory:</span> Review live demand data before making coverage decisions.
          </div>
        </div>
      </div>
    </div>
  );
};
