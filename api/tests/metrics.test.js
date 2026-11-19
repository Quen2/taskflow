// Tests des métriques Prometheus : format, labels normalisés, 404, 500, logs.
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import { createMetrics } from '../src/metrics.js';
import { createMemoryRepository } from '../src/repositories/memory.js';

function newApp(repository = createMemoryRepository()) {
  const log = vi.fn();
  const app = createApp({
    repository,
    appEnv: 'test',
    appVersion: '1.2.3',
    log,
    metrics: createMetrics({ appVersion: '1.2.3', collectDefaults: false }),
  });
  return { app, log };
}

async function metricsText(app) {
  const response = await request(app).get('/metrics');
  return response.text;
}

describe('GET /metrics', () => {
  it('répond 200 au format texte, avec la version en ligne', async () => {
    const { app } = newApp();

    const response = await request(app).get('/metrics');

    expect(response.status).toBe(200);
    expect(response.type).toBe('text/plain');
    expect(response.text).toContain('taskflow_build_info{version="1.2.3"} 1');
  });

  it('utilise la route Express, jamais l URL réelle', async () => {
    const { app } = newApp();
    await request(app).post('/api/tasks').send({ title: 'Mesurer' });
    await request(app).patch('/api/tasks/1/toggle');

    const text = await metricsText(app);

    expect(text).toContain('route="/api/tasks"');
    expect(text).toContain('route="/api/tasks/:id/toggle"');
    expect(text).not.toContain('/api/tasks/1');
    expect(text).toContain('taskflow_tasks_created_total 1');
  });

  it('compte une URL inconnue sous "unmatched"', async () => {
    const { app } = newApp();
    await request(app).get('/une/url/inconnue');

    const text = await metricsText(app);

    expect(text).toMatch(
      /http_requests_total\{[^}]*route="unmatched"[^}]*status_code="404"/,
    );
    expect(text).not.toContain('/une/url/inconnue');
  });

  it('compte une réponse 500', async () => {
    const repository = {
      ...createMemoryRepository(),
      list: () => Promise.reject(new Error('base indisponible')),
    };
    const { app } = newApp(repository);
    const response = await request(app).get('/api/tasks');
    expect(response.status).toBe(500);

    const text = await metricsText(app);

    expect(text).toMatch(
      /http_requests_total\{[^}]*status_code="500"[^}]*\} 1/,
    );
  });

  it('ne logue pas les collectes et ne se compte pas elle-même', async () => {
    const { app, log } = newApp();

    await request(app).get('/metrics');
    const text = await metricsText(app);

    expect(log).not.toHaveBeenCalled();
    expect(text).not.toContain('route="/metrics"');
  });
});
