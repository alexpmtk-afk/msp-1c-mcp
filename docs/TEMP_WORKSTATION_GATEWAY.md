> **SUPERSEDED (2026-10-12): DO NOT RE-ENABLE WINDOWS IP FORWARDING.** The user observed lost Internet access after the temporary Windows subnet-router experiment and restored service by disabling IPv4 forwarding on both interfaces. Use [GitHub Windows 1C Bridge](GITHUB_WINDOWS_1C_BRIDGE.md) for the new local-LAN PowerShell Remoting/COM executor design. This page remains only as historical context; its routing steps are NOT an active runbook.

# Temporary gateway: Windows workstation -> 1C host

Status: **proposed, not configured**, recorded on 2026-10-12.

## Goal

Enable ChatGPT-led, REMOTE-executed, read-only 1C research while the user's
Windows workstation is powered on, without changing the legacy 1C server.
Keep the production code, API credentials and eventual MCP tools on the
MSP Ubuntu VPS. Later replace the gateway with an always-on site/network peer
without changing the higher-level 1C connector.

## Planned path

ChatGPT -> private msp-server-bridge (reviewed fixed actions)
-> REMOTE Ubuntu (MSP) -> Tailscale tailnet
-> user's Windows workstation (temporary subnet router)
-> one approved internal Windows 1C host -> 1C HTTP/OData service (if published).

Public GitHub is a **source repository**, not a secure secret store
and not itself a means of reaching a private Windows network.

## Minimal pilot, in stages

1. Check if Tailscale is already installed on the user's **workstation**
   (not the Windows Server 2008 R2 host); identify whether workstation OS
   is supported. Confirm membership in the same tailnet as MSP VPS.
2. Before changing routing, verify user has local administrative rights
   on the workstation and authorization to use the network.
3. Verify the internal target is reachable from the workstation (RDP currently
   works). Do not change old 1C server firewall, IP address or netmask.
4. Configure the workstation as a Tailscale **subnet router**, with Windows
   IP forwarding enabled, advertising **only the 1C host as a /32 route**
   rather than the entire private subnet; approve the route in Tailscale
   admin and apply least-privilege tailnet policy.
5. On REMOTE, confirm existing Tailscale settings and possible route overlap,
   then enable acceptance of approved routes only as appropriate; verify
   host reachability and the expected traffic path. No RDP/SMB/WinRM should
   become Internet-accessible.
6. Investigate whether 1C has a published HTTPS/OData interface. Basic network
   reachability by itself does **not** mean a 1C API exists.
7. Only after confirming safe API access and separate 1C service identity:
   deploy the read-only diagnostic client on REMOTE, store credentials
   outside Git and whitelist specific GitHub bridge probes.

## Safety and limitations

- The user's workstation may be turned off, interrupting connectivity.
  **24/7 production availability remains a separate requirement**.
- Current Tailscale Windows client is not supported on Windows Server 2008 R2:
  install nothing on the legacy server for this approach.
- Windows subnet routing needs local administrator privileges, IP forwarding,
  explicit route approval and tailnet access rules. These steps are pending.
- The original network report showed different masks on workstation and
  server. Do not normalize or modify them. Connectivity through subnet
  routing must be verified empirically; RDP working today is not proof.
- Public code must not contain passwords, private host IPs, complete document
  data or other operational secrets.
- Posting documents can only be rehearsed in a controlled TEST infobase with
  explicit authorization.
- Before later migration to an always-on gateway: deploy new route peer,
  verify, move route approval and access rules, retire workstation route,
  retest. Do not keep conflicting advertised /32 routes unintentionally.

## Official references

- https://tailscale.com/docs/features/subnet-routers?tab=windows
- https://tailscale.com/docs/install/windows
