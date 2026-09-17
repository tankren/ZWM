"! <p class="shorttext synchronized">WM stock cockpit - stock movements</p>"
"! Executes the quantity-based movements of the cockpit: transfers and scrap.
"!
"! Both are "create a transfer order" operations that differ only in the
"! movement type and the destination, so a single implementation serves both
"! and the movement type comes from the action configuration
"! (table ZWM_STK_ACT_1T) instead of being hard-coded.
"!
"! Blocking and unblocking are NOT handled here: they are posting changes with
"! their own multi-layer bookkeeping and live in ZCL_WM_STOCK_BLOCK.
"!
"! The result carries a message number rather than a message text, so that all
"! wording stays in message class ZWM_MSG and none of it leaks into this class.
CLASS zcl_wm_stock_action DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! What the user entered on the detail screen.
    TYPES: BEGIN OF ty_request,
             quantity   TYPE lqua_gesme,
             bwart      TYPE bwart,
             dest_lgort TYPE lgort_d,
             dest_lgtyp TYPE lgtyp,
             dest_lgpla TYPE lgpla,
           END OF ty_request.

    "! Outcome of a movement. SUCCESS decides whether MSG_NO is a success or a
    "! failure message.
    TYPES: BEGIN OF ty_result,
             success TYPE abap_bool,
             tanum   TYPE tanum,
             msg_no  TYPE symsgno,
             msg_v1  TYPE symsgv,
             msg_v2  TYPE symsgv,
           END OF ty_result.

    "! Posts the movement configured in IS_ACTION for the stock of IS_STOCK.
    METHODS execute
      IMPORTING is_stock          TYPE zwm_quan_1s
                is_action         TYPE zcl_wm_action_config=>ty_action
                is_request        TYPE ty_request
      RETURNING VALUE(rs_result)  TYPE ty_result.

    "! Confirms an existing transfer order. Needed only for warehouses that
    "! work with two-step transfer orders; one-step warehouses let
    "! L_TO_CREATE_SINGLE complete the order through I_KOMPL.
    METHODS confirm
      IMPORTING iv_lgnum         TYPE lgnum
                iv_tanum         TYPE tanum
      RETURNING VALUE(rs_result) TYPE ty_result.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_to_request,
             lgnum TYPE lgnum,
             bwlvs TYPE bwlvs,
             matnr TYPE matnr,
             werks TYPE werks_d,
             lgort TYPE lgort_d,
             charg TYPE charg_d,
             bestq TYPE bestq,
             sobkz TYPE sobkz,
             sonum TYPE lvs_sonum,
             anfme TYPE lqua_gesme,
             altme TYPE meins,
             vltyp TYPE lgtyp,
             vlpla TYPE lgpla,
             nltyp TYPE lgtyp,
             nlpla TYPE lgpla,
           END OF ty_to_request.

    "! The single place in this class that talks to the transfer-order
    "! function module.
    METHODS create_to
      IMPORTING is_to         TYPE ty_to_request
      EXPORTING ev_tanum      TYPE tanum
                ev_subrc      TYPE sysubrc.
ENDCLASS.


