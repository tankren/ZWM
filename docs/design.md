# ZWM Stock Cockpit — Design

Warehouse stock cockpit for classic LE-WM on S/4HANA: query/display stock (LS24-like),
plus configurable action buttons (Transfer / Scrap / Block / Unblock / Reasons) that all
execute through standard SAP function modules.

- **Program**: `ZWM_STOCK_COCKPIT` — classic report (selection screen + `cl_salv_table`)
- **Package**: `ZWM` — "WM Custom Object Package"
- **Delivery**: abapGit (`~/opencode/ZWM/abapgit`)
- **Message class**: `ZWM_MSG`

---

## 1. Scope

| In scope | Out of scope |
|---|---|
| Read/display warehouse stock (`LQUA` + `MAKT`/`MARA`/`MBEW`) | Embedded EWM (`/SCWM/*`) |
| Transfer bin→bin and storage location→storage location | Handling units (HU) packing |
| Scrap (551/555) | Inventory counting (LI01N/LI20N) |
| Multi-layer block / unblock (3 layers) | QM inspection-lot workflow (QM02 path) |
| Configurable toolbar buttons, authorization per button | Output/printing, label printing, RFC/OData |

---

## 2. Why classic WM (LE-WM) and not EWM

The target system is **S/4HANA 2023 (SAP_BASIS 758)**. Verified on the system:

- Classic LE-WM tables are present and active: `LQUA`, `LQUAB`, `LAGP`, `LTAK`, `LTAP`,
  `LTBK`, `LTBP`, `T340D`, `MLGN`, `MLGT`.
- No `/SCWM/*` tables, no warehouse-442 customizing in `T340D`.

**Decision**: build on the classic LE-WM quant/TO model (`LQUA` + transfer orders).
This also matches the reference screenshots, which show `Typ`/`StorageBin`/`Total Stock`/
`Available stock`/`Stock` columns — i.e. quant fields.

---

## 3. Why one function module covers Transfer, Scrap, Block and Unblock

`L_TO_CREATE_SINGLE` (function group `SAPLL03B`) was inspected on the system. Its interface is:

```
I_LGNUM  warehouse number        I_VLTYP / I_VLBER / I_VLPLA   source storage type/section/bin
I_BWLVS  movement type           I_NLTYP / I_NLBER / I_NLPLA   destination type/section/bin
I_MATNR  material                I_RLTYP / I_RLBER / I_RLPLA   return storage type/bin
I_WERKS  plant                   I_BESTQ                        source stock category
I_LGORT  storage location        I_SOBKZ / I_SONUM              special stock indicator/no.
I_CHARG  batch                   I_ANFME / I_ALTME              requested quantity / UoM
I_KOMPL  complete TO immediately I_COMMIT_WORK
```

Every stock movement in this cockpit is "create a transfer order", and they differ **only** in
movement type, source/destination and source stock category. That is precisely why the action
table (`ZWM_STK_ACT_1T`) can be config-driven: a new button is a new row, not new code.

### Movement type mapping

| Button | Movement type | Source stock category `I_BESTQ` | Source → destination |
|---|---|---|---|
| Transfer bin → bin | `999` | `''` (unrestricted) | same or different storage type/bin |
| Transfer storage location → storage location | `309` / `311` | `''` | different `I_LGORT` |
| Scrap (unrestricted) | `551` | `''` | bin → scrap |
| Scrap (blocked) | `555` | `S` | bin → scrap |
| **Block** | **`344`** | `''` | source bin = destination bin (posting change) |
| **Unblock** | **`343`** | `S` | source bin = destination bin (posting change) |
| Confirm transfer order | — | — | `L_TO_CONFIRM` |

Movement types verified in `T156T`: `343` = "TF blocked to unre." (blocked → unrestricted),
`344` = blocked/unrestricted posting change. This matches the reference specification
(`BLOCK&UNBLOCK.docx`): *first block ⇒ IM movement 344, last release ⇒ IM movement 343*.

The movement type is **not hard-coded**: it is read from `ZWM_STK_ACT_1T-BWART`, so a customer
using `309` instead of `311` changes one table cell.

### Why `L_TO_CONFIRM` is needed

