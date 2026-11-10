'use client';

import React, { FormEvent, useCallback, useEffect, useState } from 'react';
import { BadgeCheck, Boxes, Building2, CircleAlert, LoaderCircle, Plus, RefreshCw, Search, Tag } from 'lucide-react';
import {
  addPartnerCoverage, createPlatformCategory, createPlatformMapping, createPlatformProduct, createPlatformVariant,
  deletePartnerCoverage, getAllBusinesses, getPartnerCoverage, getPlatformCategories, getPlatformMappings, getPlatformProducts,
  PlatformCatalogCategory, PlatformCatalogProduct, PlatformCatalogVariant, PlatformPartnerMapping, updatePlatformCategory,
  updatePlatformMapping, updatePlatformProduct, Business,
  updatePlatformVariant,
  uploadPlatformCatalogImage,
} from '@/lib/api';

type View = 'products' | 'categories' | 'partners';
const inputClass = 'min-h-11 w-full rounded-xl border border-slate-200 bg-white px-3 text-sm text-slate-800 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100';
const buttonClass = 'inline-flex min-h-10 items-center justify-center gap-2 rounded-xl bg-blue-700 px-4 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-800 disabled:cursor-not-allowed disabled:opacity-50';
const money = (minor: number) => `₹${(minor / 100).toFixed(2)}`;

