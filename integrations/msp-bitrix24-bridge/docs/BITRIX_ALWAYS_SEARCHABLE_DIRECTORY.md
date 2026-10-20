## PS2 LocalService worker runtime acceptance (next, zero network)

`bin/probe-bitrix-worker-runtime-service.ps1` is an offline smoke:
under LOCAL SERVICE verify actual PowerShell 2.0 x64, signed staged source
hashes, ability to load System.Web.Extensions JavaScriptSerializer,
synthetic Unicode JSON and UTF-8 roundtrip, and read-only SQLite
6,433 customers / 6,433 index / quick_check. It must reject configured
or enabled worker. It writes only aggregate PASS/FAIL to the machine state
receipt and **never queries a customer's name**, calls HTTP/1C/Bitrix,
or touches SQLite.

`bin/run-bitrix-worker-runtime-smoke.ps1` is the elevated PS2 one-time
runner: hash-pin and syntax check the probe, register one manually
started zero-trigger task under LOCAL SERVICE, accept the status and
database unchanged, delete that exact temporary task on PASS.
It does not enable the worker, set any token, start a listener, alter the
existing collector or remove the prior failed S4 exchange-plan survey.
A FAIL may leave a temporary task; never blindly rerun without
read-only diagnosis.

## Machine-side offline staging (not a live Bitrix connection)

`bin/stage-bitrix-outbound-code.ps1` prepares the already checked
SRV's existing machine-owned `query-bitrix-search-index.ps1` with
a backwards-compatible stdin/hex adapter and installs the inactive
`bitrix-search-outbound-once.ps1` source only. Before changes it checks
the accepted 6433-row DB, all safe-idle flags, old query script hash,
main collector boot-OFF. It pins both new files by SHA-256, makes an
atomic NTFS swap of just the query adapter, and retains the original
adapter in machine-owned staging for possible rollback. No 1C access,
no calls to Bitrix, no worker config, no worker token, no worker
scheduler task, no outbound HTTPS. Do not re-run if failed or staged.
A future explicit acceptance must test .NET System.Web.Extensions and
real PS2 LOCAL SERVICE runtime before any live worker enablement.

## Prepared machine-only outbound Bitrix search worker (not deployed)

`bin/bitrix-search-outbound-once.ps1` is PowerShell 2.0 (ASCII), code-only
until a dedicated HTTPS relay, registered Bitrix app, and separate
machine-DPAPI worker-token provisioning are accepted. It refuses to run
unless executing as LOCAL SERVICE on SRV, an already accepted 6433-row
search index exists, a machine-owned worker.ini explicitly says ACTIVE=1,
and BASE_URL is the pinned VPS Tailscale hostname with a distinct
/b24-relay path. It **does not reuse or change** the existing 1C queue,
1C bridge agent or public :8443 endpoint.

Each invocation: HTTPS GET /worker/next with a strong machine-secret
header -> validate bounded query type/length/id -> invoke local SQLite
search adapter with Unicode query sent only as ASCII UTF-8 HEX over
standard input (not visible in process command line) -> return up to
20 GUID/name matches as ASCII-escaped JSON via HTTPS POST /worker/result.
Uses the previously verified machine curl and CA bundle; no incoming
SRV listener, no password in arguments, no user-profile files, no query
text or customer names in diagnostic stdout. CURL config with token
is passed through anonymous process stdin; no persistent secret file.
No 1C/Bitrix write operations. No automatic schedule or service created.
The bounded result is transferred to VPS **only after explicit enablement**.

`query-bitrix-search-index.ps1` now supports
`-ReadHexQueryFromStandardInput -OutputUtf8Hex` for lossless Cyrillic
and to avoid personal search strings in process listings. The original
read-only JSON CLI mode remains available.

Required before a live user test: SRV runtime System.Web.Extensions
availability on Windows Server 2008 R2/PS2, dedicated HTTPS path
and proxy verified independently without touching Hermes or 1C service,
private worker token provisioned with restrictive NTFS/DPAPI, a synthetic
closed-loop test, then explicit opt-in of machine worker ACTIVE=1.
The initial SQLite snapshot is static while Option B remains paused.

