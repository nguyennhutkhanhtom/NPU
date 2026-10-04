from pathlib import Path
from hashlib import sha256
import json, subprocess
root=Path(__file__).resolve().parents[3]
prefix='docs/verification/rtl_policy_attention1/'
def head(name): return subprocess.check_output(['git','show','HEAD:'+prefix+name],cwd=root)
name='archive_policy_attention1.py'
assert head(name)==(root/prefix/name).read_bytes(), name
result=json.loads(head('results.json'))
working=(root/prefix/'results.json').read_bytes()
assert json.loads(working)==result
assert head('results.json')==working.replace(b'\r\n',b'\n')
assert sha256(head('archive_policy_attention1.py')).hexdigest()==result['inventory_helper_sha256']
assert sha256((root/'AGENTS.md').read_bytes()).hexdigest()==result['rules_sha256']
assert result['rtl_sources']=={p.name:sha256(p.read_bytes()).hexdigest() for p in (root/'Verilog Source code').iterdir() if p.suffix in ('.sv','.v','.svh','.mem')}
out=root/'docs/verification/rtl_policy_attention1_git';out.mkdir(exist_ok=False)
checked={'status':'PAYLOAD_AND_REFERENCED_HASHES_PASS', 'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
 'scope':'Source review metadata only. Initial strict manifest-byte comparison failed because JSON staged before the -text attribute was normalized CRLF to LF. Payload identical; original archive left unchanged. The raw hashed inventory helper, rules and current34source assets match. Not a functional/timing/application gate.',
 'committed_manifest_sha256':sha256(head('results.json')).hexdigest(),'working_manifest_sha256':sha256(working).hexdigest(),
 'json_payload_identical':True,'difference':'CRLF-to-LF only','inventory_helper_sha256':result['inventory_helper_sha256'],'rtl_sources':result['rtl_sources'],
 'command':'python tests/full_rtl/build/verify_policy_head.py'}
(out/'results.json').write_text(json.dumps(checked,indent=2)+'\n',encoding='utf-8',newline='\n')
print('POLICY_HEAD_PAYLOAD_HASHES_PASS: metadata CRLF/LF difference explicit; helper/rules/current34source hashes match')
