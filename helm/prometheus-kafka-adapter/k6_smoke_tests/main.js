// K6 Smoke Tests — prometheus-kafka-adapter
// Entry point: imports all test scenarios and runs them sequentially.

import { config, validateConfig } from './config/config.js';
import { runSMOKE001 } from './tests/SMOKE-001.test.js';
import { runSMOKE002 } from './tests/SMOKE-002.test.js';
import { runSMOKE003 } from './tests/SMOKE-003.test.js';
import { runSMOKE004 } from './tests/SMOKE-004.test.js';
import { runNEG001 } from './tests/SMOKE-NEG-001.test.js';
import { runNEG002 } from './tests/SMOKE-NEG-002.test.js';
import { runNEG003 } from './tests/SMOKE-NEG-003.test.js';
import { runNEG004 } from './tests/SMOKE-NEG-004.test.js';
import { runNEG005 } from './tests/SMOKE-NEG-005.test.js';
import { runNEG006 } from './tests/SMOKE-NEG-006.test.js';
import { runNEG007 } from './tests/SMOKE-NEG-007.test.js';

// K6 options: single iteration smoke test
export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    checks: ['rate>=0.80'], // At least 80% checks must pass
  },
};

export default function () {
  validateConfig();
  const baseUrl = config.BASE_URL;

  // Positive scenarios
  runSMOKE001(baseUrl);
  runSMOKE002(baseUrl);
  runSMOKE003(baseUrl);
  runSMOKE004(baseUrl);

  // Negative scenarios
  runNEG001(baseUrl);
  runNEG002(baseUrl);
  runNEG003(baseUrl);

  // Auth-dependent negative scenarios (only when Basic Auth is enabled)
  if (config.BASIC_AUTH_ENABLED) {
    runNEG004(baseUrl);
    runNEG005(baseUrl);
  }

  // Routing negative scenarios
  runNEG006(baseUrl);
  runNEG007(baseUrl);
}
