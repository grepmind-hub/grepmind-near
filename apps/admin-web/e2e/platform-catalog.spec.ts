import { expect, test } from '@playwright/test';
import { readQaOtp } from './qa-otp';

test('Admin manages Food/Grocery products and an eligible partner mapping', async ({ page, request }) => {
  test.setTimeout(120_000);
  const adminPhone = process.env.E2E_ADMIN_PHONE_E164;
  test.skip(!adminPhone, 'Set E2E_ADMIN_PHONE_E164 to the local development root-admin fixture.');

  const unauthorized = await request.get('/api/v1/admin/catalog/products');
  expect(unauthorized.status(), 'catalog operations require an authenticated admin').toBe(401);

  await page.goto('/admin/login');
  await page.getByLabel('Administrator mobile number').fill(adminPhone!);
  const otpRequest = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Continue securely' }).click();
  const otpResponse = await otpRequest;
  expect(otpResponse.status()).toBe(202);
  const payload = (await otpResponse.json())?.data;
  expect(payload?.otp_code).toBeUndefined();
  await page.getByLabel('Six-digit verification code').fill(await readQaOtp(payload.challenge_id, adminPhone!, payload.expires_at));
  const verification = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/verify') && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Verify and continue' }).click();
  expect((await verification).status()).toBe(200);
  await expect(page).toHaveURL(/\/admin\/dashboard$/);

  await page.getByRole('button', { name: /Platform Catalog/ }).click();
  await expect(page.getByRole('heading', { name: 'Platform catalog' })).toBeVisible();
  await expect(page.getByText('Loading live catalog…')).toHaveCount(0);
  await expect(page.getByText('Catalog data could not be loaded. Check the Admin API connection and retry.')).toHaveCount(0);
  await page.screenshot({ path: 'test-results/phase2r1-admin-catalog.png', fullPage: true });

  const marker = `${Date.now()}`;
  const foodName = `QA Food ${marker}`;
  const foodSKU = `QA-FOOD-${marker}`;
  await page.getByRole('button', { name: 'New product' }).click();
  await page.getByLabel('Product name').fill(foodName);
  await page.getByLabel('Product SKU').fill(foodSKU);
  await page.getByLabel('Food / Grocery category').selectOption({ label: 'food · Food' });
  await page.getByLabel('Variant name').fill('Single pack');
  await page.getByLabel('Variant SKU').fill(`${foodSKU}-EACH`);
  await page.getByLabel('Unit label').fill('each');
  await page.getByLabel('Selling price (₹)').fill('24.50');
  await page.getByLabel('Availability cities (comma separated)').fill('Cuttack, Jajpur');
  await page.getByLabel('Description').fill('Temporary Food catalog acceptance fixture.');
  await page.getByRole('button', { name: 'Save as draft' }).click();
  const foodRow = page.getByText(foodName, { exact: true }).locator('xpath=../..');
  await expect(foodRow).toBeVisible();
  await foodRow.getByRole('button', { name: 'Activate' }).click();
  await expect(foodRow.getByText('active')).toBeVisible();
  await foodRow.getByRole('button', { name: 'Edit', exact: true }).last().click();
  await page.getByLabel('Description').fill('Edited through the Admin catalog workflow.');
  await page.getByLabel('Selling price (₹)').fill('29.75');
  await page.getByRole('button', { name: 'Save changes' }).click();
  await expect(foodRow.getByText('₹29.75', { exact: false }).first()).toBeVisible();

  const groceryName = `QA Grocery ${marker}`;
  const grocerySKU = `QA-GROCERY-${marker}`;
  await page.getByRole('button', { name: 'New product' }).click();
  await page.getByLabel('Product name').fill(groceryName);
  await page.getByLabel('Product SKU').fill(grocerySKU);
  await page.getByLabel('Food / Grocery category').selectOption({ label: 'grocery · Grocery' });
  await page.getByLabel('Variant name').fill('1 kg');
  await page.getByLabel('Variant SKU').fill(`${grocerySKU}-1KG`);
  await page.getByLabel('Unit label').fill('1 kg');
  await page.getByLabel('Selling price (₹)').fill('82.00');
  await page.getByLabel('Availability cities (comma separated)').fill('Cuttack, Jajpur');
  await page.getByLabel('Description').fill('Temporary Grocery catalog acceptance fixture.');
  await page.getByRole('button', { name: 'Save as draft' }).click();
  const groceryRow = page.getByText(groceryName, { exact: true }).locator('xpath=../..');
  await expect(groceryRow).toBeVisible();
  await groceryRow.getByRole('button', { name: 'Activate' }).click();

  const search = page.getByRole('textbox', { name: 'Search catalog' });
  await search.fill(grocerySKU);
  await expect(page.getByText(groceryName, { exact: true })).toBeVisible();
  await expect(page.getByText(foodName, { exact: true })).toHaveCount(0);
  await search.clear();
  await page.screenshot({ path: 'test-results/phase2r1-admin-catalog.png', fullPage: true });

  await page.getByRole('button', { name: 'Partner mapping' }).click();
  const coveragePartnerSelect = page.getByLabel('Coverage partner');
  const partnerOptions = await coveragePartnerSelect.locator('option').evaluateAll((options) =>
    options.map((option) => ({ value: (option as HTMLOptionElement).value, label: option.textContent ?? '' }))
      .filter((option) => option.value && /· (Cuttack|Jajpur)$/i.test(option.label)));
  expect(partnerOptions.length, 'a verified Cuttack/Jajpur partner must exist in the cloned local dataset').toBeGreaterThan(0);
  const partner = partnerOptions[0];
  const partnerCity = partner.label.endsWith('Jajpur') ? 'Jajpur' : 'Cuttack';
  const selectCoveragePartner = async () => {
    const response = page.waitForResponse((item) => item.url().includes(`/admin/catalog/partners/${partner.value}/coverage`) && item.request().method() === 'GET');
    await coveragePartnerSelect.selectOption(partner.value);
    await response;
  };
  await selectCoveragePartner();
  await page.getByLabel('Coverage city').selectOption(partnerCity);
  if (await page.getByRole('button', { name: 'Deactivate coverage' }).count() === 0) {
    await page.getByRole('button', { name: 'Add coverage' }).click();
  }
  await expect(page.getByRole('button', { name: 'Deactivate coverage' })).toBeVisible();

  await page.getByRole('button', { name: 'Map partner' }).click();
  const businessSelect = page.locator('select[name="business"]');
  await businessSelect.selectOption(partner.value);
  await page.locator('select[name="product"]').selectOption({ label: `${groceryName} · grocery` });
  await page.locator('select[name="variant"]').selectOption({ label: '1 kg · ₹82.00' });
  await page.locator('select[name="mode"]').selectOption('finite');
  await page.locator('input[name="quantity"]').fill('16');
  await page.locator('input[name="preparation"]').fill('20');
  await page.locator('input[name="cost"]').fill('55.00');
  await page.getByRole('button', { name: 'Create pending mapping' }).click();
  const mappingRow = page.getByText(`${groceryName} · 1 kg`, { exact: true }).locator('xpath=../..');
  await expect(mappingRow.getByText('pending')).toBeVisible();
  await mappingRow.getByRole('button', { name: 'Approve' }).click();
  await expect(mappingRow.getByText('approved')).toBeVisible();
  await expect(mappingRow.getByText(/Partner cost ₹55\.00/)).toBeVisible();
  await page.screenshot({ path: 'test-results/phase2r1-admin-partner-mapping.png', fullPage: true });

  await page.getByRole('button', { name: 'products', exact: true }).click();
  const finalFoodRow = page.getByText(foodName, { exact: true }).locator('xpath=../..');
  await finalFoodRow.getByRole('button', { name: 'Deactivate' }).click();
  await expect(finalFoodRow.getByText('inactive')).toBeVisible();
});
