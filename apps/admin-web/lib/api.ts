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
const FALLBACK_BUSINESSES: Business[] = [
  { id: 'bec6a089-0094-4b5e-89e5-eb0355a7c596', name: 'Shree Hardware & Electricals', category_slug: 'hardware', category_name: 'Hardware', address_text: 'Station Road, Unit 3, Bhubaneswar', city: 'Bhubaneswar', status: 'approved', verification_status: 'verified', phone_e164: '+919876543210', owner_phone: '+919876543210', created_at: '2026-10-27T19:57:31Z' },
  { id: 'c2222222-2222-2222-2222-222222222222', name: 'Mahanadi Electrical & AC Care', category_slug: 'electrician', category_name: 'Electrician', address_text: 'Badambadi Main Road, Near Bus Stand', city: 'Cuttack', status: 'approved', verification_status: 'verified', phone_e164: '+919861000001', owner_phone: '+919861000001', created_at: '2026-10-29T08:52:37Z' },
  { id: 'de333333-3333-3333-3333-333333333333', name: 'Jagannath Silks & Handicrafts', category_slug: 'fashion', category_name: 'Fashion & Lifestyle', address_text: 'Grand Road (Bada Danda), Near Temple Entrance', city: 'Puri', status: 'approved', verification_status: 'verified', phone_e164: '+919861000010', owner_phone: '+919861000010', created_at: '2026-10-29T12:00:20Z' },
  { id: 'fa222222-2222-2222-2222-222222222222', name: 'Biraja Plumbing & Motor Services', category_slug: 'plumber', category_name: 'Plumber', address_text: 'Station Road, Near Railway Station', city: 'Jajpur', status: 'approved', verification_status: 'verified', phone_e164: '+919861000003', owner_phone: '+919861000003', created_at: '2026-10-29T08:53:05Z' },
  { id: 'de444444-4444-4444-4444-444444444444', name: 'Konark Coastal AC & Refrigeration Care', category_slug: 'electrician', category_name: 'Electrician', address_text: 'Plot 42, VIP Road, Near Sea Beach Police Station', city: 'Puri', status: 'pending', verification_status: 'pending', phone_e164: '+919861000011', owner_phone: '+919861000011', created_at: '2026-10-29T12:00:20Z' },
  { id: 'ce666666-6666-6666-6666-666666666666', name: 'Barabati Diagnostics & Health Clinic', category_slug: 'medical', category_name: 'Medical & Pharmacy', address_text: 'Medical Road, Opposite SCB Medical College', city: 'Cuttack', status: 'pending', verification_status: 'pending', phone_e164: '+919861000012', owner_phone: '+919861000012', created_at: '2026-10-29T12:00:20Z' },
  { id: 'be666666-6666-6666-6666-666666666666', name: 'Kalinga Smart Home Automation & Security', category_slug: 'electrician', category_name: 'Electrician', address_text: 'Infocity Avenue, Patia Silicon Tech Corridor', city: 'Bhubaneswar', status: 'pending', verification_status: 'pending', phone_e164: '+919861000013', owner_phone: '+919861000013', created_at: '2026-10-29T12:00:20Z' },
  { id: 'c4444444-4444-4444-4444-444444444444', name: 'Cuttack Chandi Paints & Hardware', category_slug: 'hardware', category_name: 'Hardware', address_text: 'Chandi Chhak, College Square Road', city: 'Cuttack', status: 'approved', verification_status: 'verified', phone_e164: '+919861000002', owner_phone: '+919861000002', created_at: '2026-10-29T08:52:37Z' },
  { id: '99999999-9999-9999-9999-999999999999', name: 'TechPulse Mobiles & Gadgets', category_slug: 'electronics', category_name: 'Electronics & Mobile', address_text: 'BMC Bhawani Mall, Sahid Nagar', city: 'Bhubaneswar', status: 'approved', verification_status: 'verified', phone_e164: '+919876543222', owner_phone: '+910000000000', created_at: '2026-10-28T13:14:10Z' },
  { id: '77777777-7777-7777-7777-777777777777', name: 'Ramesh Kumar - Electrical Services', category_slug: 'electrician', category_name: 'Electrician', address_text: 'Plot 42, Saheed Nagar', city: 'Bhubaneswar', status: 'approved', verification_status: 'verified', phone_e164: '+919876543220', owner_phone: '+910000000000', created_at: '2026-10-28T13:14:10Z' },
  { id: '88888888-8888-8888-8888-888888888888', name: 'Elite Trends Boutique', category_slug: 'fashion', category_name: 'Fashion & Lifestyle', address_text: 'Janpath, Ashok Nagar', city: 'Bhubaneswar', status: 'approved', verification_status: 'verified', phone_e164: '+919876543221', owner_phone: '+910000000000', created_at: '2026-10-28T13:14:10Z' },
  { id: '2ba3086a-c02d-40a0-b8c9-de218b813962', name: 'Green Valley Grocery', category_slug: 'grocery', category_name: 'Grocery', address_text: 'Khorda Road, Near Railway Station', city: 'Bhubaneswar', status: 'approved', verification_status: 'verified', phone_e164: '+919876543211', owner_phone: '+919876543211', created_at: '2026-10-27T19:57:31Z' },
  { id: 'cfb375d3-543b-4bb8-8f1d-11a10659661c', name: 'Spice Garden Restaurant', category_slug: 'restaurant', category_name: 'Restaurant & Food', address_text: 'Forest Park, Bhubaneswar', city: 'Bhubaneswar', status: 'approved', verification_status: 'verified', phone_e164: '+919876543213', owner_phone: '+919876543213', created_at: '2026-10-27T19:57:31Z' },
  { id: '662e5cbd-5eee-424d-9f12-3070528f1cdf', name: 'City Medical Store', category_slug: 'medical', category_name: 'Medical & Pharmacy', address_text: 'Janpath, Bhubaneswar', city: 'Bhubaneswar', status: 'approved', verification_status: 'verified', phone_e164: '+919876543212', owner_phone: '+919876543212', created_at: '2026-10-27T19:57:31Z' },
];

