import axios, { AxiosInstance } from 'axios'

const baseURL = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8080/api/v1'

export const api: AxiosInstance = axios.create({
  baseURL,
  headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
})

// Auto-attach stored token in browser environments
if (typeof window !== 'undefined') {
  const token = localStorage.getItem('admin_token')
  if (token) {
    api.defaults.headers.common['Authorization'] = `Bearer ${token}`
  }
}

export function setAuthToken(token: string | null) {
  if (token) {
    api.defaults.headers.common['Authorization'] = `Bearer ${token}`
    if (typeof window !== 'undefined') {
      localStorage.setItem('admin_token', token)
    }
  } else {
    delete api.defaults.headers.common['Authorization']
    if (typeof window !== 'undefined') {
      localStorage.removeItem('admin_token')
    }
  }
}

export interface Paged<T> {
  data: T[]
  meta: { request_id: string; [key: string]: unknown }
}

export interface Stats {
  pending_verifications: number
  reported_listings: number
  pending_offers: number
  active_listings: number
}

export interface Business {
  id: string
  name: string
  slug?: string
  category_slug: string
  category_name?: string
  address_text: string
  city?: string
  status: string
  verification_status: string
  phone_e164?: string
  owner_phone?: string
  created_at: string
}

export interface Report {
  id: string
  reporter_phone?: string
  target_type: string
  target_id: string
  target_name?: string
  reason: string
  status: string
  created_at: string
  resolved_at?: string
  resolution_reason?: string
}

export interface Offer {
  id: string
  business_id: string
  business_name: string
  title: string
  description?: string
  starts_at: string
  ends_at: string
  status: string
  discount_percent?: number
}

export interface AuditLog {
  id: string
  actor_phone?: string
  action: string
  target_type: string
  target_id: string
  reason?: string
  created_at: string
}

// ---------- API client methods ----------

export async function getStats(): Promise<Stats> {
  const res = await api.get<{ data: Stats }>('/admin/stats')
  return res.data.data
}

export async function getPendingBusinesses(): Promise<Business[]> {
  const res = await api.get<{ data: Business[] }>('/admin/businesses/pending')
  return res.data.data ?? []
}

export async function getAllBusinesses(status?: string): Promise<Business[]> {
  const params = status && status !== 'all' ? { status } : {}
  const res = await api.get<{ data: Business[] }>('/admin/businesses', { params })
  return res.data.data ?? []
}

export async function approveBusiness(id: string, reason?: string) {
  const res = await api.post(`/admin/businesses/${id}/approve`, { reason })
  return res.data
}

export async function rejectBusiness(id: string, reason: string) {
  const res = await api.post(`/admin/businesses/${id}/reject`, { reason })
  return res.data
}

export async function verifyBusiness(id: string, verification_status: 'verified' | 'rejected', reason?: string) {
  const res = await api.post(`/admin/businesses/${id}/verify`, { verification_status, reason })
  return res.data
}

export async function getReports(status?: string): Promise<Report[]> {
  const params = status && status !== 'all' ? { status } : {}
  const res = await api.get<{ data: Report[] }>('/admin/reports', { params })
  return res.data.data ?? []
}

export async function resolveReport(id: string, resolution: 'action_taken' | 'dismissed', reason?: string) {
  const res = await api.post(`/admin/reports/${id}/resolve`, { resolution, reason })
  return res.data
}

export async function getOffers(status?: string): Promise<Offer[]> {
  const params = status && status !== 'all' ? { status } : {}
  const res = await api.get<{ data: Offer[] }>('/admin/offers', { params })
  return res.data.data ?? []
}

export async function approveOffer(id: string) {
  const res = await api.post(`/admin/offers/${id}/approve`)
  return res.data
}

export async function rejectOffer(id: string) {
  const res = await api.post(`/admin/offers/${id}/reject`)
  return res.data
}

export async function getAuditLogs(): Promise<AuditLog[]> {
  const res = await api.get<{ data: AuditLog[] }>('/admin/audit-logs')
  return res.data.data ?? []
}
