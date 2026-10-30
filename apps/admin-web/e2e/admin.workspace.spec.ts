// Admin Web Portal E2E Tests
import { test, expect } from '@playwright/test';

test.describe('Admin Web Portal', () => {
  test('Admin login', async ({ page }) => {
    await page.goto('http://localhost:3000/admin/login');
    
    await page.fill('input[placeholder*="phone"]', '+910000000000');
    await page.click('button:has-text("Send OTP")');
    await page.waitForTimeout(2000);
    
    await page.fill('input[placeholder*="OTP"]', '123456');
    await page.click('button:has-text("Verify")');
    await page.waitForTimeout(2000);
    
    await expect(page).toHaveURL('/admin/dashboard');
    await expect(page.locator('h1')).toContainText('Dashboard');
  });

  test('Admin dashboard loads', async ({ page }) => {
    await page.goto('http://localhost:3000/admin/dashboard');
    
    await expect(page).toHaveURL('/admin/dashboard');
    await expect(page.locator('h1')).toContainText('Dashboard');
  });

  test('Merchant registry', async ({ page }) => {
    await page.goto('http://localhost:3000/admin/merchant-registry');
    
    await expect(page).toHaveURL('/admin/merchant-registry');
    await expect(page.locator('.merchant-table')).toBeVisible();
  });

  test('Reports & Disputes', async ({ page }) => {
    await page.goto('http://localhost:3000/admin/reports');
    
    await expect(page).toHaveURL('/admin/reports');
    await expect(page.locator('.reports-table')).toBeVisible();
  });

  test('Audit Trail', async ({ page }) => {
    await page.goto('http://localhost:3000/admin/audit-logs');
    
    await expect(page).toHaveURL('/admin/audit-logs');
    await expect(page.locator('.audit-table')).toBeVisible();
  });
});
