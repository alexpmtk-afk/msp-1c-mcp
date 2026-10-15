#requires -version 2
# DEPRECATED: prior partial staging recovery has completed; this version is fail-closed.
# An ACL defect was discovered on a deployed SRV. Never recursively strip inherited rights.
Write-Output 'RESULT=FAIL;STAGE=BITRIX24_PARTIAL_RECOVERY;GATE=DEPRECATED_REQUIRES_ACL_REVIEW'
exit 1
