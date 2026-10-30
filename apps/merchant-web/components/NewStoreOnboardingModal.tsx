'use client';

import React, { useState } from 'react';
import { Store, MapPin, Sparkles, CheckCircle2, AlertCircle } from 'lucide-react';
import { Business } from '../lib/types';

interface NewStoreOnboardingModalProps {
  userPhone: string;
  onStoreCreated: (newBiz: Business) => void;
  onCancel: () => void;
}

export const NewStoreOnboardingModal: React.FC<NewStoreOnboardingModalProps> = ({
  userPhone,
  onStoreCreated,
  onCancel,
}) => {
  const [name, setName] = useState('');
  const [category, setCategory] = useState('Hardware & Electrical');
  const [categorySlug, setCategorySlug] = useState('hardware');
  const [locality, setLocality] = useState('Nayapalli');
  const [city, setCity] = useState('Bhubaneswar');
  const [address, setAddress] = useState('');
  const [radiusKm, setRadiusKm] = useState(10);
  const [error, setError] = useState('');

  const handleCategoryChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const val = e.target.value;
    setCategory(val);
    if (val.includes('Hardware')) setCategorySlug('hardware');
    else if (val.includes('Electrician')) setCategorySlug('electrician');
    else if (val.includes('Plumb')) setCategorySlug('plumber');
    else if (val.includes('Grocery')) setCategorySlug('grocery');
    else setCategorySlug('general');
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) {
      setError('Please provide your storefront name.');
      return;
    }
    if (!address.trim()) {
      setError('Please provide your street address.');
      return;
    }

    const newBiz: Business = {
      id: `biz-${Date.now()}`,
      ownerPhone: userPhone,
      name: name.trim(),
      category,
      categorySlug,
      locality: locality.trim(),
      city,
      phone: userPhone,
      rating: 5.0,
      reviewCount: 0,
      isOpen: true,
      isVerified: true,
      address: address.trim(),
      serviceRadiusKm: radiusKm,
      acceptsRequests: true,
      coverPhotoUrl: 'http://localhost:9000/grepmind-media/shops/hardware_shop.png',
    };

    onStoreCreated(newBiz);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 backdrop-blur-sm p-4">
      <div className="relative w-full max-w-lg rounded-3xl bg-surface p-7 shadow-2xl border border-borderMuted">
        <div className="flex items-center space-x-3 mb-4">
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary text-white shadow-md shadow-primary/20">
            <Store className="h-6 w-6" />
          </div>
          <div>
            <div className="flex items-center space-x-1.5">
              <h2 className="text-base font-bold text-slateText-main">Welcome to Grepmind Near</h2>
              <Sparkles className="h-4 w-4 text-amber-500" />
            </div>
            <p className="text-xs text-slateText-secondary">
              First-time login detected for <strong className="text-slateText-main">{userPhone}</strong>. Register your storefront to get started.
            </p>
          </div>
        </div>

        {error && (
          <div className="mb-4 flex items-center space-x-2 rounded-xl bg-rose-50 border border-rose-200 p-3 text-xs text-rose-700">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-bold text-slateText-main mb-1">
              Store / Business Name *
            </label>
            <input
              type="text"
              required
              placeholder="e.g. Kalinga Electricals & Hardware"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2.5 text-xs text-slateText-main placeholder:text-slateText-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-bold text-slateText-main mb-1">
                Category *
              </label>
              <select
                value={category}
                onChange={handleCategoryChange}
                className="w-full rounded-xl border border-borderMuted bg-background px-3 py-2.5 text-xs text-slateText-main focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              >
                <option value="Hardware & Electrical">Hardware & Electrical</option>
                <option value="Electrician & Repairs">Electrician & Repairs</option>
                <option value="Plumbing & Water Motors">Plumbing & Water Motors</option>
                <option value="Grocery & Daily Needs">Grocery & Daily Needs</option>
                <option value="Restaurant & Cafe">Restaurant & Cafe</option>
              </select>
            </div>

            <div>
              <label className="block text-xs font-bold text-slateText-main mb-1">
                City *
              </label>
              <select
                value={city}
                onChange={(e) => setCity(e.target.value)}
                className="w-full rounded-xl border border-borderMuted bg-background px-3 py-2.5 text-xs text-slateText-main focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              >
                <option value="Bhubaneswar">Bhubaneswar</option>
                <option value="Cuttack">Cuttack</option>
                <option value="Jajpur">Jajpur</option>
              </select>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-bold text-slateText-main mb-1">
                Locality / Area *
              </label>
              <input
                type="text"
                required
                placeholder="e.g. Nayapalli / Badambadi"
                value={locality}
                onChange={(e) => setLocality(e.target.value)}
                className="w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2.5 text-xs text-slateText-main placeholder:text-slateText-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-slateText-main mb-1">
                Service Radius: {radiusKm} km
              </label>
              <input
                type="range"
                min="1"
                max="30"
                value={radiusKm}
                onChange={(e) => setRadiusKm(Number(e.target.value))}
                className="w-full accent-primary mt-2"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-bold text-slateText-main mb-1">
              Full Street Address *
            </label>
            <input
              type="text"
              required
              placeholder="e.g. Plot 45, Near IRC Village, Bhubaneswar, Odisha"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              className="w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2.5 text-xs text-slateText-main placeholder:text-slateText-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>

          <div className="mt-6 pt-4 border-t border-borderMuted flex items-center justify-end space-x-2.5">
            <button
              type="button"
              onClick={onCancel}
              className="rounded-xl border border-borderMuted px-4 py-2.5 text-xs font-semibold text-slateText-main hover:bg-slate-50"
            >
              Sign Out
            </button>
            <button
              type="submit"
              className="rounded-xl bg-primary px-5 py-2.5 text-xs font-bold text-white hover:bg-primary/90 shadow-md shadow-primary/20"
            >
              Launch My Storefront
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