export function PlatformCatalogView() {
  const [view, setView] = useState<View>('products');
  const [products, setProducts] = useState<PlatformCatalogProduct[]>([]);
  const [categories, setCategories] = useState<PlatformCatalogCategory[]>([]);
  const [mappings, setMappings] = useState<PlatformPartnerMapping[]>([]);
  const [businesses, setBusinesses] = useState<Business[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [query, setQuery] = useState('');

  const refresh = useCallback(async (keepCurrentView = false) => {
    if (!keepCurrentView) setLoading(true);
    setError('');
    try {
      const [p, c, m, b] = await Promise.all([
        getPlatformProducts(), getPlatformCategories(), getPlatformMappings(), getAllBusinesses('approved'),
      ]);
      setProducts(p); setCategories(c); setMappings(m); setBusinesses(b.filter(x => x.verification_status === 'verified'));
    } catch { setError('Catalog data could not be loaded. Check the Admin API connection and retry.'); }
    finally { if (!keepCurrentView) setLoading(false); }
  }, []);
  useEffect(() => { const timer = window.setTimeout(() => void refresh(), 0); return () => window.clearTimeout(timer); }, [refresh]);

  async function action(run: () => Promise<unknown>) {
    setBusy(true); setError('');
    try { await run(); await refresh(true); }
    catch { setError('The change was not saved. Review the values and try again.'); }
    finally { setBusy(false); }
  }

  const visibleProducts = products.filter(p => `${p.name} ${p.sku} ${p.vertical}`.toLowerCase().includes(query.toLowerCase()));
  const visibleMappings = mappings.filter(m => `${m.product_name} ${m.business_name} ${m.status}`.toLowerCase().includes(query.toLowerCase()));

  return <section className="space-y-6">
    <header className="flex flex-wrap items-end justify-between gap-4">
      <div><p className="text-xs font-bold uppercase tracking-[.16em] text-blue-700">Commerce foundation</p><h1 className="mt-1 text-2xl font-bold text-slate-900">Platform catalog</h1><p className="mt-1 max-w-2xl text-sm text-slate-500">Manage Grepmind-owned Food and Grocery products, prices, service areas, and approved fulfillment partners.</p></div>
      <button className="inline-flex min-h-10 items-center gap-2 rounded-xl border border-slate-200 bg-white px-4 text-sm font-semibold text-slate-700" onClick={() => void refresh()}><RefreshCw size={16}/> Refresh</button>
    </header>
    <div className="grid gap-3 sm:grid-cols-3">
      <Metric icon={Boxes} label="Platform products" value={products.length}/><Metric icon={Tag} label="Categories" value={categories.length}/><Metric icon={BadgeCheck} label="Partner mappings" value={mappings.length}/>
    </div>
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-slate-200 bg-white p-3 shadow-sm">
      <div className="flex gap-1">{(['products','categories','partners'] as View[]).map((id) => <button key={id} onClick={() => setView(id)} className={`min-h-10 rounded-xl px-4 text-sm font-semibold capitalize ${view===id?'bg-blue-700 text-white':'text-slate-600 hover:bg-slate-100'}`}>{id==='partners'?'Partner mapping':id}</button>)}</div>
      <label className="relative w-full sm:max-w-xs"><Search className="absolute left-3 top-3 text-slate-400" size={16}/><input className={`${inputClass} pl-9`} value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search catalog" aria-label="Search catalog"/></label>
    </div>
    {error && <div role="alert" className="flex items-center gap-2 rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800"><CircleAlert size={17}/>{error}</div>}
    {loading ? <div className="flex min-h-52 items-center justify-center gap-2 text-sm text-slate-500"><LoaderCircle className="animate-spin" size={18}/>Loading live catalog…</div> : <>
      {view==='products' && <ProductsPanel products={visibleProducts} categories={categories} busy={busy} run={action}/>}
      {view==='categories' && <CategoriesPanel categories={categories} busy={busy} run={action}/>}
      {view==='partners' && <PartnersPanel products={products} mappings={visibleMappings} businesses={businesses} busy={busy} run={action}/>}
    </>}
  </section>;
}

function Metric({icon: Icon,label,value}:{icon:React.ElementType;label:string;value:number}) { return <div className="flex items-center gap-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm"><span className="grid h-11 w-11 place-items-center rounded-xl bg-blue-50 text-blue-700"><Icon size={20}/></span><div><p className="text-xs font-medium text-slate-500">{label}</p><p className="text-xl font-bold text-slate-900">{value}</p></div></div>; }

function ProductsPanel({products,categories,busy,run}:{products:PlatformCatalogProduct[];categories:PlatformCatalogCategory[];busy:boolean;run:(fn:()=>Promise<unknown>)=>Promise<void>}) {
  const [open,setOpen]=useState(false);
  const [editing,setEditing]=useState<PlatformCatalogProduct|null>(null);
  const [addingVariant,setAddingVariant]=useState<string|null>(null);
  const [editingVariant,setEditingVariant]=useState<PlatformCatalogVariant|null>(null);
  const [imageText,setImageText]=useState(''); const [uploadingImage,setUploadingImage]=useState(false); const [imageError,setImageError]=useState('');
  async function submit(e:FormEvent<HTMLFormElement>) {
    e.preventDefault(); const form=e.currentTarget; const f=new FormData(form);
    const areas=String(f.get('cities')).split(',').map(city=>({city:city.trim()})).filter(x=>x.city);
    const price=Math.round(Number(f.get('price'))*100);
    const images=String(f.get('images')||'').split('\n').map(x=>x.trim()).filter(Boolean);
    await run(async()=>{
      if (editing) {
        await updatePlatformProduct(editing.id,{category_id:f.get('category'),name:f.get('name'),description:f.get('description'),image_urls:images,tax_classification:String(f.get('tax')||''),areas});
        const variant=editing.variants[0];
        if (variant) await updatePlatformVariant(variant.id,{name:f.get('variant'),unit_label:f.get('unit'),price_minor:price,currency:'INR'});
      } else {
        await createPlatformProduct({sku:f.get('sku'),category_id:f.get('category'),name:f.get('name'),description:f.get('description'),image_urls:images,tax_classification:String(f.get('tax')||''),status:'draft',areas,variants:[{sku:f.get('variant_sku'),name:f.get('variant'),unit_label:f.get('unit'),price_minor:price,currency:'INR'}]});
      }
    });
    form.reset(); setOpen(false); setEditing(null);setImageText('');
  }
  function edit(product:PlatformCatalogProduct) { setEditing(product);setImageText(product.image_urls.join('\n'));setOpen(true); }
  async function uploadImage(file?:File) { if(!file)return;setUploadingImage(true);setImageError('');try{const url=await uploadPlatformCatalogImage(file);setImageText(current=>[...current.split('\n').map(x=>x.trim()).filter(Boolean),url].slice(0,8).join('\n'));}catch{setImageError('Image upload failed. Check the file type, 10 MB limit, and media service.');}finally{setUploadingImage(false);} }
  async function submitVariant(productID:string,e:FormEvent<HTMLFormElement>) { e.preventDefault();const form=e.currentTarget;const f=new FormData(form);await run(()=>createPlatformVariant(productID,{sku:f.get('sku'),name:f.get('name'),unit_label:f.get('unit'),price_minor:Math.round(Number(f.get('price'))*100),currency:'INR'}));form.reset();setAddingVariant(null); }
  async function saveVariant(e:FormEvent<HTMLFormElement>) { e.preventDefault();if(!editingVariant)return;const form=e.currentTarget;const f=new FormData(form);await run(()=>updatePlatformVariant(editingVariant.id,{name:f.get('name'),unit_label:f.get('unit'),price_minor:Math.round(Number(f.get('price'))*100),currency:'INR',is_active:f.get('active')==='true'}));setEditingVariant(null); }
  return <div className="space-y-4"><div className="flex justify-end"><button className={buttonClass} onClick={()=>{setEditing(null);setImageText('');setOpen(v=>!v)}}><Plus size={16}/> New product</button></div>
    {open&&<form key={editing?.id??'new'} onSubmit={submit} className="grid gap-3 rounded-2xl border border-blue-100 bg-blue-50/50 p-5 sm:grid-cols-2">
      <Field label="Product name"><input required name="name" defaultValue={editing?.name} className={inputClass}/></Field><Field label="Product SKU"><input required name="sku" readOnly={!!editing} defaultValue={editing?.sku} className={`${inputClass} read-only:bg-slate-100`}/></Field>
      <Field label="Food / Grocery category"><select required name="category" defaultValue={editing?.category_id??''} className={inputClass}><option value="">Choose category</option>{categories.filter(c=>c.is_active).map(c=><option key={c.id} value={c.id}>{c.vertical} · {c.name}</option>)}</select></Field>
      <Field label="Tax classification (optional)"><input name="tax" defaultValue={editing?.tax_classification} className={inputClass} placeholder="e.g. GST classification"/></Field>
      <Field label="Variant name"><input required name="variant" defaultValue={editing?.variants[0]?.name} className={inputClass} placeholder="e.g. 500 g pack"/></Field><Field label="Variant SKU"><input required name="variant_sku" readOnly={!!editing} defaultValue={editing?.variants[0]?.sku} className={`${inputClass} read-only:bg-slate-100`}/></Field>
      <Field label="Unit label"><input required name="unit" defaultValue={editing?.variants[0]?.unit_label} className={inputClass} placeholder="500 g"/></Field><Field label="Selling price (₹)"><input required min="0" step="0.01" type="number" name="price" defaultValue={editing?.variants[0]?(editing.variants[0].price_minor/100).toFixed(2):''} className={inputClass}/></Field>
      <Field label="Availability cities (comma separated)"><input required name="cities" defaultValue={editing?.areas.map(a=>a.city).join(', ')||'Cuttack, Jajpur'} className={inputClass}/></Field>
      <Field label="Image URLs (one per line)"><textarea name="images" value={imageText} onChange={e=>setImageText(e.target.value)} className={inputClass} rows={2} placeholder="https://… or /media/…"/><input type="file" accept="image/jpeg,image/png,image/webp" onChange={e=>void uploadImage(e.target.files?.[0])} disabled={uploadingImage||imageText.split('\n').filter(Boolean).length>=8} className="mt-2 block w-full text-xs text-slate-600 file:mr-3 file:min-h-9 file:rounded-lg file:border-0 file:bg-blue-50 file:px-3 file:font-semibold file:text-blue-700"/>{uploadingImage&&<span className="text-xs text-blue-700">Uploading image…</span>}{imageError&&<span role="alert" className="text-xs text-rose-700">{imageError}</span>}</Field>
      <Field label="Description"><textarea name="description" defaultValue={editing?.description} className={inputClass} rows={2}/></Field>
      <div className="flex items-end gap-2"><button disabled={busy||uploadingImage} className={buttonClass}>{editing?'Save changes':'Save as draft'}</button><button type="button" onClick={()=>{setOpen(false);setEditing(null);setImageText('')}} className="min-h-10 rounded-xl px-3 text-sm font-semibold text-slate-600">Cancel</button><span className="text-xs text-slate-500">Selling price is in ₹; stored in paise.</span></div>
    </form>}
    <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white"><div className="grid grid-cols-[1fr_auto] gap-4 border-b bg-slate-50 px-5 py-3 text-xs font-bold uppercase tracking-wide text-slate-500"><span>Product</span><span>Status / action</span></div>
      {products.length===0?<Empty>No platform products yet. Create products after confirming catalog data.</Empty>:products.map(p=><React.Fragment key={p.id}><div className="grid grid-cols-[1fr_auto] items-center gap-3 border-b border-slate-100 px-5 py-4 last:border-0"><div className="min-w-0"><p className="truncate font-semibold text-slate-900">{p.name}</p><p className="mt-1 text-xs text-slate-500">{p.vertical} · {p.category_name} · {p.sku} · {p.areas.map(a=>a.locality?`${a.locality}, ${a.city}`:a.city).join(', ')}</p><p className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-slate-600">{p.variants.map(v=><span key={v.id}>{v.name}: {money(v.price_minor)} <button type="button" onClick={()=>setEditingVariant(v)} className="font-semibold text-blue-700">Edit</button></span>)}</p></div><div className="flex items-center gap-2"><span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold capitalize text-slate-700">{p.status}</span><button disabled={busy} onClick={()=>edit(p)} className="min-h-9 rounded-lg border border-slate-200 px-3 text-xs font-semibold text-slate-700">Edit</button><button disabled={busy||p.status==='inactive'} onClick={()=>setAddingVariant(addingVariant===p.id?null:p.id)} className="min-h-9 rounded-lg border border-slate-200 px-3 text-xs font-semibold text-slate-700">Add variant</button>{p.status==='draft'&&<button disabled={busy||p.variants.length===0||p.areas.length===0} onClick={()=>void run(()=>updatePlatformProduct(p.id,{status:'active'}))} className="min-h-9 rounded-lg border border-blue-200 px-3 text-xs font-semibold text-blue-700 disabled:opacity-40">Activate</button>}{p.status==='active'&&<button disabled={busy} onClick={()=>void run(()=>updatePlatformProduct(p.id,{status:'inactive'}))} className="min-h-9 rounded-lg border border-slate-200 px-3 text-xs font-semibold text-slate-600">Deactivate</button>}</div></div>{editingVariant?.product_id===p.id&&<form onSubmit={saveVariant} className="grid gap-3 border-b border-slate-100 bg-blue-50/50 p-4 sm:grid-cols-5"><Field label="Variant name"><input required name="name" defaultValue={editingVariant.name} className={inputClass}/></Field><Field label="Unit"><input required name="unit" defaultValue={editingVariant.unit_label} className={inputClass}/></Field><Field label="Selling price (₹)"><input required min="0" step="0.01" name="price" type="number" defaultValue={(editingVariant.price_minor/100).toFixed(2)} className={inputClass}/></Field><Field label="Active"><select name="active" defaultValue={String(editingVariant.is_active)} className={inputClass}><option value="true">Active</option><option value="false">Inactive</option></select></Field><div className="flex items-end gap-2"><button disabled={busy} className={buttonClass}>Save variant</button><button type="button" onClick={()=>setEditingVariant(null)} className="min-h-10 rounded-xl px-3 text-sm font-semibold text-slate-600">Cancel</button></div></form>}{addingVariant===p.id&&<form onSubmit={e=>void submitVariant(p.id,e)} className="grid gap-3 border-b border-slate-100 bg-slate-50 p-4 sm:grid-cols-5"><Field label="Variant SKU"><input required name="sku" className={inputClass}/></Field><Field label="Name"><input required name="name" className={inputClass}/></Field><Field label="Unit"><input required name="unit" className={inputClass}/></Field><Field label="Selling price (₹)"><input required min="0" step="0.01" name="price" type="number" className={inputClass}/></Field><button disabled={busy} className={buttonClass}>Save variant</button></form>}</React.Fragment>)}
    </div>
  </div>;
}

function CategoriesPanel({categories,busy,run}:{categories:PlatformCatalogCategory[];busy:boolean;run:(fn:()=>Promise<unknown>)=>Promise<void>}) {
  const [open,setOpen]=useState(false);const [vertical,setVertical]=useState<'food'|'grocery'>('food');const [parentID,setParentID]=useState('');const [editing,setEditing]=useState<PlatformCatalogCategory|null>(null);
  async function submit(e:FormEvent<HTMLFormElement>){e.preventDefault();const form=e.currentTarget;const f=new FormData(form);await run(()=>createPlatformCategory({vertical,slug:String(f.get('slug')),name:String(f.get('name')),sort_order:Number(f.get('sort_order')||0),...(parentID?{parent_id:parentID}:{})}));form.reset();setOpen(false);setParentID('');}
  async function saveEdit(e:FormEvent<HTMLFormElement>,category:PlatformCatalogCategory){e.preventDefault();const form=e.currentTarget;const f=new FormData(form);await run(()=>updatePlatformCategory(category.id,{name:String(f.get('name')),sort_order:Number(f.get('sort_order')||0)}));setEditing(null);}
  return <div className="space-y-4"><div className="flex justify-end"><button className={buttonClass} onClick={()=>setOpen(x=>!x)}><Plus size={16}/> New category</button></div>
    {open&&<form onSubmit={submit} className="grid gap-3 rounded-2xl border border-blue-100 bg-blue-50/50 p-5 sm:grid-cols-5"><Field label="Vertical"><select name="vertical" value={vertical} onChange={e=>{setVertical(e.target.value as 'food'|'grocery');setParentID('')}} className={inputClass}><option value="food">Food</option><option value="grocery">Grocery</option></select></Field><Field label="Name"><input required name="name" className={inputClass}/></Field><Field label="Slug"><input required name="slug" className={inputClass}/></Field><Field label="Parent category"><select aria-label="Parent category" value={parentID} onChange={e=>setParentID(e.target.value)} className={inputClass}><option value="">Top-level category</option>{categories.filter(c=>c.vertical===vertical&&c.is_active).map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></Field><Field label="Sort order"><input name="sort_order" type="number" min="0" defaultValue="0" className={inputClass}/></Field><button disabled={busy} className={buttonClass}>Create category</button></form>}
    <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white">{categories.length===0?<Empty>No platform categories.</Empty>:categories.map(c=><div key={c.id} className="border-b border-slate-100 px-5 py-4 last:border-0">{editing?.id===c.id?<form onSubmit={e=>void saveEdit(e,c)} className="grid gap-3 sm:grid-cols-[1fr_160px_auto_auto]"><Field label="Category name"><input name="name" required defaultValue={c.name} className={inputClass}/></Field><Field label="Sort order"><input name="sort_order" type="number" min="0" defaultValue={c.sort_order} className={inputClass}/></Field><button disabled={busy} className={buttonClass}>Save</button><button type="button" onClick={()=>setEditing(null)} className="min-h-10 px-3 text-sm font-semibold text-slate-600">Cancel</button></form>:<div className="flex items-center justify-between gap-3"><div><p className="font-semibold text-slate-900">{c.name}<span className="ml-2 rounded-full bg-slate-100 px-2 py-1 text-[11px] font-semibold uppercase text-slate-600">{c.vertical}</span>{c.is_system&&<span className="ml-2 text-xs text-slate-400">System root</span>}</p><p className="text-xs text-slate-500">/{c.slug} · Sort {c.sort_order}</p></div><div className="flex items-center gap-2"><span className="text-xs text-slate-500">{c.is_active?'Active':'Inactive'}</span><button disabled={busy} onClick={()=>setEditing(c)} className="min-h-9 rounded-lg border border-slate-200 px-3 text-xs font-semibold text-slate-700">Edit</button>{!c.is_system&&<button disabled={busy} onClick={()=>void run(()=>updatePlatformCategory(c.id,{is_active:!c.is_active}))} className="min-h-9 rounded-lg border border-slate-200 px-3 text-xs font-semibold text-slate-700">{c.is_active?'Deactivate':'Activate'}</button>}</div></div>}</div>)}</div>
  </div>;
}

function PartnersPanel({products,mappings,businesses,busy,run}:{products:PlatformCatalogProduct[];mappings:PlatformPartnerMapping[];businesses:Business[];busy:boolean;run:(fn:()=>Promise<unknown>)=>Promise<void>}) {
  const [open,setOpen]=useState(false); const [productID,setProductID]=useState(''); const [editing,setEditing]=useState<PlatformPartnerMapping|null>(null);
  const variants=products.find(p=>p.id===productID)?.variants??[];
  async function submit(e:FormEvent<HTMLFormElement>) { e.preventDefault(); const form=e.currentTarget; const f=new FormData(form); const mode=String(f.get('mode')); const product=products.find(p=>p.id===String(f.get('product'))); const variant=product?.variants.find(v=>v.id===String(f.get('variant'))); if(!variant)return;
    const input=mode==='finite'?{business_id:f.get('business'),variant_id:variant.id,inventory_mode:mode,available_quantity:Number(f.get('quantity')),preparation_minutes:Number(f.get('preparation')||0),supply_price_minor:Math.round(Number(f.get('cost')||0)*100)}:mode==='capacity'?{business_id:f.get('business'),variant_id:variant.id,inventory_mode:mode,capacity_per_day:Number(f.get('capacity')),preparation_minutes:Number(f.get('preparation')||0),supply_price_minor:Math.round(Number(f.get('cost')||0)*100)}:{business_id:f.get('business'),variant_id:variant.id,inventory_mode:mode,preparation_minutes:Number(f.get('preparation')||0),supply_price_minor:Math.round(Number(f.get('cost')||0)*100)};
    await run(()=>createPlatformMapping(input)); form.reset();setProductID('');setOpen(false);
  }
  async function submitEdit(e:FormEvent<HTMLFormElement>,mapping:PlatformPartnerMapping) { e.preventDefault();const form=e.currentTarget;const f=new FormData(form);const mode=String(f.get('mode'));const input=mode==='finite'?{inventory_mode:mode,available_quantity:Number(f.get('quantity')),capacity_per_day:null,preparation_minutes:Number(f.get('preparation')||0),supply_price_minor:Math.round(Number(f.get('cost')||0)*100)}:mode==='capacity'?{inventory_mode:mode,available_quantity:null,capacity_per_day:Number(f.get('capacity')),preparation_minutes:Number(f.get('preparation')||0),supply_price_minor:Math.round(Number(f.get('cost')||0)*100)}:{inventory_mode:mode,available_quantity:null,capacity_per_day:null,preparation_minutes:Number(f.get('preparation')||0),supply_price_minor:Math.round(Number(f.get('cost')||0)*100)};await run(()=>updatePlatformMapping(mapping.id,input));setEditing(null); }
  return <div className="space-y-4">
    <div className="flex justify-end"><button className={buttonClass} onClick={()=>setOpen(x=>!x)}><Plus size={16}/> Map partner</button></div>
    {open&&<form onSubmit={submit} className="grid gap-3 rounded-2xl border border-blue-100 bg-blue-50/50 p-5 sm:grid-cols-3">
      <Field label="Verified partner"><select required name="business" className={inputClass}><option value="">Select business</option>{businesses.map(b=><option key={b.id} value={b.id}>{b.name} · {b.city}</option>)}</select></Field>
      <Field label="Platform product"><select required name="product" className={inputClass} value={productID} onChange={e=>setProductID(e.target.value)}><option value="">Select product</option>{products.filter(p=>p.status==='active').map(p=><option key={p.id} value={p.id}>{p.name} · {p.vertical}</option>)}</select></Field>
      <Field label="Variant"><select required name="variant" className={inputClass}><option value="">Select variant</option>{variants.filter(v=>v.is_active).map(v=><option key={v.id} value={v.id}>{v.name} · {money(v.price_minor)}</option>)}</select></Field>
      <Field label="Inventory mode"><select name="mode" className={inputClass}><option value="untracked">Untracked</option><option value="finite">Finite stock</option><option value="capacity">Daily capacity</option></select></Field>
      <Field label="Available quantity"><input name="quantity" min="0" type="number" className={inputClass}/></Field><Field label="Capacity/day"><input name="capacity" min="0" type="number" className={inputClass}/></Field>
      <Field label="Preparation minutes"><input name="preparation" min="0" max="1440" type="number" className={inputClass}/></Field><Field label="Private partner supply price (₹)"><input name="cost" min="0" step="0.01" type="number" className={inputClass}/></Field>
      <div className="flex items-end gap-2"><button disabled={busy} className={buttonClass}>Create pending mapping</button><button type="button" onClick={()=>setOpen(false)} className="min-h-10 rounded-xl px-3 text-sm font-semibold text-slate-600">Cancel</button></div>
    </form>}
    <CoverageManager businesses={businesses} run={run}/>
    <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white">{mappings.length===0?<Empty>No partner mappings match this search.</Empty>:mappings.map(m=><div key={m.id} className="border-b border-slate-100 px-5 py-4 last:border-0">
      <div className="flex flex-wrap items-center justify-between gap-3"><div><p className="font-semibold text-slate-900">{m.product_name} · {m.variant_name}</p><p className="mt-1 text-xs text-slate-500"><Building2 className="mr-1 inline" size={13}/>{m.business_name} · {m.business_city} · {m.vertical} · {m.inventory_mode}{m.available_quantity!=null?` (${m.available_quantity} available)`:m.capacity_per_day!=null?` (${m.capacity_per_day}/day)`:''}{m.supply_price_minor!=null?` · Partner cost ${money(m.supply_price_minor)}`:''}</p></div><div className="flex items-center gap-2"><span className="rounded-full bg-amber-50 px-2.5 py-1 text-xs font-semibold capitalize text-amber-800">{m.status}</span><button disabled={busy} onClick={()=>setEditing(editing?.id===m.id?null:m)} className="min-h-9 rounded-lg border border-slate-200 px-3 text-xs font-semibold text-slate-700">Stock &amp; cost</button>{m.status!=='approved'&&<button disabled={busy} onClick={()=>void run(()=>updatePlatformMapping(m.id,{status:'approved'}))} className="min-h-9 rounded-lg border border-emerald-200 px-3 text-xs font-semibold text-emerald-700">Approve</button>}{m.status==='approved'&&<button disabled={busy} onClick={()=>void run(()=>updatePlatformMapping(m.id,{status:'inactive'}))} className="min-h-9 rounded-lg border border-slate-200 px-3 text-xs font-semibold text-slate-600">Disable</button>}</div></div>
      {editing?.id===m.id&&<form onSubmit={e=>void submitEdit(e,m)} className="mt-4 grid gap-3 rounded-xl bg-slate-50 p-4 sm:grid-cols-3"><Field label="Inventory mode"><select name="mode" defaultValue={m.inventory_mode} className={inputClass}><option value="untracked">Untracked</option><option value="finite">Finite stock</option><option value="capacity">Daily capacity</option></select></Field><Field label="Available quantity"><input name="quantity" defaultValue={m.available_quantity} min="0" type="number" className={inputClass}/></Field><Field label="Capacity/day"><input name="capacity" defaultValue={m.capacity_per_day} min="0" type="number" className={inputClass}/></Field><Field label="Preparation minutes"><input name="preparation" defaultValue={m.preparation_minutes} min="0" max="1440" type="number" className={inputClass}/></Field><Field label="Partner supply price (₹)"><input name="cost" defaultValue={m.supply_price_minor!=null?(m.supply_price_minor/100).toFixed(2):''} min="0" step="0.01" type="number" className={inputClass}/></Field><div className="flex items-end gap-2"><button disabled={busy} className={buttonClass}>Save capability</button><button type="button" onClick={()=>setEditing(null)} className="min-h-10 rounded-xl px-3 text-sm font-semibold text-slate-600">Cancel</button></div></form>}
    </div>)}</div>
  </div>;
}

