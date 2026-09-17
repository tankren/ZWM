# ZWM — WM Stock Cockpit

ABAP report for SAP S/4HANA (classic LE-WM) that displays stock the way LS24 does
and offers **configurable** action buttons for **transfer**, **scrap** and
**multi-layer block / unblock**.

This repository is an [abapGit](https://abapgit.org) repository: `.abapgit.xml`
sits at the root and all SAP objects live under `src/`.

## What it does

* **Query / display** — selection screen with warehouse number, material, plant,
  storage location, stock category, special stock and batch, plus an
  *additional filter* block (storage type, storage bin, GR number, GR date,
  inspection lot, storage unit, country of origin). The result is an
  `CL_SALV_TABLE` list over `LQUA` + `MARA` + `MAKT` + `MBEW`, including
  standard price and extended cost.
* **Action buttons** — the ALV toolbar is built at runtime from the customizing
  table `ZWM_STK_ACT_1T`, so adding or changing a button is a table entry, not a
  code change. Buttons whose authorization object is not granted to the user are
  not added to the toolbar at all.
* **All movements go through function modules** — every action calls
  `L_TO_CREATE_SINGLE` (and `L_TO_CONFIRM`), with the movement type taken from
  the config table (`999` bin→bin, `309`/`311` storage-location transfer, `551`
  scrap, `344` block, `343` unblock).
* **Three-layer blocking** — SAP WM only knows `BESTQ = 'S'`, so the up-to-three
  block reasons per quant (department, reason code, reason text, blocker) are
  kept in `ZWM_BLOCKLOG_1T`. The first block posts the IM 344 posting change,
  layers 2 and 3 only add a reason, and only the release of the **last** layer
  posts the 343.

## Objects delivered

| Area | Objects |
|---|---|
| Report | `ZWM_STOCK_COCKPIT_1P` (classic report — no dynpros) |
| Transaction | `ZWM_STOCK_COCKPIT` — starts `ZWM_STOCK_COCKPIT_1P` |
| Classes | `ZCL_WM_MSG`, `ZCL_WM_ACTION_CONFIG`, `ZCL_WM_STOCK_QUERY`, `ZCL_WM_STOCK_ACTION`, `ZCL_WM_STOCK_BLOCK`, `ZCL_WM_STOCK_ALV` |
| Tables | `ZWM_STK_ACT_1T` (action buttons), `ZWM_BLOCK_RSN_1T` (block reason codes, SM30), `ZWM_BLOCKLOG_1T` (block layers) |
| Structure / table type | `ZWM_QUAN_1S`, `ZWM_QUAN_1TT` |
| Domains | `ZWM_ACTTYPE`, `ZWM_DEPT`, `ZWM_LAYER`, `ZWM_BLKSTAT` |
| Data elements | `ZWM_ACTION_ID`, `ZWM_ACTTYPE`, `ZWM_DEPT`, `ZWM_LAYER`, `ZWM_BLCREASON`, `ZWM_BLKSTAT` |
| Message class | `ZWM_MSG` (messages 001–040) |

## Import

1. In the abapGit report, create a repository for
   `https://github.com/tankren/ZWM.git`, set the **target package** (e.g. `ZWM`),
   then **Pull** and **Activate**.
2. Generate the table maintenance generator for `ZWM_BLOCK_RSN_1T` in SE11
   (Utilities → Table Maintenance Generator) so it becomes SM30-editable —
   abapGit does not transport the generator.
3. Load the seed data for `ZWM_STK_ACT_1T` (the buttons) and
   `ZWM_BLOCK_RSN_1T` (the reason codes).
4. Run transaction `ZWM_STOCK_COCKPIT` (or `SA38` with program
   `ZWM_STOCK_COCKPIT_1P`).

Full details, including the sample configuration rows, are in
[`docs/install.md`](docs/install.md).

## Notes

* No `package.devc.xml` is shipped on purpose — abapGit repositories do not store
  SAP package names; the target package is chosen in the abapGit repository
  settings.
* Warehouse customizing (`T340D`, `T300`, `T301`, `T333`, `T334`) must exist for
  the warehouse you use, otherwise the transfer-order function module cannot
  work.
* The reference transactions of the original specification use a customer
  `/RB04/` namespace and live in a different system; this project is a rebuild
  from the specification documents, not a copy of that source.
* The sources were authored outside SAP and have not been compiled or activated
  there, so a syntax error may surface during import.

## Documentation

* [`docs/design.md`](docs/design.md) — architecture and the reasoning behind each
  decision (why classic LE-WM, why one function module, why the three-layer
  table, the LUW design, the authorization approach, known limitations).
* [`docs/install.md`](docs/install.md) — prerequisites, import, post-import
  setup and sample configuration.
