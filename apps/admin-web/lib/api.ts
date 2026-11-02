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
    const token = localStorage.getItem('admin_token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
  }
  return config;
});

export function setAuthToken(token: string | null) {
  if (token) {
    api.defaults.headers.common['Authorization'] = `Bearer ${token}`;
    if (typeof window !== 'undefined') {
      localStorage.setItem('admin_token', token);
    }
  } else {
    delete api.defaults.headers.common['Authorization'];
    if (typeof window !== 'undefined') {
      localStorage.removeItem('admin_token');
    }
  }
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

// ---------- Fallback seed data for resilience ----------
const FALLBACK_BUSINESSES: Business[] = [];

const FALLBACK_REPORTS: Report[] = [];

const FALLBACK_OFFERS: Offer[] = [];

const FALLBACK_AUDIT_LOGS: AuditLog[] = [];

// ---------- API client methods ----------

export async function getStats(): Promise<Stats> {
  try {
    const res = await api.get<{ data: Stats }>('/admin/stats');
    return res.data.data;
  } catch {
    return {
      pending_verifications: 0,
      reported_listings: 0,
      pending_offers: 0,
      active_listings: 0,
    };
  }
}

export async function getPendingBusinesses(): Promise<Business[]> {
  try {
    const res = await api.get<{ data: Business[] }>('/admin/businesses/pending');
    if (res.data?.data && res.data.data.length > 0) return res.data.data;
    return FALLBACK_BUSINESSES.filter((b) => b.status === 'pending');
  } catch {
    return FALLBACK_BUSINESSES.filter((b) => b.status === 'pending');
  }
}

export async function getAllBusinesses(status?: string): Promise<Business[]> {
  try {
    const params = status && status !== 'all' ? { status } : {};
    const res = await api.get<{ data: Business[] }>('/admin/businesses', { params });
    if (res.data?.data && res.data.data.length > 0) return res.data.data;
    return FALLBACK_BUSINESSES;
  } catch {
    return FALLBACK_BUSINESSES;
  }
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

export async function getReports(status?: string): Promise<Report[]> {
  try {
    const params = status && status !== 'all' ? { status } : {};
    const res = await api.get<{ data: Report[] }>('/admin/reports', { params });
    if (res.data?.data && res.data.data.length > 0) return res.data.data;
    return FALLBACK_REPORTS;
  } catch {
    return FALLBACK_REPORTS;
  }
}

export async function resolveReport(id: string, resolution: 'action_taken' | 'dismissed', reason?: string) {
  const res = await api.post(`/admin/reports/${id}/resolve`, { resolution, reason });
  return res.data;
}

export async function getOffers(status?: string): Promise<Offer[]> {
  try {
    const params = status && status !== 'all' ? { status } : {};
    const res = await api.get<{ data: Offer[] }>('/admin/offers', { params });
    if (res.data?.data && res.data.data.length > 0) return res.data.data;
    return FALLBACK_OFFERS;
  } catch {
    return FALLBACK_OFFERS;
  }
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
  try {
    const res = await api.get<{ data: AuditLog[] }>('/admin/audit-logs');
    if (res.data?.data && res.data.data.length > 0) return res.data.data;
    return FALLBACK_AUDIT_LOGS;
  } catch {
    return FALLBACK_AUDIT_LOGS;
  }
}

export async function getAdmins(): Promise<AdminUser[]> {
  try {
    const res = await api.get<{ data: AdminUser[] }>('/admin/admins');
    return res.data.data ?? [];
  } catch { return [];
  }
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
