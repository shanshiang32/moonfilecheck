"""Create self-contained CLI/source archives using only the Python standard library."""
from pathlib import Path
import hashlib
import json
import os
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'release'
OUT.mkdir(exist_ok=True)
SKIP = {'.tools','.mooncakes','.git','_build','target','release','dist','artifacts','__pycache__'}

def archive(name, entries):
    target = OUT/name
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for path, relative in sorted(entries,key=lambda pair:str(pair[1])):
            if path.is_file(): z.write(path,relative.as_posix())
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None
    return dict(file=name,bytes=target.stat().st_size,sha256=hashlib.sha256(target.read_bytes()).hexdigest())

assert (ROOT/'dist/engine.js').exists(), 'run node scripts/build.mjs first'
assert (ROOT/'tests/oracle-baseline.json').exists()
source=[]
for directory, dirs, files in os.walk(ROOT):
    dirs[:] = [name for name in dirs if name not in SKIP]
    for name in files:
        p=Path(directory)/name
        source.append((p,Path('moonfilecheck-source-0.1.1')/p.relative_to(ROOT)))
portable=[(p,Path('moonfilecheck-cli-0.1.1')/p.relative_to(ROOT/'dist')) for p in (ROOT/'dist').rglob('*') if p.is_file()]
manifest={
 'version':'0.1.1',
 'artifacts':[archive('moonfilecheck-source-0.1.1.zip',source),archive('moonfilecheck-cli-0.1.1.zip',portable)],
 'verification':json.loads((ROOT/'docs/evidence/verification.json').read_text(encoding='utf8')),
 'security':json.loads((ROOT/'docs/evidence/security.json').read_text(encoding='utf-8-sig')),
}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
(OUT/'SHA256SUMS.txt').write_text(''.join(f'{a["sha256"]}  {a["file"]}\n' for a in manifest['artifacts']),encoding='ascii')
print(json.dumps(manifest,ensure_ascii=False,indent=2))
