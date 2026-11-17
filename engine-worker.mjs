import { parentPort, workerData } from 'node:worker_threads';
globalThis.__moonfilecheck_request = workerData.serialized;
await import(workerData.engine);
parentPort.postMessage(JSON.parse(globalThis.__moonfilecheck_result));
