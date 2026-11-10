import { test, expect } from '@playwright/test';

const businessId = 'qa-fulfillment-business';
const order = (id: string, reference: string) => ({
  id,
  business_id: businessId,
  reference_code: reference,
  status: 'placed',
  vertical: 'food',
  delivery_locality: 'Kuanpal',
  delivery_district: 'Cuttack',
  special_instructions: 'Pack the chutney separately.',
  payment_status: 'not_collected',
  created_at: '2026-11-06T10:00:00Z',
  updated_at: '2026-11-06T10:00:00Z',
  items: [{ product_name: 'QA Biryani', variant_name: 'Regular', unit_label: 'plate', quantity: 2 }],
  status_events: [{ status: 'placed', event_kind: 'status_change', created_at: '2026-11-06T10:00:00Z' }],
});

test.describe('Merchant platform order fulfillment UI', () => {
  test('accepts, prepares, and marks an assigned QA order ready without showing prices', async ({ page }) => {
    const qaOrder = order('qa-order-accept', 'QA-FULFILL-ACCEPT');

    await page.addInitScript(() => {
      localStorage.setItem('grepmind_merchant_token', 'qa-browser-token');
      localStorage.setItem('grepmind_merchant_session', JSON.stringify({
        userId: 'qa-merchant-owner', name: 'QA Merchant', phone: '+919900000001', role: 'owner', token: 'qa-browser-token',
      }));
    });
    await page.route('**/api/v1/**', async route => {
      const url = new URL(route.request().url());
      const path = url.pathname.replace('/api/v1', '');
      if (path === '/events') return route.abort();
      if (path === '/merchant/businesses') return route.fulfill({ json: { data: [{ id: businessId, name: 'QA Kuanpal Partner', slug: 'qa-kuanpal', category_slug: 'restaurant', locality: 'Kuanpal', city: 'Cuttack', status: 'approved', verification_status: 'verified', accepts_requests: true }] } });
      if (path === '/merchant/profile') return route.fulfill({ json: { data: { id: businessId, name: 'QA Kuanpal Partner', slug: 'qa-kuanpal', category_slug: 'restaurant', locality: 'Kuanpal', city: 'Cuttack', status: 'approved', verification_status: 'verified' } } });
      if (path === '/merchant/requests') return route.fulfill({ json: { data: { requests: [] } } });
      if (path === '/merchant/coverage') return route.fulfill({ json: { data: { accepts_requests: true, service_radius_m: 5000 } } });
      if (path === `/merchant/businesses/${businessId}/members`) return route.fulfill({ json: { data: { members: [{ id: 'qa-member', business_id: businessId, user_id: 'qa-merchant-owner', role: 'owner', status: 'active' }] } } });
      if (path === `/merchant/businesses/${businessId}/platform-orders`) return route.fulfill({ json: { data: [qaOrder], meta: { count: 1 } } });
      if (path.startsWith(`/merchant/businesses/${businessId}/platform-orders/`) && route.request().method() === 'POST') {
        const action = path.split('/').pop();
        qaOrder.status = action === 'accept' ? 'accepted' : action === 'prepare' ? 'preparing' : 'ready_for_pickup';
        qaOrder.updated_at = new Date().toISOString();
        qaOrder.status_events.push({ status: qaOrder.status, event_kind: action === 'accept' ? 'partner_accepted' : action === 'prepare' ? 'preparation_started' : 'ready_for_pickup', created_at: qaOrder.updated_at });
        return route.fulfill({ json: { data: qaOrder, meta: { changed: true } } });
      }
      if (path === '/notifications') return route.fulfill({ json: { data: [] } });
      if (path === '/merchant/products' || path === '/merchant/services' || path === '/merchant/operating-hours' || path === `/merchant/businesses/${businessId}/offers`) return route.fulfill({ json: { data: [] } });
      return route.fulfill({ json: { data: [] } });
    });

    await page.goto('', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Workspace overview' })).toBeVisible();
    await page.getByRole('button', { name: /Platform Orders/ }).click();
    await expect(page.locator('#platform-orders-title')).toBeVisible();
    await page.locator('article button').first().click();
    await expect(page.getByText('QA Biryani')).toBeVisible();
    await expect(page.getByText('Pack the chutney separately.')).toBeVisible();
    await expect(page.getByText(/₹|unit price|supply price/i)).toHaveCount(0);
    await expect(page.getByText(/Payment has not been collected/)).toBeVisible();

    await page.getByRole('button', { name: 'Accept order' }).click();
    await expect(page.getByText('Accepted', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Start preparation' }).click();
    await expect(page.getByText('Preparing', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Mark ready for pickup' }).click();
    await expect(page.getByText('Ready for pickup', { exact: true })).toBeVisible();
    await expect(page.getByText(/delivered|delivery is complete/i)).toHaveCount(0);
    await page.screenshot({ path: 'test-results/phase2r4-platform-order-ready.png', fullPage: true });
  });

  test('requires a meaningful rejection reason', async ({ page }) => {
    const qaOrder = order('qa-order-reject', 'QA-FULFILL-REJECT');
    await page.addInitScript(() => {
      localStorage.setItem('grepmind_merchant_token', 'qa-browser-token');
      localStorage.setItem('grepmind_merchant_session', JSON.stringify({ userId: 'qa-merchant-owner', name: 'QA Merchant', phone: '+919900000001', role: 'owner', token: 'qa-browser-token' }));
    });
    await page.route('**/api/v1/**', async route => {
      const path = new URL(route.request().url()).pathname.replace('/api/v1', '');
      if (path === '/events') return route.abort();
      if (path === '/merchant/businesses') return route.fulfill({ json: { data: [{ id: businessId, name: 'QA Kuanpal Partner', slug: 'qa-kuanpal', category_slug: 'restaurant', locality: 'Kuanpal', city: 'Cuttack', status: 'approved', verification_status: 'verified', accepts_requests: true }] } });
      if (path === '/merchant/profile') return route.fulfill({ json: { data: { id: businessId, name: 'QA Kuanpal Partner', slug: 'qa-kuanpal', category_slug: 'restaurant', locality: 'Kuanpal', city: 'Cuttack', status: 'approved', verification_status: 'verified' } } });
      if (path === '/merchant/requests') return route.fulfill({ json: { data: { requests: [] } } });
      if (path === '/merchant/coverage') return route.fulfill({ json: { data: { accepts_requests: true, service_radius_m: 5000 } } });
      if (path === `/merchant/businesses/${businessId}/members`) return route.fulfill({ json: { data: { members: [{ id: 'qa-member', business_id: businessId, user_id: 'qa-merchant-owner', role: 'owner', status: 'active' }] } } });
      if (path === `/merchant/businesses/${businessId}/platform-orders`) return route.fulfill({ json: { data: [qaOrder], meta: { count: 1 } } });
      if (path === '/notifications' || path === '/merchant/products' || path === '/merchant/services' || path === '/merchant/operating-hours' || path === `/merchant/businesses/${businessId}/offers`) return route.fulfill({ json: { data: [] } });
      return route.fulfill({ json: { data: [] } });
    });
    await page.goto('', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Workspace overview' })).toBeVisible();
    await page.getByRole('button', { name: /Platform Orders/ }).click();
    await page.locator('article button').first().click();
    await page.getByRole('button', { name: 'Reject with reason' }).click();
    await expect(page.getByRole('button', { name: 'Confirm rejection' })).toBeDisabled();
    await page.getByLabel('Reason (10–500 characters)').fill('Capacity unavailable today.');
    await expect(page.getByRole('button', { name: 'Confirm rejection' })).toBeEnabled();
  });
});
