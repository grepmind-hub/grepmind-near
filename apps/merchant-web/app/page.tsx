'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertCircle, BellRing, CheckCircle2, Loader2, X } from 'lucide-react';
import { Header } from '../components/Header';
import { Sidebar } from '../components/Sidebar';
import { OverviewCards } from '../components/OverviewCards';
import { RequestsManager } from '../components/RequestsManager';
import { CatalogManager } from '../components/CatalogManager';
import { HoursCoverageManager } from '../components/HoursCoverageManager';
import { TeamManager } from '../components/TeamManager';
import { AuthLoginView } from '../components/AuthLoginView';
import { NewStoreOnboardingModal } from '../components/NewStoreOnboardingModal';
import { OffersManager } from '../components/OffersManager';
import type { Business, MerchantOffer, MerchantSession, OperatingHoursDay, ProductItem, ServiceItem, ServiceRequest, TeamMember } from '../lib/types';
import {
  createMerchantOffer, createMerchantProduct, createMerchantService,
  createMerchantTeamMember, deleteMerchantOffer, deleteMerchantProduct, deleteMerchantService,
  fetchMerchantBusinesses, fetchMerchantSnapshot, fetchNotifications, logoutMerchant, markNotificationAsRead,
  MerchantApiError, playBookingChime, RealtimeNotification, revokeMerchantTeamMember,
  saveMerchantCoverage, saveOperatingHours, setMerchantProductStock, subscribeToEvents,
  updateMerchantProduct, updateMerchantService,
  updateServiceRequestStatus,
} from '../lib/api';

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
function mapHours(rows: any[] | undefined): OperatingHoursDay[] {
  if (!rows?.length) return weekdayNames.map(day => ({ day, isOpen: false, openTime: '', closeTime: '' }));
  const byDay = new Map<number, any>(rows.map(row => [Number(row.weekday), row]));
  return weekdayNames.map((day, weekday) => {
    const row = byDay.get(weekday);
    return { day, isOpen: row ? !row.is_closed : false, openTime: String(row?.opens_at || '').slice(0, 5), closeTime: String(row?.closes_at || '').slice(0, 5) };
  });
}

