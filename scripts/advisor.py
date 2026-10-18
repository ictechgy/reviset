"""Run explicitly requested local advisors and preserve replayable evidence."""
import argparse, datetime, hashlib, json, pathlib, subprocess, time
parser=argparse.ArgumentParser();parser.add_argument('--provider',choices=['claude','grok','agy'],required=True);parser.add_argument('--prompt',required=True);parser.add_argument('--slug',required=True);parser.add_argument('--scope',required=True);parser.add_argument('--timeout',type=int,default=480)
a=parser.parse_args();root=pathlib.Path(__file__).resolve().parents[1];prompt_path=pathlib.Path(a.prompt).resolve();data=prompt_path.read_bytes();digest=hashlib.sha256(data).hexdigest()
base=root/'.omx/artifacts'/('ask-'+a.provider+'-'+a.slug+'-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'));base.mkdir(parents=True,exist_ok=True)
cwd=base/'workspace';cwd.mkdir();(base/'prompt.txt').write_bytes(data)
exe={'claude':'/Users/coden/.local/bin/claude','grok':'/Users/coden/.grok/bin/grok','agy':'/Users/coden/.local/bin/agy'}[a.provider]
if a.provider=='claude':argv=[exe,'-p','--tools','','--no-session-persistence','--strict-mcp-config','--setting-sources','','--disable-slash-commands','--no-chrome','--permission-mode','dontAsk']
elif a.provider=='grok':argv=[exe,'--prompt-file',str(base/'prompt.txt'),'--tools','','--disable-web-search','--no-subagents','--no-plan','--permission-mode','dontAsk','--max-turns','4']
else:argv=[exe,'-p',data.decode(),'--sandbox','--disable-slash-commands','--print-timeout','420s']
version=subprocess.run([exe,'--version'],capture_output=True,text=True).stdout.strip()
start=datetime.datetime.now(datetime.timezone.utc).isoformat();record={'provider':a.provider,'scope':a.scope,'executable':exe,'version':version,'argv':argv if a.provider!='agy' else [exe,'-p','<prompt.txt sha256='+digest+'>']+argv[3:],'cwd':str(cwd),'prompt_path':str(base/'prompt.txt'),'prompt_sha256':digest,'started_at':start}
(base/'invocation.json').write_text(json.dumps(record,indent=2))
with (base/'stdout.txt').open('wb') as stdout,(base/'stderr.txt').open('wb') as stderr:
 try:
  proc=subprocess.Popen(argv,cwd=cwd,stdin=subprocess.PIPE if a.provider=='claude' else subprocess.DEVNULL,stdout=stdout,stderr=stderr)
  try:proc.communicate(data if a.provider=='claude' else None,timeout=a.timeout);code=proc.returncode
  except subprocess.TimeoutExpired:proc.kill();proc.wait();code=124
 except Exception as e:stderr.write(str(e).encode());code=127
record.update(exit_code=code,finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat());(base/'invocation.json').write_text(json.dumps(record,indent=2))
rawout=(base/'stdout.txt').read_text(errors='replace');rawerr=(base/'stderr.txt').read_text(errors='replace')
artifact='# External advisor invocation\n\n## Original user task\nBuild a usable macOS app; discuss and review with Claude, Grok, Agy. Claude must produce multiple visual concepts for the user.\n\n## Backend and final prompt\n'+a.provider+'\n\n```text\n'+data.decode()+'\n```\n\n## Invocation records\n```json\n'+json.dumps(record,indent=2)+'\n```\n\n## Raw CLI output\n### stdout\n```text\n'+rawout+'\n```\n### stderr\n```text\n'+rawerr+'\n```\n\n## Concise summary\nInvocation complete; validate contract before using as evidence.\n\n## Action items / next steps\nAssess the raw output, adopt or reject findings against this exact scope.\n'
base.with_suffix('.md').write_text(artifact);print(json.dumps({'directory':str(base),'exit_code':code,'stdout_bytes':len(rawout.encode()),'stderr_bytes':len(rawerr.encode()),'prompt_sha256':digest}),flush=True)
