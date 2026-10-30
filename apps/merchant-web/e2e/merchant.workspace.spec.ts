// Merchant Web Portal E2E Tests
import { test, expect } from '@playwright/test';

test.describe('Merchant Web Portal', () => {
  test('Merchant login flow', async ({ page }) => {
    await page.goto('http://localhost:3000/auth/login');
    
    // Enter phone number
    await page.fill('input[placeholder*="phone"]', '+919876543210');
    
    // Send OTP
    await page.click('button:has-text("Send OTP")');
    await page.waitForTimeout(2000);
    
    // Enter OTP
    await page.fill('input[placeholder*="OTP"]', '123456');
    
    // Verify OTP
    await page.click('button:has-text("Verify")');
    await page.waitForTimeout(2000);
    
    // Verify dashboard loads
    await expect(page).toHaveURL('/dashboard');
    await expect(page.locator('h1')).toContainText('Dashboard');
  });

  test('Merchant dashboard loads', async ({ page }) => {
    await page.goto('http://localhost:3000/dashboard');
    
    await expect(page).toHaveURL('/dashboard');
    await expect(page.locator('h1')).toContainText('Dashboard');
    await expect(page.locator('.request-table')).toBeVisible();
  });

  test('Service request management', async ({ page }) => {
    await page.goto('http://localhost:3000/merchant/requests');
    
    await expect(page).toHaveURL('/merchant/requests');
    
    // Verify request table loads
    await expect(page.locator('.request-table')).toBeVisible();
  });

  test('Catalog management', async ({ page }) => {
    await page.goto('http://localhost:3000/merchant/catalog');
    
    await expect(page).toHaveURL('/merchant/catalog');
    await expect(page.locator('.catalog-table')).toBeVisible();
  });
});
