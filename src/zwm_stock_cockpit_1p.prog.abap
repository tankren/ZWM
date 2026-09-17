*&---------------------------------------------------------------------*
*& Report ZWM_STOCK_COCKPIT_1P
*&---------------------------------------------------------------------*
*& Warehouse stock cockpit (classic LE-WM).
*&
*& Part 1 - query and display stock per quant, LS24 style.
*& Part 2 - execute configured actions on the selected quant:
*&          transfer, scrap, block, unblock, block reasons.
*&
*& The result list toolbar is built at runtime from table ZWM_STK_ACT_1T,
*& so a new button is a configuration row, not a code change.
*&
*& Every action executes a standard function module. Transfer and scrap
*& call L_TO_CREATE_SINGLE / L_TO_CONFIRM; block and unblock call
*& L_TO_CREATE_SINGLE with movement type 344 / 343.
*&
*& Design notes: see docs/design.md in the abapGit repository.
*&
*& Transaction ZWM_STOCK_COCKPIT starts this report. The program itself
*& carries the _1P suffix so that the transaction can own the plain name.
*&---------------------------------------------------------------------*
REPORT zwm_stock_cockpit_1p.

* The classic work areas behind the selection screen. TABLES is required so
* that the FOR clauses of the SELECT-OPTIONS below can resolve their fields.
TABLES: lqua, mara.

*----------------------------------------------------------------------*
* Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK blk_sel WITH FRAME TITLE text-001.
  PARAMETERS p_lgnum TYPE lgnum OBLIGATORY.
  SELECT-OPTIONS s_matnr FOR lqua-matnr.
  SELECT-OPTIONS s_werks FOR lqua-werks.
  SELECT-OPTIONS s_lgort FOR lqua-lgort.
  SELECT-OPTIONS s_bestq FOR lqua-bestq.
  SELECT-OPTIONS s_sobkz FOR lqua-sobkz.
  SELECT-OPTIONS s_sonum FOR lqua-sonum.
  SELECT-OPTIONS s_charg FOR lqua-charg.
SELECTION-SCREEN END OF BLOCK blk_sel.

SELECTION-SCREEN BEGIN OF BLOCK blk_add WITH FRAME TITLE text-002.
  SELECT-OPTIONS s_lgtyp FOR lqua-lgtyp.
  SELECT-OPTIONS s_lgpla FOR lqua-lgpla.
  SELECT-OPTIONS s_wenum FOR lqua-wenum.
  SELECT-OPTIONS s_wdatu FOR lqua-wdatu.
  SELECT-OPTIONS s_qplos FOR lqua-qplos.
  SELECT-OPTIONS s_lenum FOR lqua-lenum.
  SELECT-OPTIONS s_herkl FOR mara-herkl.
SELECTION-SCREEN END OF BLOCK blk_add.

*----------------------------------------------------------------------*
* Globals
*----------------------------------------------------------------------*
CONSTANTS c_msgid TYPE symsgid VALUE 'ZWM_MSG'.

DATA: go_msg    TYPE REF TO zcl_wm_msg,
      go_config TYPE REF TO zcl_wm_action_config,
      go_query  TYPE REF TO zcl_wm_stock_query,
      go_action TYPE REF TO zcl_wm_stock_action,
      go_block  TYPE REF TO zcl_wm_stock_block,
      go_alv    TYPE REF TO zcl_wm_stock_alv,
      gt_stock  TYPE zcl_wm_stock_query=>tt_stock.

*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM create_services.
  PERFORM load_stock.

  IF gt_stock IS INITIAL.
    go_msg->add_info( zcl_wm_msg=>cs_msg-no_stock_found ).
    PERFORM display_messages.
    RETURN.
  ENDIF.

  PERFORM run_cockpit.

*----------------------------------------------------------------------*
* Service objects
*----------------------------------------------------------------------*
FORM create_services.
  go_msg    = NEW #( ).
  go_config = NEW #( ).
  go_query  = NEW #( ).
  go_action = NEW #( ).
  go_block  = NEW zcl_wm_stock_block( go_config ).
  go_alv    = NEW zcl_wm_stock_alv( go_config ).
