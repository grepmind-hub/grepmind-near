import { createRequire } from 'node:module';

const require = createRequire('/mnt/d/grepmind-near/apps/admin-web/package.json');
const { chromium } = require('@playwright/test');

const origin = process.env.PHASE2E_ADMIN_URL || 'http://localhost:3003';
const phone = '+919990000001';
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
page.setDefaultTimeout(20000);
const observed = [];
page.on('response', async (response) => {
  if (response.url().includes('/media/upload')) observed.push({ status: response.status(), url: response.url() });
});
page.on('console', (message) => { if (message.type() === 'error') observed.push({ console: message.text() }); });

try {
  await page.goto(`${origin}/admin/login`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1200);
  await page.getByLabel('Administrator mobile number').fill(phone);
  if (await page.getByLabel('Administrator mobile number').inputValue() !== phone) throw new Error('Admin phone field did not retain the QA number.');
  await page.waitForTimeout(250);
  await page.getByRole('button', { name: 'Continue securely' }).click();
  const localOtp = await page.getByText(/Local development code:/).innerText();
  const otp = localOtp.match(/\b\d{6}\b/)?.[0];
  if (!otp) throw new Error('QA-only local OTP was not rendered by the login screen.');
  await page.getByLabel('Six-digit verification code').fill(otp);
  await page.getByRole('button', { name: 'Verify and continue' }).click();
  await page.waitForURL(/\/admin\/dashboard/);
  await page.getByRole('button', { name: /Platform Catalog/ }).click();
  await page.getByRole('heading', { name: 'Platform catalog' }).waitFor();
  await page.screenshot({ path: '/mnt/d/grepmind-near/docs/phases/screenshots/phase2e-admin-catalog-empty.png', fullPage: true });
  for (const fixture of [
    { vertical: 'food', city: 'Cuttack', name: 'Phase 2E QA Food Cuttack', sku: 'P2E-QA-FOOD-CTK', variant: 'QA meal pack', vsku: 'P2E-QA-FOOD-CTK-1', unit: '1 pack', price: '149.00' },
    { vertical: 'grocery', city: 'Cuttack', name: 'Phase 2E QA Grocery Cuttack', sku: 'P2E-QA-GROC-CTK', variant: 'QA 1 kg pack', vsku: 'P2E-QA-GROC-CTK-1', unit: '1 kg', price: '89.00' },
    { vertical: 'food', city: 'Jajpur', name: 'Phase 2E QA Food Chhatia', sku: 'P2E-QA-FOOD-JJP', variant: 'QA meal pack', vsku: 'P2E-QA-FOOD-JJP-1', unit: '1 pack', price: '129.00' },
    { vertical: 'grocery', city: 'Jajpur', name: 'Phase 2E QA Grocery Chhatia', sku: 'P2E-QA-GROC-JJP', variant: 'QA 1 L pack', vsku: 'P2E-QA-GROC-JJP-1', unit: '1 L', price: '65.00' },
  ]) {
    const existing = page.getByText(fixture.name, { exact: true });
    if (await existing.count()) {
      const row = existing.first().locator('xpath=../..');
      const activate = row.getByRole('button', { name: 'Activate', exact: true });
      if (await activate.count()) await activate.click();
      continue;
    }
    await page.getByRole('button', { name: 'New product' }).click();
    await page.getByLabel('Product name').fill(fixture.name);
    await page.getByLabel('Product SKU').fill(fixture.sku);
    const categoryOptions = await page.locator('select[name="category"] option').allTextContents();
    const categoryLabel = categoryOptions.find((label) => label.toLowerCase() === `${fixture.vertical} · ${fixture.vertical}`);
    if (!categoryLabel) throw new Error(`Missing ${fixture.vertical} catalog root category.`);
    await page.locator('select[name="category"]').selectOption({ label: categoryLabel });
    await page.getByLabel('Variant name').fill(fixture.variant);
    await page.getByLabel('Variant SKU').fill(fixture.vsku);
    await page.getByLabel('Unit label').fill(fixture.unit);
    await page.getByLabel('Selling price (₹)').fill(fixture.price);
    await page.getByLabel('Availability cities (comma separated)').fill(fixture.city);
    await page.getByLabel('Description').fill('Temporary Phase 2E integration test fixture. Not for sale.');
    if (fixture.vertical === 'food') {
      await page.locator('input[type="file"]').setInputFiles('/mnt/d/grepmind-near/apps/mobile/assets/images/category_sample_atlas.png');
      await page.getByText('Uploading image…').waitFor({ state: 'hidden' });
      await page.waitForFunction(() => document.querySelector('textarea[name="images"]')?.value.includes('/media/'), null, { timeout: 10000 }).catch(async () => {
        throw new Error(`Image upload did not populate the product URL. UI: ${(await page.locator('main').innerText()).slice(0, 1200)}; responses: ${JSON.stringify(observed)}`);
      });
    }
    await page.getByRole('button', { name: 'Save as draft' }).click();
    await page.getByText(fixture.name, { exact: true }).waitFor();
    const row = page.getByText(fixture.name, { exact: true }).locator('xpath=../..');
    await row.getByRole('button', { name: 'Activate', exact: true }).click();
    await page.getByText(fixture.name, { exact: true }).waitFor();
  }
  await page.getByRole('button', { name: 'Partner mapping' }).click();
  for (const mapping of [
    { name: 'Phase 2E QA Food Cuttack', variant: 'QA meal pack', partner: '2e000000-0000-4000-8000-000000000101' },
    { name: 'Phase 2E QA Grocery Cuttack', variant: 'QA 1 kg pack', partner: '2e000000-0000-4000-8000-000000000102' },
    { name: 'Phase 2E QA Food Chhatia', variant: 'QA meal pack', partner: '2e000000-0000-4000-8000-000000000103' },
    { name: 'Phase 2E QA Grocery Chhatia', variant: 'QA 1 L pack', partner: '2e000000-0000-4000-8000-000000000104' },
  ]) {
    const mappingLabel = `${mapping.name} · ${mapping.variant}`;
    if (await page.getByText(mappingLabel, { exact: true }).count()) {
      const existingRow = page.getByText(mappingLabel, { exact: true }).first().locator('xpath=../..');
      const approveExisting = existingRow.getByRole('button', { name: 'Approve', exact: true });
      if (await approveExisting.count()) await approveExisting.click();
      await page.getByText(mappingLabel, { exact: true }).first().locator('xpath=../..').getByText(/approved/i).waitFor();
      continue;
    }
    await page.getByRole('button', { name: 'Map partner' }).click();
    await page.locator('select[name="business"]').selectOption(mapping.partner);
    const options = await page.locator('select[name="product"] option').evaluateAll((items) => items.map((option) => ({ value: option.value, label: option.textContent || '' })));
    const productOption = options.find((option) => option.label.includes(mapping.name));
    if (!productOption) throw new Error(`Missing active product option for ${mapping.name}.`);
    await page.locator('select[name="product"]').selectOption(productOption.value);
    await page.locator('select[name="variant"] option').nth(1).waitFor({ state: 'attached' });
    const variantValue = await page.locator('select[name="variant"] option').nth(1).getAttribute('value');
    if (!variantValue) throw new Error(`Missing active variant for ${mapping.name}.`);
    await page.locator('select[name="variant"]').selectOption(variantValue);
    await page.locator('select[name="mode"]').selectOption('finite');
    await page.locator('input[name="quantity"]').fill('20');
    await page.locator('input[name="preparation"]').fill('15');
    await page.locator('input[name="cost"]').fill('95.00');
    await page.getByRole('button', { name: 'Create pending mapping' }).click();
    await page.getByText(mappingLabel, { exact: true }).waitFor();
    const mappingRow = page.getByText(mappingLabel, { exact: true }).first().locator('xpath=../..');
    await mappingRow.getByRole('button', { name: 'Approve', exact: true }).click();
    await page.getByText(mappingLabel, { exact: true }).first().locator('xpath=../..').getByText(/approved/i).waitFor();
  }
  await page.screenshot({ path: '/mnt/d/grepmind-near/docs/phases/screenshots/phase2e-admin-catalog-fixtures.png', fullPage: true });
  console.log(JSON.stringify({ result: 'admin_login_catalog_upload_and_partner_mapping_ui_passed', qa_skus: ['P2E-QA-FOOD-CTK', 'P2E-QA-GROC-CTK', 'P2E-QA-FOOD-JJP', 'P2E-QA-GROC-JJP'], screenshot: 'docs/phases/screenshots/phase2e-admin-catalog-fixtures.png' }));
} catch (error) {
  await page.screenshot({ path: '/mnt/d/grepmind-near/docs/phases/screenshots/phase2e-admin-catalog-failure.png', fullPage: true }).catch(() => undefined);
  console.error(JSON.stringify({ error: String(error), observed, currentUrl: page.url() }));
  process.exitCode = 1;
} finally {
  await browser.close();
}
