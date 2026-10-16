# Bitrix24 portal binding — approved target, NOT installed

- Portal: `https://b24-uwmjda.bitrix24.ru/` (user-supplied on 2026-10-16)
- App type: **server-side local application with UI**.
- Search placement: `CRM_DETAIL_SEARCH`.
- Placement label: `Клиенты из 1С`.
- Scopes: `crm`, `placement`, `user_basic`.
  The third scope is used solely to validate the current OAuth user via
  `user.current`. `crm` is required by the search widget's placement.
- Status: *source prepared; not deployed, app not installed*.
- `member_id`: **UNKNOWN** until a genuine installed-app OAuth callback.
- `client_id`, `client_secret`, access/refresh tokens, worker token:
  **not present in repository** and must remain in protected runtime secrets.
- HTTPS origin/handler URL: **UNKNOWN**, cannot safely invent or reuse
  existing 1C agent Funnel. Choose a dedicated approved HTTPS reverse proxy
  after inspecting existing REMOTE services and port/conflict policy.
- SRV: 6,433 client index PASS under LOCAL SERVICE; no inbound exposure.
- OData native registration / Option B: paused; FTS5 snapshot is not dynamic.
- No CRM writes or customer bulk import. `crmShowFoundEntities` is only
  a transient list. Selecting an item requires separately approved mapping
  of onec_guid to CRM entity ID and deduplication.
- Required first end-to-end acceptance: synthetic, no real customer data;
  then read-only named match, authorized portal user, deny foreign domain,
  deny invalid/expired OAuth, rate limit, 20 max results, no database copies.

## Bitrix24 administrator step — only *after* the HTTPS handler is live

Use `Приложения → Разработчикам → Другое → Локальное приложение`.
Create a server-side app; select the scopes above. Complete installation,
capture `member_id` automatically server-side, register
`CRM_DETAIL_SEARCH` with `placement.bind` under the authenticated app.
Do not create an incoming webhook as a substitute; it cannot register
this placement. Do not send credentials or tokens in chat/GitHub.

Official docs:
https://apidocs.bitrix24.ru/api-reference/widgets/crm/detail-search.html
https://apidocs.bitrix24.ru/api-reference/user/user-current.html
https://apidocs.bitrix24.ru/local-integrations/local-apps.html
