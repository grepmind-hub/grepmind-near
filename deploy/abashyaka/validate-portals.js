// Execute with Node inside the Admin container on the private application network.
// No authentication bypass, account provisioning, or public requests.
const http = require('node:http');
async function check(url, expected, host) {
  // Use http.request: Node fetch can override the Host header used for vhosts.
  const response = await new Promise((resolve, reject) => {
    const request = http.get(url, { headers: host ? { Host: host } : {} }, result => {
      let body = '';
      result.setEncoding('utf8');
      result.on('data', chunk => { body += chunk; });
      result.on('end', () => resolve({ status: result.statusCode, body }));
      result.on('error', reject);
    });
    request.setTimeout(10000, () => request.destroy(new Error('Request timeout')));
    request.on('error', reject);
  });
  if (response.status !== expected) {
    throw new Error(`${url} (${host || 'direct'}): HTTP ${response.status}, expected ${expected}`);
  }
  const body = response.body;
  console.log(JSON.stringify({url, host: host || 'direct', status: response.status, bytes: body.length}));
  return body;
}
async function main() {
  await check('http://admin:3000/admin/login', 200);
  await check('http://admin:3000/api/v1/categories', 200);
  await check('http://nginx/healthz', 200, 'api.abashyaka.com');
  await check('http://nginx/api/v1/categories', 200, 'api.abashyaka.com');
  await check('http://nginx/api/v1/events', 401, 'api.abashyaka.com');
  await check('http://nginx/api/v1/admin/admins', 401, 'admin.abashyaka.com');
  await check('http://nginx/api/v1/merchant/businesses', 401, 'api.abashyaka.com');
  await check('http://nginx/', 404, 'merchant.abashyaka.com');
  await check('http://nginx/healthz', 404, 'unapproved.invalid');
  for (const [host, path] of [['admin.abashyaka.com', '/admin/login']]) {
    const html = await check('http://nginx' + path, 200, host);
    const scripts = [...html.matchAll(/src="([^" ]*\/_next\/[^" ]+\.js[^" ]*)"/g)];
    if (scripts.length < 2) throw new Error(`Expected Next.js assets for ${host}`);
    for (const asset of scripts.slice(0, 2)) {
      await check('http://nginx' + asset[1], 200, host);
    }
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
