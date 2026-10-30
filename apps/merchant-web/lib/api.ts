// apps/merchant-web/lib/api.ts
// Direct Media, Notifications & Real-Time API client for Merchant Web Portal

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
  payload?: any;
  is_read: boolean;
  created_at: string;
}

/**
 * Upload an image file directly to MinIO via the Go backend and Nginx reverse proxy.
 */
export async function uploadMediaFile(
  file: File,
  purpose: 'storefront' | 'product' | 'service' | 'kyc' | 'avatar' | 'general' = 'product'
): Promise<UploadedMedia> {
  const formData = new FormData();
  formData.append('file', file);
  formData.append('purpose', purpose);

  // Use same-origin /api/v1 to route through Nginx without CORS blocks
  const res = await fetch('/api/v1/media/upload', {
    method: 'POST',
    body: formData,
  });

  if (!res.ok) {
    const errorBody = await res.json().catch(() => ({}));
    throw new Error(errorBody?.error?.message || `Upload failed with status ${res.status}`);
  }

  const json = await res.json();
  return json.data as UploadedMedia;
}

/**
 * Update service booking status via backend API.
 */
export async function updateServiceRequestStatus(
  businessId: string,
  requestId: string,
  status: string
): Promise<void> {
  const token = typeof window !== 'undefined' ? localStorage.getItem('grepmind_merchant_token') : null;
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const res = await fetch(`/api/v1/merchant/businesses/${businessId}/requests/${requestId}/status`, {
    method: 'PATCH',
    headers,
    body: JSON.stringify({ status }),
  });

  if (!res.ok) {
    // Fallback to legacy endpoint if business-scoped path fails
    await fetch(`/api/v1/merchant/requests/${requestId}/status`, {
      method: 'PATCH',
      headers,
      body: JSON.stringify({ status }),
    });
  }
}

/**
 * Fetch persistent notifications for store.
 */
export async function fetchNotifications(businessId?: string): Promise<RealtimeNotification[]> {
  const url = businessId
    ? `/api/v1/notifications?business_id=${businessId}`
    : `/api/v1/notifications`;
  const res = await fetch(url);
  if (!res.ok) return [];
  const json = await res.json();
  return (json.data || []) as RealtimeNotification[];
}

/**
 * Mark notification as read.
 */
export async function markNotificationAsRead(id: string): Promise<void> {
  await fetch(`/api/v1/notifications/${id}/read`, { method: 'POST' });
}

/**
 * Plays a pleasant synthetic dual-tone chime on new service request.
 */
export function playBookingChime() {
  if (typeof window === 'undefined') return;
  try {
    const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
    if (!AudioContextClass) return;
    const ctx = new AudioContextClass();
    
    // First chime tone (D5 - 587.33 Hz)
    const osc1 = ctx.createOscillator();
    const gain1 = ctx.createGain();
    osc1.type = 'sine';
    osc1.frequency.setValueAtTime(587.33, ctx.currentTime);
    gain1.gain.setValueAtTime(0.25, ctx.currentTime);
    gain1.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.35);
    osc1.connect(gain1);
    gain1.connect(ctx.destination);
    osc1.start();
    osc1.stop(ctx.currentTime + 0.36);

    // Second harmonious tone (A5 - 880 Hz)
    const osc2 = ctx.createOscillator();
    const gain2 = ctx.createGain();
    osc2.type = 'sine';
    osc2.frequency.setValueAtTime(880, ctx.currentTime + 0.12);
    gain2.gain.setValueAtTime(0.3, ctx.currentTime + 0.12);
    gain2.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.55);
    osc2.connect(gain2);
    gain2.connect(ctx.destination);
    osc2.start(ctx.currentTime + 0.12);
    osc2.stop(ctx.currentTime + 0.56);
  } catch (_) {}
}

/**
 * Subscribe to real-time Server-Sent Events (SSE).
 */
export function subscribeToEvents(
  businessId: string,
  onEvent: (event: { type: string; payload?: any; title?: string; body?: string; request_id?: string }) => void
): () => void {
  if (typeof window === 'undefined') return () => {};

  const url = `/api/v1/events?business_id=${encodeURIComponent(businessId)}`;
  const eventSource = new EventSource(url);

  eventSource.addEventListener('service_request.created', (e: MessageEvent) => {
    try {
      const data = JSON.parse(e.data);
      onEvent({ type: 'service_request.created', ...data });
    } catch (_) {}
  });

  eventSource.addEventListener('service_request.status_updated', (e: MessageEvent) => {
    try {
      const data = JSON.parse(e.data);
      onEvent({ type: 'service_request.status_updated', ...data });
    } catch (_) {}
  });

  eventSource.addEventListener('notification.created', (e: MessageEvent) => {
    try {
      const data = JSON.parse(e.data);
      onEvent({ type: 'notification.created', ...data });
    } catch (_) {}
  });

  eventSource.onerror = () => {
    // Auto-reconnect handled natively by EventSource
  };

  return () => {
    eventSource.close();
  };
}