ENDFORM.

*----------------------------------------------------------------------*
* Read the stock for the current selection
*----------------------------------------------------------------------*
FORM load_stock.
  DATA ls_sel TYPE zcl_wm_stock_query=>ty_sel.

  PERFORM build_selection CHANGING ls_sel.
  gt_stock = go_query->get_stock( ls_sel ).
ENDFORM.

FORM build_selection CHANGING cs_sel TYPE zcl_wm_stock_query=>ty_sel.
  cs_sel-lgnum = p_lgnum.
  cs_sel-matnr = s_matnr[].
  cs_sel-werks = s_werks[].
  cs_sel-lgort = s_lgort[].
  cs_sel-bestq = s_bestq[].
  cs_sel-sobkz = s_sobkz[].
  cs_sel-sonum = s_sonum[].
  cs_sel-charg = s_charg[].
  cs_sel-lgtyp = s_lgtyp[].
  cs_sel-lgpla = s_lgpla[].
  cs_sel-wenum = s_wenum[].
  cs_sel-wdatu = s_wdatu[].
  cs_sel-qplos = s_qplos[].
  cs_sel-lenum = s_lenum[].
  cs_sel-herkl = s_herkl[].
ENDFORM.

*----------------------------------------------------------------------*
* Display / action loop
*
* The list is re-opened after every action so the user sees the new
* stock and the new block layers immediately.
*----------------------------------------------------------------------*
FORM run_cockpit.
  DATA: lv_action TYPE zwm_action_id,
        ls_result TYPE zcl_wm_stock_alv=>ty_result.

  DO.
    CLEAR: lv_action, ls_result.

    go_alv->display(
      EXPORTING
        it_stock     = gt_stock
        iv_lgnum     = p_lgnum
        iv_title     = |Stock cockpit - warehouse { p_lgnum }|
      IMPORTING
        es_result    = ls_result
        ev_action_id = lv_action ).

    IF ls_result-msg_no IS NOT INITIAL AND ls_result-success = abap_false.
      go_msg->add_error( iv_number = ls_result-msg_no iv_v1 = ls_result-msg_v1 ).
      PERFORM display_messages.
    ENDIF.

    IF lv_action IS INITIAL.
      EXIT.
    ENDIF.

    PERFORM process_action USING lv_action.
    PERFORM load_stock.
    PERFORM display_messages.

    IF gt_stock IS INITIAL.
      EXIT.
    ENDIF.
  ENDDO.
ENDFORM.

*----------------------------------------------------------------------*
* Route a pressed button to its handler
*----------------------------------------------------------------------*
FORM process_action USING iv_action_id TYPE zwm_action_id.
  DATA: ls_action TYPE zcl_wm_action_config=>ty_action,
        ls_stock  TYPE zwm_quan_1s.

  ls_action = go_config->get_action( iv_action_id ).
  IF ls_action IS INITIAL.
    go_msg->add_error( iv_number = zcl_wm_msg=>cs_msg-action_not_configured
                       iv_v1     = CONV symsgv( iv_action_id ) ).
    RETURN.
  ENDIF.

  IF go_config->is_authorized( ls_action ) = abap_false.
    go_msg->add_error( iv_number = zcl_wm_msg=>cs_msg-no_authority
                       iv_v1     = CONV symsgv( sy-uname )
                       iv_v2     = CONV symsgv( iv_action_id ) ).
    RETURN.
  ENDIF.

  ls_stock = go_alv->get_selected_row( gt_stock ).
  IF ls_stock IS INITIAL.
    go_msg->add_error( zcl_wm_msg=>cs_msg-select_one_line ).
    RETURN.
  ENDIF.

  CASE ls_action-action_type.
    WHEN 'TRANSFER' OR 'SCRAP'.
      PERFORM execute_movement USING ls_stock ls_action.
    WHEN 'BLOCK'.
      PERFORM execute_block USING ls_stock ls_action.
    WHEN 'UNBLOCK'.
      PERFORM execute_release USING ls_stock ls_action.
    WHEN 'INFO'.
      PERFORM show_block_reasons USING ls_stock.
    WHEN OTHERS.
      go_msg->add_error( iv_number = zcl_wm_msg=>cs_msg-action_not_configured
                         iv_v1     = CONV symsgv( iv_action_id ) ).
  ENDCASE.
