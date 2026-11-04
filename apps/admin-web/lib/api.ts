import axios, { AxiosInstance } from 'axios';

// When running in the browser, always use relative '/api/v1' routed through Nginx
// This completely avoids cross-origin (CORS) blocks and port 8080 mismatches!
const baseURL =
  typeof window !== 'undefined'
    ? '/api/v1'
    : (process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://api:8080/api/v1');

export const api: AxiosInstance = axios.create({
  baseURL,
  headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
});

// Dynamic request interceptor to always attach active auth token
api.interceptors.request.use((config) => {
  if (typeof window !== 'undefined') {
    const token = sessionStorage.getItem('admin_access_token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
  }
  return config;
});

let refreshInFlight: Promise<string | null> | null = null;

api.interceptors.response.use((response) => response, async (error) => {
  const original = error.config as (typeof error.config & { _retried?: boolean }) | undefined;
  if (typeof window === 'undefined' || error.response?.status !== 401 || !original || original._retried || original.url?.includes('/auth/')) {
    return Promise.reject(error);
  }
  original._retried = true;
  const refreshToken = sessionStorage.getItem('admin_refresh_token');
  if (!refreshToken) {
    clearAuthToken();
    window.location.assign('/admin/login');
    return Promise.reject(error);
  }
  refreshInFlight ??= axios.post(`${baseURL}/auth/refresh`, { refresh_token: refreshToken }).then((res) => {
    const nextAccess = res.data?.data?.access_token as string | undefined;
    const nextRefresh = res.data?.data?.refresh_token as string | undefined;
    if (!nextAccess || !nextRefresh) throw new Error('Session refresh response was incomplete.');
    setAuthToken(nextAccess, nextRefresh);
    return nextAccess;
  }).catch(() => {
    clearAuthToken();
    window.location.assign('/admin/login');
    return null;
  }).finally(() => { refreshInFlight = null; });
  const token = await refreshInFlight;
  if (!token) return Promise.reject(error);
  original.headers = original.headers ?? {};
  original.headers.Authorization = `Bearer ${token}`;
  return api(original);
});

export function setAuthToken(token: string | null, refreshToken?: string | null) {
  if (token) {
    api.defaults.headers.common['Authorization'] = `Bearer ${token}`;
    if (typeof window !== 'undefined') {
      sessionStorage.setItem('admin_access_token', token);
      if (refreshToken) sessionStorage.setItem('admin_refresh_token', refreshToken);
    }
  } else {
    clearAuthToken();
  }
}

function clearAuthToken() {
  delete api.defaults.headers.common['Authorization'];
  if (typeof window !== 'undefined') {
    sessionStorage.removeItem('admin_access_token');
    sessionStorage.removeItem('admin_refresh_token');
  }
}

export function hasAuthToken(): boolean {
  return typeof window !== 'undefined' && Boolean(sessionStorage.getItem('admin_access_token'));
}

export interface Paged<T> {
  data: T[];
  meta: { request_id: string; [key: string]: unknown };
}

export interface Stats {
  pending_verifications: number;
  reported_listings: number;
  pending_offers: number;
  active_listings: number;
  pending_claims: number;
  service_requests: number;
  customer_orders: number;
  active_accounts: number;
  notification_events: number;
}

export interface Business {
  id: string;
  name: string;
  slug?: string;
  category_slug: string;
  category_name?: string;
  address_text: string;
  city?: string;
  status: string;
  verification_status: string;
  phone_e164?: string;
  owner_phone?: string;
  created_at: string;
}

export interface BusinessClaim {
  id: string;
  business_id: string;
  business_name: string;
  category_slug: string;
  category: string;
  address: string;
  locality: string;
  city: string;
  claimant_id: string;
  claimant_name: string;
  claimant_phone: string;
  message: string;
  created_at: string;
}

export interface Report {
  id: string;
  reporter_phone?: string;
  target_type: string;
  target_id: string;
  target_name?: string;
  reason: string;
  status: string;
  created_at: string;
  resolved_at?: string;
  resolution_reason?: string;
}

export interface Offer {
  id: string;
  business_id: string;
  business_name: string;
  title: string;
  description?: string;
  starts_at: string;
  ends_at: string;
  status: string;
  discount_percent?: number;
}

export interface AuditLog {
  id: string;
  actor_phone?: string;
  action: string;
  target_type: string;
  target_id: string;
  reason?: string;
  created_at: string;
}

export interface AdminUser {
  id: string;
  phone_e164: string;
  display_name: string;
  role: string;
  created_at: string;
}

export interface AdminTrendPoint {
  date: string;
  new_listings: number;
  service_requests: number;
  customer_orders: number;
}

export interface AdminCategoryVolume {
  category: string;
  count: number;
}

export interface AdminTrends {
  series: AdminTrendPoint[];
  categories: AdminCategoryVolume[];
}

export interface ListingActivity {
  id: string;
  user_id: string;
  phone_e164: string;
  display_name: string;
  business_id: string;
  business_name: string;
  category: string;
  city: string;
  status: string;
  created_at: string;
}

export interface UserAccessRecord {
  id: string;
  phone_e164: string;
  display_name: string;
  status: string;
  roles: string[];
  created_at: string;
}

// ---------- API client methods ----------

export async function getStats(city: string, range: string): Promise<Stats> {
  const params: Record<string, string> = { range };
  if (city !== 'All Cities') params.city = city;
  const res = await api.get<{ data: Stats }>('/admin/stats', { params });
  return res.data.data;
}

export async function getAdminTrends(city: string, range: string): Promise<AdminTrends> {
  const params: Record<string, string> = { range };
  if (city !== 'All Cities') params.city = city;
  const res = await api.get<{ data: AdminTrends }>('/admin/trends', { params });
  return res.data.data;
}

export async function getListingActivity(city: string, range: string): Promise<ListingActivity[]> {
  const params: Record<string, string> = { range };
  if (city !== 'All Cities') params.city = city;
  const res = await api.get<{ data: ListingActivity[] }>('/admin/listing-activity', { params });
  return res.data.data ?? [];
}

export async function getUserAccess(): Promise<{ users: UserAccessRecord[]; canManageRoles: boolean }> {
  const res = await api.get<{ data: UserAccessRecord[]; meta?: { can_manage_roles?: boolean } }>('/admin/user-access');
  return { users: res.data.data ?? [], canManageRoles: res.data.meta?.can_manage_roles === true };
}

export async function saveUserAccess(phone_e164: string, display_name: string, roles: string[]): Promise<void> {
  await api.post('/admin/user-access', { phone_e164, display_name, roles });
}

export async function getPendingBusinesses(): Promise<Business[]> {
  const res = await api.get<{ data: Business[] }>('/admin/businesses/pending');
  return res.data.data ?? [];
}

export async function getAllBusinesses(status?: string): Promise<Business[]> {
  const params = status && status !== 'all' ? { status } : {};
  const res = await api.get<{ data: Business[] }>('/admin/businesses', { params });
  return res.data.data ?? [];
}

export async function approveBusiness(id: string, reason?: string) {
  const res = await api.post(`/admin/businesses/${id}/approve`, { reason });
  return res.data;
}

export async function rejectBusiness(id: string, reason: string) {
  const res = await api.post(`/admin/businesses/${id}/reject`, { reason });
  return res.data;
}

export async function verifyBusiness(id: string, verification_status: 'verified' | 'rejected', reason?: string) {
  const res = await api.post(`/admin/businesses/${id}/verify`, { verification_status, reason });
  return res.data;
}

export async function getBusinessClaims(): Promise<BusinessClaim[]> {
  const res = await api.get<{ data: BusinessClaim[] }>('/admin/business-claims');
  return res.data.data ?? [];
}

export async function decideBusinessClaim(id: string, decision: 'approve' | 'reject', note: string) {
  const res = await api.post(`/admin/business-claims/${id}/decision`, { decision, note });
  return res.data;
}

export async function getReports(status?: string): Promise<Report[]> {
  const params = status && status !== 'all' ? { status } : {};
  const res = await api.get<{ data: Report[] }>('/admin/reports', { params });
  return res.data.data ?? [];
}

export async function resolveReport(id: string, resolution: 'action_taken' | 'dismissed', reason?: string) {
  const res = await api.post(`/admin/reports/${id}/resolve`, { resolution, reason });
  return res.data;
}

export async function getOffers(status?: string): Promise<Offer[]> {
  const params = status && status !== 'all' ? { status } : {};
  const res = await api.get<{ data: Offer[] }>('/admin/offers', { params });
  return res.data.data ?? [];
}

export async function approveOffer(id: string) {
  const res = await api.post(`/admin/offers/${id}/approve`);
  return res.data;
}

export async function rejectOffer(id: string) {
  const res = await api.post(`/admin/offers/${id}/reject`);
  return res.data;
}

export async function getAuditLogs(): Promise<AuditLog[]> {
  const res = await api.get<{ data: AuditLog[] }>('/admin/audit-logs');
  return res.data.data ?? [];
}

export async function getAdmins(): Promise<AdminUser[]> {
  const res = await api.get<{ data: AdminUser[] }>('/admin/admins');
  return res.data.data ?? [];
}

export async function addAdmin(phone_e164: string, display_name?: string): Promise<AdminUser> {
  const res = await api.post<{ data: AdminUser }>('/admin/admins', {
    phone_e164,
    display_name: display_name || 'Platform Admin',
  });
  return res.data.data;
}

export async function revokeAdmin(userId: string) {
  const res = await api.delete(`/admin/admins/${userId}`);
  return res.data;
}
