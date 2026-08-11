// Configuration for prometheus-kafka-adapter smoke tests

// Approved cluster allowlist
const APPROVED_CLUSTERS = ['us-dev-5', 'us-dev-2', 'env-2a', 'stage'];

// Environment variables
const BASE_URL = __ENV.BASE_URL || '';
const BASIC_AUTH_USERNAME = __ENV.BASIC_AUTH_USERNAME || '';
const BASIC_AUTH_PASSWORD = __ENV.BASIC_AUTH_PASSWORD || '';
const BASIC_AUTH_ENABLED = BASIC_AUTH_USERNAME !== '' && BASIC_AUTH_PASSWORD !== '';

// Validate required environment variables
export function validateConfig() {
  if (!BASE_URL) {
    throw new Error('FATAL: BASE_URL environment variable is required but not set.');
  }
}

// Cluster guardrail validation
export function validateCluster() {
  const isApproved = APPROVED_CLUSTERS.some((cluster) => BASE_URL.includes(cluster));
  if (!isApproved) {
    console.log(
      JSON.stringify({
        phase: 'config',
        level: 'warn',
        message: `BASE_URL "${BASE_URL}" does not match any approved CSP cluster. Proceeding as this service may be deployed standalone.`,
        approvedClusters: APPROVED_CLUSTERS,
      })
    );
  }
}

export const config = {
  BASE_URL,
  BASIC_AUTH_USERNAME,
  BASIC_AUTH_PASSWORD,
  BASIC_AUTH_ENABLED,
  APPROVED_CLUSTERS,
};

export default config;