ENDFORM.

*----------------------------------------------------------------------*
* Transfer / scrap
*----------------------------------------------------------------------*
FORM execute_movement USING is_stock  TYPE zwm_quan_1s
                            is_action TYPE zcl_wm_action_config=>ty_action.
  DATA: ls_request TYPE zcl_wm_stock_action=>ty_request,
        ls_result  TYPE zcl_wm_stock_action=>ty_result,
        lv_bwart   TYPE bwart,
        lv_ok      TYPE abap_bool,
        lv_title   TYPE string.

  lv_bwart = is_action-bwart.
  IF lv_bwart IS INITIAL.
    lv_bwart = '999'.
  ENDIF.

  CLEAR gt_fields.

  PERFORM add_popup_field USING 'LQUA' 'GESME' 'Requested quantity'
                                is_stock-verme 'X'.

  PERFORM add_popup_field USING 'T156' 'BWART' 'Movement type'
                                lv_bwart 'X'.

  PERFORM add_popup_field USING 'LQUA' 'LGORT' 'Destination storage location'
                                is_stock-lgort ''.

  PERFORM add_popup_field USING 'LQUA' 'LGTYP' 'Destination storage type'
                                is_stock-lgtyp ''.

  PERFORM add_popup_field USING 'LQUA' 'LGPLA' 'Destination storage bin'
                                is_stock-lgpla ''.

  lv_title = 'Inventory control station'.
  PERFORM show_popup USING lv_title CHANGING lv_ok.
  IF lv_ok = abap_false.
    RETURN.
  ENDIF.

  PERFORM get_popup_value USING 'GESME' CHANGING ls_request-quantity.
  PERFORM get_popup_value USING 'BWART' CHANGING ls_request-bwart.
  PERFORM get_popup_value USING 'LGORT' CHANGING ls_request-dest_lgort.
  PERFORM get_popup_value USING 'LGTYP' CHANGING ls_request-dest_lgtyp.
  PERFORM get_popup_value USING 'LGPLA' CHANGING ls_request-dest_lgpla.

  ls_result = go_action->execute( is_stock   = is_stock
                                  is_action  = is_action
                                  is_request = ls_request ).

  PERFORM report_result USING ls_result-success
                              ls_result-msg_no
                              ls_result-msg_v1
                              ls_result-msg_v2.
ENDFORM.

