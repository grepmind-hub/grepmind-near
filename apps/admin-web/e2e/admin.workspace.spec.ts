// Admin Web Portal E2E Tests
import { test, expect } from '@playwright/test';

test.describe('Admin Web Portal access boundaries', () => {
  test('login offers the existing OTP flow without demo credentials', async ({ page }) => {
    await page.goto('/admin/login');
    await expect(page.getByRole('heading', { name: 'Admin sign in' })).toBeVisible();
    await expect(page.getByLabel('Administrator mobile number')).toBeVisible();
    await expect(page.getByText(/development code/i)).toHaveCount(0);
  });

  test('dashboard redirects unauthenticated visitors to OTP sign in', async ({ page }) => {
    await page.goto('/admin/dashboard');
    await expect(page).toHaveURL(/\/admin\/login$/);
    await expect(page.getByRole('heading', { name: 'Admin sign in' })).toBeVisible();
  });

  test('local admin signs in, loads protected data, and signs out', async ({ page }) => {
    const adminPhone = process.env.E2E_ADMIN_PHONE_E164;
    test.skip(!adminPhone, 'Set E2E_ADMIN_PHONE_E164 to the local development admin fixture.');

    await page.goto('/admin/login');
    const otpRequest = page.waitForResponse((response) =>
      response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST',
    );
    await page.getByLabel('Administrator mobile number').fill(adminPhone!);
    await page.getByRole('button', { name: 'Continue securely' }).click();

    const otpResponse = await otpRequest;
    expect(otpResponse.status()).toBe(202);
    const otpPayload = await otpResponse.json();
    const localDevelopmentCode = otpPayload?.data?.otp_code;
    expect(localDevelopmentCode).toMatch(/^\d{6}$/);

    const otpInput = page.getByLabel('Six-digit verification code');
    await otpInput.fill(localDevelopmentCode);
    expect(await otpInput.evaluate((element) => (element as HTMLInputElement).value.length)).toBe(6);
    const verifyButton = page.getByRole('button', { name: 'Verify and continue' });
    await expect(verifyButton).toBeEnabled();
    const statsRequest = page.waitForResponse((response) =>
      response.url().includes('/api/v1/admin/stats') && response.request().method() === 'GET',
    );
    const trendsRequest = page.waitForResponse((response) =>
      response.url().includes('/api/v1/admin/trends') && response.request().method() === 'GET',
    );
    const listingActivityRequest = page.waitForResponse((response) =>
      response.url().includes('/api/v1/admin/listing-activity') && response.request().method() === 'GET',
    );
    const userAccessRequest = page.waitForResponse((response) =>
      response.url().includes('/api/v1/admin/user-access') && response.request().method() === 'GET',
    );
    let accessTokenForCleanup: string | null = null;
    try {
      const verifyResponsePromise = page.waitForResponse((response) =>
        response.url().endsWith('/auth/otp/verify') && response.request().method() === 'POST',
      );
      await verifyButton.click();
      const verifyResponse = await verifyResponsePromise;
      expect(verifyResponse.status()).toBe(200);
      accessTokenForCleanup = (await verifyResponse.json())?.data?.access_token ?? null;
      expect(accessTokenForCleanup).toBeTruthy();

      await expect(page).toHaveURL(/\/admin\/dashboard$/);
      const statsResponse = await statsRequest;
      const activityResponse = await listingActivityRequest;
      const accessResponse = await userAccessRequest;
      expect(statsResponse.status(), 'admin stats API').toBe(200);
      const trendsResponse = await trendsRequest;
      expect(trendsResponse.status(), 'admin trends API').toBe(200);
      expect(activityResponse.status(), 'listing activity API').toBe(200);
      expect(accessResponse.status(), 'user access API').toBe(200);
      await expect(page.getByText('Executive command center')).toBeVisible();
      await expect(page.getByText('Trend intelligence')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'New listings' })).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Service requests' })).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Customer orders' })).toBeVisible();
      await expect(page.getByRole('link', { name: /Open Merchant Portal/ })).toHaveAttribute('href', 'http://localhost:3001/');
      await expect(page.getByText('Live platform data could not be loaded. Check the API connection and refresh.')).toHaveCount(0);

      const adminSections = [
        { navigation: 'Listing Verification', heading: 'Listing verification' },
        { navigation: 'Merchant Registry', heading: 'Platform Merchant Registry' },
        { navigation: 'Reports & Disputes', heading: 'Consumer Reports & Disputes' },
        { navigation: 'Offers & Promos', heading: 'Promotions & Offer Moderation' },
        { navigation: 'Audit Trail', heading: 'Platform Audit Trail' },
        { navigation: 'Listing Activity', heading: 'Team listing activity' },
        { navigation: 'Admins & Access', heading: 'Platform Administrators & Permissions' },
      ];
      for (const section of adminSections) {
        await page.getByRole('button', { name: new RegExp(section.navigation) }).click();
        await expect(page.getByRole('heading', { name: section.heading })).toBeVisible();
      }

      await expect(page.getByRole('heading', { name: 'User access control' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Add account access' })).toBeEnabled();

      await page.getByRole('button', { name: /Ownership claims/ }).click();
      await expect(page).toHaveURL(/\/admin\/dashboard\/businesses$/);
      await expect(page.getByRole('heading', { name: 'Ownership claims' })).toBeVisible();
      await expect(page.getByRole('button', { name: /Dashboard/ })).toBeVisible();
      await page.getByRole('button', { name: /Dashboard/ }).click();
      await expect(page).toHaveURL(/\/admin\/dashboard$/);
      await expect(page.getByText('Executive command center')).toBeVisible();

      const logoutRequest = page.waitForResponse((response) =>
        response.url().endsWith('/auth/logout') && response.request().method() === 'POST',
      );
      await page.getByTitle('Sign out of Admin Session').click();
      expect((await logoutRequest).status()).toBe(200);
      accessTokenForCleanup = null;
      await expect(page).toHaveURL(/\/admin\/login$/);
      expect(await page.evaluate(() => sessionStorage.getItem('admin_access_token'))).toBeNull();
      expect(await page.evaluate(() => sessionStorage.getItem('admin_refresh_token'))).toBeNull();
    } finally {
      if (accessTokenForCleanup) {
        const cleanupStatus = await page.evaluate(async (token) => {
          const response = await fetch('/api/v1/auth/logout', {
            method: 'POST',
            headers: { Authorization: `Bearer ${token}` },
          });
          sessionStorage.removeItem('admin_access_token');
          sessionStorage.removeItem('admin_refresh_token');
          return response.status;
        }, accessTokenForCleanup).catch(() => 0);
        if (cleanupStatus !== 200) throw new Error(`Could not revoke E2E session (HTTP ${cleanupStatus}).`);
      }
    }
  });
});
