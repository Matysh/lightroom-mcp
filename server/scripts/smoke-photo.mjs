#!/usr/bin/env node
// Opt-in live test: edit only a new virtual copy, restore its snapshot, keep it for review.
import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import jpeg from 'jpeg-js';

const sourceId = process.argv[2];
if (!sourceId || !/^\d+$/.test(sourceId)) throw new Error('Usage: node server/scripts/smoke-photo.mjs PHOTO_ID (creates one virtual copy)');
const root = fileURLToPath(new URL('../../', import.meta.url));
const out = path.join(root, '.cache', 'verification');
await fs.mkdir(out, { recursive: true });
const report = { checkedAt: new Date().toISOString(), sourceId, steps: [] };
const saveReport = () => fs.writeFile(path.join(out, 'photo-smoke.json'), JSON.stringify(report, null, 2));
const client = new Client({ name: 'lightroom-virtual-copy-smoke', version: '1.0.0' });
await client.connect(new StdioClientTransport({ command: process.execPath, args: [path.join(root, 'scripts', 'start-local.mjs')], stderr: 'pipe' }));
async function call(name, args) {
  const result = await client.callTool({ name, arguments: args });
  if (result.isError) throw new Error(`${name}: ${JSON.stringify(result.content)}`);
  const text = result.content.find(block => block.type === 'text')?.text;
  return { data: text ? JSON.parse(text) : null, image: result.content.find(block => block.type === 'image') };
}
async function metadata(id) {
  return (await call('get_photo_metadata', { photo_id: id, sections: ['developSettings'] })).data;
}
async function preview(id, label) {
  // Lightroom's cache can lag Develop edits. Fetch twice after settling.
  await delay(3500);
  await call('get_photo_preview', { photo_id: id, size: 1024 });
  const result = await call('get_photo_preview', { photo_id: id, size: 1024 });
  assert.equal(result.image?.mimeType, 'image/jpeg');
  const bytes = Buffer.from(result.image.data, 'base64');
  const decoded = jpeg.decode(bytes, { useTArray: true });
  let sum = 0;
  for (let i = 0; i < decoded.data.length; i += 4) sum += 0.2126 * decoded.data[i] + 0.7152 * decoded.data[i + 1] + 0.0722 * decoded.data[i + 2];
  const meanLuminance = sum / (decoded.width * decoded.height);
  const file = path.join(out, `${label}.jpg`);
  await fs.writeFile(file, bytes);
  return { file, width: decoded.width, height: decoded.height, bytes: bytes.length, meanLuminance };
}
let before;
let snapshot;
let restored = false;
try {
  const original = await metadata(sourceId);
  const copies = (await call('create_virtual_copies', { photo_ids: [sourceId], copy_name: `MCP connection test ${new Date().toISOString()}` })).data;
  assert.equal(copies.created, 1);
  report.copyId = copies.copies[0].copy_id;
  await saveReport();
  before = await metadata(report.copyId);
  assert.equal(before.isVirtualCopy, true);
  assert.equal(String(before.virtualCopy.masterPhotoId), String(original.id));
  snapshot = (await call('create_develop_snapshot', { photo_id: report.copyId, name: 'Before MCP connection test' })).data.snapshot;
  report.snapshot = snapshot;
  report.beforeSettings = before.developSettings;
  await saveReport();
  report.beforePreview = await preview(report.copyId, 'before');
  report.steps.push('read-settings', 'render-before-preview', 'create-virtual-copy', 'create-snapshot');
  const wanted = {
    Exposure2012: Math.min(5, before.developSettings.exposure + 0.5),
    Contrast2012: Math.min(100, before.developSettings.contrast + 10),
  };
  await call('set_develop_settings', { photo_id: report.copyId, settings: wanted });
  const edited = await metadata(report.copyId);
  assert.ok(Math.abs(edited.developSettings.exposure - wanted.Exposure2012) < 0.001, 'Exposure readback mismatch');
  assert.equal(edited.developSettings.contrast, wanted.Contrast2012);
  report.requestedSettings = wanted;
  report.afterSettings = edited.developSettings;
  report.steps.push('apply-settings', 'verify-settings-readback');
  report.afterPreview = await preview(report.copyId, 'after');
  assert.ok(Math.abs(report.afterPreview.meanLuminance - report.beforePreview.meanLuminance) > 1, 'Preview did not reflect the edit');
  report.steps.push('verify-preview-change');
  await saveReport();
  await call('apply_develop_snapshot', { photo_id: report.copyId, snapshot_id: snapshot.id });
  const back = await metadata(report.copyId);
  assert.deepEqual(back.developSettings, before.developSettings, 'Restored settings differ');
  restored = true;
  report.restoredSettings = back.developSettings;
  report.restoredPreview = await preview(report.copyId, 'restored');
  report.steps.push('restore-snapshot', 'verify-restored-settings');
  const originalAfter = await metadata(sourceId);
  assert.deepEqual(originalAfter.developSettings, original.developSettings, 'Original develop settings changed');
  report.originalUnchanged = true;
  report.passed = true;
  console.log(JSON.stringify({ passed: true, sourceId, copyId: report.copyId, before: { exposure: before.developSettings.exposure, contrast: before.developSettings.contrast }, applied: wanted, restored, previews: { before: report.beforePreview, after: report.afterPreview, restored: report.restoredPreview }, originalUnchanged: true }, null, 2));
} catch (error) {
  report.error = String(error);
  throw error;
} finally {
  if (!restored && snapshot && report.copyId) {
    try {
      await call('apply_develop_snapshot', { photo_id: report.copyId, snapshot_id: snapshot.id });
      const back = await metadata(report.copyId);
      assert.deepEqual(back.developSettings, before.developSettings);
      report.restoredAfterFailure = true;
    } catch (error) { report.restoreError = String(error); }
  }
  await saveReport();
  await client.close();
}