`L_TO_CREATE_SINGLE` creates the transfer order; stock only moves when the TO is confirmed.
For a single-step cockpit action `ZCL_WM_STOCK_ACTION` passes `I_KOMPL = 'X'` so the TO is
completed immediately, and still exposes an explicit `confirm( )` for two-step warehouses.

---

## 4. Why the 3-layer blocking needs its own table

From the specification:

> Up to **3 reasons/layers** can block one Quant. Only the **first** block generates an
> IM-level 344 movement; layers 2 and 3 merely add a reason. After the **last** release the
> system generates an IM-level 343 movement and the S status is removed.

WM itself only knows two states — blocked (`LQUA-BESTQ = 'S'`) or not. It has no concept of
"who blocked it and why, three times over". Therefore:

- **WM** holds the physical block (`BESTQ = 'S'`, movement types 344/343).
- **`ZWM_BLOCKLOG_1T`** holds the business layers (up to 3 per quant), each with department,
  reason code, reason text, blocker and timestamp.

Rules enforced by `ZCL_WM_STOCK_BLOCK`:

1. Block on a quant with 0 existing layers → insert layer 1 **and** post 344.
2. Block on a quant that already has ≥1 layer → insert next layer, **no** WM movement.
3. Block when 3 layers already exist → rejected (`max_layers_reached`).
4. Release one layer while other layers remain → mark layer released, **no** WM movement.
5. Release the last open layer → mark released **and** post 343.
6. Release reason code must match the block reason code → validated (`release_reason_mismat`).

The release history is kept in the log row (releaser, release reason, timestamps) rather than
overwriting, because the specification's report needs to show *"was blocked before but has
since been released"*.

### The LUW question

Blocking writes two things that must stay consistent: the WM transfer order and the log row.
`ZCL_WM_STOCK_BLOCK` therefore calls `L_TO_CREATE_SINGLE` with **`I_COMMIT_WORK = space`**,
writes the log row, and only then issues a single `COMMIT WORK AND WAIT`. If the log insert
fails, `ROLLBACK WORK` discards the queued transfer order. This is the reason the commit flag
differs from `ZCL_WM_STOCK_ACTION` (where it is `'X'`, because a transfer has nothing else to
keep in step).

---

## 5. Why the buttons are configuration-driven

`06_Lager_xxx_stock_transfer.docx` states: *"The buttons can be add/modified individually over
Customizing."* and each Lager_xxx transaction *"is linked to desired group of people
(responsibility in the plant) and granted over authorisation."*

So `ZWM_STK_ACT_1T` holds, per button:

- presentation: label, icon, quickinfo, sort order, active flag
- behaviour: action type, function module name, movement type
- security: authorization object / field / value
- scope: warehouse number (blank = all warehouses)

`ZCL_WM_STOCK_ALV` builds the ALV toolbar at runtime from this table, so a new button or a new
department restriction is a table entry, not a transport of code. The **`ACTION_ID` doubles as
the ALV function code**, which is how a button press is routed back to its configuration row.

`FM_NAME` records which function module the action posts through. The call itself is
encapsulated in `ZCL_WM_STOCK_ACTION` / `ZCL_WM_STOCK_BLOCK` rather than performed dynamically,
because `L_TO_CREATE_SINGLE` has a very large interface that is only safe when type-checked at
compile time. Configurability that actually changes behaviour comes from `BWART`.

---

## 6. Data model

### Domains and data elements

| Object | Definition |
|---|---|
| Domain `ZWM_ACTTYPE` | CHAR 10 — `TRANSFER`, `SCRAP`, `BLOCK`, `UNBLOCK`, `INFO` |
| Domain `ZWM_DEPT` | CHAR 4 — `QM`, `LOG`, `PP`, `FERT`, `SAM`, `VERS` |
| Domain `ZWM_LAYER` | CHAR 1 — `1`, `2`, `3` |
| Domain `ZWM_BLKSTAT` | CHAR 1 — `O` (open), `R` (released) |
| Data element `ZWM_ACTION_ID` | CHAR 10, built-in type |
| Data element `ZWM_ACTTYPE` | on domain `ZWM_ACTTYPE` |
| Data element `ZWM_DEPT` | on domain `ZWM_DEPT` |
| Data element `ZWM_LAYER` | on domain `ZWM_LAYER` |
| Data element `ZWM_BLCREASON` | CHAR 4, built-in type |
| Data element `ZWM_BLKSTAT` | on domain `ZWM_BLKSTAT` |

