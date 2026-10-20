"""Windows-native PowerShell smoke: exercise the real initial-import row parser without CRM/SRV."""
from pathlib import Path
import os
import subprocess
import sys
import unittest

SRC = Path(__file__).resolve().parents[1] / "bin" / "import-all-newbase-buyers-once-v1.ps1"

@unittest.skipUnless(sys.platform == "win32", "PowerShell.exe Windows regression only")
class NativeRowParsing(unittest.TestCase):
    def test_first_20_rows_from_sqlite_ascii_hex(self):
        s=SRC.read_text(encoding="ascii")
        start=s.index("function DecodeHex(")
        end=s.index("function Details(",start)
        part=s[start:end]
        synthetic=[]
        for i in range(20):
            guid=f"{i+1:08x}-0000-0000-0000-000000000000"
            cat=("LEGAL","PERSON","REVIEW")[i%3]
            short=("ООО Тест" if cat=="LEGAL" else "Иван Петров") + str(i)
            fields=[guid,cat,short.encode().hex().upper(),"".encode().hex().upper(),short.encode().hex().upper(),"7701234567".encode().hex().upper()]
            synthetic.append("|".join(fields))
        import base64
        encoded=base64.b64encode("\n".join(synthetic).encode("utf-8")).decode("ascii")
        script = ("$ErrorActionPreference='Stop';"
                  "function Fail([string]$x){throw('NEWBASE_'+$x)};"
                  +part
                  +"$data=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+encoded+"'));"
                  +"try{$x=Rows $data;if($x.Count -ne 20){throw('COUNT_'+$x.Count)};"
                  +"if($x[0].title -ne 'ООО Тест0'){throw 'TEXT_MISMATCH'};"
                  +"if($x[1].kind -ne 3){throw 'PERSON_MISMATCH'};"
                  +"'IMPORT_FIRST_20_ROWS_RUNTIME=PASS'}"
                  +"catch{'IMPORT_FIRST_20_ROWS_RUNTIME=FAIL';"
                  +"'ERR_TYPE='+$_.Exception.GetType().FullName;"
                  +"'ERR_ID='+$_.FullyQualifiedErrorId;"
                  +"'ERR_LINE='+$_.InvocationInfo.ScriptLineNumber;exit 3}")
        proc=subprocess.run(["powershell.exe","-NoProfile","-NonInteractive","-Command",script],
                            capture_output=True,text=True,timeout=25)
        self.assertEqual(proc.returncode,0,msg=proc.stdout[-1600:]+"\n"+proc.stderr[-1000:])
        self.assertIn("IMPORT_FIRST_20_ROWS_RUNTIME=PASS",proc.stdout)

if __name__=="__main__":
    unittest.main()
