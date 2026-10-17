# MSP Bitrix24 ← 1C: native buyer-change registration design (draft)

Status: engineering design only. **No production 1C changes, no exchange-node creation,
no SelectChanges/NotifyChangesReceived POST calls, no SRV schedule activation.**

## Verified facts and boundaries

- TEST `NewBase`: 6,433 active buyers in the protected SRV SQLite store, including
  1,941 legal entities, 4,486 natural persons and 6 unclassified. These are
  **TEST counts**; production population must be measured separately.
- TEST OData exposes `Catalog_Контрагенты` and its
  `Catalog_Контрагенты_КонтактнаяИнформация` table part.
- Prior TEST OData metadata showed only the unrelated
  `ExchangePlan_ОбменСПодключаемымОборудованиемOffline`. Do not reuse it.
- The S4 v1 survey failed during `PARSE_EXCHANGE_PLANS` with generic
  `RUNTIME_ERROR`. No successful source change registration was demonstrated.
- The new isolated `survey-exchange-plan-metadata-service-v2.ps1` is **GET-only**.
  Its parser checks `SelectChanges` and `NotifyChangesReceived`, not the
  obsolete internal guess `ConfirmChanges`. Declared function names in
  `$metadata` are *hints*, not proof of executable support.
- The direct SRV → Bitrix24 outbound HTTPS design is a separate transport.
  No customer's personal data should transit VPS/GitHub/Telegram.
- The actual production UNF platform/build, configuration modification policy,
  OData publishing policy, and permitted extension mechanism must be
  verified on a production-like TEST clone, **before** any write action.

## Chosen trigger and transport

1. Create a **dedicated non-distributed exchange plan** in a compatible,
   separately reviewed 1C extension. Register the `Контрагенты` object
   (automatic change registration) for an independent Bitrix consumer node.
   Record creation, edits and deletions; filtering only `Покупатель=true`
   *at registration time* would lose buyer deactivations.
2. Audit how phones, email and dependent contact records are stored in this
   particular UNF build. If changes are not part of a counterparty write,
   additionally register the corresponding objects or use a scoped event
   subscription that registers the owning counterparty GUID.
3. **No HTTP or Bitrix calls inside a 1C object-write event.**
   Registration is local to the 1C transaction and must not depend on network.
4. An independent machine-owned SRV agent polls its own change stream
   approximately every minute (target, not a real-time guarantee). To read
   registered changes through standard OData, `SelectChanges` uses POST with
   `DataExchangePoint` and monotonically tracked `MessageNo`.
   This is a state-changing operation; use it **only on approved TEST** after
   validating permissions and the actual OData signature.
5. For every changed GUID, fetch the current customer data using authorized
   OData GETs. Persist `source-event/message ID`, GUID, classification,
   relevant fields, content hash and a Bitrix outbox item within the same
   durable local SQLite transaction. De-duplicate repeated messages.
6. **Only after the SQLite commit and readback** confirm 1C receipt using
   `NotifyChangesReceived` (POST). A timeout after either POST is ambiguous:
   do not advance or reissue numbers blindly; reconcile local receipt and
   source-side state before retry.
7. Independently transmit queued updates to Bitrix24 REST in bounded batches.
   Record the source GUID ↔ CRM entity ID mapping and last acknowledged
   payload hash. If the API response is ambiguous, read Bitrix24 first; never
   blindly create another card. A CRM outage must not block 1C user writes.
8. Keep a daily 08:30 source reconciliation pass to detect missed or
   out-of-band changes; send only rows that actually differ. Do not overwrite
   newer edits made in CRM without an explicit field-ownership policy.

## Proposed acceptance stages

- **S4A: Offline-only.** CI tests XML metadata parsing (1492 entity sets,
  escaped names, absent action declarations, malformed XML, duplicate plans,
  prohibited DTD). Native PowerShell 2 syntax remains a separate SRV gate.
- **S4B: One-shot GET on TEST SRV.** Inspect any leftover v1 task/state first
  (without deleting it). Run a hash-pinned V2 worker only under the existing
  LocalService identity, manual and triggerless; report aggregate metadata and
  sanitized error class. No SelectChanges / ack / Bitrix requests.
- **S4C: Extension compatibility (offline / TEST clone).** Confirm platform
  supports exchange-plan inclusion of borrowed counterparty objects and
  autobooking; validate contact-data event coverage and rollback. Do not
  install a speculative extension on the production information base.
- **S4D: Controlled synthetic TEST event.** Create a dedicated TEST buyer,
  update its phone and buyer flag, then validate one change registration for
  each event, GUID upsert, durable outbox and correct ack order. Test crashed
  worker, duplicate event, ambiguous ack, unavailable Bitrix API and recovery.
- **S4E: Production go/no-go.** Requires separate explicit authorization,
  backups, isolated credentials, rights review, retention/PII review,
  observability, load testing and an unambiguous rollback plan.

## Source references

- 1C platform change registration:
  https://v8.1c.ru/platforma/sluzhba-registratsii-izmeneniy/
- Exchange plans:
  https://v8.1c.ru/platforma/plan-obmena/
- 1C documented OData operations:
  https://its.1c.eu/db/v8323doc/bookmark/dev/TI000002299
- Extension enhancement history:
  https://wonderland.v8.1c.ru/blog/razvitie-mekhanizma-rasshireniy/
- Local contract:
  `docs/CUSTOMER_SCOPE_POLICY.md`,
  `docs/SYNC_ARCHITECTURE_OPTION_B.md`.