export default function MerchantWorkspacePage() {
  const [businesses, setBusinesses] = useState<Business[]>([]);
  const [currentBusiness, setCurrentBusiness] = useState<Business | null>(null);
  const [activeTab, setActiveTab] = useState('overview');
  const [session, setSession] = useState<MerchantSession | null>(null);
  const [isInitializing, setIsInitializing] = useState(true);
  const [isLoadingData, setIsLoadingData] = useState(false);
  const [showNewStoreModal, setShowNewStoreModal] = useState(false);
  const [requests, setRequests] = useState<ServiceRequest[]>([]);
  const [products, setProducts] = useState<ProductItem[]>([]);
  const [services, setServices] = useState<ServiceItem[]>([]);
  const [hours, setHours] = useState<OperatingHoursDay[]>([]);
  const [team, setTeam] = useState<TeamMember[]>([]);
  const [offers, setOffers] = useState<MerchantOffer[]>([]);
  const [notifications, setNotifications] = useState<RealtimeNotification[]>([]);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [incomingAlert, setIncomingAlert] = useState<{ id: string; customerName: string; serviceName: string } | null>(null);
  const [toastMessage, setToastMessage] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  const showToast = useCallback((message: string) => {
    setToastMessage(message);
    window.setTimeout(() => setToastMessage(null), 3500);
  }, []);

  const applySnapshot = useCallback((snapshot: Awaited<ReturnType<typeof fetchMerchantSnapshot>>, user: MerchantSession) => {
    const { profile, coverage } = snapshot;
    const mappedBusiness: Business = {
      id: profile.id,
      ownerPhone: user.phone,
      name: profile.name,
      category: profile.category_name || profile.category_slug || 'Business',
      categorySlug: profile.category_slug || '',
      locality: profile.locality || '',
      city: profile.city || '',
      phone: profile.phone_e164 || user.phone,
      isOpen: profile.status === 'approved' && Boolean(coverage.accepts_requests),
      acceptsRequests: profile.status === 'approved' && Boolean(coverage.accepts_requests),
      isVerified: profile.status === 'approved' || profile.verification_status === 'verified',
      status: profile.status,
      verificationStatus: profile.verification_status,
      address: profile.address_text || '',
      serviceRadiusKm: Math.round(Number(coverage.service_radius_m || 5000) / 1000),
      coverPhotoUrl: profile.cover_photo_url || undefined,
    };
    const mappedRequests: ServiceRequest[] = (snapshot.requests || []).map((r: any) => ({
      id: r.id, businessId: profile.id, customerName: r.customer_name || 'Customer', customerPhone: r.customer_phone || '',
      serviceName: typeof r.service_name === 'string' ? r.service_name : 'Service request',
      description: r.description || '', requestedFor: r.requested_for || '', address: '',
      status: r.status, createdAt: r.created_at,
    }));
    const mappedProducts: ProductItem[] = (snapshot.products || []).map((p: any) => ({
      id: p.id, businessId: p.business_id, name: p.name, description: p.description || '', price: Number(p.price || 0),
      stockStatus: p.stock_status || 'unknown', isPublished: Boolean(p.is_published), imageUrl: p.image_url || undefined,
    }));
    const mappedServices: ServiceItem[] = (snapshot.services || []).map((s: any) => ({
      id: s.id, businessId: s.business_id, name: s.name, description: s.description || '', basePrice: Number(s.indicative_price_min || 0),
      maximumPrice: s.indicative_price_max == null ? undefined : Number(s.indicative_price_max), isActive: Boolean(s.is_active),
    }));
    const mappedTeam: TeamMember[] = (snapshot.members || []).map((m: any) => ({
      id: m.id, businessId: m.business_id, userId: m.user_id, name: m.display_name || 'Team member', phone: m.phone_e164,
      role: m.role, status: m.status, createdAt: m.created_at,
    }));
    const ownMembership = mappedTeam.find(m => m.userId === user.userId);
    const nextSession = ownMembership ? { ...user, role: ownMembership.role } : user;
    setSession(nextSession);
    localStorage.setItem('grepmind_merchant_session', JSON.stringify(nextSession));
    setCurrentBusiness(mappedBusiness);
    setBusinesses(previous => [mappedBusiness, ...previous.filter(item => item.id !== mappedBusiness.id)]);
    setRequests(mappedRequests);
    setProducts(mappedProducts);
    setServices(mappedServices);
    setHours(mapHours(snapshot.hours));
    setTeam(mappedTeam);
    setOffers(snapshot.offers || []);
    setLastUpdated(new Date());
  }, []);

  const loadWorkspace = useCallback(async (user: MerchantSession, businessId?: string) => {
    setIsLoadingData(true); setLoadError(null);
    try {
      const directory = await fetchMerchantBusinesses();
      const directoryBusinesses: Business[] = directory.map(profile => ({
        id: profile.id, name: profile.name, ownerPhone: user.phone,
        category: profile.category_name || profile.category_slug || 'Business', categorySlug: profile.category_slug || '',
        locality: profile.locality || '', city: profile.city || '', phone: profile.phone_e164 || user.phone,
        isOpen: profile.status === 'approved' && Boolean(profile.accepts_requests), acceptsRequests: profile.status === 'approved' && Boolean(profile.accepts_requests),
        isVerified: profile.status === 'approved' || profile.verification_status === 'verified', address: profile.address_text || '',
        status: profile.status, verificationStatus: profile.verification_status,
        serviceRadiusKm: Math.round(Number(profile.service_radius_m || 5000) / 1000), coverPhotoUrl: profile.cover_photo_url || undefined,
      }));
      setBusinesses(directoryBusinesses);
      if (!directoryBusinesses.length) {
        if (businessId) throw new MerchantApiError('This account no longer has access to that business.', 403);
        setCurrentBusiness(null); setShowNewStoreModal(true); return;
      }
      const target = directory.find(item => item.id === businessId) || directory[0];
      const snapshot = await fetchMerchantSnapshot(target.id);
      applySnapshot(snapshot, user);
      setShowNewStoreModal(false);
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : 'Unable to load merchant data.');
    } finally { setIsLoadingData(false); }
  }, [applySnapshot]);

  useEffect(() => {
    const saved = localStorage.getItem('grepmind_merchant_session');
    if (saved && localStorage.getItem('grepmind_merchant_token')) {
      try { const parsed = JSON.parse(saved) as MerchantSession; setSession(parsed); void loadWorkspace(parsed); }
      catch { localStorage.removeItem('grepmind_merchant_session'); }
    }
    const expire = () => { setSession(null); setCurrentBusiness(null); setShowNewStoreModal(false); showToast('Your secure session expired. Sign in again.'); };
    window.addEventListener('merchant-session-expired', expire);
    setIsInitializing(false);
    return () => window.removeEventListener('merchant-session-expired', expire);
  }, [loadWorkspace, showToast]);

  const refreshSnapshot = useCallback(async () => {
    if (!session || !currentBusiness) return undefined;
    try {
      const snapshot = await fetchMerchantSnapshot(currentBusiness.id);
      applySnapshot(snapshot, session);
      const latestNotifications = await fetchNotifications(currentBusiness.id);
      setNotifications(latestNotifications);
      return snapshot;
    } catch (error) { setLoadError(error instanceof Error ? error.message : 'Unable to refresh merchant data.'); return undefined; }
  }, [session, currentBusiness, applySnapshot]);

  const refreshNotifications = useCallback(async () => {
    if (!currentBusiness) return;
    try { setNotifications(await fetchNotifications(currentBusiness.id)); }
    catch (error) { setLoadError(error instanceof Error ? error.message : 'Unable to refresh notifications.'); }
  }, [currentBusiness]);

  useEffect(() => {
    if (!session || !currentBusiness) return;
    const unsubscribe = subscribeToEvents(currentBusiness.id, event => {
      if (event.type === 'service_request.created') playBookingChime();
      void refreshSnapshot().then(snapshot => {
        const requestId = event.payload?.request_id;
        if (requestId && event.type === 'service_request.created') {
          const req = snapshot?.requests?.find((item: any) => item.id === requestId);
          if (req) setIncomingAlert({ id: req.id, customerName: req.customer_name || 'Customer', serviceName: req.service_name || 'Service request' });
        }
      });
      void refreshNotifications();
    });
    void refreshNotifications();
    const interval = window.setInterval(() => { void refreshSnapshot(); void refreshNotifications(); }, 30000);
    return () => { unsubscribe(); window.clearInterval(interval); };
  }, [session, currentBusiness, refreshSnapshot, refreshNotifications]);

  const runAction = async (action: () => Promise<unknown>, success: string) => {
    setLoadError(null);
    try { await action(); await refreshSnapshot(); showToast(success); }
    catch (error) { setLoadError(error instanceof Error ? error.message : 'The change could not be saved.'); }
  };

  const handleLogin = (newSession: MerchantSession) => {
    localStorage.setItem('grepmind_merchant_session', JSON.stringify(newSession));
    setSession(newSession);
    void loadWorkspace(newSession);
  };

  const handleLogout = async () => {
    try { await logoutMerchant(); } catch { /* local credentials are cleared by the API helper */ }
    localStorage.removeItem('grepmind_merchant_session');
    setSession(null); setCurrentBusiness(null); setRequests([]); setProducts([]); setServices([]); setHours([]); setTeam([]); setOffers([]); setNotifications([]); setActiveTab('overview');
    showToast('Signed out securely.');
  };

  const handleStoreCreated = async () => {
    setShowNewStoreModal(false);
    if (session) await loadWorkspace(session);
  };

  const currentRequests = useMemo(() => currentBusiness ? requests.filter(r => r.businessId === currentBusiness.id) : [], [requests, currentBusiness]);
  const currentProducts = useMemo(() => currentBusiness ? products.filter(p => p.businessId === currentBusiness.id) : [], [products, currentBusiness]);
  const currentServices = useMemo(() => currentBusiness ? services.filter(s => s.businessId === currentBusiness.id) : [], [services, currentBusiness]);
  const currentTeam = useMemo(() => currentBusiness ? team.filter(m => m.businessId === currentBusiness.id) : [], [team, currentBusiness]);
  const pendingRequestsCount = currentRequests.filter(r => r.status === 'requested').length;

  if (isInitializing) return <div className="grid min-h-screen place-items-center bg-background"><Loader2 className="animate-spin text-primary"/></div>;
  if (!session) return <AuthLoginView onLoginSuccess={handleLogin}/>;
  if (showNewStoreModal) return <NewStoreOnboardingModal userPhone={session.phone} onStoreCreated={handleStoreCreated} onCancel={handleLogout}/>;
  if (!currentBusiness) return <main className="grid min-h-screen place-items-center bg-background p-6"><div className="max-w-md rounded-2xl border border-borderMuted bg-surface p-8 text-center shadow-card">{isLoadingData ? <Loader2 className="mx-auto animate-spin text-primary"/> : <AlertCircle className="mx-auto text-amber-600"/>}<h1 className="mt-4 text-xl font-bold text-slateText-main">{isLoadingData ? 'Loading your workspace' : 'Merchant workspace unavailable'}</h1><p className="mt-2 text-sm text-slateText-secondary">{loadError || 'We could not load a business linked to this account.'}</p>{loadError && <button onClick={() => void loadWorkspace(session)} className="mt-4 rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-white">Retry</button>}<button onClick={handleLogout} className="mt-4 block w-full text-sm font-semibold text-primary">Sign out</button></div></main>;

  return <div className="flex min-h-screen flex-col bg-[#F3F6FC] text-slateText-main">
    <Header businesses={businesses} currentBusiness={currentBusiness} session={session} notifications={notifications} onSelectBusiness={business => void loadWorkspace(session, business.id)} onToggleStoreStatus={() => void runAction(() => saveMerchantCoverage(currentBusiness.id, currentBusiness.serviceRadiusKm * 1000, !currentBusiness.acceptsRequests), 'Request availability updated.')} onLogout={handleLogout} onSelectNotification={n => { void runAction(() => markNotificationAsRead(n.id), 'Notification marked as read.'); setActiveTab('requests'); }}/>
    <div className="flex flex-1 overflow-hidden">
      <Sidebar activeTab={activeTab} onTabChange={setActiveTab} pendingRequestsCount={pendingRequestsCount} verificationStatus={currentBusiness.verificationStatus || currentBusiness.status || 'unknown'}/>
      <main className="min-w-0 flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8">
        <div className="mx-auto max-w-[1500px] space-y-6">
          <header className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-xs font-semibold uppercase tracking-[.16em] text-primary">Merchant operations</p><h1 className="mt-1 text-2xl font-bold tracking-tight text-slateText-main">{({ overview: 'Workspace overview', requests: 'Customer requests', catalog: 'Catalog & inventory', hours: 'Hours & coverage', team: 'Team & access', offers: 'Offers & promotions', analytics: 'Store activity' } as Record<string, string>)[activeTab]}</h1><p className="mt-1 text-sm text-slateText-secondary">{currentBusiness.name} · {currentBusiness.locality}, {currentBusiness.city}</p></div><div className="flex items-center gap-2"><span className={`rounded-full border px-3 py-1.5 text-xs font-semibold ${currentBusiness.isVerified ? 'border-emerald-200 bg-emerald-50 text-emerald-700' : 'border-amber-200 bg-amber-50 text-amber-800'}`}>{currentBusiness.isVerified ? 'Approved listing' : 'Verification pending'}</span><button onClick={() => void refreshSnapshot()} aria-label="Refresh workspace data" className="grid h-10 w-10 place-items-center rounded-xl border border-borderMuted bg-white text-primary hover:bg-blue-50"><RefreshGlyph/></button></div></header>
          {loadError && <div role="alert" className="flex items-start gap-3 rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800"><AlertCircle className="mt-0.5 h-4 w-4 shrink-0"/><div className="flex-1">{loadError}</div><button aria-label="Dismiss error" onClick={() => setLoadError(null)}><X size={16}/></button></div>}
          {isLoadingData && <div className="flex items-center gap-2 rounded-xl border border-blue-100 bg-blue-50 p-3 text-sm text-blue-800"><Loader2 size={16} className="animate-spin"/>Syncing live merchant data…</div>}
          {activeTab === 'overview' && <OverviewCards business={currentBusiness} requests={currentRequests} productCount={currentProducts.length} serviceCount={currentServices.length} hours={hours} updatedAt={lastUpdated} onNavigateTab={setActiveTab}/>}
          {activeTab === 'requests' && <RequestsManager requests={currentRequests} onUpdateStatus={(id, status) => void runAction(() => updateServiceRequestStatus(currentBusiness.id, id, status), `Request updated to ${status.replace('_', ' ')}.`)}/>}
          {activeTab === 'catalog' && <CatalogManager
            products={currentProducts}
            services={currentServices}
            onAddProduct={input => void runAction(() => createMerchantProduct(currentBusiness.id, input), 'Product saved to your catalog.')}
            onUpdateProduct={(product, input) => void runAction(() => updateMerchantProduct(currentBusiness.id, product.id, input), 'Product changes saved.')}
            onAddService={input => void runAction(() => createMerchantService(currentBusiness.id, input), 'Service saved to your catalog.')}
            onUpdateService={(service, input) => void runAction(() => updateMerchantService(currentBusiness.id, service.id, input), 'Service changes saved.')}
            onToggleService={service => void runAction(() => updateMerchantService(currentBusiness.id, service.id, { name: service.name, description: service.description, indicative_price_min: service.basePrice, is_active: !service.isActive }), service.isActive ? 'Service paused.' : 'Service activated.')}
            onToggleProductStock={product => void runAction(() => setMerchantProductStock(currentBusiness.id, product.id, product.stockStatus === 'in_stock' ? 'out_of_stock' : 'in_stock'), 'Product availability updated.')}
            onDeleteProduct={product => { if (window.confirm(`Delete ${product.name}?`)) void runAction(() => deleteMerchantProduct(currentBusiness.id, product.id), 'Product deleted.'); }}
            onDeleteService={service => { if (window.confirm(`Delete ${service.name}?`)) void runAction(() => deleteMerchantService(currentBusiness.id, service.id), 'Service deleted.'); }}
          />}
          {activeTab === 'hours' && <HoursCoverageManager business={currentBusiness} hours={hours} onSaveHours={async updated => { const rows = updated.map((day, weekday) => ({ weekday, is_closed: !day.isOpen, opens_at: day.isOpen ? `${day.openTime}:00` : null, closes_at: day.isOpen ? `${day.closeTime}:00` : null })); await saveOperatingHours(currentBusiness.id, rows); await refreshSnapshot(); showToast('Operating hours saved.'); }} onSaveRadius={async radius => { await saveMerchantCoverage(currentBusiness.id, radius * 1000, currentBusiness.acceptsRequests); await refreshSnapshot(); }}/ >}
          {activeTab === 'team' && <TeamManager business={currentBusiness} team={currentTeam} canManageTeam={session.role === 'owner'} onAddMember={input => void runAction(() => createMerchantTeamMember(currentBusiness.id, { display_name: input.displayName, phone_e164: input.phoneE164, role: input.role }), 'Team member added.')} onRevokeMember={member => { if (window.confirm(`Revoke access for ${member.name}?`)) void runAction(() => revokeMerchantTeamMember(currentBusiness.id, member.userId), 'Team member access revoked.'); }}/ >}
          {activeTab === 'offers' && <OffersManager offers={offers} onCreate={input => void runAction(() => createMerchantOffer(currentBusiness.id, input), 'Offer submitted for review.')} onDelete={offer => { if (window.confirm(`Delete offer ${offer.title}?`)) void runAction(() => deleteMerchantOffer(offer.id), 'Offer deleted.'); }}/ >}
          {activeTab === 'analytics' && <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{[
            ['Requests received', currentRequests.length], ['Pending', pendingRequestsCount], ['Completed', currentRequests.filter(r => r.status === 'completed').length], ['Active offers', offers.filter(o => o.status === 'approved').length],
          ].map(([label, value]) => <article key={label} className="rounded-2xl border border-borderMuted bg-surface p-5 shadow-card"><p className="text-sm text-slateText-secondary">{label}</p><p className="mt-2 text-3xl font-bold text-slateText-main">{value}</p><p className="mt-3 text-xs text-slateText-muted">Counted from current business records.</p></article>)}</section>}
        </div>
      </main>
    </div>
    {incomingAlert && <div className="fixed right-5 top-20 z-50 w-[min(24rem,calc(100vw-2rem))] rounded-2xl border border-blue-200 bg-white p-4 shadow-2xl"><div className="flex gap-3"><span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-primary text-white"><BellRing size={18}/></span><div className="min-w-0 flex-1"><div className="flex justify-between"><strong className="text-sm text-primary">New customer request</strong><button onClick={() => setIncomingAlert(null)} aria-label="Dismiss alert"><X size={16}/></button></div><p className="mt-2 truncate text-sm font-semibold">{incomingAlert.serviceName}</p><p className="mt-1 text-xs text-slateText-secondary">{incomingAlert.customerName}</p><button onClick={() => { setActiveTab('requests'); setIncomingAlert(null); }} className="mt-3 min-h-10 rounded-lg bg-primary px-3 text-xs font-semibold text-white">Open requests</button></div></div></div>}
    {toastMessage && <div role="status" className="fixed bottom-5 right-5 z-50 flex items-center gap-2 rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white shadow-xl"><CheckCircle2 size={17} className="text-emerald-400"/>{toastMessage}</div>}
  </div>;
}

function RefreshGlyph() { return <svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M20 7v5h-5M4 17v-5h5"/><path d="M5.6 9A7 7 0 0 1 18 6l2 2M4 16l2 2a7 7 0 0 0 12.4-3"/></svg>; }
