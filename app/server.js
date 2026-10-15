'use strict';

const express = require('express');
const client = require('prom-client');
const path = require('path');

const PROMETHEUS_URL = process.env.PROMETHEUS_URL || 'http://prometheus:9090';

const buildInfo = {
  version: process.env.APP_VERSION || 'dev',
  commit: process.env.GIT_COMMIT || 'unknown',
  build: process.env.BUILD_NUMBER || 'local',
  image: process.env.IMAGE_TAG || 'n/a',
};

// Run a single instant PromQL query. Resolves to the raw result array, or null on any failure.
async function promQuery(query) {
  try {
    const url = `${PROMETHEUS_URL}/api/v1/query?query=${encodeURIComponent(query)}`;
    const res = await fetch(url, { signal: AbortSignal.timeout(2000) });
    if (!res.ok) return null;
    const body = await res.json();
    return body.status === 'success' ? body.data.result : null;
  } catch {
    return null;
  }
}

function scalar(result) {
  if (!result || result.length === 0) return null;
  const v = parseFloat(result[0].value[1]);
  return Number.isFinite(v) ? v : null;
}

function createApp() {
  const app = express();

  // One registry per app instance keeps tests isolated.
  const register = new client.Registry();
  client.collectDefaultMetrics({ register }); // CPU, memory, event loop, GC, etc.

  const httpRequests = new client.Counter({
    name: 'http_requests_total',
    help: 'Total HTTP requests',
    labelNames: ['method', 'route', 'status_code'],
    registers: [register],
  });
  const httpDuration = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request duration in seconds',
    labelNames: ['method', 'route', 'status_code'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
    registers: [register],
  });
  new client.Gauge({
    name: 'app_build_info',
    help: 'Build metadata (value is always 1)',
    labelNames: ['version', 'commit', 'build'],
    registers: [register],
  }).set({ version: buildInfo.version, commit: buildInfo.commit, build: buildInfo.build }, 1);

  // Request instrumentation. The route label uses the matched route pattern (not the raw URL)
  // so label cardinality stays bounded.
  app.use((req, res, next) => {
    const end = httpDuration.startTimer();
    res.on('finish', () => {
      const route = req.route ? req.baseUrl + req.route.path : 'unmatched';
      const labels = { method: req.method, route, status_code: res.statusCode };
      httpRequests.inc(labels);
      end(labels);
    });
    next();
  });

  app.get('/healthz', (req, res) => res.json({ status: 'ok' }));

  app.get('/api/hello', (req, res) => {
    res.json({ message: 'Hello from the Cloud-Native DevOps platform', ...buildInfo });
  });

  // Demo endpoint so the error-rate panels have something to show.
  app.get('/api/fail', (req, res) => {
    res.status(500).json({ error: 'intentional demo failure' });
  });

  app.get('/api/status', (req, res) => {
    const mem = process.memoryUsage();
    res.json({
      status: 'ok',
      uptimeSeconds: Math.round(process.uptime()),
      node: process.version,
      memory: { rss: mem.rss, heapUsed: mem.heapUsed },
      build: buildInfo,
      timestamp: new Date().toISOString(),
    });
  });

  // Aggregates a few Prometheus queries for the custom dashboard.
  app.get('/api/overview', async (req, res) => {
    const [up, reqRate, p95, errRatio, cpu, mem] = await Promise.all([
      promQuery('up'),
      promQuery('sum(rate(http_requests_total[1m]))'),
      promQuery('histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))'),
      promQuery('sum(rate(http_requests_total{status_code=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))'),
      promQuery('sum(rate(process_cpu_seconds_total{job="node-app"}[1m]))'),
      promQuery('sum(process_resident_memory_bytes{job="node-app"})'),
    ]);

    res.json({
      prometheusReachable: up !== null,
      targets: (up || []).map((r) => ({
        job: r.metric.job,
        instance: r.metric.instance,
        up: r.value[1] === '1',
      })),
      metrics: {
        requestsPerSecond: scalar(reqRate),
        p95LatencySeconds: scalar(p95),
        errorRatio: scalar(errRatio),
        cpuCores: scalar(cpu),
        memoryBytes: scalar(mem),
      },
    });
  });

  app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  app.use(express.static(path.join(__dirname, 'public')));

  return app;
}

module.exports = { createApp };

if (require.main === module) {
  const port = process.env.PORT || 3000;
  const server = createApp().listen(port, () => console.log(`Listening on :${port}`));
  process.on('SIGTERM', () => server.close(() => process.exit(0)));
}
