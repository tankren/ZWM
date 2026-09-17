"! <p class="shorttext synchronized">WM stock cockpit - quant query</p>
"! Reads warehouse stock (quants) and enriches it with material, valuation and
"! blocking information. This class is read-only and has no user-interface
"! dependency, so it can be reused by any report or test.
"!
"! The selection uses the classic LE-WM quant table LQUA as the driver. Empty
"! range tables mean "no restriction", which is how an ABAP SQL IN condition
"! behaves, so the same static statement serves every combination of criteria.
"!
"! Country of origin is not part of a quant (LQUA has no HERKL); it is taken
"! from the material master and therefore filtered in ABAP, not in SQL.
CLASS zcl_wm_stock_query DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Range types for the selection criteria.
    TYPES ty_r_matnr TYPE RANGE OF matnr.
    TYPES ty_r_werks TYPE RANGE OF werks_d.
    TYPES ty_r_lgort TYPE RANGE OF lgort_d.
    TYPES ty_r_bestq TYPE RANGE OF bestq.
    TYPES ty_r_sobkz TYPE RANGE OF sobkz.
    TYPES ty_r_sonum TYPE RANGE OF lvs_sonum.
    TYPES ty_r_charg TYPE RANGE OF charg_d.
    TYPES ty_r_lgtyp TYPE RANGE OF lgtyp.
    TYPES ty_r_lgpla TYPE RANGE OF lgpla.
    TYPES ty_r_wenum TYPE RANGE OF lvs_wenum.
    TYPES ty_r_wdatu TYPE RANGE OF lvs_wdatu.
    TYPES ty_r_qplos TYPE RANGE OF qplos.
    TYPES ty_r_lenum TYPE RANGE OF lenum.
    TYPES ty_r_herkl TYPE RANGE OF herkl.

    "! Selection criteria of the cockpit. LGNUM is mandatory, every other
    "! criterion is optional.
    TYPES: BEGIN OF ty_sel,
             lgnum TYPE lgnum,
             matnr TYPE ty_r_matnr,
             werks TYPE ty_r_werks,
             lgort TYPE ty_r_lgort,
             bestq TYPE ty_r_bestq,
             sobkz TYPE ty_r_sobkz,
             sonum TYPE ty_r_sonum,
             charg TYPE ty_r_charg,
             lgtyp TYPE ty_r_lgtyp,
             lgpla TYPE ty_r_lgpla,
             wenum TYPE ty_r_wenum,
             wdatu TYPE ty_r_wdatu,
             qplos TYPE ty_r_qplos,
             lenum TYPE ty_r_lenum,
             herkl TYPE ty_r_herkl,
           END OF ty_sel.

    TYPES ty_stock TYPE zwm_quan_1s.
    TYPES tt_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    "! Reads the stock that matches the selection, ordered by storage type,
    "! storage bin and quant number.
    METHODS get_stock
      IMPORTING is_sel          TYPE ty_sel
      RETURNING VALUE(rt_stock) TYPE tt_stock.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_waers,
             bwkey TYPE bwkey,
             waers TYPE waers,
           END OF ty_waers.
    TYPES tt_waers TYPE STANDARD TABLE OF ty_waers WITH EMPTY KEY.

    "! Currency cache, so the company-code currency is not read per row.
    DATA mt_waers TYPE tt_waers.

    METHODS read_stock
      IMPORTING is_sel         TYPE ty_sel
      RETURNING VALUE(rt_lqua) TYPE STANDARD TABLE OF lqua
                               WITH EMPTY KEY.

    METHODS enrich_material
      CHANGING ct_stock TYPE tt_stock.

    METHODS enrich_blocking
      CHANGING ct_stock TYPE tt_stock.

    METHODS filter_country
      IMPORTING is_sel  TYPE ty_sel
      CHANGING  ct_stock TYPE tt_stock.

    METHODS get_currency
      IMPORTING iv_bwkey        TYPE bwkey
      RETURNING VALUE(rv_waers) TYPE waers.
ENDCLASS.


