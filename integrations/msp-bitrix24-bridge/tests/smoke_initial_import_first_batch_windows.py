"""Windows CI, actual SQLite executable + first batch PS parser, synthetic buyers only."""
import pathlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile

if sys.platform != "win32":
    raise SystemExit("WINDOWS_ONLY")

base=pathlib.Path(__file__).resolve().parents[1]
worker=(base/"bin"/"import-all-newbase-buyers-once-v2.ps1").read_text(encoding="ascii")
start=worker.index("function SqlRead(")
end=worker.index("function Details(",start)
real_functions=worker[start:end]
root_env=pathlib.Path(__import__("os").environ["RUNNER_TEMP"])
choices=list((root_env/"msp-sqlite-acceptance").rglob("sqlite3.exe"))
if len(choices)!=1: raise RuntimeError("SQLITE_TOOL_NOT_FOUND")

with tempfile.TemporaryDirectory(prefix="msp-bulk-source-v2-") as temp:
    root=pathlib.Path(temp)
    (root/"bin").mkdir()
    (root/"data").mkdir()
    shutil.copy2(choices[0],root/"bin"/"sqlite3.exe")
    db=root/"data"/"customers.db"
    conn=sqlite3.connect(str(db))
    conn.executescript("""CREATE TABLE customers(onec_guid TEXT PRIMARY KEY,onec_type TEXT,name_short TEXT,
name_full TEXT,person_name TEXT,inn TEXT,buyer INTEGER,deletion_mark INTEGER,invalid INTEGER);
CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY);""")
    fixtures=[]
    for i in range(20):
        cat=["LEGAL","PERSON","REVIEW"][i%3]
        name=("ООО Тестовая компания" if cat=="LEGAL" else "Петров Иван")+" "+str(i)
        fixtures.append((f"{i+1:08x}-0000-0000-0000-000000000000",cat,name,name,name,
                         "7701234567" if cat=="LEGAL" else "",1,0,0))
    conn.executemany("INSERT INTO customers VALUES (?,?,?,?,?,?,?,?,?)",fixtures)
    conn.commit()
    conn.close()
    # These exact SQL and parsing statements also appear in the shipping V2 worker.
    qstart=worker.index('  $query="SELECT c.onec_guid')
    qend=worker.index('  $phase=',qstart)
    first_batch=worker[qstart:qend]
    if "  $pending=SqlRead $query" not in first_batch:
        raise RuntimeError("SOURCE_SQL_NOT_PARENTHESIZED_AS_SINGLE_VARIABLE")
    if '  $items=Rows $pending' not in first_batch:
        raise RuntimeError("SOURCE_ROW_DECODER_NOT_USED")
    escaped_root=str(root).replace("'","''")
    test=f"""$ErrorActionPreference='Stop'
$root='{escaped_root}'
$BatchSize=20
function Fail([string]$Code){{throw('NEWBASE_'+$Code)}}
{real_functions}
try{{
{first_batch}
 if($items.Count -ne 20){{throw('SOURCE_BATCH_COUNT='+$items.Count)}}
 if($items[0].title -ne 'ООО Тестовая компания 0'){{throw 'FIRST_LEGAL_MISMATCH'}}
 if($items[1].kind -ne 3){{throw 'SECOND_PERSON_NOT_CONTACT'}}
 if($items[2].category -ne 'REVIEW'){{throw 'REVIEW_CATEGORY_MISSING'}}
 'FIRST_20_READ_SQLITE_AND_DECODE=PASS'
}}catch{{
 'FIRST_20_READ_SQLITE_AND_DECODE=FAIL'
 'ERR_TYPE='+$_.Exception.GetType().Name
 'ERR_ID='+$_.FullyQualifiedErrorId
 'ERR_LINE='+$_.InvocationInfo.ScriptLineNumber
 exit 3
}}
"""
    f=root/"smoke.ps1";f.write_text(test,encoding="ascii",errors="xmlcharrefreplace")
    # Script contains Cyrillic text in fixture assertion; use UTF-8 with BOM for Windows PowerShell 5.
    f.write_text(test,encoding="utf-8-sig")
    p=subprocess.run(["powershell.exe","-NoProfile","-NonInteractive","-File",str(f)],
                     capture_output=True,text=True,timeout=60,encoding="utf-8",errors="replace")
    print("SOURCE_BATCH_NATIVE_RETURN="+str(p.returncode))
    print(p.stdout[-1500:])
    if p.returncode!=0:
        print(p.stderr[-1500:])
        raise SystemExit(p.returncode)
