import http from 'k6/http';
import { sleep } from 'k6';

const paths = [
  { path: '/', weight: 43 },
  { path: '/about', weight: 30 },
  { path: '/contact', weight: 17 },
  { path: '/login', weight: 10 },
];

const targetUrl = __ENV.TARGET_URL || 'http://flask-app.aws-selfhosted.com';
const virtualUsers = __ENV.VUS || 40;

function getRandomPath() {
  const totalWeight = paths.reduce((sum, p) => sum + p.weight, 0);
  let r = Math.random() * totalWeight;
  for (const p of paths) {
    if (r < p.weight) {
      return p.path;
    }
    r -= p.weight;
  }
}

function getRandomSleep() {
  return Math.random() * 1.5 + 0.5;
}

export const options = {
  stages: [
    { duration: '1m', target: virtualUsers },
    { duration: '5m', target: virtualUsers },
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000'],
    'http_req_failed': ['rate<0.05'],
  },
};

export default function () {
  const path = getRandomPath();
  const url = `${targetUrl}${path}`;
  
  http.get(url);
  sleep(getRandomSleep());
}
