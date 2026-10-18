"""Run V3 actual Verify/CommitMap functions on Windows PowerShell + real SQLite, no CRM."""
import base64, json, os, shutil, sqlite3, subprocess, sys, tempfile
from pathlib import Path
if sys.platform!="win32":raise SystemExit("WINDOWS_ONLY")
ROOT=Path(__file__).resolve().parents[1]/"bin"
v3=(ROOT/"import-all-newbase-buyers-once-v3.ps1").read_text("ascii")
core=(ROOT/"msp-newbase-bitrix-core-v2.ps1").read_text("ascii")
def extract(s,a,b):
    i=s.index(a)
    return s[i:s.index(b,i+len(a))]
helpers="\n".join([
 extract(core,"function HexUtf8(","function Unhex("),
 extract(core,"function SqlJson(","function Http("),
 extract(core,"function Query(","function Lit("),
 extract(core,"function BResult(","function VerifyBatchList("),
 extract(v3,"function Details(","function Found("),
 extract(v3,"function Verify(","\ntry{"),
])
items=[];data={"result":{"result":{}}}
for i in range(15):
    legal=i%2==0
    guid=f"{i+200:08x}-0000-0000-0000-000000000000"
    name=("ООО Компания " if legal else "Иван Петров ")+str(i)
    item={"guid":guid,"kind":4 if legal else 3,"category":"LEGAL" if legal else "PERSON",
          "title":name,"full":"Общество пример "+str(i) if legal else "", "inn":"7701234567" if legal else ""}
    comment="Source=1C NewBase; Type="+item["category"]
    if legal:comment+="; FullName="+item["full"]+"; INN="+item["inn"]
    else:comment+="; Name="+name
    if i in (2,13): comment+=" DIFFERENT"
    crm={"id":101+i,"originId":guid,"originatorId":"MSP_ONEC_NEWBASE",
         "comments":comment,("title" if legal else "name"):name}
    data["result"]["result"]["k"+str(i)]={"item":crm}
    items.append(item)
def b64(x):
    return base64.b64encode(json.dumps(x,ensure_ascii=False).encode("utf8")).decode("ascii")
bins=list((Path(os.environ["RUNNER_TEMP"])/"msp-sqlite-acceptance").rglob("sqlite3.exe"))
if len(bins)!=1:raise RuntimeError("SQLITE_EXE_MISSING")
with tempfile.TemporaryDirectory(prefix="v3-native-reconcile-") as d:
    root=Path(d);(root/"bin").mkdir();(root/"data").mkdir()
    shutil.copy2(bins[0],root/"bin"/"sqlite3.exe")
    db=sqlite3.connect(str(root/"data"/"customers.db"))
    db.executescript("""CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY,crm_id INT,entity_kind INT,mapped_utc TEXT);
CREATE TABLE msp_initial_inflight(onec_guid TEXT PRIMARY KEY,crm_type INT,attempt_utc TEXT);
CREATE TABLE msp_initial_details_review(onec_guid TEXT PRIMARY KEY,crm_id INT,detail_state TEXT,created_utc TEXT);""")
    db.executemany("INSERT INTO msp_initial_inflight VALUES(?,?,datetime('now'))",[(x["guid"],x["kind"]) for x in items]);db.commit();db.close()
    ps=r"""$ErrorActionPreference='Stop'
$script:root='__ROOT__'
function Fail([string]$x){throw('NEWBASE_'+$x)}
function Require([bool]$x,[string]$code){if(-not $x){Fail $code}}
__HELPERS__
$script:reply=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__REPLY__'))
$objects=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__ITEMS__'))|ConvertFrom-Json
function Batch([object[]]$Commands){if($Commands.Count -ne 15){Fail 'BATCH_COUNT'};return $script:reply}
$items=New-Object Collections.ArrayList
$ids=New-Object Collections.ArrayList
foreach($x in $objects){[void]$items.Add($x)}
for($i=0;$i -lt 15;$i++){[void]$ids.Add([int](101+$i))}
try{
 $details=Verify $items $ids
 if($details.Count -ne 15){Fail 'DETAILS_COUNT'}
 if(@($details|Where-Object {$_ -eq 'DIFF'}).Count -ne 2){Fail 'DETAILS_REVIEW_COUNT'}
 CommitMap $items $ids $details
 $result=Query "SELECT (SELECT count(*) FROM msp_initial_map)||':'||(SELECT count(*) FROM msp_initial_inflight)||':'||(SELECT count(*) FROM msp_initial_details_review);"
 if($result -ne '15:0:2'){Fail 'SQLITE_STATE_MISMATCH'}
 'V3_NATIVE_RECONCILE=PASS'
}catch{
 'V3_NATIVE_RECONCILE=FAIL'
 'ERROR_ID='+$_.FullyQualifiedErrorId
 'ERROR_TYPE='+$_.Exception.GetType().Name
 'ERROR_LINE='+$_.InvocationInfo.ScriptLineNumber
 exit 3
}
"""
    for a,b in {"__ROOT__":str(root).replace("'","''"),"__HELPERS__":helpers,
                "__ITEMS__":b64(items),"__REPLY__":b64(data)}.items():
        ps=ps.replace(a,b)
    script=root/"smoke.ps1";script.write_text(ps,encoding="utf-8-sig")
    r=subprocess.run(["powershell.exe","-NoProfile","-NonInteractive","-File",str(script)],
                     capture_output=True,text=True,timeout=60,encoding="utf-8",errors="replace")
    print("V3_NATIVE_RECONCILE_EXIT="+str(r.returncode))
    print(r.stdout[-1000:])
    if r.returncode!=0:
        print(r.stderr[-1000:])
        raise SystemExit(r.returncode)
