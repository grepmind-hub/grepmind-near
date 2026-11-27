'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { AdminHeader } from '@/components/AdminHeader';
import { AdminSidebar, AdminTab } from '@/components/AdminSidebar';
import { GraphicalMetricsView } from '@/components/GraphicalMetricsView';
import { VerificationQueueView } from '@/components/VerificationQueueView';
import { BusinessesRegistryView } from '@/components/BusinessesRegistryView';
import { MerchantApplicationDrawer } from '@/components/MerchantApplicationDrawer';
import type { BusinessApplication } from '@/lib/api';
import { ReportsDisputesView } from '@/components/ReportsDisputesView';
import { OffersModerationView } from '@/components/OffersModerationView';
import { AuditLogsView } from '@/components/AuditLogsView';
import { AdminUsersView } from '@/components/AdminUsersView';
import { BusinessClaimsView } from '@/components/BusinessClaimsView';
import { ListingActivityView } from '@/components/ListingActivityView';
import { UserAccessView } from '@/components/UserAccessView';
import { PlatformCatalogView } from '@/components/PlatformCatalogView';
import { ServiceAreasView } from '@/components/ServiceAreasView';
import { RiderManagementView } from '@/components/RiderManagementView';
import { DispatchBoardView } from '@/components/DispatchBoardView';
import { RiderEarningsView } from '@/components/RiderEarningsView';
import { AdminReconciliationQueue } from '@/components/AdminReconciliationQueue';
import { AdminPaymentTracking } from '@/components/AdminPaymentTracking';
import { FinanceOverview } from '@/components/FinanceOverview';
import type { FinanceReturn } from '@/components/FinanceOrderLink';
import type { RelatedAttempt } from '@/components/AdminReconciliationQueue';
import { CODFinanceView } from '@/components/CODFinanceView';
import { MerchantSettlementFinanceView } from '@/components/MerchantSettlementFinanceView';
import {
  api,
  setAuthToken,
  hasAuthToken,
  getStats,
  getPendingBusinesses,
  getAllBusinesses,
  getReports,
  getOffers,
  getAuditLogs,
  getAdmins,
  getAdminTrends,
  getBusinessClaims,
  decideBusinessClaim,
  getListingActivity,
  getUserAccess,
  saveUserAccess,
  addAdmin,
  revokeAdmin,
  approveBusiness,
  rejectBusiness,
  verifyBusiness,
  resolveReport,
  approveOffer,
  rejectOffer,
  Stats,
  Business,
  Report,
  Offer,
  AuditLog,
  AdminUser,
  AdminTrends,
  BusinessClaim,
  ListingActivity,
  UserAccessRecord,
} from '@/lib/api';