*----------------------------------------------------------------------*
* Block - add a new layer, or change the reason of an open layer
*----------------------------------------------------------------------*
FORM execute_block USING is_stock  TYPE zwm_quan_1s
                        is_action TYPE zcl_wm_action_config=>ty_action.
  DATA: lt_layers  TYPE zcl_wm_stock_block=>tt_layer,
        ls_request TYPE zcl_wm_stock_block=>ty_block_request,
        ls_result  TYPE zcl_wm_stock_block=>ty_result,
        lv_bwart   TYPE bwart,
        lv_open    TYPE i,
        lv_layer   TYPE zwm_layer,
        lv_chosen  TYPE zwm_layer,
        lv_ok      TYPE abap_bool,
        lv_title   TYPE string.

  lv_bwart = is_action-bwart.
  IF lv_bwart IS INITIAL.
    lv_bwart = zcl_wm_stock_block=>c_bwart_block.
  ENDIF.

  lt_layers = go_block->get_open_layers( is_stock ).
  lv_open   = lines( lt_layers ).

  IF lv_open >= zcl_wm_stock_block=>c_max_layers.
    go_msg->add_error( iv_number = zcl_wm_msg=>cs_msg-max_layers_reached
                       iv_v1     = CONV symsgv( is_stock-lqnum ) ).
    RETURN.
  ENDIF.

  IF lt_layers IS NOT INITIAL.
    lv_title = |Existing block layers of quant { is_stock-lqnum }|.
    PERFORM show_layers USING lt_layers lv_title.
  ENDIF.

  lv_layer = go_block->next_free_layer( lv_open ).

  CLEAR gt_fields.

  PERFORM add_popup_field USING 'ZWM_BLOCKLOG_1T' 'LAYER'
                                'Layer to change (blank = add new layer)'
                                lv_layer ''.

  PERFORM add_popup_field USING 'ZWM_BLOCKLOG_1T' 'DEPT' 'Department'
                                '' 'X'.

  lv_title = 'Block stock'.
  PERFORM show_popup USING lv_title CHANGING lv_ok.
  IF lv_ok = abap_false.
    RETURN.
  ENDIF.

  PERFORM get_popup_value USING 'LAYER' CHANGING lv_chosen.
  PERFORM get_popup_value USING 'DEPT' CHANGING ls_request-dept.

  " The reason code is never typed in: the user picks one of the reasons that
  " table T157E holds for the movement type of this action.
  lv_title = |Block reason ({ lv_bwart })|.
  PERFORM select_reason USING lv_bwart lv_title
                        CHANGING ls_request-reason_code
                                 ls_request-reason_text.
  IF ls_request-reason_code IS INITIAL.
    RETURN.
  ENDIF.

  IF lv_chosen IS NOT INITIAL AND lv_chosen < lv_layer.
    " The user pointed at a layer that is already open - change its reason.
    ls_result = go_block->modify_reason( is_stock   = is_stock
                                         iv_layer   = lv_chosen
                                         is_request = ls_request
                                         iv_bwart   = lv_bwart ).
  ELSE.
    ls_result = go_block->block( is_stock   = is_stock
                                 is_request = ls_request
                                 iv_bwart   = lv_bwart ).
  ENDIF.

  PERFORM report_result USING ls_result-success
                              ls_result-msg_no
                              ls_result-msg_v1
                              ls_result-msg_v2.
ENDFORM.

*----------------------------------------------------------------------*
* Unblock - release one layer
*----------------------------------------------------------------------*
FORM execute_release USING is_stock  TYPE zwm_quan_1s
                          is_action TYPE zcl_wm_action_config=>ty_action.
  DATA: lt_layers  TYPE zcl_wm_stock_block=>tt_layer,
        ls_request TYPE zcl_wm_stock_block=>ty_release_request,
        ls_result  TYPE zcl_wm_stock_block=>ty_result,
        lv_bwart   TYPE bwart,
        lv_ok      TYPE abap_bool,
        lv_title   TYPE string,
        lv_default TYPE zwm_layer.

  lv_bwart = is_action-bwart.
  IF lv_bwart IS INITIAL.
    lv_bwart = zcl_wm_stock_block=>c_bwart_unblock.
  ENDIF.

  lt_layers = go_block->get_open_layers( is_stock ).

  IF lt_layers IS INITIAL.
    go_msg->add_error( iv_number = zcl_wm_msg=>cs_msg-quant_not_blocked
                       iv_v1     = CONV symsgv( is_stock-lqnum ) ).
    RETURN.
  ENDIF.

  lv_title = |Open block layers of quant { is_stock-lqnum }|.
  PERFORM show_layers USING lt_layers lv_title.

  lv_default = lt_layers[ 1 ]-layer.

  CLEAR gt_fields.

  PERFORM add_popup_field USING 'ZWM_BLOCKLOG_1T' 'LAYER' 'Layer to release'
                                lv_default 'X'.

  lv_title = 'Release blocked stock'.
  PERFORM show_popup USING lv_title CHANGING lv_ok.
  IF lv_ok = abap_false.
    RETURN.
  ENDIF.

  PERFORM get_popup_value USING 'LAYER' CHANGING ls_request-layer.

  " The release reason has to repeat the block reason, so it is picked from
  " the same T157E list and checked again inside the block logic.
  lv_title = |Release reason ({ lv_bwart })|.
  PERFORM select_reason USING lv_bwart lv_title
                        CHANGING ls_request-reason_code
                                 ls_request-reason_text.
  IF ls_request-reason_code IS INITIAL.
    RETURN.
  ENDIF.

  ls_result = go_block->release( is_stock   = is_stock
                                 is_request = ls_request
                                 iv_bwart   = lv_bwart ).

  PERFORM report_result USING ls_result-success
                              ls_result-msg_no
                              ls_result-msg_v1
                              ls_result-msg_v2.
