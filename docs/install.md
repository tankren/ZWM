# ZWM Stock Cockpit — Installation & Configuration

Everything here is done **after** importing the repository with abapGit.

---

## 1. Prerequisites

### 1.1 Warehouse customizing (mandatory)

The cockpit posts through `L_TO_CREATE_SINGLE`. That function module reads the warehouse
customizing and fails with `BWLVS_WRONG` / `VLTYP_WRONG` / `NLTYP_WRONG` when it is missing.
Before using the cockpit in a warehouse, the following must exist:

| Table | Contents |
|---|---|
| `T340D` | Movement type control per warehouse number |
| `T300` / `T301` | Storage type / storage type control |
| `T333` | Movement type control (LE-WM) |
| `T334` | Stock removal / placement control |

Check with transaction `LS03N` (storage type) and `LT01` before the first cockpit run.

### 1.2 Authorization

Each button can carry its own authorization check (columns `AUTH_OBJECT`, `AUTH_FIELD`,
`AUTH_VALUE` of `ZWM_STK_ACT_1T`). When `AUTH_OBJECT` is empty the button is open to
everyone. The check is executed through the generic `AUTHORITY_CHECK` function module,
so the object **and** the field name are both taken from the table.

---

## 2. Import with abapGit

1. Start the abapGit report (`ZABAPGIT` / `ZABAPGIT_STANDALONE`).
2. Create or open the online repository you already set up.
3. **Set the target package to `ZWM`** in the repository settings
   (Advanced → Change Remote / Repository Settings).
   The repository does not carry a `package.devc.xml`, so abapGit takes the package from
   this setting — that is intentional, because abapGit repositories deliberately do not
   store package names.
4. **Pull**. Objects are created in the order the dependency graph requires
   (domains → data elements → tables → message class → classes → program).
5. **Activate** all objects (abapGit activates after import; check the log for
   "Objects activated" and re-run activation in SE80/SE11 if anything stayed inactive).

### Import order notes

The repository contains no `package.devc.xml`. This is deliberate: abapGit's own
documentation states that repositories do not store SAP package names and that the
software component must **not** be part of the package file, so the target system decides.
If your abapGit version complains about a missing package file, create the package `ZWM`
manually in SE21 before pulling.

---

## 3. Post-import steps that abapGit cannot do

### 3.1 Table maintenance generator for `ZWM_BLOCK_RSN_1T` (SM30)

abapGit does not reliably serialise table maintenance generators, so this must be
generated **once** per system:

1. `SE11` → open table `ZWM_BLOCK_RSN_1T` → **Display** → `Utilities` →
   **Table Maintenance Generator**.
2. Authorization group: use your local convention (e.g. `&NC&` for no check).
3. Function group: create a new one, e.g. `ZWM_BLOCK_RSN`.
4. Maintenance type: **one step**.
5. Over view / maintenance screen: leave the defaults, then **Create**.
6. The table is now editable with `SM30` → view `ZWM_BLOCK_RSN_1T`.

To restrict editing per department, maintain authorizations for the generated function
group in your roles.

### 3.2 Seed data

Both configuration tables start empty. The cockpit shows a message
(`No action buttons are configured in table ZWM_STK_ACT_1T`) and no buttons until
`ZWM_STK_ACT_1T` has at least one active row.

#### `ZWM_STK_ACT_1T` — action buttons

Maintain with `SM30`/`SE16` (or `SM34` if you put it in a view cluster).
`ACTION_ID` doubles as the ALV function code, so keep it short and unique.

| ACTION_ID | SORT_NO | ACTION_TYPE | ICON_NAME | BUTTON_TEXT | QUICKINFO | FM_NAME | BWART | ACTIVE |
|---|---|---|---|---|---|---|---|---|
| `TRANSFER_BIN` | 10 | `TRANSFER` | `ICON_TRANSFER` | Transfer | Transfer stock to another bin | `L_TO_CREATE_SINGLE` | `999` | `X` |
| `TRANSFER_SLOC` | 20 | `TRANSFER` | `ICON_TRANSFER` | Transfer SLoc | Transfer to another storage location | `L_TO_CREATE_SINGLE` | `311` | `X` |
| `SCRAP` | 30 | `SCRAP` | `ICON_DELETE` | Scrap | Scrap stock from the bin | `L_TO_CREATE_SINGLE` | `551` | `X` |
| `BLOCK` | 40 | `BLOCK` | `ICON_LOCKED` | Block | Block stock (adds a block layer) | `L_TO_CREATE_SINGLE` | `344` | `X` |
| `UNBLOCK` | 50 | `UNBLOCK` | `ICON_UNLOCKED` | Unblock | Release a block layer | `L_TO_CREATE_SINGLE` | `343` | `X` |
| `BLOCK_INFO` | 60 | `INFO` | `ICON_DISPLAY` | Reasons | Display the block reasons of a bin | *(empty)* | *(empty)* | `X` |

Notes:

- `LGNUM` empty = the button is offered in every warehouse. Fill it to restrict a button
  to one warehouse number.
- `ACTION_TYPE` must be one of the `ZWM_ACTTYPE` domain values:
  `TRANSFER`, `SCRAP`, `BLOCK`, `UNBLOCK`, `INFO`.
- **`BWART` is the real configurable switch.** Every action posts a transfer order through
  `L_TO_CREATE_SINGLE`; only the movement type and the destination differ. To use a
  different movement type (e.g. `309` instead of `311`), change `BWART` — no code change.