function CoverageManager({businesses,run}:{businesses:Business[];run:(fn:()=>Promise<unknown>)=>Promise<void>}) {
  const [businessID,setBusinessID]=useState(''); const [city,setCity]=useState('Cuttack'); const [coverage,setCoverage]=useState<Record<string,unknown>[]>([]); const [error,setError]=useState('');
  async function select(id:string){setBusinessID(id);setError('');if(!id){setCoverage([]);return;}try{setCoverage(await getPartnerCoverage(id));}catch{setError('Coverage could not be loaded.');}}
  async function refresh(){if(!businessID)return;try{setCoverage(await getPartnerCoverage(businessID));}catch{setError('Coverage could not be loaded.');}}
  return <div className="space-y-3 rounded-2xl border border-slate-200 bg-white p-4"><div><p className="text-sm font-semibold text-slate-900">Partner service coverage</p><p className="text-xs text-slate-500">Approval requires coverage that overlaps the product’s city availability.</p></div><div className="grid gap-2 sm:grid-cols-[1fr_180px_auto]">
    <select aria-label="Coverage partner" value={businessID} onChange={e=>void select(e.target.value)} className={inputClass}><option value="">Choose verified partner</option>{businesses.map(b=><option key={b.id} value={b.id}>{b.name} · {b.city}</option>)}</select><select aria-label="Coverage city" value={city} onChange={e=>setCity(e.target.value)} className={inputClass}><option>Cuttack</option><option>Jajpur</option></select><button type="button" disabled={!businessID} onClick={()=>void run(async()=>{await addPartnerCoverage(businessID,{city});await refresh();})} className="min-h-10 rounded-xl border border-blue-200 bg-white px-3 text-sm font-semibold text-blue-700">Add coverage</button>
  </div>{error&&<p role="alert" className="text-xs text-rose-700">{error}</p>}<div className="flex flex-wrap gap-2">{coverage.map(item=><span key={String(item.id)} className="inline-flex items-center gap-2 rounded-lg bg-slate-100 px-3 py-2 text-xs text-slate-700">{String(item.city)}{item.locality?` · ${String(item.locality)}`:''}{Boolean(item.is_active)?'':' · inactive'}{Boolean(item.is_active)&&<button type="button" aria-label="Deactivate coverage" onClick={()=>void run(async()=>{await deletePartnerCoverage(businessID,String(item.id));await refresh();})} className="font-bold text-rose-700">×</button>}</span>)}</div></div>;
}
function Field({label,children}:{label:string;children:React.ReactNode}) { return <label className="block space-y-1.5 text-xs font-semibold text-slate-600">{label}{children}</label>; }
function Empty({children}:{children:React.ReactNode}) { return <div className="px-5 py-12 text-center text-sm text-slate-500">{children}</div>; }
