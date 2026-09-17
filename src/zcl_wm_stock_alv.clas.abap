"! <p class="shorttext synchronized">WM stock cockpit - result list</p>"
"! Presents the stock list and builds its toolbar from the action
"! configuration table ZWM_STK_ACT_1T.
"!
"! WHY THE TOOLBAR IS BUILT AT RUNTIME
"! The warehouse specification requires the buttons to be maintainable in
"! customizing and to be granted per department through authorizations. The
"! toolbar is therefore not a fixed GUI status: every active action of the
"! current warehouse becomes a button, and an action the user is not
"! authorized for is not offered at all.
"!
"! This class owns presentation and event routing only. It never posts
"! anything; it reports which button was pressed and which row was selected,
"! and the report decides what happens next.
CLASS zcl_wm_stock_alv DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_stock TYPE zwm_quan_1s.
    TYPES tt_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_result,
             success TYPE abap_bool,
             msg_no  TYPE symsgno,
             msg_v1  TYPE symsgv,
           END OF ty_result.

    "! IO_CONFIG is injected so the toolbar can be tested with prepared
    "! customizing instead of the database.
    METHODS constructor
      IMPORTING io_config TYPE REF TO zcl_wm_action_config OPTIONAL.

    "! Displays the list. When the user leaves the list through one of the
    "! configured buttons, EV_ACTION_ID carries that action, otherwise it is
    "! empty.
    METHODS display
      IMPORTING it_stock         TYPE tt_stock
                iv_lgnum         TYPE lgnum
                iv_title         TYPE string OPTIONAL
      EXPORTING es_result        TYPE ty_result
                ev_action_id     TYPE zwm_action_id.

    "! The single selected row of the list, or an initial structure when the
    "! selection is not exactly one row.
    METHODS get_selected_row
      IMPORTING it_stock         TYPE tt_stock
      RETURNING VALUE(rs_stock)  TYPE ty_stock.

  PRIVATE SECTION.
    DATA mo_config  TYPE REF TO zcl_wm_action_config.
    DATA mo_salv    TYPE REF TO cl_salv_table.
    DATA mt_actions TYPE zcl_wm_action_config=>tt_action.
    DATA mv_pressed TYPE ui_func.
    DATA mv_lgnum   TYPE lgnum.

    METHODS build_toolbar
      IMPORTING io_functions TYPE REF TO cl_salv_functions_list.

    METHODS set_column_visibility.

    METHODS on_added_function
      FOR EVENT added_function OF cl_salv_events
      IMPORTING e_salv_function.
ENDCLASS.


CLASS zcl_wm_stock_alv IMPLEMENTATION.

  METHOD constructor.
    mo_config = COND #( WHEN io_config IS BOUND THEN io_config
                        ELSE NEW zcl_wm_action_config( ) ).
  ENDMETHOD.


  METHOD display.
    mv_lgnum   = iv_lgnum.
    mv_pressed = space.

    " A writable copy is needed: cl_salv_table=>factory takes the table as a
    " CHANGING parameter, and IT_STOCK is read only.
    DATA lt_display TYPE tt_stock.
    lt_display = it_stock.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = mo_salv
          CHANGING  t_table      = lt_display ).

        IF iv_title IS NOT INITIAL.
          " set_list_header expects a fixed length character field, so the
          " string is converted explicitly.
          DATA(lv_header) = CONV lvc_title( iv_title ).
          mo_salv->get_display_settings( )->set_list_header( lv_header ).
        ENDIF.

        mo_salv->get_selections( )->set_selection_mode(
          if_salv_c_selection_mode=>row_column ).

        mo_salv->get_columns( )->set_optimize( abap_true ).
        set_column_visibility( ).

        DATA(lo_functions) = mo_salv->get_functions( ).
        lo_functions->set_all( abap_true ).
        build_toolbar( lo_functions ).

        SET HANDLER on_added_function FOR mo_salv->get_event( ).

        mo_salv->display( ).

        es_result-success = abap_true.

      CATCH cx_salv_msg INTO DATA(lx_msg).
        es_result-msg_no = zcl_wm_msg=>cs_msg-internal_error.
        es_result-msg_v1 = lx_msg->get_text( ).
        RETURN.
      CATCH cx_root INTO DATA(lx_root).
        es_result-msg_no = zcl_wm_msg=>cs_msg-internal_error.
        es_result-msg_v1 = lx_root->get_text( ).
        RETURN.
    ENDTRY.

    " Turn the pressed function code back into a configured action.
    IF mv_pressed IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_action_id TYPE zwm_action_id.
    lv_action_id = mv_pressed.

    READ TABLE mt_actions INTO DATA(ls_action)
      WITH KEY action_id = lv_action_id.
    IF sy-subrc = 0.
      ev_action_id = ls_action-action_id.
    ENDIF.
  ENDMETHOD.


  METHOD build_toolbar.
    mt_actions = mo_config->get_actions( mv_lgnum ).

    LOOP AT mt_actions INTO DATA(ls_action).
      " An action the user is not authorized for is not offered.
      IF mo_config->is_authorized( ls_action ) = abap_false.
        CONTINUE.
      ENDIF.

      " The action id doubles as the function code, which is how display( )
      " maps the pressed button back to its configuration.
      " The parameters of SET_FUNCTION are fixed length character fields, so the
      " configured values are passed as they are. A CONV string( ) is rejected
      " by the compiler because a string cannot be passed to a character field.
      IF ls_action-icon_name IS INITIAL.
        io_functions->set_function(
          name    = ls_action-action_id
          text    = ls_action-button_text
          tooltip = ls_action-quickinfo ).
      ELSE.
        io_functions->set_function(
          name    = ls_action-action_id
          text    = ls_action-button_text
          tooltip = ls_action-quickinfo
          icon    = ls_action-icon_name ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD set_column_visibility.
    " Technical columns that the warehouse list does not need. The warehouse
    " number is shown in the list header instead.
    DATA(lo_columns) = mo_salv->get_columns( ).

    TRY.
        lo_columns->get_column( 'LGNUM' )->set_visible( abap_false ).
        lo_columns->get_column( 'KOBER' )->set_visible( abap_false ).
        lo_columns->get_column( 'SPGRU' )->set_visible( abap_false ).
        lo_columns->get_column( 'LETYP' )->set_visible( abap_false ).
      CATCH cx_salv_not_found.
        " A column that is not part of the structure needs no handling.
    ENDTRY.
  ENDMETHOD.


  METHOD get_selected_row.
    IF mo_salv IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA(lt_rows) = mo_salv->get_selections( )->get_selected_rows( ).
    IF lines( lt_rows ) <> 1.
      RETURN.
    ENDIF.

    READ TABLE lt_rows INTO DATA(lv_row) INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    READ TABLE it_stock INTO rs_stock INDEX lv_row.
  ENDMETHOD.


  METHOD on_added_function.
    " Remember the pressed button; display( ) resolves it when the user
    " leaves the list.
    mv_pressed = e_salv_function.
  ENDMETHOD.

ENDCLASS.
