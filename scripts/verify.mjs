import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { evaluate } from '../cli.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
process.chdir(root);
const run = (args, input) => spawnSync(process.execPath, ['cli.mjs', ...args], {
  input, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, timeout: 40000,
});
const summary = { deterministic: 0, cli: 0, differential: 0, oracle_mode:'none', mismatches: [] };
const fixture = JSON.parse(readFileSync('tests/cases.json', 'utf8'));
const actual = await evaluate(fixture.map(x => ({ ...x, allow_empty: true })), { timeout: 60000 });
for (let i = 0; i < fixture.length; i++) {
  assert.equal(actual[i].status, fixture[i].expected, `${fixture[i].name}: ${JSON.stringify(actual[i])}`);
  summary.deterministic++;
}
for (const [args, input, code, contains] of [
  [['examples/registers.fc', '--input', 'examples/registers.txt'], '', 0, 'PASS'],
  [['examples/registers.fc', '--input', 'examples/registers-broken.txt'], '', 1, 'FAIL'],
  [['examples/diagnostics.fc', '--input', 'examples/diagnostics.txt'], '', 0, 'PASS'],
  [['examples/registers.fc'], readFileSync('examples/registers.txt'), 0, 'PASS'],
  [['--request-json'], '{"rules":"","input":""}', 2, 'empty-rules'],
  [['--request-json'], '{"rules":"","input":"","allow_empty":true}', 0, 'pass'],
  [['--request-json'], '{"rules":"check: a","input":"a","variables":false}', 2, 'invalid-request'],
  [['--request-json'], '{"rules":"check: a","input":"a","allow_empty":1}', 2, 'invalid-request'],
  [['--request-json'], '{bad', 2, 'ERROR'],
  [['--bad'], '', 2, 'unknown option'],
  [['--timeout', '0'], '', 2, 'timeout'],
  [['does-not-exist.fc'], '', 2, 'ERROR'],
  [['--request-json'], JSON.stringify({rules:'check: $V', input:'a.b', variables:{V:'a.b'}}), 0, 'pass'],
  [['--request-json'], JSON.stringify({rules:'check: a', input:'\ud800'}), 2, 'invalid-json'],
]) {
  const result = run(args, input);
  assert.equal(result.status, code, JSON.stringify({args, ...result}));
  assert.ok((result.stdout + result.stderr).includes(contains), contains);
  summary.cli++;
}
await assert.rejects(evaluate({ rules:'check: a', input:'a' }, { timeout:1 }), /timed out/);
summary.cli++;

// Fixed-seed generated programs, including reversed order, whitespace, boundaries,
// dependency-carrying unordered matches and negative-window interactions.
let state = 0x5eed2026;
function random(n) { state ^= state << 13; state ^= state >>> 17; state ^= state << 5; return (state >>> 0) % n; }
const generated = [];
for (let i = 0; i < 2400; i++) {
  const token = ['alpha', 'beta', '世界', '𐐀', 'café'][random(5)];
  const n = random(1000), m = random(1000);
  const text = [token, String(n), 'end', 'error'];
  for (let j = text.length - 1; j > 0; j--) { const k = random(j + 1); [text[j], text[k]] = [text[k], text[j]]; }
  const rules = [
    `check: ${token}\ncheck: end`,
    `check: ${token}\nnot: error\ncheck: end`,
    `unordered: ${token}\nunordered: end`,
    `check: ${token}\nsameln: end`,
    `check: ${token}\nnextln: end`,
    'regex: N=[0-9]+\ncheck: $(v=$N)\ncheck: $v',
    'regex: R=r[0-9]+\nunordered: $(v=$R) = load\nunordered: use $v',
    `check: ${token}$()`,
  ][random(8)];
  let input = text.join([' ', '\n', '\r\n'][random(3)]);
  if (rules.includes('use $v')) input = random(2) ? `r${n} = load\nuse r${n}` : `use r${m}\nr${n} = load`;
  if (rules.includes('$(v=$N)')) input = `${n} ${random(2) ? n : m}`;
  generated.push({name:`seed-5eed2026-${i}`, rules, input, allow_empty:true});
}
const oracle = resolve(process.env.MOONFILECHECK_ORACLE || `.tools/oracle-target/release/moonfilecheck-oracle${process.platform==='win32'?'.exe':''}`);
const cases = [...fixture, ...generated];
const fingerprint = createHash('sha256').update(JSON.stringify(cases)).digest('hex');
let expected;
const live = existsSync(oracle) && !process.argv.includes('--recorded');
if (process.argv.includes('--record-oracle') && !live) throw Error('recording requires a live Rust oracle');
if (live) {
  const baseline = spawnSync(oracle, [], { input: JSON.stringify(cases), encoding:'utf8', maxBuffer:32*1024*1024, timeout:60000 });
  assert.equal(baseline.status, 0, String(baseline.error || baseline.stderr));
  expected = JSON.parse(baseline.stdout).map(x=>x.status);
  summary.oracle_mode = 'live-rust';
  if (process.argv.includes('--record-oracle')) {
    writeFileSync('tests/oracle-baseline.json',JSON.stringify({oracle:'filecheck 0.5.0 / regex 1.11.1',cases_sha256:fingerprint,statuses:expected},null,2)+'\n');
  }
} else {
  const recorded = JSON.parse(readFileSync('tests/oracle-baseline.json','utf8'));
  assert.equal(recorded.cases_sha256,fingerprint,'recorded oracle does not match the current generated corpus');
  expected = recorded.statuses;
  summary.oracle_mode = 'recorded-rust';
}
assert.equal(expected.length,cases.length);
const observed = await evaluate(cases.map(x => ({...x, allow_empty:true})), { timeout:60000 });
for (let i=0;i<cases.length;i++) {
  if (expected[i] !== observed[i].status) summary.mismatches.push({case:cases[i],expected:expected[i],actual:observed[i]});
}
summary.differential = cases.length;
mkdirSync('artifacts', {recursive:true});
writeFileSync('artifacts/verification.json', JSON.stringify(summary,null,2)+'\n');
if (process.argv.includes('--record-oracle')) {
  mkdirSync('docs/evidence', {recursive:true});
  writeFileSync('docs/evidence/verification.json',JSON.stringify(summary,null,2)+'\n');
}
assert.equal(summary.mismatches.length, 0, JSON.stringify(summary.mismatches.slice(0,5),null,2));
console.log(JSON.stringify(summary,null,2));
