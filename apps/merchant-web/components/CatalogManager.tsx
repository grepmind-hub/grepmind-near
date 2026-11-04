'use strict';
'use client';

import React, { useState } from 'react';
import { ProductItem, ServiceItem } from '../lib/types';
import { Plus, Search, Check, X, Package, Wrench, UploadCloud, Image as ImageIcon, Loader2, Pencil } from 'lucide-react';
import { uploadMediaFile } from '../lib/api';

interface CatalogManagerProps {
  products: ProductItem[];
  services: ServiceItem[];
  onAddProduct: (product: { name: string; description: string; price: number; stock_status: string; is_published: boolean; image_url?: string }) => void;
  onUpdateProduct: (product: ProductItem, input: { name: string; description: string; price: number; stock_status: string; is_published: boolean; image_url?: string }) => void;
  onAddService: (service: { name: string; description: string; indicative_price_min: number; is_active: boolean }) => void;
  onUpdateService: (service: ServiceItem, input: { name: string; description: string; indicative_price_min: number; is_active: boolean }) => void;
  onToggleService: (service: ServiceItem) => void;
  onToggleProductStock: (product: ProductItem) => void;
  onDeleteProduct: (product: ProductItem) => void;
  onDeleteService: (service: ServiceItem) => void;
}

export const CatalogManager: React.FC<CatalogManagerProps> = ({
  products,
  services,
  onAddProduct,
  onUpdateProduct,
  onAddService,
  onUpdateService,
  onToggleService,
  onToggleProductStock,
  onDeleteProduct,
  onDeleteService,
}) => {
  const [activeTab, setActiveTab] = useState<'products' | 'services'>('products');
  const [searchQuery, setSearchQuery] = useState('');
  const [isAddProductOpen, setIsAddProductOpen] = useState(false);
  const [isAddServiceOpen, setIsAddServiceOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<ProductItem | null>(null);
  const [editingService, setEditingService] = useState<ServiceItem | null>(null);

  // New product form state
  const [newProductName, setNewProductName] = useState('');
  const [newProductPrice, setNewProductPrice] = useState('');
  const [newProductStock, setNewProductStock] = useState('in_stock');
  const [newProductDescription, setNewProductDescription] = useState('');
  const [uploadedImageUrl, setUploadedImageUrl] = useState('');
  const [isUploadingImage, setIsUploadingImage] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  // New service form state
  const [newServiceName, setNewServiceName] = useState('');
  const [newServicePrice, setNewServicePrice] = useState('');
  const [newServiceDescription, setNewServiceDescription] = useState('');

  const filteredProducts = products.filter(
    (p) =>
      p.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const filteredServices = services.filter((s) =>
    s.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const handleCreateProduct = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newProductName || !newProductPrice) return;
    const input = {
      name: newProductName,
      price: parseFloat(newProductPrice),
      stock_status: newProductStock,
      is_published: editingProduct?.isPublished ?? true,
      description: newProductDescription,
      image_url: uploadedImageUrl || editingProduct?.imageUrl,
    };
    if (editingProduct) onUpdateProduct(editingProduct, input); else onAddProduct(input);
    setEditingProduct(null);
    setNewProductName('');
    setNewProductPrice('');
    setNewProductDescription('');
    setUploadedImageUrl('');
    setUploadError(null);
    setIsAddProductOpen(false);
  };

  const handleCreateService = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newServiceName || !newServicePrice) return;
    const input = {
      name: newServiceName,
      indicative_price_min: parseFloat(newServicePrice),
      description: newServiceDescription,
      is_active: editingService?.isActive ?? true,
    };
    if (editingService) onUpdateService(editingService, input); else onAddService(input);
    setEditingService(null);
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
              onClick={() => { setEditingProduct(null); setNewProductName(''); setNewProductPrice(''); setNewProductDescription(''); setUploadedImageUrl(''); setIsAddProductOpen(true); }}
              className="flex items-center space-x-1.5 rounded-xl bg-primary px-3.5 py-1.5 text-xs font-bold text-white shadow-sm hover:bg-primary-dark transition-colors"
            >
              <Plus className="h-4 w-4" />
              <span>Add Product</span>
            </button>
          ) : (
            <button
              onClick={() => { setEditingService(null); setNewServiceName(''); setNewServicePrice(''); setNewServiceDescription(''); setIsAddServiceOpen(true); }}
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
                {p.imageUrl && <img src={p.imageUrl} alt={p.name} className="mb-3 h-36 w-full rounded-xl object-cover"/>}
                {/* Header: Category & Stock Switch */}
                <div className="flex items-center justify-between">
                  <span className="rounded-lg bg-slate-100 px-2.5 py-0.5 text-[10px] font-bold text-slateText-secondary uppercase tracking-wider">
                    Product
                  </span>
                  <button
                    onClick={() => onToggleProductStock(p)}
                    className={`flex items-center space-x-1 rounded-full px-2 py-0.5 text-[10px] font-bold transition-colors ${
                      p.stockStatus === 'in_stock'
                        ? 'bg-emerald-50 text-emerald-700 border border-emerald-200'
                        : 'bg-rose-50 text-rose-700 border border-rose-200'
                    }`}
                  >
                    <span className={`h-1.5 w-1.5 rounded-full ${p.stockStatus === 'in_stock' ? 'bg-emerald-500' : 'bg-rose-500'}`} />
                    <span>{p.stockStatus.replace('_', ' ')}</span>
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
                      ₹{p.price}
                    </span>
                  </div>
                </div>

                <button
                  onClick={() => onToggleProductStock(p)}
                  className="rounded-lg border border-borderMuted px-2.5 py-1 text-[11px] font-semibold text-slateText-secondary hover:bg-slate-50 transition-colors"
                >
                  {p.stockStatus === 'in_stock' ? 'Mark Out of Stock' : 'Mark In Stock'}
                </button>
                <button aria-label={`Edit ${p.name}`} onClick={() => { setEditingProduct(p); setNewProductName(p.name); setNewProductPrice(String(p.price)); setNewProductDescription(p.description); setNewProductStock(p.stockStatus); setUploadedImageUrl(p.imageUrl || ''); setIsAddProductOpen(true); }} className="ml-2 rounded-lg border border-borderMuted p-2 text-slateText-secondary hover:bg-blue-50 hover:text-primary"><Pencil size={14}/></button>
                <button onClick={() => onDeleteProduct(p)} className="ml-2 rounded-lg border border-rose-200 px-2.5 py-1 text-[11px] font-semibold text-rose-600 hover:bg-rose-50">Delete</button>
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
                    <span>{s.isActive ? 'Active service' : 'Paused service'}</span>
                  </div>
                </div>

                <h4 className="mt-2.5 text-sm font-bold text-slateText-main">{s.name}</h4>
                <p className="mt-1 text-xs text-slateText-secondary line-clamp-3 leading-relaxed">
                  {s.description}
                </p>
              </div>

              <div className="mt-4 pt-3 border-t border-borderMuted flex items-center justify-between">
                <div>
                  <div className="text-[10px] text-slateText-muted font-bold uppercase">Starting Rate</div>
                  <div className="text-base font-black text-slateText-main">From ₹{s.basePrice}</div>
                </div>
                <span className="rounded-xl bg-emerald-50 px-2.5 py-1 text-xs font-bold text-emerald-700">
                  {s.isActive ? 'Bookable Online' : 'Paused'}
                </span>
                <button onClick={() => onToggleService(s)} className="rounded-lg border border-borderMuted px-2.5 py-1 text-[11px] font-semibold text-slateText-secondary hover:bg-slate-50">{s.isActive ? 'Pause' : 'Activate'}</button>
                <button aria-label={`Edit ${s.name}`} onClick={() => { setEditingService(s); setNewServiceName(s.name); setNewServicePrice(String(s.basePrice)); setNewServiceDescription(s.description); setIsAddServiceOpen(true); }} className="ml-2 rounded-lg border border-borderMuted p-2 text-slateText-secondary hover:bg-blue-50 hover:text-primary"><Pencil size={14}/></button>
                <button onClick={() => onDeleteService(s)} className="ml-2 rounded-lg border border-rose-200 px-2.5 py-1 text-[11px] font-semibold text-rose-600 hover:bg-rose-50">Delete</button>
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
              <h3 className="text-sm font-bold text-slateText-main">{editingProduct ? 'Edit product' : 'Add Product to Store Catalog'}</h3>
              <button
                onClick={() => { setIsAddProductOpen(false); setEditingProduct(null); }}
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
                  <label className="text-xs font-bold text-slateText-main">Stock availability</label>
                  <select
                    value={newProductStock}
                    onChange={(e) => setNewProductStock(e.target.value)}
                    className="mt-1 w-full rounded-xl border border-borderMuted bg-background px-3.5 py-2 text-xs text-slateText-main focus:border-primary focus:outline-none"
                  >
                    <option value="in_stock">In stock</option>
                    <option value="out_of_stock">Out of stock</option>
                    <option value="unknown">Not specified</option>
                  </select>
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
                  onClick={() => { setIsAddProductOpen(false); setEditingProduct(null); }}
                  className="rounded-xl px-4 py-2 text-xs font-semibold text-slateText-secondary hover:bg-slate-100"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white shadow-sm hover:bg-primary-dark"
                >
                  {editingProduct ? 'Save product changes' : 'Publish to Store'}
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
              <h3 className="text-sm font-bold text-slateText-main">{editingService ? 'Edit service' : 'Create Service Package'}</h3>
              <button
                onClick={() => { setIsAddServiceOpen(false); setEditingService(null); }}
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
                  onClick={() => { setIsAddServiceOpen(false); setEditingService(null); }}
                  className="rounded-xl px-4 py-2 text-xs font-semibold text-slateText-secondary hover:bg-slate-100"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white shadow-sm hover:bg-primary-dark"
                >
                  {editingService ? 'Save service changes' : 'Publish Service'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
