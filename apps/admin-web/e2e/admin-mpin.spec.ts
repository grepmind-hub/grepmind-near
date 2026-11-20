import { expect, test } from '@playwright/test';

test('Admin can enroll a PIN after OTP and use it on a returning visit', async ({ page }) => {
  let enrolled = false;
  let otpRequests = 0;
  const session = { access_token: 'mock-admin-access', refresh_token: 'mock-admin-refresh', user: { roles: ['admin'] } };

  await page.route('**/api/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    switch (path) {
      case '/api/v1/auth/admin-mpin':
        return route.fulfill({ json: { data: { enabled: true, enrolled } } });
      case '/api/v1/auth/otp/request':
        otpRequests++;
        return route.fulfill({ status: 202, json: { data: { challenge_id: 'mock-challenge' } } });
      case '/api/v1/auth/otp/verify':
        return route.fulfill({ json: { data: { ...session, admin_mpin_enrollment_available: true } } });
      case '/api/v1/auth/admin-mpin/enroll':
        expect(route.request().headers().authorization).toBe('Bearer mock-admin-access');
        expect(route.request().postDataJSON()).toEqual({ pin: '726591' });
        enrolled = true;
        return route.fulfill({ status: 204 });
      case '/api/v1/auth/admin-mpin/remove':
        expect(route.request().headers().authorization).toBe('Bearer mock-admin-access');
        enrolled = false;
        return route.fulfill({ status: 204 });
      case '/api/v1/auth/admin-mpin/verify':
        expect(route.request().postDataJSON()).toEqual({ pin: '726591' });
        return route.fulfill({ json: { data: session } });
      case '/api/v1/admin/trends':
        return route.fulfill({ json: { data: { series: [], categories: [] } } });
      default:
        return route.fulfill({ json: { data: [] } });
    }
  });

  await page.goto('/admin/login');
  await page.getByLabel('Administrator mobile number').fill('+919990000174');
  await page.getByRole('button', { name: 'Continue securely' }).click();
  await page.getByLabel('Six-digit verification code').fill('183796');
  const initialVerification = page.waitForResponse((response) => response.url().endsWith('/api/v1/auth/otp/verify'));
  await page.getByRole('button', { name: 'Verify and continue' }).click();
  const verificationResponse = await initialVerification;
  expect(verificationResponse.status()).toBe(200);
  expect((await verificationResponse.json()).data.admin_mpin_enrollment_available).toBe(true);
  await expect(page.getByLabel('New six-digit PIN')).toBeVisible();
  await page.getByLabel('New six-digit PIN').fill('726591');
  await page.getByLabel('Confirm PIN').fill('726592');
  await page.getByRole('button', { name: 'Save PIN' }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'The PINs must match.' })).toBeVisible();
  await page.getByLabel('Confirm PIN').fill('726591');
  await page.getByRole('button', { name: 'Save PIN' }).click();
  await expect(page).toHaveURL(/\/admin\/dashboard$/);

  await page.getByTitle('Sign out of Admin Session').click();
  await expect(page).toHaveURL(/\/admin\/login$/);
  await expect(page.getByRole('button', { name: 'Use OTP instead' })).toBeVisible();
  await page.getByLabel('Six-digit PIN').fill('726591');
  await page.getByRole('button', { name: 'Verify PIN' }).click();
  await expect(page).toHaveURL(/\/admin\/dashboard$/);
  expect(otpRequests).toBe(1);

  await page.getByTitle('Sign out of Admin Session').click();
  await page.getByRole('button', { name: 'Use OTP instead' }).click();
  await page.getByLabel('Administrator mobile number').fill('+919000000001');
  await page.getByRole('button', { name: 'Continue securely' }).click();
  await page.getByLabel('Six-digit verification code').fill('183796');
  await page.getByRole('button', { name: 'Verify and continue' }).click();
  await page.getByRole('button', { name: 'Remove browser PIN' }).click();
  await expect(page.getByLabel('Administrator mobile number')).toBeVisible();
});