ENDFORM.

*----------------------------------------------------------------------*
* Pick a reason code from table T157E
*
* The cockpit does not keep its own reason codes: T157E (the standard text
* table of movement reasons) is the only source, so the list simply shows
* what has been maintained for the movement type of the action. The block
* logic validates the choice again before it writes anything.
*----------------------------------------------------------------------*
FORM select_reason USING    iv_bwart       TYPE bwart
                            iv_title       TYPE string
                   CHANGING cv_reason_code TYPE mb_grbew
                            cv_reason_text TYPE grtxt.
  DATA: lt_reasons TYPE zcl_wm_action_config=>tt_reason,
        lt_display TYPE zcl_wm_action_config=>tt_reason,
        lt_rows    TYPE salv_t_row,
        lo_salv    TYPE REF TO cl_salv_table,
        lo_error   TYPE REF TO cx_root,
        lv_text    TYPE string,
        lv_header  TYPE lvc_title.

  lt_reasons = go_config->get_reasons( iv_bwart ).

  IF lt_reasons IS INITIAL.
    go_msg->add_error( iv_number = zcl_wm_msg=>cs_msg-reason_not_found
                       iv_v1     = CONV symsgv( iv_bwart ) ).
    RETURN.
  ENDIF.

  lt_display = lt_reasons.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = lo_salv
                              CHANGING  t_table      = lt_display ).

      lo_salv->get_columns( )->set_optimize( abap_true ).
      lo_salv->get_functions( )->set_all( abap_true ).
      lo_salv->get_selections( )->set_selection_mode(
        if_salv_c_selection_mode=>single ).
      lv_header = iv_title.
      lo_salv->get_display_settings( )->set_list_header( lv_header ).
      lo_salv->set_screen_popup( start_column = 5
                                 end_column   = 95
                                 start_line   = 3
                                 end_line     = 20 ).
      lo_salv->display( ).

      lt_rows = lo_salv->get_selections( )->get_selected_rows( ).

    CATCH cx_salv_msg INTO lo_error.
      lv_text = lo_error->get_text( ).
      go_msg->add_error( iv_number = zcl_wm_msg=>cs_msg-internal_error
                         iv_v1     = CONV symsgv( lv_text ) ).
      RETURN.
  ENDTRY.

  IF lines( lt_rows ) <> 1.
    " The list was closed without choosing a reason.
    go_msg->add_info( zcl_wm_msg=>cs_msg-enter_reason ).
    RETURN.
  ENDIF.

  READ TABLE lt_reasons INTO DATA(ls_reason) INDEX lt_rows[ 1 ].
  IF sy-subrc = 0.
    cv_reason_code = ls_reason-grund.
    cv_reason_text = ls_reason-grtxt.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* Block reasons of a quant
*----------------------------------------------------------------------*
FORM show_block_reasons USING is_stock TYPE zwm_quan_1s.
  DATA: lt_layers TYPE zcl_wm_stock_block=>tt_layer,
        lv_title  TYPE string.

  lt_layers = go_block->get_open_layers( is_stock ).

  IF lt_layers IS INITIAL.
    go_msg->add_info( iv_number = zcl_wm_msg=>cs_msg-quant_not_blocked
                      iv_v1     = CONV symsgv( is_stock-lqnum ) ).
    RETURN.
  ENDIF.

  lv_title = |Block layers of quant { is_stock-lqnum }|.
  PERFORM show_layers USING lt_layers lv_title.
ENDFORM.

