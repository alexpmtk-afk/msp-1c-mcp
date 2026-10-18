"""Offline Windows PowerShell execute real metadata parser with 1C OData table-part XML shapes."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import hashlib

SCRIPT=Path(__file__).resolve().parents[1]/"bin"/"probe-newbase-contactinfo-metadata-readonly-v2.ps1"
OWNER="Catalog_Контрагенты"
CONTACT="КонтактнаяИнформация"
PART=OWNER+"_"+CONTACT

def metadata(use_set=False):
    extra=(f'<EntitySet Name="{PART}" EntityType="Test.{PART}"/>' if use_set else "")
    return f'''<?xml version="1.0" encoding="utf-8"?>
<edmx:Edmx xmlns:edmx="http://schemas.microsoft.com/ado/2007/06/edmx" Version="1.0">
 <edmx:DataServices><Schema xmlns="http://schemas.microsoft.com/ado/2008/09/edm" Namespace="Test">
 <EntityContainer Name="Container"><EntitySet Name="{OWNER}" EntityType="Test.{OWNER}"/>{extra}</EntityContainer>
 <EntityType Name="{OWNER}"><Key><PropertyRef Name="Ref_Key"/></Key>
  <Property Name="Ref_Key" Type="Edm.Guid"/>
  <NavigationProperty Name="{CONTACT}" Type="Collection(Test.{PART})"/>
 </EntityType>
 <EntityType Name="{PART}"><Property Name="НомерСтроки" Type="Edm.Int32"/>
  <Property Name="Представление" Type="Edm.String"/>
  <Property Name="Вид" Type="Edm.String"/>
  <NavigationProperty Name="Owner" Type="Test.{OWNER}"/>
 </EntityType></Schema></edmx:DataServices></edmx:Edmx>'''

class PhoneV2(unittest.TestCase):
 def test_static_boundaries(self):
    s=SCRIPT.read_text("ascii")
    for marker in ("#requires -version 2", "ParseMetadata", "NavigationProperty",
                   "PHONE_ERROR_ID=", "PHONE_ERROR_LINE=", "PHONE_EXCEPTION_TYPE=",
                   "PHONE_V2_ALREADY_EXISTS","OFFLINE_TEST_CI_ONLY",
                   "TEST_NEWBASE_CONTACTINFO_METADATA_READONLY_V2",
                   "CUSTOMER_DATA_EXPORTED=0","ONEC_WRITES=0","BITRIX_REQUESTS=0"):
        self.assertIn(marker,s)
    for denied in ("$req.Method='POST'", "RegisterTaskDefinition", "DeleteTask(",
                   "SELECT * FROM customers", "crm.item.add?", "crm.item.update?"):
        self.assertNotIn(denied,s)
    print("PHONE_METADATA_V2_WORKER_SHA256="+hashlib.sha256(SCRIPT.read_bytes()).hexdigest())

 @unittest.skipUnless(sys.platform=="win32","Windows PowerShell runtime")
 def test_native_navigation_table_part(self):
    self.execute(use_set=False)

 @unittest.skipUnless(sys.platform=="win32","Windows PowerShell runtime")
 def test_native_entityset_table_part(self):
    self.execute(use_set=True)

 def execute(self,use_set):
    with tempfile.TemporaryDirectory() as d:
     source=Path(d)/"fixture.xml";source.write_text(metadata(use_set),encoding="utf-8")
     env=os.environ.copy();env["CI"]="true"
     cp=subprocess.run(["powershell.exe","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
       "-File",str(SCRIPT),"-OfflineFixturePath",str(source)],
       capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=35,env=env)
     print("PHONE_V2_NATIVE_EXIT="+str(cp.returncode))
     print(cp.stdout[-1800:])
     self.assertEqual(cp.returncode,0,msg=cp.stderr+"\n"+cp.stdout)
     origin="PART_ENTITY_SET" if use_set else "OWNER_NAVIGATION"
     self.assertIn("PHONE_OFFLINE_ORIGIN="+origin,cp.stdout)
     self.assertIn("PHONE_OFFLINE_PROPERTIES=3",cp.stdout)
     self.assertIn("RESULT=PASS;STAGE=PHONE_METADATA_V2_OFFLINE",cp.stdout)
if __name__=="__main__":unittest.main()