### Before creating the local FTS5 index

The one-shot installer first creates a **machine-owned SQLite consistent
backup** in `C:\ProgramData\MspCustomerStore\backups\customers-pre-bitrix-search-v1.db`,
using SQLite `.backup`, and verifies its `quick_check` and 6,433 unique
GUIDs. Only after backup verification does it stage scripts and launch
the FTS5 build. This backup contains personal data and MUST stay within
the existing protected SRV folder; never attach or upload it to GitHub,
VPS or chat. Existing main collector autostart remains disabled.

## Implemented local read-only Bitrix lookup preparation, 16 Oct 2026

S4 (native registration) is PAUSED at user direction after
`PARSE_EXCHANGE_PLANS/RUNTIME_ERROR`. Do not rerun the survey.
The prior one-time `MspCustomerStoreExchangeSurvey` task may remain
in Task Scheduler; it was created without triggers. Its cleanup must
be independently verified, not silently deleted during Bitrix work.

Priority switched to exposing the already S3-accepted local customer
list for **Bitrix24 CRM_DETAIL_SEARCH** (no bulk CRM creation).
Official API: https://apidocs.bitrix24.ru/api-reference/widgets/crm/detail-search.html
An authenticated Bitrix app with `placement,crm` rights needs a public
HTTPS iframe handler and a safe search-data route. Neither handler nor
Bitrix portal/app credentials are configured. The existing GitHub/
Tailscale remote transport and SRV loopback OData are NOT a live widget
handler and must not be presented as such.

The new `bin/build-bitrix-search-index.ps1` creates FTS5/trigram
`customer_search_v1` inside the **existing machine-owned SQLite DB**
without altering `customers`. It requires LOCAL SERVICE and accepted
6,433-row S3 receipt; one-shot and fail-closed. Names, person names,
and nullable INN are indexed in the protected DB.

`bin/query-bitrix-search-index.ps1` uses the machine-only
LOCAL SERVICE context to return **at most 20 matches as UTF-8 JSON**,
search text >=3 characters, and COMPANY or CONTACT intent.
FTS5 handles Cyrillic case insensitive substrings. REVIEW entries remain
queryable in both categories, with `needsReview` set. SQL query
injection is prevented by encoding the exact query as hex inside
an FTS5 quoted phrase. The adapter is a local CLI, not a network API.
Only the future authenticated HTTPS widget handler may call it.
Do not publish SRV 2008R2, SQLite or IIS OData to the Internet.
No PII leaves SRV at this stage.

Bitrix24 placement can only be genuinely connected after an approved
HTTPS transport, installed OAuth/local app, and Bitrix portal identity.
Sending all 6,433 records to a VPS, Bitrix Disk or CRM is NOT part of
this read-only search preparation.

# MSP Bitrix24: Always-searchable 1C buyer directory (15 Oct 2026)

**Status:** User-confirmed PRODUCT GOAL; target architecture/proposed technical
implementation, NOT activated in Bitrix24, 1C or SRV.

## What the manager must be able to do

- Open the Client field in an appropriate Bitrix24 CRM form and begin typing
  the beginning or part of a customer name.
- See possible existing **Bitrix24** companies/contacts and matching clients
  from the **complete, current 1C buyer directory**, including companies
  and natural persons with no INN.
- Choose an existing CRM entity if present. If the customer exists in
  1C but **does not** yet exist in Bitrix24 CRM, create/link the appropriate
  company/contact **upon selection**, after checking for duplicates.
- If not in 1C and not in CRM, permit new-client workflow under rules
  still to be agreed; do NOT silently create a source 1C record.
- Multiple managers must search concurrently without causing any full
  scan or additional demand-driven OData query to 1C.

**Key distinction:** 'all buyers are SEARCHABLE from Bitrix24' does not
necessarily mean 'precreate all buyer entities in Bitrix24 CRM'.
The second option is possible but can clutter CRM, create duplicates,
and is not needed to meet the stated workflow.

## Bitrix24-supported integration point