CLASS zcl_wm_stock_query IMPLEMENTATION.

  METHOD get_stock.
    DATA(lt_lqua) = read_stock( is_sel ).

    IF lt_lqua IS INITIAL.
      RETURN.
    ENDIF.

    " Every LQUA field of the display structure carries the same name, so the
    " flat assignment does the whole mapping.
    rt_stock = CORRESPONDING #( lt_lqua ).

    enrich_material( CHANGING ct_stock = rt_stock ).
    enrich_blocking( CHANGING ct_stock = rt_stock ).
    filter_country( EXPORTING is_sel = is_sel CHANGING ct_stock = rt_stock ).
  ENDMETHOD.


  METHOD read_stock.
    " An empty range table is not a restriction, so all optional criteria can be
    " expressed in one static statement.
    SELECT * FROM lqua
      WHERE lgnum = @is_sel-lgnum
        AND matnr IN @is_sel-matnr
        AND werks IN @is_sel-werks
        AND lgort IN @is_sel-lgort
        AND bestq IN @is_sel-bestq
        AND sobkz IN @is_sel-sobkz
        AND sonum IN @is_sel-sonum
        AND charg IN @is_sel-charg
        AND lgtyp IN @is_sel-lgtyp
        AND lgpla IN @is_sel-lgpla
        AND wenum IN @is_sel-wenum
        AND wdatu IN @is_sel-wdatu
        AND qplos IN @is_sel-qplos
        AND lenum IN @is_sel-lenum
      ORDER BY lgtyp, lgpla, lqnum
      INTO TABLE @rt_lqua.
  ENDMETHOD.


  METHOD enrich_material.
    DATA lt_matnr TYPE STANDARD TABLE OF matnr WITH EMPTY KEY.
    DATA lt_makt TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    DATA lt_mara TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    DATA lt_mbew TYPE STANDARD TABLE OF mbew WITH EMPTY KEY.

    lt_matnr = VALUE #( FOR ls_stock IN ct_stock ( ls_stock-matnr ) ).
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    IF lt_matnr IS INITIAL.
      RETURN.
    ENDIF.

    SELECT matnr, spras, maktx FROM makt
      FOR ALL ENTRIES IN @lt_matnr
      WHERE matnr = @lt_matnr-table_line
        AND spras = @sy-langu
      INTO TABLE @lt_makt.

    SELECT matnr, mtart, matkl, herkl FROM mara
      FOR ALL ENTRIES IN @lt_matnr
      WHERE matnr = @lt_matnr-table_line
      INTO TABLE @lt_mara.

    " MBEW has no currency; the currency belongs to the company code of the
    " valuation area and is resolved by get_currency( ).
    SELECT matnr, bwkey, stprs, peinh FROM mbew
      FOR ALL ENTRIES IN @lt_matnr
      WHERE matnr = @lt_matnr-table_line
      INTO TABLE @lt_mbew.

    LOOP AT ct_stock ASSIGNING FIELD-SYMBOL(<ls_stock>).
      READ TABLE lt_makt INTO DATA(ls_makt)
        WITH KEY matnr = <ls_stock>-matnr.
      IF sy-subrc = 0.
        <ls_stock>-maktx = ls_makt-maktx.
      ENDIF.

      READ TABLE lt_mara INTO DATA(ls_mara)
        WITH KEY matnr = <ls_stock>-matnr.
      IF sy-subrc = 0.
        <ls_stock>-mtart = ls_mara-mtart.
        <ls_stock>-matkl = ls_mara-matkl.
        <ls_stock>-herkl = ls_mara-herkl.
      ENDIF.

      READ TABLE lt_mbew INTO DATA(ls_mbew)
        WITH KEY matnr = <ls_stock>-matnr bwkey = <ls_stock>-werks.
      IF sy-subrc = 0.
        <ls_stock>-stprs = ls_mbew-stprs.
        <ls_stock>-waers = get_currency( <ls_stock>-werks ).

        " STPRS is quoted per price unit, so the extended cost must divide by
        " PEINH. A price unit of zero would raise a division by zero.
        DATA(lv_peinh) = COND peinh( WHEN ls_mbew-peinh IS INITIAL THEN 1
                                                             ELSE ls_mbew-peinh ).
        <ls_stock>-extval = ls_mbew-stprs / lv_peinh * <ls_stock>-gesme.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD enrich_blocking.
    CONSTANTS lc_status_open TYPE zwm_blkstat VALUE 'O'.

    DATA lv_lgnum TYPE lgnum.
    DATA lt_lqnum TYPE STANDARD TABLE OF lvs_lqnum WITH EMPTY KEY.
    DATA lt_log TYPE STANDARD TABLE OF zwm_blocklog_1t WITH EMPTY KEY.

    READ TABLE ct_stock INTO DATA(ls_first) INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    lv_lgnum = ls_first-lgnum.

    lt_lqnum = VALUE #( FOR ls_stock IN ct_stock ( ls_stock-lqnum ) ).
    SORT lt_lqnum.
    DELETE ADJACENT DUPLICATES FROM lt_lqnum.

    " Only open layers count for the display; released layers are history.
    SELECT * FROM zwm_blocklog_1t
      FOR ALL ENTRIES IN @lt_lqnum
      WHERE lgnum  = @lv_lgnum
        AND lqnum  = @lt_lqnum-table_line
        AND status = @lc_status_open
      INTO TABLE @lt_log.

    IF lt_log IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT ct_stock ASSIGNING FIELD-SYMBOL(<ls_stock>).
      LOOP AT lt_log INTO DATA(ls_log) WHERE lqnum = <ls_stock>-lqnum.
        CASE ls_log-layer.
          WHEN '1'.
            <ls_stock>-reason1 = ls_log-reason_text.
            <ls_stock>-blocker1 = ls_log-blocker.
          WHEN '2'.
            <ls_stock>-reason2 = ls_log-reason_text.
            <ls_stock>-blocker2 = ls_log-blocker.
          WHEN '3'.
            <ls_stock>-reason3 = ls_log-reason_text.
            <ls_stock>-blocker3 = ls_log-blocker.
          WHEN OTHERS.
            CONTINUE.
        ENDCASE.
        <ls_stock>-block_count = <ls_stock>-block_count + 1.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD filter_country.
    IF is_sel-herkl IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_keep TYPE tt_stock.
    LOOP AT ct_stock ASSIGNING FIELD-SYMBOL(<ls_stock>).
      IF <ls_stock>-herkl IN is_sel-herkl.
        APPEND <ls_stock> TO lt_keep.
      ENDIF.
    ENDLOOP.
    ct_stock = lt_keep.
  ENDMETHOD.


  METHOD get_currency.
    DATA ls_waers TYPE ty_waers.

    READ TABLE mt_waers INTO ls_waers WITH KEY bwkey = iv_bwkey.
    IF sy-subrc = 0.
      rv_waers = ls_waers-waers.
      RETURN.
    ENDIF.

    " Valuation area -> company code -> currency.
    SELECT SINGLE a~waers FROM t001k AS k
      INNER JOIN t001 AS a ON a~bukrs = k~bukrs
      WHERE k~bwkey = @iv_bwkey
      INTO @DATA(lv_waers).

    ls_waers-bwkey = iv_bwkey.
    ls_waers-waers = lv_waers.
    APPEND ls_waers TO mt_waers.

    rv_waers = lv_waers.
  ENDMETHOD.

ENDCLASS.
