import axios, { AxiosInstance } from 'axios'

const baseURL = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8080/api/v1'

export const api: AxiosInstance = axios.create({
  baseURL,
  headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
})

export function setAuthToken(token: string | null) {
  if (token) {
    api.defaults.headers.common['Authorization'] = `Bearer ${token}`
  } else {
    delete api.defaults.headers.common['Authorization']
  }
}

export interface Paged<T> {
  data: T[]
  meta: { request_id: string; [key: string]: unknown }
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
  is_open_now?: boolean
  distance_m?: number
  cover_photo_url?: string
}

export interface Report {
  id: string
  target_type: string
  target_id: string
  reason: string
  status: string
  created_at: string
  reporter_user_id?: string
}

export interface AuditLog {
  id: string
  action: string
  target_type: string
  target_id: string
  reason?: string
  created_at: string
  actor_user_id?: string
}