Official REST widget **`CRM_DETAIL_SEARCH`**, accessed by an installed
local application with `crm, placement` rights:
https://apidocs.bitrix24.com/api-reference/widgets/crm/detail-search.html

Confirmed documented behavior:
1. A user types at least **3 characters** in the Contact or Company
   field of the CRM 'Client' block.
2. An installed application's entry appears alongside native CRM matches.
   User **clicks the application entry** to start external search.
3. Handler receives `PLACEMENT_OPTIONS.searchQuery` and
   `entityTypeName=COMPANY|CONTACT`. Authenticated handler queries a
   protected **search index**, not the 1C OData endpoint directly.
4. The handler passes options to `crmShowFoundEntities`; Bitrix renders
   them in its selector.
5. Selecting an external option emits `onCrmEntityIsNeedToCreate`.
   After verifying stable GUID mapping and CRM duplicates, the application
   creates or links the CRM record, then signals `crmShowCreatedEntity`
   with actual Bitrix entity ID.

**Caution:** This is not automatic first-keystroke completion; an extra
application-choice click after >=3 characters is documented. If seamless
live suggestions without this click are essential, evaluate a custom UI
integration separately. Portal-specific availability/rights not tested.

## Data plane and query plan

- 1C TEST/production as authoritative master for customer reference
  -> change registration **Option B** -> one durable SRV local index
  (SQLite suggested; compatibility/security validation pending).
- Index includes all eligible buyer identities `Ref_Key`, type, normalized
  search/display name, company full name (when present), nullable INN,
  source version and CRM link status.
- For an incremental update, touch only changed GUID, not all 6,433.
- Search request from Bitrix sends **short query + entity type**; search
  indexes and limits suggestions (e.g., top 10-20), never transfers all
  6,433 rows per keystroke.
- User's CRM status 'already linked' versus 'found in 1C only' must be
  determined by `bitrix_links` and a duplicate check in CRM. Never
  create a second CRM item for the same `Ref_Key`.
- Separate natural-person search without INN; company search with optional
  organization full name and INN. Six unknown type records flagged for
  review and must not silently disappear.
- No external client names, INNs or GUIDs in public logs, GitHub or Telegram.

## Network reachability issue — NOT solved yet

The current SRV 1C agent is an **outbound HTTPS poll** design. A Bitrix
external-search widget requires a prompt **HTTPS handler reachable from
Bitrix**, plus quick access to a searchable index.

A SQLite file on SRV alone **does not** automatically make it accessible
to a cloud Bitrix24 application. The existing slow/polling bridge must not
be misrepresented as an already functional real-time search transport.
Options to evaluate safely:
A. Authenticated, narrowly scoped *private query relay* that accesses SRV
   index without publishing the legacy SRV directly. Feasibility and
   latency still unknown.
B. Separate minimal, protected **search-only projection** at a trusted
   online application host, refreshed from SRV by change events. This
   exports restricted personal data (client names/types), hence requires
   explicit security/data-residency approval, encryption, RBAC and
   retention policy. No such mirror created or authorized.

Do not expose the raw 2008 R2 server to the Internet, share DB through
SMB, or publish 1C OData as a search endpoint.
Proposed experience is not guaranteed 'always online'; SLA/availability
and fallback require design and monitoring. Freshness targets must be
measured, not invented.

## Acceptance criteria

- All 6,433 eligible TEST buyers are queryable by suitable name terms,
  subject to resolving missing display labels and six unknown types.
- Legal organizations and people without INN are both findable.
- Search returns a small list and never scans all buyer rows or calls
  1C OData for each search.
- Change in 1C causes the locally indexed entry to update through
  source-side registration, demonstrably without a global rescan.
- Existing Bitrix CRM links retained; never duplicate by GUID.
- External selection results in an actionable CRM item only after
  authorization and duplicate checks.
- Test simultaneous search load and freshness; report real latencies.
- No sync activation, data transfer outside SRV, production changes
  or 1C writes before separate explicit authorization.

References:
https://apidocs.bitrix24.com/api-reference/widgets/crm/detail-search.html
https://helpdesk.bitrix24.com/open/25516596/