`INFO` was added to `ZWM_ACTTYPE` so the "info button" of the reference screens (which shows
the block layers of a bin) is also configurable and appears in the same toolbar.

### `ZWM_STK_ACT_1T` — configurable action buttons

| Field | Type | Key | Meaning |
|---|---|---|---|
| `MANDT` | `MANDT` | X | Client |
| `ACTION_ID` | `ZWM_ACTION_ID` | X | Identifier **and** ALV function code, e.g. `TRANSFER_BIN` |
| `SORT_NO` | `INT4` | | Toolbar order |
| `ACTION_TYPE` | `ZWM_ACTTYPE` | | `TRANSFER` / `SCRAP` / `BLOCK` / `UNBLOCK` / `INFO` |
| `ICON_NAME` | `ICONNAME` | | Toolbar icon (`ICON_*`) |
| `BUTTON_TEXT` | `TEXT20` | | Button label |
| `QUICKINFO` | `TEXT60` | | Tooltip |
| `FM_NAME` | `RS38L_FNAM` | | Function module the action posts through |
| `BWART` | `BWART` | | Movement type — the real configurable switch |
| `LGNUM` | `LGNUM` | | Warehouse number, blank = all |
| `AUTH_OBJECT` | `XUOBJECT` | | Authorization object |
| `AUTH_FIELD` | `XUFIELD` | | Authorization field (blank → `ACTVT`) |
| `AUTH_VALUE` | `CHAR40` | | Expected authorization value |
| `ACTIVE` | `XFELD` | | Button enabled |
| `ERDAT`/`ERZET`/`ERNAM`/`AEDAT`/`AEZET`/`AENAM` | | | Audit |

`CONTFLAG = C` (customizing), `TABART = APPL1`.

### `ZWM_BLOCK_RSN_1T` — block reason codes (SM30)

| Field | Type | Key | Meaning |
|---|---|---|---|
| `MANDT` | `MANDT` | X | Client |
| `DEPT` | `ZWM_DEPT` | X | Department |
| `LAYER` | `ZWM_LAYER` | X | `1` / `2` / `3` |
| `REASON_CODE` | `ZWM_BLCREASON` | X | Reason code |
| `LGNUM` | `LGNUM` | | Warehouse number, blank = all |
| `REASON_TEXT` | `TEXT60` | | Default reason text |
| `DEFAULT_FLAG` | `XFELD` | | Pre-selected for this dept/layer |
| `ACTIVE` | `XFELD` | | Selectable |
| audit fields | | | |

`CONTFLAG = C`, `TABART = APPL1`. A table maintenance generator is generated once in SE11 so
the table is editable with **SM30** — see `install.md`.

### `ZWM_BLOCKLOG_1T` — block layers per quant

Key: `MANDT`, `LGNUM`, `LQNUM`, `LAYER`. `LQUA`'s real key is `MANDT`+`LGNUM`+`LQNUM`, so the
quant is fully identified by `LGNUM` + `LQNUM`; `LAYER` completes the key.

| Group | Fields |
|---|---|
| Quant identification | `LGNUM`, `LQNUM`, `LGTYP`, `LGPLA`, `MATNR`, `WERKS`, `LGORT`, `CHARG`, `BESTQ`, `SOBKZ`, `SONUM`, `MEINS`, `GESME` |
| Layer | `LAYER` (1–3), `DEPT`, `REASON_CODE`, `REASON_TEXT`, `BLOCKER`, `BLOCK_DATE`, `BLOCK_TIME`, `TANUM_BLOCK` |
| Release | `STATUS` (`O` open / `R` released), `REL_REASON_CODE`, `REL_REASON_TEXT`, `RELEASER`, `REL_DATE`, `REL_TIME`, `TANUM_REL` |

`TANUM_BLOCK` / `TANUM_REL` record the transfer order number of the 344 / 343 movement so the
WM document can be traced back from the cockpit. `CONTFLAG = A`, `TABART = APPL0`.

