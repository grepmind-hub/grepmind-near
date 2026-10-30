'use strict';
'use client';

import React, { useState } from 'react';
import { OperatingHoursDay, Business } from '../lib/types';
import { Clock, MapPin, Zap, Save, CheckCircle2, Plus, X } from 'lucide-react';

interface HoursCoverageManagerProps {
  business: Business;
  hours: OperatingHoursDay[];
  onSaveHours: (updatedHours: OperatingHoursDay[]) => void;
  onSaveRadius: (newRadius: number) => void;
}

export const HoursCoverageManager: React.FC<HoursCoverageManagerProps> = ({
  business,
  hours: initialHours,
  onSaveHours,
  onSaveRadius,
}) => {
  const [schedule, setSchedule] = useState<OperatingHoursDay[]>(initialHours);
  const [radius, setRadius] = useState<number>(business.serviceRadiusKm || 15);
  const [localities, setLocalities] = useState<string[]>([
    'Saheed Nagar',
    'Unit 3 & Janpath',
    'Nayapalli',
    'Chandrasekharpur',
    'Patia',
    'Badambadi',
  ]);
  const [newLocality, setNewLocality] = useState('');
  const [allowEmergency, setAllowEmergency] = useState(true);
  const [savedFeedback, setSavedFeedback] = useState(false);

  const handleToggleDay = (index: number) => {
    const updated = [...schedule];
    updated[index].isOpen = !updated[index].isOpen;
    setSchedule(updated);
  };

  const handleChangeTime = (index: number, field: 'openTime' | 'closeTime', value: string) => {
    const updated = [...schedule];
    updated[index][field] = value;
    setSchedule(updated);
  };

  const handleAddLocality = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newLocality.trim()) return;
    if (!localities.includes(newLocality.trim())) {
      setLocalities([...localities, newLocality.trim()]);
    }
    setNewLocality('');
  };

  const handleRemoveLocality = (loc: string) => {
    setLocalities(localities.filter((l) => l !== loc));
  };

  const handleSaveAll = () => {
    onSaveHours(schedule);
    onSaveRadius(radius);
    setSavedFeedback(true);
    setTimeout(() => setSavedFeedback(false), 3000);
  };

  const coverageAreaSqKm = Math.round(Math.PI * radius * radius);

  return (
    <div className="space-y-6">
      {/* Top Banner with Save Action */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 rounded-2xl border border-borderMuted bg-surface p-5 shadow-sm">
        <div>
          <h3 className="text-base font-bold text-slateText-main">Store Hours & Geographic Coverage</h3>
          <p className="text-xs text-slateText-secondary">
            Set your weekly business hours, service radius, and covered residential localities in {business.city}.
          </p>
        </div>

        <button
          onClick={handleSaveAll}
          className="flex items-center space-x-2 rounded-xl bg-primary px-5 py-2.5 text-xs font-bold text-white shadow-sm hover:bg-primary-dark transition-colors"
        >
          {savedFeedback ? <CheckCircle2 className="h-4 w-4 text-white" /> : <Save className="h-4 w-4" />}
          <span>{savedFeedback ? 'Changes Saved!' : 'Save Operating Settings'}</span>
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left 2 Cols: 7-Day Operating Hours Schedule */}
        <div className="lg:col-span-2 rounded-2xl border border-borderMuted bg-surface p-6 shadow-card">
          <div className="flex items-center justify-between border-b border-borderMuted pb-4 mb-4">
            <div className="flex items-center space-x-2.5">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-50 text-primary">
                <Clock className="h-4 w-4" />
              </div>
              <h4 className="text-sm font-bold text-slateText-main">Weekly Operating Hours</h4>
            </div>
            <span className="text-xs text-slateText-secondary">Times visible on customer mobile app</span>
          </div>

          <div className="space-y-3">
            {schedule.map((dayItem, index) => (
              <div
                key={dayItem.day}
                className={`flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 rounded-xl border p-3.5 transition-colors ${
                  dayItem.isOpen
                    ? 'border-borderMuted bg-background'
                    : 'border-slate-200 bg-slate-50/50 opacity-60'
                }`}
              >
                {/* Day Name & Toggle */}
                <div className="flex items-center space-x-3 w-36">
                  <button
                    onClick={() => handleToggleDay(index)}
                    className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none ${
                      dayItem.isOpen ? 'bg-primary' : 'bg-slate-300'
                    }`}
                  >
                    <span
                      className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow-lg ring-0 transition duration-200 ease-in-out ${
                        dayItem.isOpen ? 'translate-x-4' : 'translate-x-0'
                      }`}
                    />
                  </button>
                  <span className="text-xs font-bold text-slateText-main">{dayItem.day}</span>
                </div>

                {/* Time Pickers or Closed label */}
                {dayItem.isOpen ? (
                  <div className="flex items-center space-x-2 text-xs">
                    <span className="text-slateText-secondary font-medium">Opens:</span>
                    <input
                      type="text"
                      value={dayItem.openTime}
                      onChange={(e) => handleChangeTime(index, 'openTime', e.target.value)}
                      className="w-24 rounded-lg border border-borderMuted bg-surface px-2.5 py-1 text-center font-bold text-slateText-main focus:border-primary focus:outline-none"
                    />
                    <span className="text-slateText-muted">—</span>
                    <span className="text-slateText-secondary font-medium">Closes:</span>
                    <input
                      type="text"
                      value={dayItem.closeTime}
                      onChange={(e) => handleChangeTime(index, 'closeTime', e.target.value)}
                      className="w-24 rounded-lg border border-borderMuted bg-surface px-2.5 py-1 text-center font-bold text-slateText-main focus:border-primary focus:outline-none"
                    />
                  </div>
                ) : (
                  <span className="text-xs font-semibold text-slateText-muted italic">
                    Closed for customers
                  </span>
                )}
              </div>
            ))}
          </div>
        </div>

        {/* Right Col: Radius & Covered Localities */}
        <div className="space-y-6">
          {/* Radius Slider Card */}
          <div className="rounded-2xl border border-borderMuted bg-surface p-6 shadow-card">
            <div className="flex items-center space-x-2.5 border-b border-borderMuted pb-4 mb-4">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-50 text-emerald-600">
                <MapPin className="h-4 w-4" />
              </div>
              <h4 className="text-sm font-bold text-slateText-main">Service Radius</h4>
            </div>

            <div className="space-y-4">
              <div className="flex items-baseline justify-between">
                <span className="text-xs text-slateText-secondary font-medium">Coverage Distance</span>
                <span className="text-xl font-black text-primary">{radius} km</span>
              </div>

              <input
                type="range"
                min="1"
                max="50"
                value={radius}
                onChange={(e) => setRadius(parseInt(e.target.value))}
                className="w-full accent-primary cursor-pointer"
              />

              <div className="rounded-xl bg-background p-3.5 border border-borderMuted/60 text-xs text-slateText-secondary space-y-1">
                <div className="flex justify-between">
                  <span>Coverage Area:</span>
                  <strong className="text-slateText-main">~{coverageAreaSqKm} km²</strong>
                </div>
                <div className="flex justify-between">
                  <span>Estimated Customer Reach:</span>
                  <strong className="text-emerald-600">~145,000 residents</strong>
                </div>
              </div>
            </div>
          </div>

          {/* Localities Tags Card */}
          <div className="rounded-2xl border border-borderMuted bg-surface p-6 shadow-card">
            <h4 className="text-sm font-bold text-slateText-main mb-2">Priority Localities</h4>
            <p className="text-xs text-slateText-secondary mb-3">
              Add key landmarks and neighborhoods you actively serve.
            </p>

            <form onSubmit={handleAddLocality} className="flex items-center space-x-2 mb-3">
              <input
                type="text"
                placeholder="Add locality (e.g. Nayapalli)"
                value={newLocality}
                onChange={(e) => setNewLocality(e.target.value)}
                className="flex-1 rounded-xl border border-borderMuted bg-background px-3 py-1.5 text-xs text-slateText-main focus:border-primary focus:outline-none"
              />
              <button
                type="submit"
                className="flex items-center justify-center rounded-xl bg-slate-900 px-3 py-1.5 text-xs font-bold text-white hover:bg-slate-800"
              >
                <Plus className="h-3.5 w-3.5" />
              </button>
            </form>

            <div className="flex flex-wrap gap-1.5">
              {localities.map((loc) => (
                <span
                  key={loc}
                  className="inline-flex items-center space-x-1 rounded-lg bg-background border border-borderMuted px-2.5 py-1 text-xs font-medium text-slateText-main"
                >
                  <span>{loc}</span>
                  <button
                    onClick={() => handleRemoveLocality(loc)}
                    className="text-slateText-muted hover:text-rose-600"
                  >
                    <X className="h-3 w-3" />
                  </button>
                </span>
              ))}
            </div>
          </div>

          {/* Emergency / On-Demand Urgent Jobs Toggle */}
          <div className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-card flex items-center justify-between">
            <div className="flex items-start space-x-3">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-amber-50 text-amber-600">
                <Zap className="h-4 w-4" />
              </div>
              <div>
                <h5 className="text-xs font-bold text-slateText-main">Emergency On-Demand Requests</h5>
                <p className="text-[11px] text-slateText-secondary">Receive urgent 60-min callouts</p>
              </div>
            </div>

            <button
              onClick={() => setAllowEmergency(!allowEmergency)}
              className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none ${
                allowEmergency ? 'bg-amber-500' : 'bg-slate-300'
              }`}
            >
              <span
                className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow-lg ring-0 transition duration-200 ease-in-out ${
                  allowEmergency ? 'translate-x-4' : 'translate-x-0'
                }`}
              />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
