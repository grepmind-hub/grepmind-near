'use strict';
'use client';

import React, { useState, useEffect } from 'react';
import { Header } from '../components/Header';
import { Sidebar } from '../components/Sidebar';
import { OverviewCards } from '../components/OverviewCards';
import { RequestsManager } from '../components/RequestsManager';
import { CatalogManager } from '../components/CatalogManager';
import { HoursCoverageManager } from '../components/HoursCoverageManager';
import { TeamManager } from '../components/TeamManager';
import { AuthLoginView } from '../components/AuthLoginView';
import { NewStoreOnboardingModal } from '../components/NewStoreOnboardingModal';
import {
  INITIAL_BUSINESSES,
  INITIAL_REQUESTS,
  INITIAL_PRODUCTS,
  INITIAL_SERVICES,
  INITIAL_HOURS,
  INITIAL_TEAM,
} from '../lib/mockData';
import { 
  Business, 
  ServiceRequest, 
  ProductItem, 
  ServiceItem, 
  OperatingHoursDay, 
  TeamMember,
  MerchantSession 
} from '../lib/types';
import {
  subscribeToEvents,
  playBookingChime,
  updateServiceRequestStatus,
  fetchNotifications,
  markNotificationAsRead,
  RealtimeNotification,
} from '../lib/api';
import { CheckCircle2, AlertCircle, ShieldAlert, Store, BellRing, Sparkles, X } from 'lucide-react';