### `ZWM_QUAN_1S` / `ZWM_QUAN_1TT` — ALV output

Flat display structure built from `LQUA` (quant) + `MAKT` (description) + `MARA` (material
type/group/country of origin) + `MBEW` (standard price) + `ZWM_BLOCKLOG_1T` (block layers).
`ZWM_QUAN_1TT` is its table type.

Columns: `LGNUM`, `LGTYP`, `LGPLA`, `LQNUM`, `KOBER`, `MATNR`, `MAKTX`, `WERKS`, `LGORT`,
`MTART`, `MATKL`, `CHARG`, `REVLV`, `HERKL`, `MEINS`, `BESTQ`, `SOBKZ`, `SONUM`, `GESME`,
`VERME`, `EINME`, `AUSME`, `WDATU`, `VFDAT`, `QPLOS`, `ZEUGN`, `LETYP`, `SPGRU`,
`BLOCK_COUNT`, `REASON1..3`, `BLOCKER1..3`, `STPRS`, `WAERS`, `EXTVAL`.

Two things worth recording:

- **`MBEW` has no currency field.** The currency for `STPRS` is resolved through
  `T001K` (valuation area → company code) and `T001` (`WAERS`), cached per valuation area.
- **`STPRS` is quoted per price unit `PEINH`**, so the extended cost is computed as
  `STPRS / PEINH * GESME` with a guard for `PEINH = 0`.
- `HERKL` (country of origin) is **not** on `LQUA`, so that selection criterion is applied in
  ABAP after the material enrichment, not in the `LQUA` `WHERE` clause.

---

## 7. Architecture

```
ZWM_STOCK_COCKPIT  (report)
├── selection screen 1000          image.png
├── ALV result list (cl_salv_table) image2.png   ← ZCL_WM_STOCK_ALV
│      dynamic toolbar from ZWM_STK_ACT_1T
├── detail popup (POPUP_GET_VALUES) image3.png   ← transfer / scrap
├── block / unblock popup                        ← ZCL_WM_STOCK_BLOCK
└── block-reasons popup (cl_salv_table)
        │
        ├── ZCL_WM_STOCK_QUERY    read LQUA + MAKT/MARA/MBEW + ZWM_BLOCKLOG_1T → ZWM_QUAN_1TT
        ├── ZCL_WM_STOCK_ACTION   transfer / scrap  → L_TO_CREATE_SINGLE + L_TO_CONFIRM
        ├── ZCL_WM_STOCK_BLOCK    block / unblock   → L_TO_CREATE_SINGLE (344/343) + ZWM_BLOCKLOG_1T
        ├── ZCL_WM_ACTION_CONFIG  read ZWM_STK_ACT_1T / ZWM_BLOCK_RSN_1T, AUTHORITY_CHECK
        └── ZCL_WM_MSG            message collection
```

**Separation of concerns** (per code-quality standards: small, single-responsibility units):

- `ZCL_WM_ACTION_CONFIG` is the only class that reads the config tables. It returns typed
  structures, so nothing else knows the table layout. This is the dependency-injection seam:
  the other classes receive the config object in their constructor, they do not fetch it.
- `ZCL_WM_STOCK_QUERY` is read-only and has no UI dependency → unit-testable.
- `ZCL_WM_STOCK_ACTION` and `ZCL_WM_STOCK_BLOCK` perform the writes. The actual
  `CALL FUNCTION` is isolated in one private method each, so the decision logic
  (which movement type, is this the last layer, is the reason valid) can be tested without
  a WM document.
- `ZCL_WM_STOCK_ALV` owns only presentation and event routing.
- `ZCL_WM_MSG` centralises message-class access; no literal message text in business logic.

### Why a report and not a module pool

The reference screens are classic dynpros, and a module pool with screens 0100–0500 was the
first design. It was abandoned for a concrete delivery reason: **dynpros are serialised by
abapGit as separate files** (flow logic in its own ABAP file, plus a screen XML whose format
changed repeatedly across abapGit releases). Hand-writing that format risks breaking the whole
repository import. abapGit's own development guideline says new dynpro screens and popups
should not be added to the source code.

A classic report is fully safe, because:

