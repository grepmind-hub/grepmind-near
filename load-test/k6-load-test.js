import http from 'k6/http';
import { sleep, check } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 10 },
    { duration: '5m', target: 50 },
    { duration: '10m', target: 100 },
    { duration: '5m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'],
    http_req_failed: ['rate<0.01'],
  },
};

const API_BASE = __ENV.API_BASE_URL || 'http://localhost:8080';

export default function () {
  // Test business search endpoint
  const searchRes = http.get(`${API_BASE}/api/v1/businesses?lat=20.2961&lng=85.8245&radius_m=5000`);
  check(searchRes, {
    'search status is 200': (r) => r.status === 200,
    'search response time < 2s': (r) => r.timings.duration < 2000,
  });

  sleep(1);

  // Test business detail endpoint
  const bizRes = http.get(`${API_BASE}/api/v1/businesses/test-biz-id`);
  check(bizRes, {
    'business detail status is 200 or 404': (r) => r.status === 200 || r.status === 404,
  });

  sleep(1);

  // Test categories endpoint
  const catRes = http.get(`${API_BASE}/api/v1/categories`);
  check(catRes, {
    'categories status is 200': (r) => r.status === 200,
  });

  sleep(1);
}
