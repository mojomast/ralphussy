// Wrapper to re-export the existing compiled DB helper from the original
// dashboard so the new dashboard can import it with a simple path.
module.exports = require('../swarm-dashboard/dist/database-bun.js');