- `SELECTION-SCREEN` statements live in the ABAP source and are **not** serialised separately.
- `cl_salv_table` provides the LS24-like grid and the dynamic toolbar.
- `POPUP_GET_VALUES` provides the input dialogs; its screen is SAP's, so nothing is serialised.

The functional behaviour is the same as the reference transactions.

---

## 8. User interface

| Element | Reference | Content |
|---|---|---|
| Selection screen 1000 | `image.png` | Warehouse number (mandatory), material, plant, storage location, stock category, special stock indicator/number, batch; plus the **Additional filter** block: storage type, storage bin, GR number, GR date, inspection lot, storage unit, country of origin. |
| ALV result list | `image2.png` | One row per quant. Header shows warehouse / material / description. Toolbar = standard ALV functions + **dynamically generated action buttons** from `ZWM_STK_ACT_1T`. |
| Transfer / Scrap dialog | `image3.png` | Requested quantity (defaults to available stock), movement type, destination storage location / type / bin. |
| Block / Unblock dialog | `BLOCK&UNBLOCK.docx` | Layer (1–3), department, reason code, reason text. Unblock additionally validates that the release reason matches the block reason. |
| Reasons popup | `BLOCK&UNBLOCK.docx` | Layer count and per-layer reason/blocker/date — the "info button" screen. |

The result list is re-opened after every action, so the new stock and the new block layers are
immediately visible — this mirrors the reference behaviour ("Save → returns to previous screen
→ refresh shows reason code, reason text, blocker").

---

## 9. Error handling

- Every FM call is wrapped; `SY-SUBRC` and the `EXCEPTIONS` list are converted into messages
  through `ZCL_WM_MSG` (message class `ZWM_MSG`). No raw `MESSAGE` statements in classes.
- Business rejections (4th block layer, reason mismatch on release, quantity > available,
  no stock) are returned as a **structured result**, not raised as exceptions.
- The commit strategy differs deliberately per class and is documented in section 4.

## 10. Security

Each action button carries its own authorization check. Because the authorization *object and
field* both come from a table, the classic `AUTHORITY-CHECK` statement cannot be used (it
requires literal field names). The cockpit therefore calls the generic
**`AUTHORITY_CHECK`** function module, passing `AUTH_OBJECT`, `AUTH_FIELD` (default `ACTVT`)
and `AUTH_VALUE`.

Note its **inverted protocol**: the function raises `USER_IS_AUTHORIZED` on success, so
`SY-SUBRC = 1` means *authorized*. This is easy to get backwards and is called out in the code.

A button the user is not authorized for is **not added to the toolbar at all**, so departments
only see the movements they may perform — mirroring the reference specification's role table.

---

## 11. Known limitations and assumptions

1. **Not compile-checked in SAP.** The objects were authored as abapGit files on a workstation;
   they were never created in the target system, because the connected user lacks the
   `S_ABPLNGVS` workbench authorization and SAP writes were ruled out. The first activation in
   the target system is therefore also the first syntax check.
2. **No WM business data in the development system.** `LQUA` is empty and `T340D` has no
   customizing for warehouse 442. The transfer-order function modules cannot be executed
   end-to-end there. ABAP Unit tests cover the pure decision logic (layer arithmetic); the FM
   calls are exercised only in a system with warehouse customizing.
3. **Warehouse customizing is a prerequisite**: `T340D`, `T300`/`T301`, `T333`, `T334` must
   exist before the buttons can post.
4. **Table maintenance generator** for `ZWM_BLOCK_RSN_1T` is created once in SE11
   (see `install.md`); abapGit does not reliably serialise it.
5. **No `package.devc.xml`** is shipped. abapGit repositories deliberately do not store package
   names (and must not store the software component), so the target package is set in the
   abapGit repository settings — `ZWM`, which already exists.
6. **Transparent table names are limited to 16 characters** by SAP itself. That is why the
   reason table is `ZWM_BLOCK_RSN_1T` and not `ZWM_BLOCK_REASON_1T` (19 characters, rejected
   by `validateNewObject`). Structures, data elements and domains allow 30.
7. The reference transactions `/RB04/YL2_LAGER_*` and `/RB04/YT2_BLKD` do **not** exist in the
   target system — that prefix is the customer's naming. This is a **rebuild from the
   specification**, not a source copy.
