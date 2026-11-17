#!/usr/bin/env node
// File/terminal host only. All rule semantics are implemented in MoonBit.
import { existsSync, openSync, readSync, closeSync, statSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { Worker } from 'node:worker_threads';

const LIMIT = 16 * 1024 * 1024;
const usage = `MoonFileCheck 0.1.1
Usage: node cli.mjs RULES [--input FILE] [--json] [-D NAME=VALUE]
       node cli.mjs --request-json < requests.json

Input defaults to stdin. Exit codes: 0 pass, 1 mismatch, 2 invalid input/error.
  --allow-empty    Accept a ruleset containing no recognized directives
  --timeout MS     Bound engine runtime (default 30000 ms)
  --json           Emit a machine-readable report
  --help           Show this help
  --version        Print version

Reference syntax: check:, sameln:, nextln:, unordered:, not:, regex:
This implements Bytecode Alliance filecheck semantics, not LLVM FileCheck.
`;

function readText(path) {
  if (path !== '-' && statSync(path).size > LIMIT) throw Error('file exceeds 16 MiB');
  const fd = path === '-' ? 0 : openSync(path, 'r');
  const chunks = [];
  let total = 0;
  try {
    for (;;) {
      const buf = Buffer.allocUnsafe(65536);
      const n = readSync(fd, buf, 0, buf.length, null);
      if (!n) break;
      total += n;
      if (total > LIMIT) throw Error('input exceeds 16 MiB');
      chunks.push(buf.subarray(0, n));
    }
  } finally { if (fd !== 0) closeSync(fd); }
  return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)).replace(/^\uFEFF/, '');
}

export async function evaluate(request, { timeout = 30000 } = {}) {
  if (!Number.isSafeInteger(timeout) || timeout < 1 || timeout > 300000) throw Error('timeout must be 1..300000 ms');
  if (Array.isArray(request) && (request.length === 0 || request.length > 4096)) throw Error('batch must contain 1..4096 requests');
  const serialized = JSON.stringify(request);
  if (serialized === undefined || Buffer.byteLength(serialized, 'utf8') > LIMIT) throw Error('request must be JSON and at most 16 MiB');
  const prebuilt = new URL('./engine.js', import.meta.url);
  const built = new URL('./_build/js/release/build/utopi/moonfilecheck/cmd/main/main.js', import.meta.url);
  const engine = existsSync(prebuilt) ? prebuilt : built;
  if (!existsSync(engine)) throw Error('engine missing; run node scripts/build.mjs first');
  return await new Promise((resolve, reject) => {
    let received = false;
    const worker = new Worker(new URL('./engine-worker.mjs', import.meta.url), {
      workerData: { serialized, engine: engine.href },
      resourceLimits: { maxOldGenerationSizeMb: 256 },
    });
    const timer = setTimeout(() => {
      void worker.terminate();
      reject(Error(`engine timed out after ${timeout} ms`));
    }, timeout);
    worker.once('message', result => { received = true; clearTimeout(timer); resolve(result); void worker.terminate(); });
    worker.once('error', error => { clearTimeout(timer); reject(error); });
    worker.once('exit', code => {
      clearTimeout(timer);
      if (!received) reject(Error(`engine worker exited without a result (code ${code})`));
    });
  });
}

// Treat terminal output as text: untrusted input must not send ANSI/OSC commands.
export function terminalText(value) {
  return String(value).replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g,
    ch => `\\u${ch.charCodeAt(0).toString(16).padStart(4, '0')}`);
}

async function main(args) {
  if (args.includes('--help') || args.includes('-h')) { console.log(usage); return; }
  if (args.includes('--version')) { console.log('MoonFileCheck 0.1.1'); return; }
  let ruleFile, inputFile = '-', json = false, batch = false, allowEmpty = false, timeout = 30000;
  const variables = Object.create(null);
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    const take = () => { if (i + 1 >= args.length) throw Error(`missing value for ${arg}`); return args[++i]; };
    if (arg === '--json') json = true;
    else if (arg === '--request-json') { batch = true; json = true; }
    else if (arg === '--allow-empty') allowEmpty = true;
    else if (arg === '--input') inputFile = take();
    else if (arg === '--timeout') {
      timeout = Number(take());
      if (!Number.isSafeInteger(timeout) || timeout < 1 || timeout > 300000) throw Error('timeout must be 1..300000 ms');
    } else if (arg === '-D' || arg.startsWith('-D')) {
      const definition = arg === '-D' ? take() : arg.slice(2);
      const match = /^([a-zA-Z0-9_]+)=(.*)$/s.exec(definition);
      if (!match) throw Error('expected -D NAME=VALUE');
      variables[match[1]] = match[2];
    } else if (arg.startsWith('-')) throw Error(`unknown option: ${arg}`);
    else if (ruleFile === undefined) ruleFile = arg;
    else throw Error(`unexpected argument: ${arg}`);
  }
  if (batch && (ruleFile !== undefined || inputFile !== '-' || allowEmpty || Object.keys(variables).length)) {
    throw Error('--request-json cannot be combined with rules, input or variable options');
  }
  if (!batch && !ruleFile) throw Error('rules file required; use --help');
  const request = batch ? JSON.parse(readText('-')) : {
    rules: readText(ruleFile), input: readText(inputFile), variables, allow_empty: allowEmpty,
  };
  const result = await evaluate(request, { timeout });
  const items = Array.isArray(result) ? result : [result];
  process.exitCode = items.some(x => x.status === 'error') ? 2 : items.some(x => x.status === 'fail') ? 1 : 0;
  if (json) console.log(JSON.stringify(result));
  else if (result.status === 'pass') console.log(`PASS: ${result.report.matches.length} matches, ${result.report.directives} directives`);
  else if (result.status === 'error') {
    console.error(`ERROR ${terminalText(ruleFile)}:${result.error.rule_line ?? 0}: ${terminalText(result.error.code)}: ${terminalText(result.error.message)}`);
  } else {
    const d = result.report.diagnostic;
    console.error(`FAIL ${terminalText(ruleFile)}:${d.rule_line}: ${terminalText(d.message)}\n  input ${terminalText(inputFile)}:${d.input_line}:${d.input_column}\n  ${terminalText(d.excerpt)}\n  pattern: ${terminalText(d.pattern)}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch(error => {
    console.error(`ERROR: ${terminalText(error.message)}`);
    process.exitCode = 2;
  });
}
