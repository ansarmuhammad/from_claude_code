import http from "k6/http";
import { check, sleep } from "k6";
import { Rate } from "k6/metrics";

// Custom metric so error-rate threshold covers both endpoints uniformly,
// on top of k6's built-in http_req_failed.
const errorRate = new Rate("errors");

const BASE_URL = __ENV.API_BASE_URL || "http://localhost:8000";

export const options = {
  scenarios: {
    ramping_load: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "30s", target: 10 }, // ramp up
        { duration: "1m", target: 10 }, // steady state
        { duration: "30s", target: 30 }, // spike
        { duration: "1m", target: 30 }, // steady state at spike
        { duration: "30s", target: 0 }, // ramp down
      ],
    },
  },
  thresholds: {
    http_req_duration: ["p(95)<500"],
    http_req_failed: ["rate<0.01"],
    errors: ["rate<0.01"],
  },
};

export default function () {
  const healthResponse = http.get(`${BASE_URL}/health`, {
    tags: { endpoint: "health" },
  });
  const healthOk = check(healthResponse, {
    "GET /health status is 200": (r) => r.status === 200,
    "GET /health body has status field": (r) => {
      try {
        return JSON.parse(r.body).status === "healthy";
      } catch (e) {
        return false;
      }
    },
  });
  errorRate.add(!healthOk);

  const tasksResponse = http.get(`${BASE_URL}/api/v1/tasks`, {
    tags: { endpoint: "list_tasks" },
  });
  const tasksOk = check(tasksResponse, {
    "GET /api/v1/tasks status is 200": (r) => r.status === 200,
    "GET /api/v1/tasks returns an array": (r) => {
      try {
        return Array.isArray(JSON.parse(r.body));
      } catch (e) {
        return false;
      }
    },
  });
  errorRate.add(!tasksOk);

  sleep(1);
}