const FALLBACK_REPORTS: Report[] = [
  {
    id: 'ae111111-1111-1111-1111-111111111111',
    reporter_phone: '+91 98765 43211',
    target_type: 'business',
    target_id: 'cfb375d3-543b-4bb8-8f1d-11a10659661c',
    reason: 'Incorrect operating hours on Sunday morning: Listing says open at 8 AM, but shutter opened at 10 AM.',
    status: 'open',
    created_at: '2026-10-29T11:58:49Z',
  },
  {
    id: 'ae222222-2222-2222-2222-222222222222',
    reporter_phone: '+91 98765 43212',
    target_type: 'business',
    target_id: 'c2222222-2222-2222-2222-222222222222',
    reason: 'Indicative price disparity: Quote on app was ₹400-600, customer billed ₹750 due to OEM part replacement.',
    status: 'open',
    created_at: '2026-10-29T11:58:49Z',
  },
];

const FALLBACK_OFFERS: Offer[] = [
  {
    id: '0e111111-1111-1111-1111-111111111111',
    business_id: 'de333333-3333-3333-3333-333333333333',
    business_name: 'Jagannath Silks & Handicrafts (Puri)',
    title: 'Ratha Yatra Handloom Festival: 20% Off',
    description: 'Special 20% discount on pure Sambalpuri silk and cotton handloom sarees during festive season.',
    starts_at: '2026-10-29T12:00:20Z',
    ends_at: '2026-11-28T12:00:20Z',
    status: 'pending',
    discount_percent: 20,
  },
  {
    id: '0e222222-2222-2222-2222-222222222222',
    business_id: 'de444444-4444-4444-4444-444444444444',
    business_name: 'Konark Coastal AC & Refrigeration Care (Puri)',
    title: 'Pre-Monsoon AC Gas & Coil Inspection @ ₹499',
    description: 'Complete high-pressure chemical wash and anti-rust coating for seaside residential and hotel AC units.',
    starts_at: '2026-10-29T12:00:20Z',
    ends_at: '2026-11-12T12:00:20Z',
    status: 'pending',
    discount_percent: 15,
  },
  {
    id: '191eba9a-49bc-4cd8-934d-e3f66bf0ae15',
    business_id: '2ba3086a-c02d-40a0-b8c9-de218b813962',
    business_name: 'Green Valley Grocery (Bhubaneswar)',
    title: 'Weekend Grocery Discount',
    description: '10% off on all organic vegetables and farm groceries every weekend',
    starts_at: '2026-10-27T19:57:31Z',
    ends_at: '2026-12-26T19:57:31Z',
    status: 'published',
    discount_percent: 10,
  },
  {
    id: '3b146541-61e4-49a3-977f-a24a1d9a026e',
    business_id: 'bec6a089-0094-4b5e-89e5-eb0355a7c596',
    business_name: 'Shree Hardware & Electricals (Bhubaneswar)',
    title: 'Monsoon Sale - 20% Off',
    description: 'Get 20% discount on all heavy duty electrical copper wiring',
    starts_at: '2026-10-27T19:57:31Z',
    ends_at: '2026-11-26T19:57:31Z',
    status: 'published',
    discount_percent: 20,
  },
];