export function AdminPortalClient({ initialTab = 'overview', initialPaymentOrder, financeReturn = 'reconciliation-queue', initialRefundStatus = 'requested' }: {
  initialTab?: AdminTab;
  initialPaymentOrder?: string;
  financeReturn?: FinanceReturn;
  initialRefundStatus?: string;
}) {
  const [refundStatus, setRefundStatus] = useState(initialRefundStatus);
  const [relatedAttempt, setRelatedAttempt] = useState<RelatedAttempt>();
  const [lastTrackingOrder, setLastTrackingOrder] = useState(initialPaymentOrder);
  const [historyFromTracking, setHistoryFromTracking] = useState(false);
  const router = useRouter();
  const [currentTab, setCurrentTab] = useState<AdminTab>(initialTab);
  const [selectedCity, setSelectedCity] = useState<string>('All Cities');
  const [selectedRange, setSelectedRange] = useState<'7d' | '14d' | '30d'>('14d');
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [metricsError, setMetricsError] = useState<string | null>(null);
  const [metricsUpdatedAt, setMetricsUpdatedAt] = useState<Date | null>(null);
  const [claims, setClaims] = useState<BusinessClaim[]>([]);
  const [claimsLoading, setClaimsLoading] = useState(true);
  const [claimsError, setClaimsError] = useState<string | null>(null);
  const [claimActionId, setClaimActionId] = useState<string | null>(null);
  const [listingActivity, setListingActivity] = useState<ListingActivity[]>([]);
  const [activityLoading, setActivityLoading] = useState(true);
  const [activityError, setActivityError] = useState<string | null>(null);
  const [userAccess, setUserAccess] = useState<UserAccessRecord[]>([]);
  const [canManageRoles, setCanManageRoles] = useState(false);
  const [accessLoading, setAccessLoading] = useState(true);
  const [accessError, setAccessError] = useState<string | null>(null);
  const [financeCapabilities, setFinanceCapabilities] = useState({ finance_read: false, finance_post: false });

  // Live state from API
  const [stats, setStats] = useState<Stats | null>(null);
  const [pendingBusinesses, setPendingBusinesses] = useState<Business[]>([]);
  const [applicationId, setApplicationId] = useState<string | null>(null);
  const [allBusinesses, setAllBusinesses] = useState<Business[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [offers, setOffers] = useState<Offer[]>([]);
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [admins, setAdmins] = useState<AdminUser[]>([]);
  const [trends, setTrends] = useState<AdminTrends | null>(null);

  // Load only API-backed operational data; authentication is handled by OTP.
  const initSessionAndLoad = useCallback(async () => {
    if (!hasAuthToken()) {
      if (typeof window !== 'undefined') window.location.replace('/admin/login');
      return;
    }
    setIsRefreshing(true);
    setLoadError(null);
    try {
      const [s, t, p, b, r, o, l, a, c, activity, access, capabilities] = await Promise.all([
        getStats(selectedCity, selectedRange),
        getAdminTrends(selectedCity, selectedRange),
        getPendingBusinesses(),
        getAllBusinesses('all'),
        getReports('all'),
        getOffers('all'),
        getAuditLogs(),
        getAdmins(),
        getBusinessClaims(),
        getListingActivity(selectedCity, selectedRange),
        getUserAccess(),
        api.get<{ data: { finance_read?: boolean; finance_post?: boolean } }>('/admin/finance/capabilities'),
      ]);

      setStats(s);
      setTrends(t);
      setMetricsUpdatedAt(new Date());
      setMetricsError(null);
      setPendingBusinesses(p);
      setAllBusinesses(b);
      setReports(r);
      setOffers(o);
      setAuditLogs(l);
      setAdmins(a);
      setClaims(c);
      setClaimsError(null);
      setClaimsLoading(false);
      setListingActivity(activity);
      setActivityError(null);
      setActivityLoading(false);
      setUserAccess(access.users);
      setCanManageRoles(access.canManageRoles);
      setFinanceCapabilities({ finance_read: capabilities.data?.data?.finance_read === true, finance_post: capabilities.data?.data?.finance_post === true });
      setAccessError(null);
      setAccessLoading(false);
    } catch (err) {
      console.error('Data load error:', err);
      setLoadError('Live platform data could not be loaded. Check the API connection and refresh.');
      setClaimsError('Claim review queue could not be loaded. Retry when the API is available.');
      setActivityError('Listing activity could not be loaded from the API.');
      setAccessError('User access could not be loaded from the API.');
    } finally {
      setClaimsLoading(false);
      setActivityLoading(false);
      setAccessLoading(false);
      setIsRefreshing(false);
    }
  }, [selectedCity, selectedRange]);

  const refreshMetrics = useCallback(async () => {
    if (!hasAuthToken() || document.visibilityState !== 'visible') return;
    try {
      const [nextStats, nextTrends] = await Promise.all([
        getStats(selectedCity, selectedRange),
        getAdminTrends(selectedCity, selectedRange),
      ]);
      setStats(nextStats);
      setTrends(nextTrends);
      setMetricsUpdatedAt(new Date());
      setMetricsError(null);
    } catch (error) {
      console.error('Dashboard metric refresh failed:', error);
      setMetricsError('Auto refresh is temporarily unavailable.');
    }
  }, [selectedCity, selectedRange]);

  useEffect(() => {
    let active = true;
    queueMicrotask(() => {
      if (active) void initSessionAndLoad();
    });
    return () => { active = false; };
  }, [initSessionAndLoad]);

  useEffect(() => {
    const timer = window.setInterval(() => void refreshMetrics(), 30_000);
    return () => window.clearInterval(timer);
  }, [refreshMetrics]);

  // Handlers for moderation actions
  async function handleBusinessDecision(item: BusinessApplication, action: 'approve' | 'reject', reason: string) {
    try {
      if (action === 'reject') {
        await rejectBusiness(item.id, reason);
      } else {
        const evidence = `Offline evidence reviewed: ${reason}`;
        if (item.verification_status !== 'verified') await verifyBusiness(item.id, 'verified', evidence);
        if (item.status !== 'approved') await approveBusiness(item.id, evidence);
      }
      await initSessionAndLoad();
      return true;
    } catch {
      return false;
    }
  }

  async function handleResolveReport(id: string, resolution: 'action_taken' | 'dismissed', reason: string) {
    try {
      await resolveReport(id, resolution, reason);
      await initSessionAndLoad();
    } catch (e) {
      console.error('Report resolution failed:', e);
      setActionError('Report resolution failed. No successful update was confirmed.');
    }
  }

  async function handleApproveOffer(id: string) {
    try {
      await approveOffer(id);
      await initSessionAndLoad();
    } catch (e) {
      console.error('Offer approval failed:', e);
      setActionError('Offer approval failed. No successful update was confirmed.');
    }
  }

  async function handleRejectOffer(id: string) {
    try {
      await rejectOffer(id);
      await initSessionAndLoad();
    } catch (e) {
      console.error('Offer rejection failed:', e);
      setActionError('Offer rejection failed. No successful update was confirmed.');
    }
  }

  async function handleAddAdmin(phone: string, name?: string) {
    try {
      await addAdmin(phone, name);
      await initSessionAndLoad();
    } catch (e) {
      console.error('Add admin failed:', e);
      throw e;
    }
  }

  async function handleRevokeAdmin(userId: string) {
    try {
      await revokeAdmin(userId);
      await initSessionAndLoad();
    } catch (e) {
      console.error('Revoke admin failed:', e);
      throw e;
    }
  }

  async function handleClaimDecision(claim: BusinessClaim, decision: 'approve' | 'reject', note: string) {
    setClaimActionId(claim.id);
    try {
      await decideBusinessClaim(claim.id, decision, note);
      const [nextClaims, nextBusinesses, nextStats] = await Promise.all([
        getBusinessClaims(), getAllBusinesses('all'), getStats(selectedCity, selectedRange),
      ]);
      setClaims(nextClaims);
      setAllBusinesses(nextBusinesses);
      setStats(nextStats);
    } catch (error) {
      console.error('Ownership claim decision failed:', error);
      setActionError('Claim decision failed. No ownership change was confirmed.');
    } finally {
      setClaimActionId(null);
    }
  }

  async function handleSaveUserAccess(phone: string, name: string, roles: string[]) {
    await saveUserAccess(phone, name, roles);
    const [nextAccess, nextAdmins] = await Promise.all([getUserAccess(), getAdmins()]);
    setUserAccess(nextAccess.users);
    setCanManageRoles(nextAccess.canManageRoles);
    setAdmins(nextAdmins);
  }

  function handleSignOut() {
    void api.post('/auth/logout').catch(() => undefined).finally(() => {
      setAuthToken(null);
      if (typeof window !== 'undefined') window.location.replace('/admin/login');
    });
  }

  const reconciliationLayout = ['reconciliation-queue', 'payment-tracking', 'finance-overview'].includes(currentTab);
  const financeReturnLabels = {
    'finance-overview': 'Back to Finance Overview',
    'cod-finance': 'Back to COD accountability',
    'merchant-finance': 'Back to merchant finance',
    'reconciliation-queue': 'Back to reconciliation queue',
  };

  return (
    <div className="flex h-screen w-full flex-col overflow-hidden bg-[#F7F8FA]">
      {/* Top Header */}
      <AdminHeader
        compactOnNarrow={reconciliationLayout}
        selectedCity={selectedCity}
        onSelectCity={setSelectedCity}
        selectedRange={selectedRange}
        onSelectRange={setSelectedRange}
        isRefreshing={isRefreshing}
        onRefresh={initSessionAndLoad}
        onSignOut={handleSignOut}
      />

      {/* Main Layout: Sidebar + Dynamic View */}
      <div className="flex min-h-0 flex-1 overflow-hidden">
        <AdminSidebar
          currentTab={currentTab}
          hideOnNarrow={reconciliationLayout}
          onSelectTab={(tab) => {
            if (tab === 'claims') {
              router.push('/dashboard/businesses');
              return;
            }
            if (tab === 'overview' && initialTab === 'claims') {
              router.push('/dashboard');
              return;
            }
            setRelatedAttempt(undefined);
            setHistoryFromTracking(false);
            setCurrentTab(tab);
          }}
          pendingCount={stats?.pending_verifications ?? 0}
          reportsCount={stats?.reported_listings ?? 0}
          offersCount={stats?.pending_offers ?? 0}
        />

        <main className={`min-w-0 flex-1 overflow-y-auto ${currentTab === 'reconciliation-queue' ? 'p-3 sm:p-6 md:p-8' : 'p-6 md:p-8'}`}>
          {actionError && <div role="alert" className="mb-4 flex items-center justify-between gap-3 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800"><span>{actionError}</span><button onClick={() => setActionError(null)} className="min-h-10 rounded-lg px-3 font-semibold">Dismiss</button></div>}
          {loadError && <div role="alert" className="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800"><span>{loadError}</span><button onClick={() => void initSessionAndLoad()} className="min-h-10 rounded-lg bg-white px-4 font-semibold text-rose-700 shadow-sm">Retry</button></div>}
          {!loadError && !stats && <div className="mb-5 animate-pulse rounded-2xl border border-[#E4E7EC] bg-white p-5 text-sm text-[#667085]">Loading live operational data…</div>}
          {currentTab === 'overview' && (
            <GraphicalMetricsView
              stats={stats}
              selectedCity={selectedCity}
              selectedRange={selectedRange}
              trends={trends}
              updatedAt={metricsUpdatedAt}
              metricsError={metricsError}
              onNavigateTab={(tab) => setCurrentTab(tab)}
            />
          )}

          {applicationId && <MerchantApplicationDrawer key={applicationId} id={applicationId} onClose={() => setApplicationId(null)} onDecision={handleBusinessDecision} />}
          {currentTab === 'verification' && (
            <VerificationQueueView
              apiPendingList={pendingBusinesses}
              onViewDetails={setApplicationId}
            />
          )}

          {currentTab === 'businesses' && (
            <BusinessesRegistryView
              businesses={allBusinesses}
              onViewDetails={setApplicationId}
            />
          )}

          {currentTab === 'reports' && (
            <ReportsDisputesView
              reports={reports}
              onResolveReport={handleResolveReport}
            />
          )}

          {currentTab === 'offers' && (
            <OffersModerationView
              offers={offers}
              onApprove={handleApproveOffer}
              onReject={handleRejectOffer}
            />
          )}

          {currentTab === 'audit-logs' && <AuditLogsView logs={auditLogs} />}

          {currentTab === 'claims' && <BusinessClaimsView
            claims={claims}
            isLoading={claimsLoading}
            error={claimsError}
            actionId={claimActionId}
            onRetry={() => void initSessionAndLoad()}
            onDecision={handleClaimDecision}
          />}

          {currentTab === 'listing-activity' && <ListingActivityView
            items={listingActivity}
            range={selectedRange}
            loading={activityLoading}
            error={activityError}
            updatedAt={metricsUpdatedAt}
            onRefresh={() => void initSessionAndLoad()}
          />}

          {currentTab === 'admin-users' && (
            <div className="space-y-8">
              <AdminUsersView admins={admins} canManageRoles={canManageRoles} onAddAdmin={handleAddAdmin} onRevokeAdmin={handleRevokeAdmin} />
              <UserAccessView users={userAccess} canManageRoles={canManageRoles} loading={accessLoading} error={accessError} onRefresh={() => void initSessionAndLoad()} onSave={handleSaveUserAccess} />
            </div>
          )}
          {currentTab === 'service-locations' && <ServiceAreasView />}
          {currentTab === 'platform-catalog' && <PlatformCatalogView />}
          {currentTab === 'riders' && <RiderManagementView />}
          {currentTab === 'dispatch' && <DispatchBoardView />}
          {currentTab === 'rider-earnings' && <RiderEarningsView />}
          {currentTab === 'finance-overview' && <FinanceOverview onSelectTab={setCurrentTab}
            refundStatus={refundStatus} onRefundStatusChange={setRefundStatus} />}
          {currentTab === 'payment-tracking' && <>
            <button type="button" onClick={() => {
              setRelatedAttempt(undefined);
              setHistoryFromTracking(false);
              setCurrentTab(initialPaymentOrder ? financeReturn : 'overview');
            }} className="mb-4 min-h-11 rounded-xl border border-[#D0D5DD] bg-white px-4 text-sm font-semibold text-[#2457D6]">
              {initialPaymentOrder ? financeReturnLabels[financeReturn] : 'Back to Admin dashboard'}
            </button>
            <AdminPaymentTracking initialReference={lastTrackingOrder} onViewHistory={(attempt, order) => {
              setRelatedAttempt(attempt);
              setLastTrackingOrder(order);
              setHistoryFromTracking(true);
              setCurrentTab('reconciliation-queue');
            }} />
          </>}
          {currentTab === 'reconciliation-queue' && <>
            {historyFromTracking && <button type="button" onClick={() => setCurrentTab('payment-tracking')}
              className="mb-4 min-h-11 rounded-xl border border-[#D0D5DD] bg-white px-4 text-sm font-semibold text-[#2457D6]">
              Back to payment tracking
            </button>}
            <AdminReconciliationQueue initialRelated={relatedAttempt} onExit={() => setCurrentTab('overview')} />
          </>}
          {currentTab === 'cod-finance' && <CODFinanceView canPost={financeCapabilities.finance_post} />}
          {currentTab === 'merchant-finance' && <MerchantSettlementFinanceView canPost={financeCapabilities.finance_post} />}
        </main>
      </div>
    </div>
  );
}
