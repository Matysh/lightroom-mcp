#!/usr/bin/env node
// Read-only connection check. It does not start AI model sessions or edit photos.
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = fileURLToPath(new URL('../../', import.meta.url));
const home = os.homedir();
const codexOutput = process.platform === 'win32'
  ? execFileSync(process.env.ComSpec || 'cmd.exe', ['/d', '/c', 'codex mcp get lightroom --json'], { encoding: 'utf8', windowsHide: true })
  : execFileSync('codex', ['mcp', 'get', 'lightroom', '--json'], { encoding: 'utf8' });
const codex = JSON.parse(codexOutput);
if (!codex.enabled || codex.transport?.type !== 'stdio') throw new Error('Codex lightroom server must be enabled with stdio transport');
const claudeCode = JSON.parse(await fs.readFile(path.join(home, '.claude.json'), 'utf8'));
const claudeDesktop = JSON.parse(await fs.readFile(path.join(process.env.APPDATA, 'Claude', 'claude_desktop_config.json'), 'utf8'));
const configs = [
  ['Codex', codex.transport],
  ['Claude Code', claudeCode.mcpServers?.lightroom],
  ['Claude Desktop', claudeDesktop.mcpServers?.lightroom],
];
const clients = [];
const report = { checkedAt: new Date().toISOString(), clients: [] };
try {
  for (const [name, config] of configs) {
    if (!config) throw new Error(`${name}: missing lightroom MCP configuration`);
    const client = new Client({ name: `lightroom-verify-${name.replaceAll(' ', '-')}`, version: '1.0.0' });
    clients.push(client);
    const transport = new StdioClientTransport({ ...config, stderr: 'pipe' });
    await client.connect(transport);
    const { tools } = await client.listTools();
    const result = await client.callTool({ name: 'get_selected_photos', arguments: { limit: 1 } });
    if (result.isError) throw new Error(`${name}: ${JSON.stringify(result.content)}`);
    const selection = JSON.parse(result.content.find(block => block.type === 'text').text);
    const required = ['get_photo_metadata', 'get_photo_preview', 'set_develop_settings', 'create_virtual_copies', 'create_develop_snapshot', 'apply_develop_snapshot'];
    for (const tool of required) if (!tools.some(t => t.name === tool)) throw new Error(`${name}: missing ${tool}`);
    const row = { name, tools: tools.length, requiredToolsAvailable: true, selection };
    report.clients.push(row);
    console.log(JSON.stringify(row));
  }
  // Keep all three connected during the check, then exercise each again.
  for (const client of clients) {
    const result = await client.callTool({ name: 'get_selected_photos', arguments: { limit: 1 } });
    if (result.isError) throw new Error('Concurrent client check failed');
  }
  report.concurrentClientsPassed = true;
  const selected = report.clients[0].selection.photos[0];
  if (selected) {
    const result = await clients[0].callTool({ name: 'get_photo_metadata', arguments: { photo_id: String(selected.id), sections: ['developSettings'] } });
    if (result.isError) throw new Error(JSON.stringify(result.content));
    report.metadata = JSON.parse(result.content.find(block => block.type === 'text').text);
    const { filename, fileFormat, cameraModel, dimensions, developSettings } = report.metadata;
    console.log(JSON.stringify({ metadata: { filename, fileFormat, cameraModel, dimensions, developSettings } }));
  }
  const out = path.join(root, '.cache', 'verification');
  await fs.mkdir(out, { recursive: true });
  await fs.writeFile(path.join(out, 'connection.json'), JSON.stringify(report, null, 2));
  console.log('Concurrent MCP connections passed. Report: .cache/verification/connection.json');
} finally {
  for (const client of clients.reverse()) await client.close().catch(() => {});
}
