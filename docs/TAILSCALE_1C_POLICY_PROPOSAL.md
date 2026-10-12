# Tailscale policy proposal for temporary access to 1C

Status: **DESIGN ONLY / NOT APPLIED**, 2026-10-12.

## Verified starting point

The tailnet's full policy shown by the owner contains exactly the default
permissive grant:

```json
{"src": ["*"], "dst": ["*"], "ip": ["*"]}
```

It also includes the default self-device Tailscale SSH rule in `check` mode.
The visible machine list shows five user-owned devices under one account
(two online, three offline). Do NOT assume that this proves there are no
other tagged, shared or service-owned devices.

Wildcard grant destinations include approved subnet routes. Adding a more
specific 1C grant while leaving the wildcard rule unchanged DOES NOT
restrict access. Grants combine additively; there is no implicit deny-rule
override.

## Design goal

1. Preserve ordinary communication between the owner's user-owned
   Tailscale devices so existing VPS/Hermes links continue working.
2. Enable **only the designated MSP Ubuntu VPS** to reach a single
   1C Windows host IP, and only on the confirmed 1C diagnostic/API port(s).
3. Leave the Tailscale SSH `check` rule as-is.
4. Prevent other tailnet nodes and approved subnet ranges from reaching
   the legacy Windows 1C host via a new advertised subnet route.

## Non-executable illustrative grant model

Replace the broad grant with a scoped `autogroup:member` ->
`autogroup:self` grant *if the actual devices are verified user-owned
and no tagged/service/shared device needs another scope*. This pattern
allows access between a user's devices but doesn't grant subnet access.

Add a separate `msp-vps` -> `one-c-host` grant for the verified
OData/API port. **The API port is still unknown**: do not assume 443
and do not enable all ports to the Windows host. The values below are
illustrative placeholders, **not** ready-to-paste policy.

```json
{
  "hosts": {
    "msp-vps": "REPLACE_WITH_VPS_TAILSCALE_IP",
    "one-c-host": "REPLACE_WITH_PRIVATE_1C_HOST_IP",
    "other-device": "REPLACE_WITH_OTHER_PEER_TAILSCALE_IP"
  },
  "grants": [
    {
      "src": ["autogroup:member"],
      "dst": ["autogroup:self"],
      "ip": ["*"]
    },
    {
      "src": ["msp-vps"],
      "dst": ["one-c-host"],
      "ip": ["tcp:REPLACE_WITH_CONFIRMED_API_PORT"]
    }
  ],
  "tests": [
    {
      "src": "msp-vps",
      "accept": ["one-c-host:REPLACE_WITH_CONFIRMED_API_PORT"]
    },
    {
      "src": "other-device",
      "deny": ["one-c-host:REPLACE_WITH_CONFIRMED_API_PORT"]
    }
  ]
}
```

The test `deny` field is an **assertion**, not a blocking ACL rule.
Only an absence of a permissive matching grant prevents traffic.
Keep the existing `ssh` section from the user's policy intact.

## Required verification BEFORE policy change

- Take a separate protected backup of the current full policy, keeping it
  out of public Git.
- Verify device ownership, tags, shared nodes, required peer-to-peer
  connections, Tailscale SSH and any existing approved subnets/routes.
  Note: `autogroup:self` does **not** apply to tagged devices.
- Determine the Windows 1C service's actual publication mode and API port;
  file-mode UNF and RDP do not imply an OData endpoint exists.
- Simulate policy and run `tests` + Tailscale UI preview/validation
  before clicking Save. Verify connectivity to VPS (including Hermes)
  and retain a working recovery path outside the changed tailnet.
- Ensure Windows workstation forwarding and host-restricted /32 subnet
  route are approved separately, and route reachability is independently
  tested from VPS; no Internet publication of legacy RDP/SMB/WinRM.
- Public Git stores **only** this placeholder design. Real addresses,
  authenticated policies, secrets and business data remain private.

## References

- https://tailscale.com/docs/reference/syntax/grants
- https://tailscale.com/docs/reference/targets-and-selectors
- https://tailscale.com/docs/reference/examples/grants
- https://tailscale.com/docs/reference/syntax/policy-file
- https://tailscale.com/docs/features/subnet-routers?tab=windows
