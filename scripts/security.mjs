import assert from 'node:assert/strict';
import { evaluate, terminalText } from '../cli.mjs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const cli = fileURLToPath(new URL('../cli.mjs', import.meta.url));
let checks = 0;
for (const timeout of [0, -1, NaN, Infinity, 300001, '30']) {
  await assert.rejects(evaluate({}, { timeout }), /timeout/); checks++;
}
for (const request of [[], Array(4097).fill({})]) {
  await assert.rejects(evaluate(request), /batch/); checks++;
}
await assert.rejects(evaluate({input: 'x'.repeat(16 * 1024 * 1024)}), /16 MiB/); checks++;
assert.equal(terminalText('\x1b]52;c;payload\x07\r\u202e'), '\\u001b]52;c;payload\\u0007\\u000d\\u202e'); checks++;
const hostile = [
  'check: $(=a{4294967295})',
  'check: $(=(?:a{1000}){1000})',
  'check: $(=(?:){1000000})',
  'check: $(=' + '('.repeat(65) + 'a' + ')'.repeat(65) + ')',
  'check: $(=' + Array(258).fill('a').join('|') + ')',
];
for (const rules of hostile) {
  const result = await evaluate({rules, input:'a'}, {timeout:5000});
  assert.equal(result.status, 'error'); checks++;
}
const oversizedExpansion = await evaluate({rules:'check: $V$V', input:'a', variables:{V:'a'.repeat(5000)}});
assert.equal(oversizedExpansion.error.code, 'resource-limit'); checks++;
const result = spawnSync(process.execPath, [cli, '--request-json'], {input:'[]',encoding:'utf8',timeout:5000});
assert.equal(result.status, 2); checks++;
const injection = spawnSync(process.execPath, [cli, '--bad\x1b[2J'], {encoding:'utf8',timeout:5000});
assert.equal(injection.status, 2); assert.ok(!injection.stderr.includes('\x1b')); checks++;
console.log(JSON.stringify({security_checks:checks,passed:true}));
