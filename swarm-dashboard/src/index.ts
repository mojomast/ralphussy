#!/usr/bin/env node

import { SwarmDashboard } from './dashboard.js';

async function main() {
  console.error('Starting dashboard...');
  const dashboard = new SwarmDashboard();
  await dashboard.init();
}

main().catch((error) => {
  console.error('Failed to start dashboard:', error);
  console.error('Stack trace:', error.stack);
  process.exit(1);
});