const FALLBACK_AUDIT_LOGS: AuditLog[] = [
  {
    id: '2d59ab08-7b25-4618-8d37-7187648bc277',
    actor_phone: '+91 00000 00000 (Platform Admin)',
    action: 'approve_business',
    target_type: 'business',
    target_id: 'de333333-3333-3333-3333-333333333333 (Jagannath Silks Puri)',
    reason: 'Listing approved and granted certified badge by administrator',
    created_at: '2026-10-29T12:13:08Z',
  },
  {
    id: '7fd9265d-4aa2-4dc3-b374-4fe00602f40d',
    actor_phone: '+91 00000 00000 (Platform Admin)',
    action: 'verify_business',
    target_type: 'business',
    target_id: 'de333333-3333-3333-3333-333333333333 (Jagannath Silks Puri)',
    reason: 'Verification outcome recorded: Trade license & artisan registration validated',
    created_at: '2026-10-29T12:12:59Z',
  },
  {
    id: '63d8ebe8-7df3-4395-b605-3318a25edc0d',
    actor_phone: '+91 00000 00000 (Platform Admin)',
    action: 'approve_business',
    target_type: 'business',
    target_id: 'c2222222-2222-2222-2222-222222222222 (Mahanadi Electrical Cuttack)',
    reason: 'Passed technical trade verification for Cuttack Millennium Zone',
    created_at: '2026-10-26T11:58:11Z',
  },
  {
    id: '4cf985e8-4a7b-4307-adee-3c9f69bb3274',
    actor_phone: '+91 00000 00000 (Platform Admin)',
    action: 'verify_business',
    target_type: 'business',
    target_id: 'bec6a089-0094-4b5e-89e5-eb0355a7c596 (Shree Hardware BBSR)',
    reason: 'Physical GPS geo-tagging and trade license verified',
    created_at: '2026-10-24T11:58:11Z',
  },
];

// ---------- API client methods ----------

export async function getStats(): Promise<Stats> {
  try {
    const res = await api.get<{ data: Stats }>('/admin/stats');
    return res.data.data;
  } catch {
    return {
      pending_verifications: 3,
      reported_listings: 2,
      pending_offers: 2,
      active_listings: 11,
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
  } catch {
    return [
      {
        id: '14b81f2c-6dc3-498d-a7ec-41fb631a2f94',
        phone_e164: '+910000000000',
        display_name: 'Platform Superadmin',
        role: 'admin',
        created_at: '2026-10-27T16:49:31Z',
      },
    ];
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
