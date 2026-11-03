// Admin Web Portal E2E Tests
import { test, expect } from '@playwright/test';

test.describe('Admin Web Portal access boundaries', () => {
  test('login offers the existing OTP flow without demo credentials', async ({ page }) => {
    await page.goto('/login');
    await expect(page.getByRole('heading', { name: 'Admin sign in' })).toBeVisible();
    await expect(page.getByLabel('Administrator mobile number')).toBeVisible();
    await expect(page.getByText(/development code/i)).toHaveCount(0);
  });

  test('dashboard redirects unauthenticated visitors to OTP sign in', async ({ page }) => {
    await page.goto('/dashboard');
    await expect(page).toHaveURL(/\/login$/);
    await expect(page.getByRole('heading', { name: 'Admin sign in' })).toBeVisible();
  });
});