- `FM_NAME` records which function module the action posts through. The call itself is
  encapsulated in `ZCL_WM_STOCK_ACTION` / `ZCL_WM_STOCK_BLOCK` so the very large
  `L_TO_CREATE_SINGLE` interface stays type-checked; the column documents the link and is
  used for validation. `INFO` has no movement, so `FM_NAME`/`BWART` stay empty.
- `AUTH_OBJECT`/`AUTH_FIELD`/`AUTH_VALUE`: leave all three empty for an unrestricted button.
  Example: `AUTH_OBJECT = M_LGNUM`, `AUTH_FIELD = ACTVT`, `AUTH_VALUE = 01`.
  When `AUTH_FIELD` is empty it defaults to `ACTVT`.

#### `ZWM_BLOCK_RSN_1T` — block reason codes

Maintained with `SM30` (after step 3.1). Key is `DEPT` + `LAYER` + `REASON_CODE` (+ `LGNUM`).

| DEPT | LAYER | REASON_CODE | LGNUM | REASON_TEXT | DEFAULT_FLAG | ACTIVE |
|---|---|---|---|---|---|---|
| `QM` | 1 | `Q001` | *(empty)* | Quality hold - inspection pending | `X` | `X` |
| `QM` | 1 | `Q002` | *(empty)* | Quality hold - complaint | | `X` |
| `LOG` | 2 | `L001` | *(empty)* | Logistics hold - stock count | `X` | `X` |
| `PP` | 3 | `P001` | *(empty)* | Production hold - rework | `X` | `X` |

`DEPT` values are the `ZWM_DEPT` domain: `QM`, `LOG`, `PP`, `FERT`, `SAM`, `VERS`.
`LAYER` is 1, 2 or 3. `LGNUM` empty = valid for every warehouse.

---

## 4. Running the cockpit

1. Transaction `SA38` (or `SE38`) → program **`ZWM_STOCK_COCKPIT`** → Execute.
   Create a transaction code for it if you want one.
2. **Selection screen**: warehouse number is mandatory; material, plant, storage location,
   stock category, special stock indicator/number and batch are optional ranges.
   The **Additional filter** block narrows by storage type, storage bin, GR number,
   GR date, inspection lot, storage unit and country of origin.
3. **Result list**: an ALV grid of quants, one row per quant (LS24-like). The columns for
   the three block layers (`REASON1..3`, `BLOCKER1..3`) and `BLOCK_COUNT` are filled from
   `ZWM_BLOCKLOG_1T`.
4. **Toolbar**: the standard ALV functions plus one button per active row of
   `ZWM_STK_ACT_1T` that the user is authorized for. Select exactly one row, then press a
   button.
5. **Transfer / Scrap** opens a dialog for quantity, movement type and the destination
   storage location/type/bin, then posts the transfer order.
6. **Block** opens a dialog for layer, department, reason code and reason text. If you
   enter a layer lower than the next free one, the existing layer's reason is changed
   instead of a new layer being added (this is the "modify reason" function of the
   specification).
7. **Unblock** asks for the layer and the release reason. **The release reason code must
   equal the block reason code**, exactly as the specification requires.
8. **Reasons** displays the block layers of the selected quant in a popup.

The list is re-read after every action, so the new stock and the new block layers are
immediately visible.

---

## 5. How blocking works (why there is a custom table)

WM itself only knows "blocked" (`LQUA-BESTQ = 'S'`) or "not blocked". The specification
requires **up to three independent block layers per quant**, each with its own department,
reason and blocker. Therefore:

- **Layer 1** creates the posting change (`L_TO_CREATE_SINGLE`, movement type `344`,
  source bin = destination bin, `I_BESTQ = ''`) **and** writes a row in `ZWM_BLOCKLOG_1T`.
- **Layers 2 and 3** only write a row in `ZWM_BLOCKLOG_1T` — no WM movement.
- **Releasing a non-last layer** only updates the row.
- **Releasing the last open layer** posts the reverse posting change (movement type `343`,
  `I_BESTQ = 'S'`) and updates the row.

The transfer order numbers of both movements are stored in the row (`TANUM_BLOCK`,
`TANUM_REL`), so the WM document can be traced back from the cockpit. Released layers are
kept (status `R`) rather than deleted, because the specification's report needs to show
"was blocked before but has since been released".

---

## 6. Known limitations

1. **Not compile-checked.** The objects were authored as abapGit files on a workstation and
   were never created in the SAP system, so the first activation in your system is also the
   first syntax check. Any activation error will be reported by abapGit with a line number.
2. **No WM business data in the development system.** `LQUA` is empty and there is no
   `T340D` entry for warehouse 442, so the transfer-order function modules cannot be
   executed end-to-end there. Only the pure logic (layer arithmetic) has ABAP Unit tests.
3. **`TABL/DT` name limit is 16 characters.** `ZWM_BLOCK_REASON_1T` (19) is rejected by SAP
   itself, which is why the reason table is `ZWM_BLOCK_RSN_1T` (16).
4. **The reference transactions do not exist in the target system.** `/RB04/YL2_LAGER_*`
   and `/RB04/YT2_BLKD` are Bosch naming; this cockpit is a rebuild from the specification,
   not a copy of that source.
5. `ZWM_QUAN_1S` is a structure and `ZWM_QUAN_1TT` its table type, both delivered by
   abapGit. Table types cannot be created through the ADT API, but abapGit handles them.
