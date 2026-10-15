'use strict';

const test = require('node:test');
const assert = require('node:assert');

// Point Prometheus at a closed port so /api/overview exercises the "unreachable" path.
// Must be set before server.js is loaded because it reads the env at require time.
process.env.PROMETHEUS_URL = 'http://127.0.0.1:9';
const { createApp } = require('../server');

let server;
let base;

test.before(async () => {
  await new Promise((resolve) => {
    server = createApp().listen(0, () => {
      base = `http://127.0.0.1:${server.address().port}`;
      resolve();
    });
  });
});

test.after(() => server.close());

test('GET /healthz returns ok', async () => {
  const res = await fetch(`${base}/healthz`);
  assert.strictEqual(res.status, 200);
  assert.deepStrictEqual(await res.json(), { status: 'ok' });
});

test('GET /api/status returns uptime and build info', async () => {
  const body = await (await fetch(`${base}/api/status`)).json();
  assert.strictEqual(body.status, 'ok');
  assert.ok(body.uptimeSeconds >= 0);
  assert.ok(body.build.version);
});

test('GET /metrics exposes Prometheus metrics including request counters', async () => {
  await fetch(`${base}/api/hello`);
  await fetch(`${base}/api/fail`);
  const text = await (await fetch(`${base}/metrics`)).text();
  assert.match(text, /process_cpu_seconds_total/);
  assert.match(text, /process_resident_memory_bytes/);
  assert.match(text, /http_requests_total\{method="GET",route="\/api\/hello",status_code="200"\} 1/);
  assert.match(text, /http_requests_total\{method="GET",route="\/api\/fail",status_code="500"\} 1/);
  assert.match(text, /http_request_duration_seconds_bucket/);
  assert.match(text, /app_build_info/);
});

test('GET /api/overview degrades gracefully when Prometheus is unreachable', async () => {
  const res = await fetch(`${base}/api/overview`);
  assert.strictEqual(res.status, 200);
  const body = await res.json();
  assert.strictEqual(body.prometheusReachable, false);
  assert.deepStrictEqual(body.targets, []);
  assert.strictEqual(body.metrics.requestsPerSecond, null);
});

test('GET / serves the custom dashboard', async () => {
  const res = await fetch(`${base}/`);
  assert.strictEqual(res.status, 200);
  assert.match(await res.text(), /Monitoring Dashboard/);
});
