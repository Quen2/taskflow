// Métriques Prometheus de l'API (format texte lu par Prometheus sur /metrics).
// Un REGISTRE PAR APPEL : chaque test crée une application neuve, avec ses
// propres compteurs (le registre global de prom-client refuserait les doublons).
import client from 'prom-client';

// Tranches de durée de l'histogramme, en secondes (5 ms à 5 s).
const DURATION_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5];

// Label "route" : la route EXPRESS (/api/tasks/:id/toggle), jamais l'URL réelle
// (/api/tasks/42/toggle), sinon une série par tâche (cardinalité explosive).
function routeLabel(req) {
  if (!req.route) return 'unmatched'; // aucune route n'a répondu (404)
  const path = `${req.baseUrl}${req.route.path}`;
  // La route "/" du routeur donne "/api/tasks/" : on retire la barre finale.
  return path.length > 1 && path.endsWith('/') ? path.slice(0, -1) : path;
}

export function createMetrics({
  appVersion = 'dev',
  collectDefaults = true,
} = {}) {
  const register = new client.Registry();

  if (collectDefaults) {
    // Mémoire, CPU, event loop... du processus Node.
    client.collectDefaultMetrics({ register });
  }

  const httpRequestsTotal = new client.Counter({
    name: 'http_requests_total',
    help: 'Nombre de requêtes HTTP traitées',
    labelNames: ['method', 'route', 'status_code'],
    registers: [register],
  });

  const httpRequestDuration = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Durée des requêtes HTTP, en secondes',
    labelNames: ['method', 'route', 'status_code'],
    buckets: DURATION_BUCKETS,
    registers: [register],
  });

  const tasksCreatedTotal = new client.Counter({
    name: 'taskflow_tasks_created_total',
    help: 'Nombre de tâches créées (métrique métier)',
    registers: [register],
  });

  const buildInfo = new client.Gauge({
    name: 'taskflow_build_info',
    help: 'Version en ligne (toujours 1, la version est dans le label)',
    labelNames: ['version'],
    registers: [register],
  });
  buildInfo.set({ version: appVersion }, 1);

  function middleware(req, res, next) {
    const stopTimer = httpRequestDuration.startTimer();
    // Les labels sont calculés à la FIN de la réponse : avant, req.route
    // n'est pas encore connu (Express ne sait pas encore quelle route répondra).
    res.on('finish', () => {
      const labels = {
        method: req.method,
        route: routeLabel(req),
        status_code: String(res.statusCode),
      };
      stopTimer(labels);
      httpRequestsTotal.inc(labels);
    });
    next();
  }

  function handler(_req, res, next) {
    register
      .metrics()
      .then((text) => {
        res.set('Content-Type', register.contentType);
        res.end(text);
      })
      .catch(next);
  }

  return {
    register,
    middleware,
    handler,
    taskCreated: () => tasksCreatedTotal.inc(),
  };
}
