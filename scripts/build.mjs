import { existsSync, mkdirSync, copyFileSync, cpSync } from 'node:fs';
import { resolve, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = fileURLToPath(new URL('../', import.meta.url));
const local = resolve(root, '.tools/moon');
const localExe = resolve(local, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon');
const env = { ...process.env };
const moon = existsSync(localExe) ? localExe : 'moon';
if (existsSync(localExe)) { env.MOON_HOME = local; env.PATH = resolve(local, 'bin') + delimiter + env.PATH; }
const result = spawnSync(moon, ['build', '--release', '--target', 'js'], { cwd: root, env, stdio: 'inherit' });
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 2);
mkdirSync(resolve(root, 'dist'), { recursive: true });
for (const file of ['cli.mjs', 'engine-worker.mjs']) copyFileSync(resolve(root, file), resolve(root, 'dist', file));
copyFileSync(resolve(root, '_build/js/release/build/utopi/moonfilecheck/cmd/main/main.js'), resolve(root, 'dist/engine.js'));
for (const file of ['README.md', 'LICENSE', 'NOTICE', 'THIRD_PARTY.md']) {
  if (existsSync(resolve(root, file))) copyFileSync(resolve(root, file), resolve(root, 'dist', file));
}
for (const dir of ['examples', 'licenses']) {
  if (existsSync(resolve(root,dir))) cpSync(resolve(root,dir),resolve(root,'dist',dir),{recursive:true});
}
mkdirSync(resolve(root,'dist/docs'),{recursive:true});
cpSync(resolve(root,'docs'),resolve(root,'dist/docs'),{recursive:true});
console.log('Built portable Node.js CLI: dist/cli.mjs');