export default function MerchantWorkspacePage() {
  const [businesses, setBusinesses] = useState<Business[]>(INITIAL_BUSINESSES);
  const [currentBusiness, setCurrentBusiness] = useState<Business>(INITIAL_BUSINESSES[0]);
  const [activeTab, setActiveTab] = useState<string>('overview');

  const [session, setSession] = useState<MerchantSession | null>(null);
  const [isInitializing, setIsInitializing] = useState(true);
  const [showNewStoreModal, setShowNewStoreModal] = useState(false);

  const [requests, setRequests] = useState<ServiceRequest[]>(INITIAL_REQUESTS);
  const [products, setProducts] = useState<ProductItem[]>(INITIAL_PRODUCTS);
  const [services, setServices] = useState<ServiceItem[]>(INITIAL_SERVICES);
  const [hours, setHours] = useState<OperatingHoursDay[]>(INITIAL_HOURS);
  const [team, setTeam] = useState<TeamMember[]>(INITIAL_TEAM);
  const [notifications, setNotifications] = useState<RealtimeNotification[]>([]);
  const [incomingAlert, setIncomingAlert] = useState<{
    id: string;
    title: string;
    body: string;
    customerName: string;
    serviceName: string;
    time: string;
  } | null>(null);

  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 3500);
  };

  // 1. Session Persistence & Initialization
  useEffect(() => {
    const saved = localStorage.getItem('grepmind_merchant_session');
    if (saved) {
      try {
        const parsed: MerchantSession = JSON.parse(saved);
        applySession(parsed);
      } catch (e) {
        localStorage.removeItem('grepmind_merchant_session');
      }
    }
    setIsInitializing(false);
  }, []);

  // 2. Strict Tenant / Merchant Isolation Logic
  const applySession = (sess: MerchantSession) => {
    setSession(sess);
    const cleanPhone = sess.phone.replace(/\s+/g, '');

    // Resolve accessible businesses:
    // A user can ONLY access businesses where they are owner (b.ownerPhone)
    // or active member in team (m.businessId)
    const teamBizIds = team
      .filter((m) => m.phone.replace(/\s+/g, '') === cleanPhone && m.status === 'active')
      .map((m) => m.businessId);

    const ownedBizIds = businesses
      .filter((b) => b.ownerPhone?.replace(/\s+/g, '') === cleanPhone)
      .map((b) => b.id);

    const allowedIds = Array.from(new Set([...teamBizIds, ...ownedBizIds]));
    const matched = businesses.filter((b) => allowedIds.includes(b.id));

    if (matched.length > 0) {
      setCurrentBusiness(matched[0]);
    } else {
      setShowNewStoreModal(true);
    }
  };

  const handleLogout = () => {
    localStorage.removeItem('grepmind_merchant_session');
    setSession(null);
    setActiveTab('overview');
    showToast('Signed out of Merchant Workspace.');
  };

  // Accessible businesses strictly for the current authenticated merchant
  const cleanUserPhone = session?.phone.replace(/\s+/g, '') || '';
  const accessibleBusinesses = businesses.filter((b) => {
    const isOwner = b.ownerPhone?.replace(/\s+/g, '') === cleanUserPhone;
    const isMember = team.some(
      (m) =>
        m.businessId === b.id &&
        m.phone.replace(/\s+/g, '') === cleanUserPhone &&
        m.status === 'active'
    );
    return isOwner || isMember;
  });

  // Switch active business (only among accessible businesses)
  const handleSelectBusiness = (biz: Business) => {
    if (accessibleBusinesses.some((b) => b.id === biz.id)) {
      setCurrentBusiness(biz);
      showToast(`Switched workspace to ${biz.name} (${biz.city})`);
    } else {
      showToast('Access denied: You do not have permissions for this store.');
    }
  };

  // Toggle store open/closed
  const handleToggleStoreStatus = () => {
    const updated = { ...currentBusiness, isOpen: !currentBusiness.isOpen };
    setCurrentBusiness(updated);
    setBusinesses(businesses.map((b) => (b.id === updated.id ? updated : b)));
    showToast(
      updated.isOpen
        ? `${updated.name} is now OPEN and accepting customer requests`
        : `${updated.name} is now PAUSED (Closed for orders)`
    );
  };

  // Real-Time SSE Event Stream Subscription (Option 5)
  useEffect(() => {
    if (!currentBusiness?.id) return;

    // Load initial persistent notifications
    fetchNotifications(currentBusiness.id)
      .then((items) => {
        if (items && items.length > 0) setNotifications(items);
      })
      .catch(() => {});

    // Connect to SSE stream
    const unsubscribe = subscribeToEvents(currentBusiness.id, (ev) => {
      if (ev.type === 'service_request.created') {
        playBookingChime();
        const p = ev.payload || {};
        const customerName = p.customer_name || 'Customer';
        const serviceName = p.service_name || p.description || 'Service Booking';

        const newReq: ServiceRequest = {
          id: p.request_id || `req-${Date.now()}`,
          businessId: currentBusiness.id,
          customerName: customerName,
          customerPhone: p.customer_phone || '+91 99*** **123',
          serviceName: serviceName,
          description: p.description || 'Customer on-demand service booking request.',
          requestedFor: p.requested_for || 'Today, Immediate Dispatch',
          address: 'Customer Address, ' + currentBusiness.locality,
          status: 'requested',
          priceEstimate: p.amount ? parseInt(String(p.amount).replace(/[^0-9]/g, '')) : 650,
          createdAt: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
        };

        setRequests((prev) => [newReq, ...prev.filter((r) => r.id !== newReq.id)]);
        setIncomingAlert({
          id: newReq.id,
          title: `🔔 New Service Booking!`,
          body: `${customerName} booked "${serviceName}"`,
          customerName,
          serviceName,
          time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
        });
        showToast(`🔔 New Service Booking received from ${customerName}!`);

        // Refresh persistent notifications
        fetchNotifications(currentBusiness.id)
          .then((items) => setNotifications(items))
          .catch(() => {});
      } else if (ev.type === 'service_request.status_updated') {
        const p = ev.payload || {};
        if (p.request_id && p.status) {
          setRequests((prev) =>
            prev.map((r) => (r.id === p.request_id ? { ...r, status: p.status } : r))
          );
        }
      }
    });

    return () => {
      unsubscribe();
    };
  }, [currentBusiness?.id]);

  // Service Request Status Transitions
  const handleUpdateStatus = (requestId: string, newStatus: ServiceRequest['status']) => {
    setRequests(
      requests.map((r) => {
        if (r.id === requestId) {
          return { ...r, status: newStatus };
        }
        return r;
      })
    );
    showToast(`Service booking updated to: ${newStatus.toUpperCase()}`);
    // Sync with backend API to broadcast status change across subscribers
    updateServiceRequestStatus(currentBusiness.id, requestId, newStatus).catch(() => {});
  };

  // Add Product
  const handleAddProduct = (newProd: Omit<ProductItem, 'id'>) => {
    const product: ProductItem = {
      ...newProd,
      businessId: currentBusiness.id,
      id: `prod-${Date.now()}`,
    };
    setProducts([product, ...products]);
    showToast(`Published "${product.name}" to store catalog!`);
  };

  // Add Service
  const handleAddService = (newServ: Omit<ServiceItem, 'id'>) => {
    const service: ServiceItem = {
      ...newServ,
      businessId: currentBusiness.id,
      id: `serv-${Date.now()}`,
    };
    setServices([service, ...services]);
    showToast(`Published service "${service.name}"!`);
  };

  // Toggle Stock Status
  const handleToggleProductStock = (productId: string) => {
    setProducts(
      products.map((p) => {
        if (p.id === productId) {
          const updatedStock = !p.inStock;
          showToast(`Marked "${p.name}" as ${updatedStock ? 'IN STOCK' : 'OUT OF STOCK'}`);
          return { ...p, inStock: updatedStock };
        }
        return p;
      })
    );
  };

  // Save Operating Hours
  const handleSaveHours = (newHours: OperatingHoursDay[]) => {
    setHours(newHours);
    showToast('Operating schedule updated successfully');
  };

  // Save Service Radius
  const handleSaveRadius = (newRadius: number) => {
    const updated = { ...currentBusiness, serviceRadiusKm: newRadius };
    setCurrentBusiness(updated);
    setBusinesses(businesses.map((b) => (b.id === updated.id ? updated : b)));
  };

  // Add Team Member
  const handleAddMember = (newMem: Omit<TeamMember, 'id' | 'businessId' | 'createdAt'>) => {
    const member: TeamMember = {
      ...newMem,
      id: `mem-${Date.now()}`,
      businessId: currentBusiness.id,
      createdAt: 'Today',
    };
    setTeam([...team, member]);
    showToast(`Added ${member.name} as ${member.role.toUpperCase()} for ${currentBusiness.name}`);
  };

  // Revoke Team Member
  const handleRevokeMember = (memberId: string) => {
    const target = team.find((m) => m.id === memberId);
    setTeam(team.filter((m) => m.id !== memberId));
    showToast(
      target ? `Revoked access for ${target.name}` : 'Revoked team member access'
    );
  };

  // Handle New Store Onboarding Submission
  const handleStoreCreated = (newBiz: Business) => {
    const updatedBizList = [newBiz, ...businesses];
    setBusinesses(updatedBizList);
    setCurrentBusiness(newBiz);
    setShowNewStoreModal(false);

    if (session) {
      const ownerMember: TeamMember = {
        id: `mem-${Date.now()}`,
        businessId: newBiz.id,
        userId: session.userId,
        name: session.name,
        phone: session.phone,
        role: 'owner',
        status: 'active',
        createdAt: 'Today',
      };
      setTeam([...team, ownerMember]);
    }

    showToast(`Storefront "${newBiz.name}" created and verified in ${newBiz.city}!`);
  };

  // 3. Render Authentication Gate if unauthenticated
  if (isInitializing) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
      </div>
    );
  }

  if (!session) {
    return (
      <AuthLoginView
        onLoginSuccess={(newSession, isNewUser) => {
          localStorage.setItem('grepmind_merchant_session', JSON.stringify(newSession));
          applySession(newSession);
          if (isNewUser) {
            setShowNewStoreModal(true);
          } else {
            showToast(`Signed in as ${newSession.name} (${newSession.role.toUpperCase()})`);
          }
        }}
      />
    );
  }

  // Filter scoped data strictly for current business
  const currentRequests = requests.filter((r) => r.businessId === currentBusiness.id);
  const currentProducts = products.filter((p) => p.businessId === currentBusiness.id);
  const currentServices = services.filter((s) => s.businessId === currentBusiness.id);
  const currentTeam = team.filter((m) => m.businessId === currentBusiness.id);

  const pendingRequestsCount = currentRequests.filter((r) => r.status === 'requested').length;

  return (
    <div className="min-h-screen bg-background flex flex-col">
      {/* Top Header */}
      <Header
        businesses={accessibleBusinesses}
        currentBusiness={currentBusiness}
        session={session}
        notifications={notifications}
        onSelectBusiness={handleSelectBusiness}
        onToggleStoreStatus={handleToggleStoreStatus}
        onLogout={handleLogout}
        onSelectNotification={(n) => {
          markNotificationAsRead(n.id).catch(() => {});
          setNotifications((prev) =>
            prev.map((item) => (item.id === n.id ? { ...item, is_read: true } : item))
          );
          setActiveTab('requests');
        }}
      />

      <div className="flex flex-1 overflow-hidden">
        {/* Left Navigation Sidebar */}
        <Sidebar
          activeTab={activeTab}
          onTabChange={setActiveTab}
          pendingRequestsCount={pendingRequestsCount}
        />

        {/* Main Content Area */}
        <main className="flex-1 overflow-y-auto p-8 custom-scrollbar">
          <div className="mx-auto max-w-7xl space-y-6">
            {/* Page Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div>
                <h1 className="text-2xl font-black tracking-tight text-slateText-main">
                  {activeTab === 'overview' && 'Merchant Overview'}
                  {activeTab === 'requests' && 'Customer Service Bookings'}
                  {activeTab === 'catalog' && 'Catalog & Inventory'}
                  {activeTab === 'hours' && 'Hours & Geographic Radius'}
                  {activeTab === 'team' && 'Team & Staff Access'}
                  {activeTab === 'analytics' && 'Storefront Analytics'}
                </h1>
                <p className="mt-1 text-xs text-slateText-secondary">
                  Managing{' '}
                  <strong className="text-slateText-main">{currentBusiness.name}</strong> •{' '}
                  {currentBusiness.locality}, {currentBusiness.city}
                </p>
              </div>

              {/* Status pill & Isolation Badge */}
              <div className="flex items-center space-x-2.5">
                <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-bold text-primary border border-blue-200">
                  Tenant Sandboxed
                </span>
                <span className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-bold text-emerald-700 border border-emerald-200">
                  Verified Merchant
                </span>
              </div>
            </div>

            {/* Dynamic Views */}
            {activeTab === 'overview' && (
              <OverviewCards
                business={currentBusiness}
                pendingRequestsCount={pendingRequestsCount}
                totalProductsCount={currentProducts.length + currentServices.length}
                onNavigateTab={setActiveTab}
              />
            )}

            {activeTab === 'requests' && (
              <RequestsManager
                requests={currentRequests}
                onUpdateStatus={handleUpdateStatus}
              />
            )}

            {activeTab === 'catalog' && (
              <CatalogManager
                products={currentProducts}
                services={currentServices}
                onAddProduct={handleAddProduct}
                onAddService={handleAddService}
                onToggleProductStock={handleToggleProductStock}
              />
            )}

            {activeTab === 'hours' && (
              <HoursCoverageManager
                business={currentBusiness}
                hours={hours}
                onSaveHours={handleSaveHours}
                onSaveRadius={handleSaveRadius}
              />
            )}

            {activeTab === 'team' && (
              <TeamManager
                business={currentBusiness}
                team={currentTeam}
                onAddMember={handleAddMember}
                onRevokeMember={handleRevokeMember}
              />
            )}

            {activeTab === 'analytics' && (
              <div className="rounded-2xl border border-borderMuted bg-surface p-8 text-center space-y-4 shadow-card">
                <div className="flex h-14 w-14 mx-auto items-center justify-center rounded-2xl bg-blue-50 text-primary">
                  <CheckCircle2 className="h-7 w-7" />
                </div>
                <h3 className="text-base font-bold text-slateText-main">Storefront Traffic Analytics</h3>
                <p className="text-xs text-slateText-secondary max-w-md mx-auto">
                  Over the past 7 days, <strong>{currentBusiness.name}</strong> received <strong>342 search impressions</strong> on the Grepmind Near mobile radar and <strong>28 customer calls & booking clicks</strong> from {currentBusiness.city}.
                </p>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 max-w-2xl mx-auto pt-4 border-t border-borderMuted text-left">
                  <div className="rounded-xl bg-background p-4 border border-borderMuted">
                    <span className="text-[11px] font-bold text-slateText-secondary">Search Impressions</span>
                    <div className="text-xl font-black text-slateText-main mt-1">342</div>
                    <span className="text-[10px] text-emerald-600 font-bold">+24% vs last week</span>
                  </div>
                  <div className="rounded-xl bg-background p-4 border border-borderMuted">
                    <span className="text-[11px] font-bold text-slateText-secondary">Direction Clicks</span>
                    <div className="text-xl font-black text-slateText-main mt-1">68</div>
                    <span className="text-[10px] text-emerald-600 font-bold">+12% vs last week</span>
                  </div>
                  <div className="rounded-xl bg-background p-4 border border-borderMuted">
                    <span className="text-[11px] font-bold text-slateText-secondary">Direct Calls</span>
                    <div className="text-xl font-black text-slateText-main mt-1">36</div>
                    <span className="text-[10px] text-emerald-600 font-bold">+9% vs last week</span>
                  </div>
                </div>
              </div>
            )}
          </div>
        </main>
      </div>

      {/* New Store Registration Onboarding Modal */}
      {showNewStoreModal && (
        <NewStoreOnboardingModal
          userPhone={session?.phone || '+91 98610 00099'}
          onStoreCreated={handleStoreCreated}
          onCancel={handleLogout}
        />
      )}

      {/* Real-Time Incoming Booking Alert Banner (Option 5) */}
      {incomingAlert && (
        <div className="fixed top-20 right-6 z-50 flex items-start space-x-3 rounded-2xl border-2 border-primary bg-surface p-4 shadow-2xl animate-in fade-in slide-in-from-top-4 duration-200 max-w-sm">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary text-white shadow-md">
            <BellRing className="h-5 w-5 animate-bounce" />
          </div>
          <div className="flex-1">
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-bold text-primary uppercase tracking-wider">
                Instant Request
              </span>
              <button
                onClick={() => setIncomingAlert(null)}
                className="text-slateText-muted hover:text-slateText-main"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
            <h4 className="text-sm font-extrabold text-slateText-main mt-0.5">
              {incomingAlert.customerName}
            </h4>
            <p className="text-xs text-slateText-secondary mt-0.5 font-medium line-clamp-1">
              {incomingAlert.serviceName}
            </p>
            <div className="mt-3 flex items-center space-x-2">
              <button
                onClick={() => {
                  setActiveTab('requests');
                  setIncomingAlert(null);
                }}
                className="rounded-lg bg-primary px-3 py-1.5 text-xs font-bold text-white shadow-sm hover:bg-primary/90 transition-colors"
              >
                Inspect Booking
              </button>
              <button
                onClick={() => setIncomingAlert(null)}
                className="rounded-lg border border-borderMuted px-3 py-1.5 text-xs font-semibold text-slateText-secondary hover:bg-slate-50 transition-colors"
              >
                Dismiss
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Floating Action Toast Notification */}
      {toastMessage && (
        <div className="fixed bottom-6 right-6 z-50 flex items-center space-x-2.5 rounded-2xl bg-slate-900 px-4 py-3 text-xs font-bold text-white shadow-2xl animate-in fade-in slide-in-from-bottom-5">
          <CheckCircle2 className="h-4 w-4 text-emerald-400" />
          <span>{toastMessage}</span>
        </div>
      )}
    </div>
  );
}