CLASS zcl_wm_stock_action IMPLEMENTATION.

  METHOD execute.
    " Guard clauses keep the happy path free of nesting.
    IF is_request-quantity <= 0.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-qty_must_be_positive.
      RETURN.
    ENDIF.

    IF is_request-quantity > is_stock-verme.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-qty_exceeds_stock.
      rs_result-msg_v1 = is_request-quantity.
      rs_result-msg_v2 = is_stock-verme.
      RETURN.
    ENDIF.

    IF is_request-bwart IS INITIAL.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-action_not_configured.
      rs_result-msg_v1 = is_action-action_id.
      RETURN.
    ENDIF.

    IF is_request-dest_lgtyp IS NOT INITIAL AND is_request-dest_lgpla IS INITIAL.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-dest_bin_required.
      RETURN.
    ENDIF.

    " A pure bin-to-bin transfer keeps the quant's storage location; a storage
    " location transfer takes the destination the user entered.
    DATA(lv_lgort) = COND lgort_d(
      WHEN is_request-dest_lgort IS INITIAL THEN is_stock-lgort
      ELSE is_request-dest_lgort ).

    DATA(ls_to) = VALUE ty_to_request(
      lgnum = is_stock-lgnum
      bwlvs = is_request-bwart
      matnr = is_stock-matnr
      werks = is_stock-werks
      lgort = lv_lgort
      charg = is_stock-charg
      bestq = is_stock-bestq
      sobkz = is_stock-sobkz
      sonum = is_stock-sonum
      anfme = is_request-quantity
      altme = is_stock-meins
      vltyp = is_stock-lgtyp
      vlpla = is_stock-lgpla
      nltyp = is_request-dest_lgtyp
      nlpla = is_request-dest_lgpla ).

    DATA lv_tanum TYPE tanum.
    DATA lv_subrc TYPE sysubrc.
    create_to( EXPORTING is_to    = ls_to
               IMPORTING ev_tanum = lv_tanum
                         ev_subrc = lv_subrc ).

    IF lv_subrc <> 0.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-to_create_failed.
      rs_result-msg_v1 = lv_subrc.
      RETURN.
    ENDIF.

    rs_result-success = abap_true.
    rs_result-tanum   = lv_tanum.
    rs_result-msg_no  = zcl_wm_msg=>cs_msg-to_created.
    rs_result-msg_v1  = lv_tanum.
  ENDMETHOD.


  METHOD confirm.
    CALL FUNCTION 'L_TO_CONFIRM'
      EXPORTING
        i_lgnum = iv_lgnum
        i_tanum = iv_tanum
        i_kompl = abap_true
      EXCEPTIONS
        no_to_found   = 1
        foreign_lock  = 2
        no_authority  = 3
        to_already_confirmed = 4
        OTHERS        = 99.

    IF sy-subrc <> 0.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-to_confirm_failed.
      rs_result-msg_v1 = iv_tanum.
      RETURN.
    ENDIF.

    rs_result-success = abap_true.
    rs_result-tanum   = iv_tanum.
    rs_result-msg_no  = zcl_wm_msg=>cs_msg-to_confirmed.
    rs_result-msg_v1  = iv_tanum.
  ENDMETHOD.


  METHOD create_to.
    " Only the relevant exceptions are named; OTHERS catches the rest so a
    " customizing problem surfaces as a message instead of a short dump.
    CALL FUNCTION 'L_TO_CREATE_SINGLE'
      EXPORTING
        i_lgnum       = is_to-lgnum
        i_bwlvs       = is_to-bwlvs
        i_matnr       = is_to-matnr
        i_werks       = is_to-werks
        i_lgort       = is_to-lgort
        i_charg       = is_to-charg
        i_bestq       = is_to-bestq
        i_sobkz       = is_to-sobkz
        i_sonum       = is_to-sonum
        i_anfme       = is_to-anfme
        i_altme       = is_to-altme
        i_vltyp       = is_to-vltyp
        i_vlpla       = is_to-vlpla
        i_nltyp       = is_to-nltyp
        i_nlpla       = is_to-nlpla
        i_kompl       = abap_true
        i_commit_work = abap_true
      IMPORTING
        e_tanum       = ev_tanum
      EXCEPTIONS
        no_to_created      = 1
        no_authority       = 2
        material_not_found = 3
        foreign_lock       = 4
        bwlvs_wrong        = 5
        vltyp_wrong        = 6
        nltyp_wrong        = 7
        vlpla_missing      = 8
        nlpla_missing      = 9
        bestq_wrong        = 10
        OTHERS             = 99.

    ev_subrc = sy-subrc.
  ENDMETHOD.

ENDCLASS.
