'use client';

import React, { useState, useEffect } from 'react';
import {
  MapPin,
  Plus,
  Search,
  CheckCircle2,
  Clock,
  ShieldCheck,
  Building,
  Navigation,
  Utensils,
  ShoppingBag,
  Pill,
  Wrench,
  Car,
  Store,
  Layers,
  X,
  RefreshCw,
  AlertCircle,
} from 'lucide-react';
import {
  ServiceLocation,
  ServiceLocationInput,
  getServiceLocations,
  addServiceLocation,
  updateServiceLocation,
} from '@/lib/api';

export const ServiceAreasView: React.FC = () => {
  const [locations, setLocations] = useState<ServiceLocation[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [districtFilter, setDistrictFilter] = useState('All');
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Form state
  const [formData, setFormData] = useState<ServiceLocationInput>({
    district: 'Cuttack',
    name: '',
    pin_codes: [],
    latitude: 20.5348,
    longitude: 86.0827,
    service_radius_km: 10.0,
    delivery_enabled: true,
    is_active: true,
    food_delivery_enabled: true,
    grocery_delivery_enabled: true,
    medicines_delivery_enabled: true,
    local_services_enabled: true,
    transport_enabled: true,
    merchant_discovery_enabled: true,
  });
  const [pinCodesText, setPinCodesText] = useState('');

  const fetchLocations = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await getServiceLocations();
      setLocations(data);
    } catch (err: any) {
      setError(err?.response?.data?.error?.message || 'Failed to load service areas.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchLocations();
  }, []);

  const districts = ['All', ...Array.from(new Set(locations.map((l) => l.district_name))).filter(Boolean)];

  const filtered = locations.filter((loc) => {
    const matchesDistrict = districtFilter === 'All' || loc.district_name.toLowerCase() === districtFilter.toLowerCase();
    const query = searchQuery.toLowerCase().trim();
    const matchesSearch =
      !query ||
      loc.name.toLowerCase().includes(query) ||
      loc.district_name.toLowerCase().includes(query) ||
      (loc.pin_codes && loc.pin_codes.some((p) => p.includes(query)));
    return matchesDistrict && matchesSearch;
  });

  const handleOpenAdd = () => {
    setEditingId(null);
    setFormData({
      district: locations[0]?.district_name || 'Cuttack',
      name: '',
      pin_codes: [],
      latitude: 20.5348,
      longitude: 86.0827,
      service_radius_km: 10.0,
      delivery_enabled: true,
      is_active: true,
      food_delivery_enabled: true,
      grocery_delivery_enabled: true,
      medicines_delivery_enabled: true,
      local_services_enabled: true,
      transport_enabled: true,
      merchant_discovery_enabled: true,
    });
    setPinCodesText('');
    setIsModalOpen(true);
  };

  const locationInput = (loc: ServiceLocation): ServiceLocationInput => ({
    district: loc.district_name,
    name: loc.name,
    pin_codes: loc.pin_codes,
    latitude: loc.latitude,
    longitude: loc.longitude,
    service_radius_km: loc.service_radius_km,
    delivery_enabled: loc.delivery_enabled,
    is_active: loc.is_active,
    food_delivery_enabled: loc.food_delivery_enabled,
    grocery_delivery_enabled: loc.grocery_delivery_enabled,
    medicines_delivery_enabled: loc.medicines_delivery_enabled,
    local_services_enabled: loc.local_services_enabled,
    transport_enabled: loc.transport_enabled,
    merchant_discovery_enabled: loc.merchant_discovery_enabled,
  });

  const handleOpenEdit = (loc: ServiceLocation) => {
    setEditingId(loc.id);
    setFormData(locationInput(loc));
    setPinCodesText(loc.pin_codes.join(', '));
    setIsModalOpen(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formData.district.trim() || !formData.name.trim()) {
      alert('District and Locality name are required.');
      return;
    }

    const pins = pinCodesText
      .split(',')
      .map((p) => p.trim())
      .filter((p) => p.length > 0);
    if (pins.some((pin) => !/^\d{6}$/.test(pin))) {
      alert('Enter six digits for each PIN code.');
      return;
    }

    setSubmitting(true);
    try {
      const input = { ...formData, pin_codes: pins };
      if (editingId) {
        await updateServiceLocation(editingId, input);
      } else {
        await addServiceLocation(input);
      }
      setIsModalOpen(false);
      await fetchLocations();
    } catch (err: any) {
      alert(err?.response?.data?.error?.message || 'Failed to save service location.');
    } finally {
      setSubmitting(false);
    }
  };

  const handleToggleDelivery = async (loc: ServiceLocation) => {
    try {
      await updateServiceLocation(loc.id, {
        ...locationInput(loc),
        delivery_enabled: !loc.delivery_enabled,
      });
      await fetchLocations();
    } catch (err: any) {
      alert('Failed to update delivery status.');
    }
  };

  return (
    <div className="space-y-6">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-xl font-bold text-[#172033]">Service Areas & PIN Code Coverage</h2>
            <span className="rounded-full bg-[#EBF0FF] px-2.5 py-0.5 text-xs font-semibold text-[#2457D6]">
              {locations.length} Areas Configured
            </span>
          </div>
          <p className="text-xs text-[#667085] mt-0.5">
            Administer geographical serviceability, active PIN codes, and category delivery capabilities across Odisha.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={fetchLocations}
            className="flex items-center gap-1.5 rounded-xl border border-[#D0D5DD] bg-white px-3 py-2 text-xs font-medium text-[#344054] shadow-xs hover:bg-[#F9FAFB]"
          >
            <RefreshCw className="h-3.5 w-3.5 text-[#667085]" />
            Refresh
          </button>
          <button
            onClick={handleOpenAdd}
            className="flex items-center gap-1.5 rounded-xl bg-[#087F0D] px-3.5 py-2 text-xs font-semibold text-white shadow-xs hover:bg-[#076E0B] transition-colors"
          >
            <Plus className="h-4 w-4" />
            Add Service Location
          </button>
        </div>
      </div>

      {/* Overview Metric Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
        <div className="rounded-2xl border border-[#EAECF0] bg-white p-4 shadow-xs">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-[#667085]">Configured Localities</span>
            <div className="rounded-lg bg-[#EBF0FF] p-2 text-[#2457D6]">
              <MapPin className="h-4 w-4" />
            </div>
          </div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-bold text-[#101828]">{locations.length}</span>
            <span className="text-xs text-[#0F766E] font-medium">Odisha Pilot</span>
          </div>
        </div>

        <div className="rounded-2xl border border-[#EAECF0] bg-white p-4 shadow-xs">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-[#667085]">Active Delivery Zones</span>
            <div className="rounded-lg bg-[#E4F7E3] p-2 text-[#087F0D]">
              <CheckCircle2 className="h-4 w-4" />
            </div>
          </div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-bold text-[#101828]">
              {locations.filter((l) => l.delivery_enabled && l.is_active).length}
            </span>
            <span className="text-xs text-[#087F0D] font-medium">Live for Orders</span>
          </div>
        </div>

        <div className="rounded-2xl border border-[#EAECF0] bg-white p-4 shadow-xs">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-[#667085]">Covered PIN Codes</span>
            <div className="rounded-lg bg-[#FFF4ED] p-2 text-[#FF8A00]">
              <Navigation className="h-4 w-4" />
            </div>
          </div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-bold text-[#101828]">
              {locations.reduce((acc, curr) => acc + (curr.pin_codes?.length || 0), 0)}
            </span>
            <span className="text-xs text-[#667085]">Verified Postal Codes</span>
          </div>
        </div>

        <div className="rounded-2xl border border-[#EAECF0] bg-white p-4 shadow-xs">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-[#667085]">Coming Soon / Expansion</span>
            <div className="rounded-lg bg-[#FEF3F2] p-2 text-[#F04438]">
              <Clock className="h-4 w-4" />
            </div>
          </div>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="text-2xl font-bold text-[#101828]">
              {locations.filter((l) => !l.delivery_enabled && l.is_active).length}
            </span>
            <span className="text-xs text-[#667085]">Discovery Mode</span>
          </div>
        </div>
      </div>

      {/* Filter & Search Bar */}
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="flex flex-1 items-center rounded-xl border border-[#E4E7EC] bg-white px-3.5 py-2 shadow-xs">
          <Search className="h-4 w-4 text-[#98A2B3] mr-2" />
          <input
            type="text"
            placeholder="Search locality name, PIN code, or district..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full text-xs text-[#1D2939] placeholder-[#98A2B3] focus:outline-none bg-transparent"
          />
        </div>

        <div className="flex items-center gap-1.5 overflow-x-auto pb-1 sm:pb-0">
          {districts.map((d) => (
            <button
              key={d}
              onClick={() => setDistrictFilter(d)}
              className={`rounded-lg px-3 py-1.5 text-xs font-medium whitespace-nowrap transition-all ${
                districtFilter === d
                  ? 'bg-[#087F0D] text-white font-semibold shadow-xs'
                  : 'bg-white border border-[#D0D5DD] text-[#344054] hover:bg-[#F9FAFB]'
              }`}
            >
              {d}
            </button>
          ))}
        </div>
      </div>

      {/* Locations Table */}
      <div className="rounded-2xl border border-[#EAECF0] bg-white shadow-xs overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-xs text-[#667085]">Loading service locations...</div>
        ) : error ? (
          <div className="p-12 text-center text-xs text-rose-600">
            <AlertCircle className="h-6 w-6 mx-auto mb-2 text-rose-500" />
            {error}
          </div>
        ) : filtered.length === 0 ? (
          <div className="p-12 text-center text-xs text-[#667085]">
            No service locations found matching the criteria.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="border-b border-[#EAECF0] bg-[#F9FAFB] text-[11px] font-semibold text-[#475467] uppercase tracking-wider">
                  <th className="py-3 px-4">Locality & District</th>
                  <th className="py-3 px-4">PIN Codes</th>
                  <th className="py-3 px-4">Coordinates & Radius</th>
                  <th className="py-3 px-4">Service Status</th>
                  <th className="py-3 px-4">Enabled Capabilities</th>
                  <th className="py-3 px-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#EAECF0] text-xs text-[#344054]">
                {filtered.map((loc) => (
                  <tr key={loc.id} className="hover:bg-[#F9FAFB] transition-colors">
                    <td className="py-3.5 px-4">
                      <div className="font-semibold text-[#101828] text-sm">{loc.name}</div>
                      <div className="text-[11px] text-[#667085] flex items-center gap-1 mt-0.5">
                        <span className="font-medium text-[#2457D6]">{loc.district_name}</span>
                        <span>•</span>
                        <span>Odisha</span>
                      </div>
                    </td>
                    <td className="py-3.5 px-4">
                      <div className="flex flex-wrap gap-1">
                        {loc.pin_codes && loc.pin_codes.length > 0 ? (
                          loc.pin_codes.map((pin) => (
                            <span
                              key={pin}
                              className="rounded-md bg-[#F2F4F7] px-2 py-0.5 text-[11px] font-mono font-medium text-[#344054]"
                            >
                              {pin}
                            </span>
                          ))
                        ) : (
                          <span className="text-[11px] text-[#98A2B3] italic">No PIN assigned</span>
                        )}
                      </div>
                    </td>
                    <td className="py-3.5 px-4">
                      {loc.latitude && loc.longitude ? (
                        <div className="text-[11px] text-[#475467]">
                          <div>
                            {loc.latitude.toFixed(4)}, {loc.longitude.toFixed(4)}
                          </div>
                          <div className="text-[#0F766E] font-medium mt-0.5">Radius: {loc.service_radius_km} km</div>
                        </div>
                      ) : (
                        <span className="text-[11px] text-[#98A2B3]">Radius: {loc.service_radius_km} km</span>
                      )}
                    </td>
                    <td className="py-3.5 px-4">
                      {loc.delivery_enabled && loc.is_active ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-[#E4F7E3] px-2.5 py-0.5 text-[11px] font-medium text-[#087F0D]">
                          <span className="h-1.5 w-1.5 rounded-full bg-[#087F0D]" />
                          Active Delivery
                        </span>
                      ) : loc.is_active ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-[#FEF3F2] px-2.5 py-0.5 text-[11px] font-medium text-[#B42318]">
                          <span className="h-1.5 w-1.5 rounded-full bg-[#B42318]" />
                          Coming Soon / Discovery Only
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-[#F2F4F7] px-2.5 py-0.5 text-[11px] font-medium text-[#667085]">
                          Inactive
                        </span>
                      )}
                    </td>
                    <td className="py-3.5 px-4">
                      <div className="flex items-center gap-1.5 flex-wrap">
                        {loc.food_delivery_enabled && (
                          <span className="inline-flex items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] font-medium bg-[#FFE4D1] text-[#7A271A]">
                            <Utensils className="h-2.5 w-2.5" /> Food
                          </span>
                        )}
                        {loc.grocery_delivery_enabled && (
                          <span className="inline-flex items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] font-medium bg-[#E4F7E3] text-[#064D3A]">
                            <ShoppingBag className="h-2.5 w-2.5" /> Grocery
                          </span>
                        )}
                        {loc.medicines_delivery_enabled && (
                          <span className="inline-flex items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] font-medium bg-[#DFEEFF] text-[#1D2939]">
                            <Pill className="h-2.5 w-2.5" /> Meds
                          </span>
                        )}
                        {loc.local_services_enabled && (
                          <span className="inline-flex items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] font-medium bg-[#F3FAF0] text-[#087F0D]">
                            <Wrench className="h-2.5 w-2.5" /> Services
                          </span>
                        )}
                        {loc.transport_enabled && (
                          <span className="inline-flex items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] font-medium bg-[#DDF5A6] text-[#1D2939]">
                            <Car className="h-2.5 w-2.5" /> Transport
                          </span>
                        )}
                        {loc.merchant_discovery_enabled && (
                          <span className="inline-flex items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] font-medium bg-[#F2F4F7] text-[#344054]">
                            <Store className="h-2.5 w-2.5" /> Discovery
                          </span>
                        )}
                      </div>
                    </td>
                    <td className="py-3.5 px-4 text-right">
                      <button
                        onClick={() => handleOpenEdit(loc)}
                        className="mr-2 rounded-lg bg-[#F2F4F7] px-2.5 py-1 text-xs font-semibold text-[#344054]"
                        aria-label={`Edit ${loc.name} service area`}
                      >
                        Edit
                      </button>
                      <button
                        onClick={() => handleToggleDelivery(loc)}
                        className={`rounded-lg px-2.5 py-1 text-xs font-semibold transition-colors ${
                          loc.delivery_enabled
                            ? 'bg-[#FEF3F2] text-[#B42318] hover:bg-[#FEE4E2]'
                            : 'bg-[#E4F7E3] text-[#087F0D] hover:bg-[#D1F2D0]'
                        }`}
                      >
                        {loc.delivery_enabled ? 'Disable Delivery' : 'Enable Delivery'}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Add Location Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="w-full max-w-lg rounded-2xl bg-white shadow-xl overflow-hidden max-h-[90vh] flex flex-col">
            <div className="flex items-center justify-between border-b border-[#EAECF0] px-6 py-4">
              <div className="flex items-center gap-2">
                <div className="rounded-lg bg-[#E4F7E3] p-1.5 text-[#087F0D]">
                  <Plus className="h-4 w-4" />
                </div>
                <h3 className="text-base font-bold text-[#101828]">{editingId ? 'Edit Service Location' : 'Add Service Location'}</h3>
              </div>
              <button
                onClick={() => setIsModalOpen(false)}
                className="rounded-lg p-1 text-[#667085] hover:bg-[#F2F4F7]"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <form onSubmit={handleSave} className="flex-1 overflow-y-auto p-6 space-y-4">
              <div>
                <label className="block text-xs font-semibold text-[#344054] mb-1">
                  District Name *
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Cuttack, Jajpur, Khordha, Puri"
                  value={formData.district}
                  readOnly={!!editingId}
                  onChange={(e) => setFormData({ ...formData, district: e.target.value })}
                  className="w-full rounded-xl border border-[#D0D5DD] px-3.5 py-2 text-xs text-[#101828] focus:border-[#087F0D] focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[#344054] mb-1">
                  Locality / Town / Village Name *
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Chhatia, Kuanpal, Infovalley, Chauliaganj"
                  value={formData.name}
                  readOnly={!!editingId}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  className="w-full rounded-xl border border-[#D0D5DD] px-3.5 py-2 text-xs text-[#101828] focus:border-[#087F0D] focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[#344054] mb-1">
                  6-Digit Indian PIN Codes (comma-separated)
                </label>
                <input
                  type="text"
                  placeholder="e.g. 754023, 754024"
                  value={pinCodesText}
                  onChange={(e) => setPinCodesText(e.target.value)}
                  className="w-full rounded-xl border border-[#D0D5DD] px-3.5 py-2 text-xs font-mono text-[#101828] focus:border-[#087F0D] focus:outline-none"
                />
              </div>

              <div className="grid grid-cols-3 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[#344054] mb-1">
                    Latitude
                  </label>
                  <input
                    type="number"
                    step="any"
                    min={-90}
                    max={90}
                    value={formData.latitude ?? ''}
                    onChange={(e) =>
                      setFormData({
                        ...formData,
                        latitude: e.target.value ? parseFloat(e.target.value) : undefined,
                      })
                    }
                    className="w-full rounded-xl border border-[#D0D5DD] px-3 py-2 text-xs text-[#101828] focus:border-[#087F0D] focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[#344054] mb-1">
                    Longitude
                  </label>
                  <input
                    type="number"
                    step="any"
                    min={-180}
                    max={180}
                    value={formData.longitude ?? ''}
                    onChange={(e) =>
                      setFormData({
                        ...formData,
                        longitude: e.target.value ? parseFloat(e.target.value) : undefined,
                      })
                    }
                    className="w-full rounded-xl border border-[#D0D5DD] px-3 py-2 text-xs text-[#101828] focus:border-[#087F0D] focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[#344054] mb-1">
                    Radius (km)
                  </label>
                  <input
                    type="number"
                    step="any"
                    min={0.01}
                    value={formData.service_radius_km}
                    onChange={(e) =>
                      setFormData({
                        ...formData,
                        service_radius_km: parseFloat(e.target.value) || 10.0,
                      })
                    }
                    className="w-full rounded-xl border border-[#D0D5DD] px-3 py-2 text-xs text-[#101828] focus:border-[#087F0D] focus:outline-none"
                  />
                </div>
              </div>

              <div className="pt-2 border-t border-[#EAECF0]">
                <label className="block text-xs font-semibold text-[#344054] mb-2">
                  Service & Delivery Availability
                </label>
                <div className="flex items-center gap-4">
                  <label className="flex items-center gap-2 text-xs text-[#344054] cursor-pointer">
                    <input
                      type="checkbox"
                      checked={formData.delivery_enabled}
                      onChange={(e) => setFormData({ ...formData, delivery_enabled: e.target.checked })}
                      className="rounded border-[#D0D5DD] text-[#087F0D] focus:ring-[#087F0D]"
                    />
                    <span>Active Delivery Enabled</span>
                  </label>

                  <label className="flex items-center gap-2 text-xs text-[#344054] cursor-pointer">
                    <input
                      type="checkbox"
                      checked={formData.is_active}
                      onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
                      className="rounded border-[#D0D5DD] text-[#087F0D] focus:ring-[#087F0D]"
                    />
                    <span>Is Active</span>
                  </label>
                </div>
              </div>

              <div className="pt-2 border-t border-[#EAECF0]">
                <label className="block text-xs font-semibold text-[#344054] mb-2">
                  Category Capabilities
                </label>
                <div className="grid grid-cols-2 gap-2 text-xs text-[#344054]">
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={formData.food_delivery_enabled}
                      onChange={(e) => setFormData({ ...formData, food_delivery_enabled: e.target.checked })}
                      className="rounded border-[#D0D5DD] text-[#087F0D]"
                    />
                    <span>Food Delivery</span>
                  </label>
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={formData.grocery_delivery_enabled}
                      onChange={(e) => setFormData({ ...formData, grocery_delivery_enabled: e.target.checked })}
                      className="rounded border-[#D0D5DD] text-[#087F0D]"
                    />
                    <span>Grocery Delivery</span>
                  </label>
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={formData.medicines_delivery_enabled}
                      onChange={(e) => setFormData({ ...formData, medicines_delivery_enabled: e.target.checked })}
                      className="rounded border-[#D0D5DD] text-[#087F0D]"
                    />
                    <span>Medicines / Pharmacy</span>
                  </label>
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={formData.local_services_enabled}
                      onChange={(e) => setFormData({ ...formData, local_services_enabled: e.target.checked })}
                      className="rounded border-[#D0D5DD] text-[#087F0D]"
                    />
                    <span>Local Services</span>
                  </label>
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={formData.transport_enabled}
                      onChange={(e) => setFormData({ ...formData, transport_enabled: e.target.checked })}
                      className="rounded border-[#D0D5DD] text-[#087F0D]"
                    />
                    <span>Transport (Cab / Auto)</span>
                  </label>
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={formData.merchant_discovery_enabled}
                      onChange={(e) => setFormData({ ...formData, merchant_discovery_enabled: e.target.checked })}
                      className="rounded border-[#D0D5DD] text-[#087F0D]"
                    />
                    <span>Merchant Discovery</span>
                  </label>
                </div>
              </div>

              <div className="flex items-center justify-end gap-3 pt-4 border-t border-[#EAECF0]">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="rounded-xl border border-[#D0D5DD] px-4 py-2 text-xs font-semibold text-[#344054] hover:bg-[#F9FAFB]"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="rounded-xl bg-[#087F0D] px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-[#076E0B] disabled:opacity-50"
                >
                  {submitting ? 'Saving...' : 'Save Location'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
