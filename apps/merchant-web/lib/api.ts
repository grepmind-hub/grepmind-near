// Same-origin authenticated API client for merchant workspace data.
export interface UploadedMedia {
  id: string;
  purpose: string;
  object_key: string;
  url: string;
  public_url: string;
  content_type: string;
  size_bytes: number;
  original_name: string;
}

export interface RealtimeNotification {
  id: string;
  user_id?: string;
  business_id?: string;
  title: string;
  body: string;
  event_type: string;
  reference_id?: string;
  payload?: Record<string, unknown>;
  is_read: boolean;
  created_at: string;
}

let refreshInFlight: Promise<string | null> | null = null;

export class MerchantApiError extends Error {
  constructor(message: string, public readonly status: number) { super(message); this.name = 'MerchantApiError'; }
}

export function setMerchantTokens(accessToken: string, refreshToken?: string) {
  localStorage.setItem('grepmind_merchant_token', accessToken);
  if (refreshToken) localStorage.setItem('grepmind_merchant_refresh_token', refreshToken);
}

export function clearMerchantTokens() {
  localStorage.removeItem('grepmind_merchant_token');
  localStorage.removeItem('grepmind_merchant_refresh_token');
}

async function refreshAccessToken(): Promise<string | null> {
  if (refreshInFlight) return refreshInFlight;
  const refreshToken = localStorage.getItem('grepmind_merchant_refresh_token');
  if (!refreshToken) return null;
  refreshInFlight = fetch('/api/v1/auth/refresh', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refresh_token: refreshToken }),
  }).then(async (response) => {
    if (!response.ok) throw new Error('Merchant session expired.');
    const json = await response.json();
    const access = json?.data?.access_token;
    const rotated = json?.data?.refresh_token;
    if (!access || !rotated) throw new Error('Session refresh response was incomplete.');
    setMerchantTokens(access, rotated);
    return access as string;
  }).catch(() => {
    clearMerchantTokens();
    return null;
  }).finally(() => { refreshInFlight = null; });
  return refreshInFlight;
}

export async function merchantApi<T = any>(path: string, init: RequestInit = {}, retry = true): Promise<T> {
  const token = localStorage.getItem('grepmind_merchant_token');
  const headers = new Headers(init.headers);
  if (token) headers.set('Authorization', `Bearer ${token}`);
  if (init.body && !(init.body instanceof FormData) && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  const response = await fetch(`/api/v1${path}`, { ...init, headers });
  if (response.status === 401 && retry && !path.startsWith('/auth/')) {
    const next = await refreshAccessToken();
    if (next) return merchantApi<T>(path, init, false);
    if (typeof window !== 'undefined') window.dispatchEvent(new Event('merchant-session-expired'));
  }
  const json = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new MerchantApiError(json?.error?.message || `Request failed (${response.status})`, response.status);
  }
  return json?.data as T;
}

export async function uploadMediaFile(
  file: File,
  purpose: 'storefront' | 'product' | 'service' | 'kyc' | 'avatar' | 'general' = 'product'
): Promise<UploadedMedia> {
  const formData = new FormData();
  formData.append('file', file);
  formData.append('purpose', purpose);
  return merchantApi<UploadedMedia>('/media/upload', { method: 'POST', body: formData });
}

export async function fetchNotifications(businessId?: string): Promise<RealtimeNotification[]> {
  const query = businessId ? `?business_id=${encodeURIComponent(businessId)}` : '';
  return merchantApi<RealtimeNotification[]>(`/notifications${query}`);
}

export async function markNotificationAsRead(id: string): Promise<void> {
  await merchantApi(`/notifications/${encodeURIComponent(id)}/read`, { method: 'POST' });
}

export async function updateServiceRequestStatus(businessId: string, requestId: string, status: string): Promise<void> {
  await merchantApi(`/merchant/businesses/${encodeURIComponent(businessId)}/requests/${encodeURIComponent(requestId)}/status`, {
    method: 'PATCH', body: JSON.stringify({ status }),
  });
}

