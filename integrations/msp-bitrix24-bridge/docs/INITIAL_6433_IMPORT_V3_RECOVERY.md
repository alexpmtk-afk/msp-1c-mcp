# Initial 6,433 buyers: V2 recovery with V3, 18 October 2026

**Target:** one-time initial load of all active buyers from TEST `NewBase` customer
snapshot on physical SRV to existing Bitrix24 CRM, not ongoing synchronization.

## Actual SRV evidence

- V1 failed at `READ_SOURCE_BATCH`, `MAPPED=0`.
- V2 got past SQLite and created CRM records, but stopped at
  `CRM_CREATE_BACKREAD`, `CRM_DETAILS_BACKREAD_MISMATCH`, `MAPPED=5`.
- V2 local SQLite had 15 unresolved `msp_initial_inflight` entries.
- Read-only SRV/CRM audit **passed**, confirming all 15 inflight CRM entries
  exist, with **15/15 exact origin identity**, **15/15 exact names**,
  **0 missing**, **0 ambiguous**, and **13 exact + 2 different comments**.
- No buyer names, INNs or GUIDs were sent to GitHub as part of this audit.
- The 15 records **must not be created again**. They already exist in CRM.

## Corrective design

- V3 does not delete or replace the V1/V2 source or task.
- V3 launcher requires the exact V2 failure receipt, idle V2 task with
  zero triggers, the accepted 15-card audit receipt, and SQLite local
  state of exactly five mapped plus fifteen unresolved records.
- V3 first re-fetches existing CRM records by `originatorId` and
  `originId`. Only after exact CRM ID, source GUID and name/title backread
  does it mark an existing record as locally mapped.
- Expected comments may differ for otherwise correctly matched records.
  V3 records those mismatches in local
  `msp_initial_details_review` instead of stopping all 6,433 customers.
  The mismatches must be separately corrected. They are **not** silently
  claimed to be synchronized.
- New CRM records are created only when origin lookup returns no record
  and the matching source GUID has no unresolved create marker. A
  durable marker is written locally before every new CRM creation.
- On a transport ambiguity V3 stops rather than retrying an add blindly.
- V3 marks `PASS_WITH_DETAILS_REVIEW` for 6,433 origin/name-verified
  mappings with unresolved comments, or `PASS` only when there are no
  details mismatches. It is not allowed to claim complete field equality
  with a non-zero review count.
- V3 uses 10 records per batch and a maximum of 800 batches. The
  full snapshot includes 1,941 LEGAL, 4,486 PERSON and six REVIEW entries.
  No automatic update schedule is enabled.

## Evidence limits

Windows/GitHub CI passed 142 main and 13 supplementary tests,
including a *native Windows PowerShell + real SQLite* simulation of
15 existing CRM entities, exactly two comment mismatches, and
15 saved mappings with zero remaining inflight. The simulator does not
test the physical SRV, real Bitrix24 throttling, or a complete 6,433-row
transfer.

## Acceptance

Only SRV status `MAPPED=6433;TARGET=6433`, zero inflight, and a separate
read-only Bitrix24 count/identity reconciliation can confirm the user's
primary goal of 6,433 visible customers. Any non-zero
`COMMENTS_REVIEW` remains a documented follow-up; production 1C stays
untouched.

Do not rerun V1 or V2; do not manually clear pending source GUIDs or
delete CRM records.