*----------------------------------------------------------------------*
* Display a list of block layers in a popup
*
* A local copy is used because cl_salv_table=>factory needs a writable
* table, and a USING parameter is read only.
*----------------------------------------------------------------------*
FORM show_layers USING it_layers TYPE zcl_wm_stock_block=>tt_layer
                       iv_title  TYPE string.
  DATA: lt_display TYPE zcl_wm_stock_block=>tt_layer,
        lo_salv    TYPE REF TO cl_salv_table,
        lo_error   TYPE REF TO cx_root,
        lv_text    TYPE string.

  lt_display = it_layers.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = lo_salv
                              CHANGING  t_table      = lt_display ).

      lo_salv->get_columns( )->set_optimize( abap_true ).
      lo_salv->get_functions( )->set_all( abap_true ).
      lo_salv->set_screen_popup( start_column = 3
                                 end_column   = 120
                                 start_line   = 2
                                 end_line     = 18 ).
      lo_salv->display( ).

    CATCH cx_salv_msg INTO lo_error.
      lv_text = lo_error->get_text( ).
      go_msg->add_error( iv_number = zcl_wm_msg=>cs_msg-internal_error
                         iv_v1     = CONV symsgv( lv_text ) ).
  ENDTRY.
ENDFORM.

*----------------------------------------------------------------------*
* Popup helpers
*
* POPUP_GET_VALUES is used for all data entry: the function module
* carries its own screen, so the report needs no dynpro of its own and
* stays fully abapGit-serialisable.
*
* The field table is a single global because a FORM interface must not
* contain a table parameter: the compiler miscounts such a parameter as
* three formal parameters ("Different number of parameters in FORM and
* PERFORM"). It also has to be writable, since POPUP_GET_VALUES fills in
* what the user typed.
*----------------------------------------------------------------------*
DATA gt_fields TYPE TABLE OF sval.

FORM add_popup_field USING iv_tabname   TYPE sval-tabname
                           iv_fieldname TYPE sval-fieldname
                           iv_text      TYPE sval-fieldtext
                           iv_value     TYPE sval-value
                           iv_required  TYPE sval-field_obl.
  DATA ls_field TYPE sval.

  ls_field-tabname   = iv_tabname.
  ls_field-fieldname = iv_fieldname.
  ls_field-fieldtext = iv_text.
  ls_field-value     = iv_value.
  ls_field-field_obl = iv_required.

  APPEND ls_field TO gt_fields.
ENDFORM.

FORM show_popup USING    iv_title TYPE string
                CHANGING cv_ok    TYPE abap_bool.
  CALL FUNCTION 'POPUP_GET_VALUES'
    EXPORTING
      popup_title     = iv_title
    TABLES
      fields          = gt_fields
    EXCEPTIONS
      error_in_fields = 1
      OTHERS          = 2.

  cv_ok = xsdbool( sy-subrc = 0 ).
ENDFORM.

FORM get_popup_value USING    iv_fieldname TYPE sval-fieldname
                     CHANGING cv_value     TYPE any.
  DATA ls_field TYPE sval.

  READ TABLE gt_fields INTO ls_field WITH KEY fieldname = iv_fieldname.
  IF sy-subrc = 0.
    cv_value = ls_field-value.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* Message output
*----------------------------------------------------------------------*
FORM report_result USING iv_success TYPE abap_bool
                         iv_msg_no  TYPE symsgno
                         iv_v1      TYPE symsgv
                         iv_v2      TYPE symsgv.

  IF iv_success = abap_true.
    go_msg->add_success( iv_number = iv_msg_no iv_v1 = iv_v1 iv_v2 = iv_v2 ).
  ELSE.
    go_msg->add_error( iv_number = iv_msg_no iv_v1 = iv_v1 iv_v2 = iv_v2 ).
  ENDIF.
ENDFORM.

FORM display_messages.
  DATA: lt_msg TYPE zcl_wm_msg=>tt_msg,
        ls_msg TYPE zcl_wm_msg=>ty_msg.

  lt_msg = go_msg->get_messages( ).

  LOOP AT lt_msg INTO ls_msg.
    MESSAGE ID c_msgid TYPE ls_msg-severity NUMBER ls_msg-number
            WITH ls_msg-v1 ls_msg-v2 ls_msg-v3 ls_msg-v4
            DISPLAY LIKE ls_msg-severity.
  ENDLOOP.

  go_msg->clear( ).
ENDFORM.
