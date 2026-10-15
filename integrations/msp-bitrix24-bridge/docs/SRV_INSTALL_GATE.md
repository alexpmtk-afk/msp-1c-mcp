# msp-bitrix24-bridge: two-stage SRV installation acceptance

1. Native PowerShell 2.0 preflight on physical SRV: PASS reported on 2026-10-15.
2. Pin every downloaded file to a reviewed exact Git commit. Verify staged hashes.
3. Stage bridge.ps1 and bridge.ini under temporary directory with installer. The installer checks administrator and SRV, creates isolated ProgramData root and task with LOCAL SERVICE account.
4. BOOT and recurring 5-minute triggers are registered **disabled**, allowing a separate manual execution without any background changes.
5. Run smoke-system.ps1 to manually start only MspBitrix24Bridge and confirm fresh LOCAL_SERVICE SAFE_IDLE heartbeat.
6. If PASS, separately enable using enable-system.ps1 -ConfirmEnable. Confirm future 5-minute heartbeat without interactive RDP session.
7. Schedule reboot check in approved server maintenance window, do not reboot SRV merely to test.
8. Emergency rollback: rollback-system.ps1 -ConfirmDisable (only MspBitrix24Bridge task).

Working MSP task MspOnecHttpsAgentSystem, GitHub transport, IIS and 1C shall not be modified. SAFE_IDLE never sends customer data and cannot write 1C.
