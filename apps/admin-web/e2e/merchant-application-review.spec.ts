import { expect, test } from '@playwright/test';

test('reviews the application, prints the details and approves after evidence is entered', async ({ page }) => {
  const business = {
    id: '054d2805-e92c-4230-9b26-215c22e90ced',
    name: 'Test Grocery',
    category_slug: 'grocery',
    category_name: 'Grocery',
    address_text: '1 Fixture Road',
    locality: 'Kuanpal',
    city: 'Cuttack',
    postal_code: '754204',
    status: 'pending',
    verification_status: 'pending',
    created_at: '2026-11-26T08:00:00Z',
    latitude: 20.551,
    longitude: 86.068,
    time_zone: 'Asia/Kolkata',
    has_storefront_photo: true,
    application: { owner_name: 'Fixture Owner', email: 'owner@example.test', tax_id: 'FIXTURE-GST', no_gst: false, enterprise_type: 'retail', operating_mode: 'both', service_radius_km: 6 },
    hours: [{ weekday: 1, opens_at: '09:00', closes_at: '18:00', is_closed: false }],
  };
  const decisions: string[] = [];
  await page.addInitScript(() => {
    sessionStorage.setItem('admin_access_token', 'browser-fixture');
    window.print = () => { document.body.dataset.printRequested = 'true'; };
  });
  await page.route('**/api/v1/**', async (route) => {
    const { pathname } = new URL(route.request().url());
    if (pathname.endsWith('/storefront')) {
      const image = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jH1sAAAAASUVORK5CYII=';
      await route.fulfill({ contentType: 'image/png', body: Buffer.from(image, 'base64') });
      return;
    }
    let data: unknown = [];
    if (pathname.endsWith('/stats')) data = { active_listings: 0, pending_verifications: 1 };
    if (pathname.endsWith('/trends')) data = { series: [], categories: [] };
    if (pathname.endsWith('/businesses') || pathname.endsWith('/businesses/pending')) data = decisions.includes('approve') ? [] : [business];
    if (pathname.endsWith(`/${business.id}`)) data = business;
    if (pathname.endsWith('/verify') || pathname.endsWith('/approve')) {
      decisions.push(pathname.endsWith('/verify') ? 'verify' : 'approve');
      expect(route.request().postDataJSON().reason).toBe('Offline evidence reviewed: Evidence QA-01');
    }
    await route.fulfill({ json: { data } });
  });

  await page.goto('/admin/dashboard');
  await page.getByRole('button', { name: 'Listing Verification' }).click();
  await page.getByRole('button', { name: 'View details' }).click();
  const drawer = page.getByRole('dialog', { name: 'Merchant application' });
  await expect(drawer.getByText('owner@example.test')).toBeVisible();
  await expect(drawer.getByText('754204')).toBeVisible();
  await expect(drawer.getByText('09:00–18:00')).toBeVisible();
  const photo = drawer.getByRole('img', { name: 'Storefront of Test Grocery' });
  await expect(photo).toBeVisible();
  await expect.poll(() => photo.evaluate((image: HTMLImageElement) => image.naturalWidth)).toBeGreaterThan(0);
  await drawer.getByRole('button', { name: 'Print / Save PDF' }).click();
  await expect(page.locator('body')).toHaveAttribute('data-print-requested', 'true');

  await page.emulateMedia({ media: 'print' });
  await expect(drawer.getByText('FIXTURE-GST')).toBeVisible();
  await expect(photo).toBeVisible();
  await expect(drawer.getByRole('button', { name: 'Verify & approve' })).toBeHidden();
  await expect(page.getByRole('button', { name: 'Listing Verification' })).toBeHidden();
  const pdf = await page.pdf({ format: 'A4' });
  expect(pdf.subarray(0, 5).toString()).toBe('%PDF-');
  expect(pdf.length).toBeGreaterThan(10_000);
  await page.emulateMedia({ media: 'screen' });

  await expect(drawer.getByRole('button', { name: 'Verify & approve' })).toBeDisabled();
  await drawer.getByLabel('Offline evidence reference').fill('Evidence QA-01');
  await drawer.getByRole('button', { name: 'Verify & approve' }).click();
  await expect(drawer).toBeHidden();
  expect(decisions).toEqual(['verify', 'approve']);
});
