"""Extract upstream positive/negative assertions plus independently specified edges.

No expected results are derived from the MoonBit implementation.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
STR = r'"(?:\\.|[^"\\])*"'

def rust_string(raw):
    text, out, i = raw[1:-1], [], 0
    mapping = {'n':'\n','r':'\r','t':'\t','0':'\0','\\':'\\','"':'"',"'":"'"}
    while i < len(text):
        if text[i] != '\\':
            out.append(text[i]); i += 1; continue
        i += 1
        c = text[i]
        if c == '\n':
            i += 1
            while i < len(text) and text[i].isspace(): i += 1
        elif c == 'u':
            end = text.index('}', i)
            out.append(chr(int(text[i+2:end],16))); i = end+1
        elif c == 'x':
            out.append(chr(int(text[i+1:i+3],16))); i += 3
        else:
            out.append(mapping[c]); i += 1
    return ''.join(out)

cases = []
source = (ROOT/'reference/upstream/basic.rs').read_text(encoding='utf8')
for block in source.split('#[test]')[1:]:
    fn = re.search(r'fn (\w+)\(', block).group(1)
    rule = re.search(r'\.text\(\s*('+STR+r')', block)
    rules = rust_string(rule.group(1)) if rule else ''
    for n, match in enumerate(re.finditer(r'c\.check\(\s*(t|'+STR+r')\s*,[\s\S]*?Ok\((true|false)\)',block)):
        arg = match.group(1)
        if arg == 't':
            ts = list(re.finditer(r'let t\s*=\s*('+STR+r')\s*;',block[:match.start()]))
            if not ts: raise ValueError(fn)
            arg = ts[-1].group(1)
        cases.append(dict(name=f'upstream/{fn}/{n}',rules=rules,input=rust_string(arg),expected='pass' if match.group(2)=='true' else 'fail',origin='bytecodealliance/filecheck tests/basic.rs'))

def add(name, rules, text, expected):
    cases.append(dict(name=name,rules=rules,input=text,expected=expected,origin='independent regression'))

for name, rules, text, expected in [
 ('register-capture','regex: R=r[0-9]+\ncheck: load $(v=$R)\nnextln: use $v','load r42\nuse r42','pass'),
 ('register-wrong','regex: R=r[0-9]+\ncheck: load $(v=$R)\nnextln: use $v','load r42\nuse r41','fail'),
 ('numeric-name','check: $(0=[a-z]+)\nnextln: $0','cat\ncat','error'),
 ('dollar-literal','check: $$5','price $5','pass'),
 ('empty-escape','check: foo$()','foobar','pass'),
 ('word-boundary','check: foo','foobar','fail'),
 ('literal-meta','check: [a].*','[a].*','pass'),
 ('empty-regex','check: $(=)','anything','pass'),
 ('nested-group','check: $(v=(cat|dog)+)\nnextln: $v','catdog\ncatdog','pass'),
 ('class-parenthesis','check: $(v=[()]+)','()','pass'),
 ('empty-optional-capture','check: $(v=a*)\ncheck: $v','bbb','pass'),
 ('undefined','check: $missing','x','error'),
 ('same-pattern-ref','check: $(v=a)$v','aa','error'),
 ('duplicate-capture','check: $(v=a)$(v=b)','ab','error'),
 ('capture-in-not','not: $(v=a)','b','error'),
 ('unterminated','check: $(v=abc','abc','error'),
 ('bad-regex','check: $(v=[)','abc','error'),
 ('bad-dollar','check: $','x','error'),
 ('regex-name','regex: =x','x','error'),
 ('negative-capture-ref','regex: V=[a-z]+\nnot: $(v=$V)','x','error'),
 ('trailing-not','check: start\nnot: error','start error','fail'),
 ('negative-boundary-window','check: one$()\nnot: half\ncheck: $()two','onehalftwo','fail'),
 ('negative-before','not: error\ncheck: start','error start','fail'),
 ('negative-after','not: error\ncheck: start','start error','pass'),
 ('unordered-overlap','unordered: same\nunordered: same','same','pass'),
 ('unordered-barrier','unordered: one\nunordered: two\ncheck: three','two three one','fail'),
 ('unordered-reversed','unordered: one\nunordered: two\ncheck: three','two one three','pass'),
 ('unordered-dependency','regex: R=r[0-9]+\nunordered: $(v=$R) = load\nunordered: use $v','use r1\nr1 = load','fail'),
 ('negative-frozen-value','check: $(v=a)\nnot: $v\ncheck: $(v=b)','a b a','pass'),
 ('unicode-cjk','check: 世界','你好 世界','pass'),
 ('unicode-boundary','check: 世界','字世界','fail'),
 ('unicode-emoji','check: hello','😀 hello','pass'),
 ('unicode-supplementary-letter','check: 𐐀','😀 𐐀','pass'),
 ('unicode-word-class','check: $(v=\\w+)\nnextln: $v','世界𐐀\n世界𐐀','pass'),
 ('crlf','check: one\r\nnextln: two','one\r\ntwo','pass'),
 ('newline-not-optional','check: one\nnextln: two','one\n\ntwo','fail'),
 ('multiline-anchor','check: $(=^two$)','one\ntwo\nthree','pass'),
 ('named-regex','check: $(v=(?P<inner>[a-z]+))','abc','pass'),
 ('escaped-non-bmp','check: $(=\\𐐀)','𐐀','error'),
]: add(name,rules,text,expected)

assert len(cases) >= 60
(ROOT/'tests/cases.json').write_text(json.dumps(cases,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
encoded=json.dumps(cases,ensure_ascii=False,separators=(',',':'))
test='''// Generated from tests/cases.json by tests/make-fixtures.py. Do not edit.
// Generated fixture text is not counted as original implementation work.
test "shared fixture corpus across backends" {
  let corpus = @json.parse(
    #|CORPUS
  )
  guard corpus is @json.Json::Array(cases) else { fail("invalid corpus") }
  for case in cases {
    guard case is @json.Json::Object(fields) else { fail("invalid case") }
    let request = @json.Json::object(fields.copy())
    guard request is @json.Json::Object(request_fields) else { fail("invalid request") }
    request_fields["allow_empty"] = @json.Json::boolean(true)
    let result = @moonfilecheck.execute(request)
    guard result is @json.Json::Object(actual) else { fail("invalid response") }
    assert_eq(actual.get("status"), fields.get("expected"))
  }
}
'''.replace('CORPUS',encoded)
(ROOT/'corpus_test.mbt').write_text(test,encoding='utf8')
print(f'{len(cases)} fixtures ({sum(c["origin"].startswith("bytecode") for c in cases)} extracted upstream assertions)')
