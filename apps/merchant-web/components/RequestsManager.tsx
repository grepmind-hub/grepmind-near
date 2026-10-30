'use strict';
'use client';

import React, { useState } from 'react';
import { ServiceRequest } from '../lib/types';
import { CalendarClock, Phone, MapPin, CheckCircle, Clock, XCircle, Search, Filter, AlertCircle, ArrowRight, Check } from 'lucide-react';

interface RequestsManagerProps {
  requests: ServiceRequest[];
  onUpdateStatus: (requestId: string, newStatus: ServiceRequest['status']) => void;
}

export const RequestsManager: React.FC<RequestsManagerProps> = ({
  requests,
  onUpdateStatus,
}) => {
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState<string>('');

  const filteredRequests = requests.filter((r) => {
    const matchesFilter = filterStatus === 'all' || r.status === filterStatus;
    const matchesSearch =
      r.customerName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      r.serviceName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      r.customerPhone.includes(searchQuery);
    return matchesFilter && matchesSearch;
  });

  const getStatusBadge = (status: ServiceRequest['status']) => {
    switch (status) {
      case 'requested':
        return (
          <span className="inline-flex items-center space-x-1 rounded-full bg-amber-50 px-2.5 py-1 text-xs font-bold text-amber-700 border border-amber-200">
            <Clock className="h-3.5 w-3.5" />
            <span>New Request</span>
          </span>
        );
      case 'accepted':
        return (
          <span className="inline-flex items-center space-x-1 rounded-full bg-blue-50 px-2.5 py-1 text-xs font-bold text-blue-700 border border-blue-200">
            <Check className="h-3.5 w-3.5" />
            <span>Booking Confirmed</span>
          </span>
        );
      case 'en_route':
        return (
          <span className="inline-flex items-center space-x-1 rounded-full bg-indigo-50 px-2.5 py-1 text-xs font-bold text-indigo-700 border border-indigo-200">
            <ArrowRight className="h-3.5 w-3.5" />
            <span>Technician En Route</span>
          </span>
        );
      case 'in_progress':
        return (
          <span className="inline-flex items-center space-x-1 rounded-full bg-purple-50 px-2.5 py-1 text-xs font-bold text-purple-700 border border-purple-200">
            <Clock className="h-3.5 w-3.5" />
            <span>Work In Progress</span>
          </span>
        );
      case 'completed':
        return (
          <span className="inline-flex items-center space-x-1 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-bold text-emerald-700 border border-emerald-200">
            <CheckCircle className="h-3.5 w-3.5" />
            <span>Completed & Paid</span>
          </span>
        );
      case 'cancelled':
        return (
          <span className="inline-flex items-center space-x-1 rounded-full bg-rose-50 px-2.5 py-1 text-xs font-bold text-rose-700 border border-rose-200">
            <XCircle className="h-3.5 w-3.5" />
            <span>Declined / Cancelled</span>
          </span>
        );
    }
  };

  return (
    <div className="space-y-6">
      {/* Top Controls: Search & Status Filters */}
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4 rounded-2xl border border-borderMuted bg-surface p-4 shadow-sm">
        {/* Search input */}
        <div className="relative flex-1">
          <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slateText-muted" />
          <input
            type="text"
            placeholder="Search customer name, phone, or service..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full rounded-xl border border-borderMuted bg-background pl-10 pr-4 py-2 text-xs font-medium text-slateText-main placeholder:text-slateText-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
          />
        </div>

        {/* Status Filter Chips */}
        <div className="flex items-center space-x-1.5 overflow-x-auto pb-1 sm:pb-0 custom-scrollbar">
          {['all', 'requested', 'accepted', 'in_progress', 'completed'].map((status) => (
            <button
              key={status}
              onClick={() => setFilterStatus(status)}
              className={`rounded-xl px-3 py-1.5 text-xs font-semibold whitespace-nowrap capitalize transition-colors ${
                filterStatus === status
                  ? 'bg-primary text-white shadow-sm'
                  : 'bg-background text-slateText-secondary hover:bg-slate-100 hover:text-slateText-main'
              }`}
            >
              {status === 'all' ? 'All Bookings' : status.replace('_', ' ')}
            </button>
          ))}
        </div>
      </div>

      {/* Requests List */}
      {filteredRequests.length === 0 ? (
        <div className="flex flex-col items-center justify-center rounded-2xl border border-dashed border-borderMuted bg-surface p-12 text-center">
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-slate-100 text-slateText-muted mb-3">
            <CalendarClock className="h-6 w-6" />
          </div>
          <h3 className="text-sm font-bold text-slateText-main">No Service Bookings Found</h3>
          <p className="mt-1 text-xs text-slateText-secondary max-w-sm">
            {searchQuery
              ? `No requests match "${searchQuery}". Try clearing search.`
              : `There are currently no ${filterStatus !== 'all' ? filterStatus : ''} customer bookings for this business.`}
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4">
          {filteredRequests.map((req) => (
            <div
              key={req.id}
              className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-card hover:shadow-cardHover transition-all"
            >
              <div className="flex flex-col md:flex-row md:items-start justify-between gap-4">
                {/* Left: Customer & Service Info */}
                <div className="space-y-2.5">
                  <div className="flex items-center space-x-3">
                    <span className="text-sm font-black text-slateText-main">{req.serviceName}</span>
                    {getStatusBadge(req.status)}
                    <span className="text-[11px] text-slateText-muted">• {req.createdAt}</span>
                  </div>

                  <p className="text-xs text-slateText-secondary leading-relaxed bg-background p-3 rounded-xl border border-borderMuted/60">
                    "{req.description}"
                  </p>

                  <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 text-xs text-slateText-main">
                    <div className="flex items-center space-x-2">
                      <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-blue-50 text-primary">
                        <CalendarClock className="h-3.5 w-3.5" />
                      </div>
                      <div>
                        <div className="text-[10px] text-slateText-muted uppercase font-bold">Slot Requested</div>
                        <div className="font-semibold">{req.requestedFor}</div>
                      </div>
                    </div>

                    <div className="flex items-center space-x-2">
                      <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-emerald-50 text-emerald-600">
                        <Phone className="h-3.5 w-3.5" />
                      </div>
                      <div>
                        <div className="text-[10px] text-slateText-muted uppercase font-bold">Customer Phone</div>
                        <a href={`tel:${req.customerPhone}`} className="font-semibold hover:underline text-primary">
                          {req.customerPhone} ({req.customerName})
                        </a>
                      </div>
                    </div>

                    <div className="flex items-center space-x-2">
                      <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-indigo-50 text-indigo-600">
                        <MapPin className="h-3.5 w-3.5" />
                      </div>
                      <div>
                        <div className="text-[10px] text-slateText-muted uppercase font-bold">Location Address</div>
                        <div className="font-semibold truncate max-w-[220px]">{req.address}</div>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Right: Actions & Pricing */}
                <div className="flex flex-row md:flex-col items-center md:items-end justify-between md:justify-start gap-3 border-t md:border-t-0 md:border-l border-borderMuted pt-3 md:pt-0 md:pl-5 shrink-0">
                  <div className="text-left md:text-right">
                    <div className="text-[10px] font-bold text-slateText-muted uppercase">Estimated Fee</div>
                    <div className="text-lg font-black text-slateText-main">
                      {req.priceEstimate ? `₹${req.priceEstimate}` : 'Custom Quote'}
                    </div>
                  </div>

                  <div className="flex items-center space-x-2">
                    {req.status === 'requested' && (
                      <>
                        <button
                          onClick={() => onUpdateStatus(req.id, 'accepted')}
                          className="rounded-xl bg-primary px-3.5 py-1.5 text-xs font-bold text-white shadow-sm hover:bg-primary-dark transition-colors"
                        >
                          Accept Booking
                        </button>
                        <button
                          onClick={() => onUpdateStatus(req.id, 'cancelled')}
                          className="rounded-xl border border-rose-200 bg-rose-50 px-3 py-1.5 text-xs font-bold text-rose-700 hover:bg-rose-100 transition-colors"
                        >
                          Decline
                        </button>
                      </>
                    )}

                    {req.status === 'accepted' && (
                      <button
                        onClick={() => onUpdateStatus(req.id, 'en_route')}
                        className="rounded-xl bg-indigo-600 px-3.5 py-1.5 text-xs font-bold text-white shadow-sm hover:bg-indigo-700 transition-colors"
                      >
                        Mark En Route
                      </button>
                    )}

                    {req.status === 'en_route' && (
                      <button
                        onClick={() => onUpdateStatus(req.id, 'in_progress')}
                        className="rounded-xl bg-purple-600 px-3.5 py-1.5 text-xs font-bold text-white shadow-sm hover:bg-purple-700 transition-colors"
                      >
                        Start Service
                      </button>
                    )}

                    {req.status === 'in_progress' && (
                      <button
                        onClick={() => onUpdateStatus(req.id, 'completed')}
                        className="rounded-xl bg-emerald-600 px-3.5 py-1.5 text-xs font-bold text-white shadow-sm hover:bg-emerald-700 transition-colors"
                      >
                        Complete Job & Collect ₹{req.priceEstimate}
                      </button>
                    )}

                    {req.status === 'completed' && (
                      <span className="flex items-center space-x-1 text-xs font-bold text-emerald-600">
                        <CheckCircle className="h-4 w-4" />
                        <span>Job Completed</span>
                      </span>
                    )}
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
