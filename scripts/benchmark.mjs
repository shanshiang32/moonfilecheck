import { performance } from 'node:perf_hooks';
import { mkdirSync, writeFileSync } from 'node:fs';
import { cpus, platform, arch } from 'node:os';
import { evaluate } from '../cli.mjs';

const results = [];
for (const size of [1024, 65536, 1048576]) {
  const input = 'noise line\n'.repeat(Math.ceil(size / 11)) + 'END';
  const request = {rules:'check: END', input};
  await evaluate(request);
  const samples = [];
  for (let i=0;i<5;i++) {
    const start = performance.now();
    const r = await evaluate(request);
    if (r.status !== 'pass') throw Error('benchmark check failed');
    samples.push(performance.now()-start);
  }
  samples.sort((a,b)=>a-b);
  results.push({input_bytes:Buffer.byteLength(input),runs:5,median_ms:samples[2],min_ms:samples[0],max_ms:samples[4]});
}
const report = {
  scope:'End-to-end evaluate() including a new worker, engine load, JSON and matching; not a pure matching-throughput benchmark',
  platform:platform(),architecture:arch(),cpu:cpus()[0].model,node:process.version,results,
};
mkdirSync(new URL('../docs/evidence/',import.meta.url),{recursive:true});
writeFileSync(new URL('../docs/evidence/benchmark.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