export async function logoutMerchant(): Promise<void> {
  const refreshToken = localStorage.getItem('grepmind_merchant_refresh_token');
  try {
    await merchantApi('/auth/logout', { method: 'POST', body: JSON.stringify({ refresh_token: refreshToken }) }, false);
  } finally {
    clearMerchantTokens();
  }
}

export interface MerchantProfile {
  id: string; name: string; slug: string; category_slug?: string; category_name?: string;
  description?: string; address_text?: string; locality?: string; city?: string; phone_e164?: string;
  cover_photo_url?: string; status: string; verification_status: string;
  latitude?: number; longitude?: number;
  accepts_requests?: boolean; service_radius_m?: number;
  business_hours?: { weekday: number; opens_at?: string; closes_at?: string; is_closed: boolean }[];
}

export async function fetchMerchantSnapshot(businessId?: string) {
  const suffix = businessId ? `?business_id=${encodeURIComponent(businessId)}` : '';
  const profile = await merchantApi<MerchantProfile>(`/merchant/profile${suffix}`);
  const id = profile.id;
  const [requestResult, products, services, hours, coverage, membersResult, offers] = await Promise.all([
    merchantApi<{ requests?: any[] }>(`/merchant/requests${suffix}`),
    merchantApi<any[]>(`/merchant/products${suffix}`),
    merchantApi<any[]>(`/merchant/services${suffix}`),
    merchantApi<any[]>(`/merchant/operating-hours${suffix}`),
    merchantApi<any>(`/merchant/coverage${suffix}`),
    merchantApi<{ members?: any[] }>(`/merchant/businesses/${encodeURIComponent(id)}/members`),
    merchantApi<any[]>(`/merchant/businesses/${encodeURIComponent(id)}/offers`),
  ]);
  return { profile, requests: requestResult.requests || [], products, services, hours, coverage, members: membersResult.members || [], offers };
}

export async function fetchMerchantBusinesses(): Promise<MerchantProfile[]> {
  return merchantApi<MerchantProfile[]>('/merchant/businesses');
}

export async function saveOperatingHours(businessId: string, hours: { weekday: number; opens_at?: string | null; closes_at?: string | null; is_closed: boolean }[]) {
  await merchantApi(`/merchant/operating-hours?business_id=${encodeURIComponent(businessId)}`, { method: 'PUT', body: JSON.stringify({ hours }) });
}

export async function saveMerchantCoverage(businessId: string, serviceRadiusM: number, acceptsRequests: boolean) {
  await merchantApi(`/merchant/coverage?business_id=${encodeURIComponent(businessId)}`, {
    method: 'PUT', body: JSON.stringify({ service_radius_m: serviceRadiusM, accepts_requests: acceptsRequests }),
  });
}

export async function createMerchantProduct(businessId: string, input: { name: string; description: string; price: number; stock_status: string; is_published: boolean; image_url?: string }) {
  return merchantApi(`/merchant/products?business_id=${encodeURIComponent(businessId)}`, { method: 'POST', body: JSON.stringify(input) });
}

export async function setMerchantProductStock(businessId: string, id: string, status: string) {
  await merchantApi(`/merchant/products/${encodeURIComponent(id)}?business_id=${encodeURIComponent(businessId)}`, { method: 'PATCH', body: JSON.stringify({ stock_status: status }) });
}

export async function updateMerchantProduct(businessId: string, id: string, input: { name: string; description: string; price: number; stock_status: string; is_published: boolean; image_url?: string }) {
  await merchantApi(`/merchant/products/${encodeURIComponent(id)}?business_id=${encodeURIComponent(businessId)}`, { method: 'PATCH', body: JSON.stringify(input) });
}

export async function deleteMerchantProduct(businessId: string, id: string) {
  await merchantApi(`/merchant/products/${encodeURIComponent(id)}?business_id=${encodeURIComponent(businessId)}`, { method: 'DELETE' });
}

export async function createMerchantService(businessId: string, input: { name: string; description: string; indicative_price_min: number; is_active: boolean }) {
  return merchantApi(`/merchant/services?business_id=${encodeURIComponent(businessId)}`, { method: 'POST', body: JSON.stringify(input) });
}

