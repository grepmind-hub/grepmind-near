'use strict';
'use client';

import React, { useState } from 'react';
import { ProductItem, ServiceItem } from '../lib/types';
import { Plus, Search, Tag, Check, X, Sparkles, Package, Wrench, IndianRupee, Layers, UploadCloud, Image as ImageIcon, Loader2 } from 'lucide-react';
import { uploadMediaFile } from '../lib/api';

interface CatalogManagerProps {
  products: ProductItem[];
  services: ServiceItem[];
  onAddProduct: (product: Omit<ProductItem, 'id'>) => void;
  onAddService: (service: Omit<ServiceItem, 'id'>) => void;
  onToggleProductStock: (productId: string) => void;
}

export const CatalogManager: React.FC<CatalogManagerProps> = ({
  products,
  services,
  onAddProduct,
  onAddService,
  onToggleProductStock,
}) => {
  const [activeTab, setActiveTab] = useState<'products' | 'services'>('products');
  const [searchQuery, setSearchQuery] = useState('');
  const [isAddProductOpen, setIsAddProductOpen] = useState(false);
  const [isAddServiceOpen, setIsAddServiceOpen] = useState(false);

  // New product form state
  const [newProductName, setNewProductName] = useState('');
  const [newProductPrice, setNewProductPrice] = useState('');
  const [newProductDiscount, setNewProductDiscount] = useState('');
  const [newProductCategory, setNewProductCategory] = useState('Hardware');
  const [newProductStock, setNewProductStock] = useState('25');
  const [newProductDescription, setNewProductDescription] = useState('');
  const [uploadedImageUrl, setUploadedImageUrl] = useState('');
  const [isUploadingImage, setIsUploadingImage] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  // New service form state
  const [newServiceName, setNewServiceName] = useState('');
  const [newServicePrice, setNewServicePrice] = useState('');
  const [newServiceDuration, setNewServiceDuration] = useState('45');
  const [newServiceDescription, setNewServiceDescription] = useState('');

  const filteredProducts = products.filter(
    (p) =>
      p.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      p.category.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const filteredServices = services.filter((s) =>
    s.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const handleCreateProduct = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newProductName || !newProductPrice) return;
    onAddProduct({
      businessId: products[0]?.businessId || 'a1111111-1111-1111-1111-111111111111',
      name: newProductName,
      price: parseFloat(newProductPrice),
      discountPrice: newProductDiscount ? parseFloat(newProductDiscount) : undefined,
      category: newProductCategory,
      stockCount: parseInt(newProductStock) || 0,
      inStock: (parseInt(newProductStock) || 0) > 0,
      description: newProductDescription,
      imageUrl: uploadedImageUrl || 'http://localhost:9000/grepmind-media/shops/hardware_shop.png',
    });
    setNewProductName('');
    setNewProductPrice('');
    setNewProductDiscount('');
    setNewProductDescription('');
    setUploadedImageUrl('');
    setUploadError(null);
    setIsAddProductOpen(false);
  };

  const handleCreateService = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newServiceName || !newServicePrice) return;
    onAddService({
      businessId: services[0]?.businessId || 'a1111111-1111-1111-1111-111111111111',
      name: newServiceName,
      basePrice: parseFloat(newServicePrice),
      durationMinutes: parseInt(newServiceDuration) || 45,
      description: newServiceDescription,
      popular: true,
    });
    setNewServiceName('');
    setNewServicePrice('');
    setNewServiceDescription('');
    setIsAddServiceOpen(false);
  };

  return (
    <div className="space-y-6">
      {/* Catalog Header & Add Buttons */}
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4 rounded-2xl border border-borderMuted bg-surface p-4 shadow-sm">
        {/* Toggle between Products and Services */}
        <div className="flex items-center space-x-1.5 rounded-xl bg-background p-1 border border-borderMuted">
          <button
            onClick={() => setActiveTab('products')}
            className={`flex items-center space-x-2 rounded-lg px-4 py-1.5 text-xs font-bold transition-all ${
              activeTab === 'products'
                ? 'bg-surface text-primary shadow-sm'
                : 'text-slateText-secondary hover:text-slateText-main'
            }`}
          >
            <Package className="h-4 w-4" />
            <span>Retail Products ({products.length})</span>
          </button>
          <button
            onClick={() => setActiveTab('services')}
            className={`flex items-center space-x-2 rounded-lg px-4 py-1.5 text-xs font-bold transition-all ${
              activeTab === 'services'
                ? 'bg-surface text-primary shadow-sm'
                : 'text-slateText-secondary hover:text-slateText-main'
            }`}
          >
            <Wrench className="h-4 w-4" />
            <span>Service Packages ({services.length})</span>
          </button>
        </div>

        {/* Search bar & Action Button */}
        <div className="flex items-center space-x-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-slateText-muted" />
            <input
              type="text"
              placeholder={`Search ${activeTab}...`}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-48 sm:w-64 rounded-xl border border-borderMuted bg-background pl-9 pr-3 py-1.5 text-xs font-medium text-slateText-main placeholder:text-slateText-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>

          {activeTab === 'products' ? (
            <button
              onClick={() => setIsAddProductOpen(true)}
              className="flex items-center space-x-1.5 rounded-xl bg-primary px-3.5 py-1.5 text-xs font-bold text-white shadow-sm hover:bg-primary-dark transition-colors"
            >
              <Plus className="h-4 w-4" />
              <span>Add Product</span>
            </button>
          ) : (
            <button
              onClick={() => setIsAddServiceOpen(true)}
              className="flex items-center space-x-1.5 rounded-xl bg-primary px-3.5 py-1.5 text-xs font-bold text-white shadow-sm hover:bg-primary-dark transition-colors"
            >
              <Plus className="h-4 w-4" />
              <span>Add Service</span>
            </button>
          )}
        </div>
      </div>

      {/* Products Tab Grid */}
      {activeTab === 'products' && (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
          {filteredProducts.map((p) => (
            <div
              key={p.id}
              className="flex flex-col justify-between rounded-2xl border border-borderMuted bg-surface p-4 shadow-card hover:shadow-cardHover transition-all"
            >
              <div>
                {/* Header: Category & Stock Switch */}
                <div className="flex items-center justify-between">
                  <span className="rounded-lg bg-slate-100 px-2.5 py-0.5 text-[10px] font-bold text-slateText-secondary uppercase tracking-wider">
                    {p.category}
                  </span>
                  <button
                    onClick={() => onToggleProductStock(p.id)}
                    className={`flex items-center space-x-1 rounded-full px-2 py-0.5 text-[10px] font-bold transition-colors ${
                      p.inStock
                        ? 'bg-emerald-50 text-emerald-700 border border-emerald-200'
                        : 'bg-rose-50 text-rose-700 border border-rose-200'
                    }`}
                  >
                    <span className={`h-1.5 w-1.5 rounded-full ${p.inStock ? 'bg-emerald-500' : 'bg-rose-500'}`} />
                    <span>{p.inStock ? `In Stock (${p.stockCount})` : 'Out of Stock'}</span>
                  </button>
                </div>

                {/* Product Name & Description */}
                <h4 className="mt-3 text-sm font-bold text-slateText-main line-clamp-1">{p.name}</h4>
                <p className="mt-1 text-xs text-slateText-secondary line-clamp-2 leading-relaxed">
                  {p.description}
                </p>
              </div>

              {/* Price Row */}
              <div className="mt-4 pt-3 border-t border-borderMuted flex items-baseline justify-between">
                <div>
                  <div className="flex items-baseline space-x-2">
                    <span className="text-base font-black text-slateText-main">
                      ₹{p.discountPrice || p.price}
                    </span>
                    {p.discountPrice && (
                      <span className="text-xs text-slateText-muted line-through">₹{p.price}</span>
                    )}
                  </div>
                  {p.discountPrice && (
                    <span className="text-[10px] font-bold text-emerald-600">
                      Save ₹{p.price - p.discountPrice}
                    </span>
                  )}
                </div>

                <button
                  onClick={() => onToggleProductStock(p.id)}
                  className="rounded-lg border border-borderMuted px-2.5 py-1 text-[11px] font-semibold text-slateText-secondary hover:bg-slate-50 transition-colors"
                >
                  {p.inStock ? 'Mark Out of Stock' : 'Mark Available'}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Services Tab Grid */}
      {activeTab === 'services' && (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {filteredServices.map((s) => (
            <div
              key={s.id}
              className="flex flex-col justify-between rounded-2xl border border-borderMuted bg-surface p-5 shadow-card hover:shadow-cardHover transition-all"
            >
              <div>
                <div className="flex items-center justify-between">
                  <div className="flex items-center space-x-1.5 text-xs text-slateText-secondary font-semibold">
                    <Wrench className="h-3.5 w-3.5 text-primary" />
                    <span>~{s.durationMinutes} mins estimated</span>
                  </div>
                  {s.popular && (
                    <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] font-bold text-primary">
                      Popular Service
                    </span>
                  )}
                </div>

                <h4 className="mt-2.5 text-sm font-bold text-slateText-main">{s.name}</h4>
                <p className="mt-1 text-xs text-slateText-secondary line-clamp-3 leading-relaxed">
                  {s.description}
                </p>
              </div>

              <div className="mt-4 pt-3 border-t border-borderMuted flex items-center justify-between">
                <div>
                  <div className="text-[10px] text-slateText-muted font-bold uppercase">Starting Rate</div>
                  <div className="text-base font-black text-slateText-main">₹{s.basePrice}</div>
                </div>
                <span className="rounded-xl bg-emerald-50 px-2.5 py-1 text-xs font-bold text-emerald-700">
                  Bookable Online
                </span>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Modal: Add Product */}
      {isAddProductOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm p-4">
          <div className="w-full max-w-lg rounded-2xl border border-borderMuted bg-surface p-6 shadow-2xl">
            <div className="flex items-center justify-between border-b border-borderMuted pb-3">
              <h3 className="text-sm font-bold text-slateText-main">Add Product to Store Catalog</h3>
              <button
                onClick={() => setIsAddProductOpen(false)}
                className="rounded-lg p-1 text-slateText-muted hover:bg-slate-100"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <form onSubmit={handleCreateProduct} className="mt-4 space-y-4">
              <div>
                <label className="text-xs font-bold text-slateText-main">Product Title</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Havells 12W LED Recessed Panel Light"
                  value={newProductName}
                  onChange={(e) => setNewProductName(e.target.value)}
                  className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-bold text-slateText-main">MRP Price (₹)</label>
                  <input
                    type="number"
                    required
                    placeholder="250"
                    value={newProductPrice}
                    onChange={(e) => setNewProductPrice(e.target.value)}
                    className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                  />
                </div>
                <div>
                  <label className="text-xs font-bold text-slateText-main">Discounted Price (₹)</label>
                  <input
                    type="number"
                    placeholder="210 (Optional)"
                    value={newProductDiscount}
                    onChange={(e) => setNewProductDiscount(e.target.value)}
                    className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-bold text-slateText-main">Category</label>
                  <select
                    value={newProductCategory}
                    onChange={(e) => setNewProductCategory(e.target.value)}
                    className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                  >
                    <option value="Hardware">Hardware & Tools</option>
                    <option value="Electrical">Electrical Switchgear</option>
                    <option value="Lighting">Lighting & Fixtures</option>
                    <option value="Wiring">Cables & Wiring</option>
                    <option value="Pipes">Pipes & Plumbing</option>
                  </select>
                </div>
                <div>
                  <label className="text-xs font-bold text-slateText-main">Initial Stock Count</label>
                  <input
                    type="number"
                    value={newProductStock}
                    onChange={(e) => setNewProductStock(e.target.value)}
                    className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                  />
                </div>
              </div>

              <div>
                <label className="text-xs font-bold text-slateText-main">Description / Specifications</label>
                <textarea
                  rows={3}
                  placeholder="Key features, warranty, brand details..."
                  value={newProductDescription}
                  onChange={(e) => setNewProductDescription(e.target.value)}
                  className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                />
              </div>

              {/* MinIO Object Storage Photo Upload (Option 4) */}
              <div>
                <label className="text-xs font-bold text-slateText-main">Product Photo (Direct MinIO Upload)</label>
                <div className="mt-1.5 flex items-center gap-3">
                  <div className="relative flex h-20 w-20 flex-shrink-0 items-center justify-center rounded-xl border border-dashed border-borderMuted bg-background overflow-hidden">
                    {uploadedImageUrl ? (
                      <img
                        src={uploadedImageUrl}
                        alt="Product Preview"
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <ImageIcon className="h-6 w-6 text-slateText-muted" />
                    )}
                    {isUploadingImage && (
                      <div className="absolute inset-0 flex items-center justify-center bg-black/40">
                        <Loader2 className="h-5 w-5 animate-spin text-white" />
                      </div>
                    )}
                  </div>

                  <div className="flex-1">
                    <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-borderMuted bg-white px-3 py-1.5 text-xs font-semibold text-slateText-main shadow-xs hover:bg-slate-50 transition-colors">
                      <UploadCloud className="h-4 w-4 text-primary" />
                      <span>{uploadedImageUrl ? 'Replace Photo' : 'Upload from Device'}</span>
                      <input
                        type="file"
                        accept="image/png,image/jpeg,image/webp"
                        className="hidden"
                        onChange={async (e) => {
                          const file = e.target.files?.[0];
                          if (!file) return;
                          setIsUploadingImage(true);
                          setUploadError(null);
                          try {
                            const res = await uploadMediaFile(file, 'product');
                            setUploadedImageUrl(res.url);
                          } catch (err: any) {
                            setUploadError(err.message || 'Upload failed');
                          } finally {
                            setIsUploadingImage(false);
                          }
                        }}
                      />
                    </label>
                    <p className="mt-1 text-[11px] text-slateText-muted">
                      Direct upload to MinIO S3 bucket (JPEG, PNG, WebP up to 10MB)
                    </p>
                    {uploadError && (
                      <p className="mt-1 text-[11px] font-semibold text-rose-600">{uploadError}</p>
                    )}
                    {uploadedImageUrl && (
                      <p className="mt-0.5 text-[11px] font-medium text-emerald-600 flex items-center gap-1">
                        <Check className="h-3 w-3" /> Stored in MinIO: {uploadedImageUrl}
                      </p>
                    )}
                  </div>
                </div>
              </div>

              <div className="flex items-center justify-end space-x-3 pt-3 border-t border-borderMuted">
                <button
                  type="button"
                  onClick={() => setIsAddProductOpen(false)}
                  className="rounded-xl px-4 py-2 text-xs font-semibold text-slateText-secondary hover:bg-slate-100"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white shadow-sm hover:bg-primary-dark"
                >
                  Publish to Store
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Add Service */}
      {isAddServiceOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm p-4">
          <div className="w-full max-w-lg rounded-2xl border border-borderMuted bg-surface p-6 shadow-2xl">
            <div className="flex items-center justify-between border-b border-borderMuted pb-3">
              <h3 className="text-sm font-bold text-slateText-main">Create Service Package</h3>
              <button
                onClick={() => setIsAddServiceOpen(false)}
                className="rounded-lg p-1 text-slateText-muted hover:bg-slate-100"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <form onSubmit={handleCreateService} className="mt-4 space-y-4">
              <div>
                <label className="text-xs font-bold text-slateText-main">Service Name</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Geyser Installation & Earthing Test"
                  value={newServiceName}
                  onChange={(e) => setNewServiceName(e.target.value)}
                  className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-bold text-slateText-main">Base Fee (₹)</label>
                  <input
                    type="number"
                    required
                    placeholder="399"
                    value={newServicePrice}
                    onChange={(e) => setNewServicePrice(e.target.value)}
                    className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                  />
                </div>
                <div>
                  <label className="text-xs font-bold text-slateText-main">Duration (Minutes)</label>
                  <input
                    type="number"
                    value={newServiceDuration}
                    onChange={(e) => setNewServiceDuration(e.target.value)}
                    className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                  />
                </div>
              </div>

              <div>
                <label className="text-xs font-bold text-slateText-main">Scope of Work Included</label>
                <textarea
                  rows={3}
                  placeholder="What is covered in this service rate? (e.g., bracket fitting, pressure testing)..."
                  value={newServiceDescription}
                  onChange={(e) => setNewServiceDescription(e.target.value)}
                  className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                />
              </div>

              <div className="flex items-center justify-end space-x-3 pt-3 border-t border-borderMuted">
                <button
                  type="button"
                  onClick={() => setIsAddServiceOpen(false)}
                  className="rounded-xl px-4 py-2 text-xs font-semibold text-slateText-secondary hover:bg-slate-100"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white shadow-sm hover:bg-primary-dark"
                >
                  Publish Service
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
