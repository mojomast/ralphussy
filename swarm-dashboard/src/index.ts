#!/usr/bin/env node

// Import the compiled JS entry so Bun/Node resolve modules normally.
// Using a .js import here avoids TypeScript import-extension errors when
// running the source with Bun in development.
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