export async function deleteMerchantService(businessId: string, id: string) {
  await merchantApi(`/merchant/services/${encodeURIComponent(id)}?business_id=${encodeURIComponent(businessId)}`, { method: 'DELETE' });
}

export async function updateMerchantService(businessId: string, id: string, input: { name: string; description: string; indicative_price_min: number; is_active: boolean }) {
  await merchantApi(`/merchant/services/${encodeURIComponent(id)}?business_id=${encodeURIComponent(businessId)}`, { method: 'PATCH', body: JSON.stringify(input) });
}

export async function createMerchantOffer(businessId: string, input: { title: string; description: string; starts_at: string; ends_at: string; discount_percent?: number }) {
  return merchantApi(`/merchant/businesses/${encodeURIComponent(businessId)}/offers`, { method: 'POST', body: JSON.stringify(input) });
}

export async function deleteMerchantOffer(id: string) {
  await merchantApi(`/merchant/offers/${encodeURIComponent(id)}`, { method: 'DELETE' });
}

export async function createMerchantTeamMember(businessId: string, input: { phone_e164: string; display_name: string; role: string }) {
  return merchantApi(`/merchant/businesses/${encodeURIComponent(businessId)}/members`, { method: 'POST', body: JSON.stringify(input) });
}

export async function revokeMerchantTeamMember(businessId: string, userId: string) {
  await merchantApi(`/merchant/businesses/${encodeURIComponent(businessId)}/members/${encodeURIComponent(userId)}`, { method: 'DELETE' });
}

export async function createMerchantBusiness(input: Record<string, unknown>) {
  return merchantApi<any>('/merchant/businesses', { method: 'POST', body: JSON.stringify(input) });
}

/** Plays a short, local notification chime after an authenticated SSE event. */
export function playBookingChime() {
  if (typeof window === 'undefined') return;
  try {
    const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
    if (!AudioContextClass) return;
    const ctx = new AudioContextClass();
    [587.33, 880].forEach((frequency, index) => {
      const start = ctx.currentTime + index * 0.12;
      const oscillator = ctx.createOscillator();
      const gain = ctx.createGain();
      oscillator.type = 'sine';
      oscillator.frequency.setValueAtTime(frequency, start);
      gain.gain.setValueAtTime(0.2, start);
      gain.gain.exponentialRampToValueAtTime(0.001, start + 0.38);
      oscillator.connect(gain); gain.connect(ctx.destination);
      oscillator.start(start); oscillator.stop(start + 0.39);
    });
  } catch (_) { /* Audio can be unavailable or blocked by browser policy. */ }
}

export function subscribeToEvents(
  businessId: string,
  onEvent: (event: { type: string; payload?: any; title?: string; body?: string; request_id?: string }) => void
): () => void {
  if (typeof window === 'undefined') return () => {};
  const url = `/api/v1/events?business_id=${encodeURIComponent(businessId)}`;
  const controller = new AbortController();
  let reconnect: ReturnType<typeof setTimeout> | undefined;
  const connect = async () => {
    try {
      const token = localStorage.getItem('grepmind_merchant_token');
      const response = await fetch(url, { headers: token ? { Authorization: `Bearer ${token}` } : {}, signal: controller.signal });
      if (response.status === 401 || response.status === 403) return;
      if (!response.ok || !response.body) throw new Error('Event stream unavailable');
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      while (!controller.signal.aborted) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true }).replace(/\r\n/g, '\n');
        let end: number;
        while ((end = buffer.indexOf('\n\n')) >= 0) {
          const frame = buffer.slice(0, end); buffer = buffer.slice(end + 2);
          const data = frame.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n');
          if (data) { try { const event = JSON.parse(data); if (event.type) onEvent(event); } catch (_) { /* Ignore malformed frames. */ } }
        }
        if (buffer.length > 1024 * 1024) throw new Error('Event frame too large');
      }
    } catch (_) { /* Retry transient network failures. */ }
    if (!controller.signal.aborted) reconnect = setTimeout(connect, 3000);
  };
  void connect();
  return () => { controller.abort(); if (reconnect) clearTimeout(reconnect); };
}
