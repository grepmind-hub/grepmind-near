import { test, expect } from '@playwright/test';

test.describe('Merchant Portal entry and authentication', () => {
  test('renders OTP login without demo credentials or fake account shortcuts', async ({ page }) => {
    await page.goto('');

    await expect(page.getByRole('heading', { name: 'Sign in to your Merchant Workspace' })).toBeVisible();
    await expect(page.getByPlaceholder('+91 98765 43210')).toBeVisible();
    await expect(page.getByRole('button', { name: /Get Verification Code/i })).toBeVisible();
    await expect(page.getByText(/Demo account|Sample merchant|123456/)).toHaveCount(0);
  });

  test('does not expose the merchant workspace without a valid session', async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.removeItem('grepmind_merchant_session');
      localStorage.removeItem('grepmind_merchant_token');
      localStorage.removeItem('grepmind_merchant_refresh_token');
    });
    await page.goto('');

    await expect(page.getByRole('heading', { name: 'Sign in to your Merchant Workspace' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Workspace overview' })).toHaveCount(0);
  });

  test('API proxy requires authentication for the merchant business directory', async ({ page }) => {
    await page.goto('');
    const status = await page.evaluate(async () => {
      const response = await fetch('/api/v1/merchant/businesses');
      return response.status;
    });
    expect(status).toBe(401);
  });
});
