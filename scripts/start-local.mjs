#!/usr/bin/env node
// Use this checkout in every MCP client and expose Develop tools by default.
// Explicit client settings (including read-only mode) still take precedence.
process.env.LIGHTROOM_MCP_TOOLSETS ??= 'all';
await import('../server/dist/index.js');
