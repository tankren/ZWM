"! <p class="shorttext synchronized">WM stock cockpit - action configuration</p>
"! Reads the cockpit configuration tables and answers the questions the UI and
"! the business logic ask: which buttons exist, what do they do, which reason
"! codes are allowed, and is the user allowed to use them.
"!
"! This class is the ONLY place that knows the layout of the configuration
"! tables. Every other class receives typed structures, which keeps the rest of
"! the code free of table dependencies and makes it easy to feed the business
"! logic with prepared data in a unit test.
CLASS zcl_wm_action_config DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! One configured action button (row of ZWM_STK_ACT_1T).
    TYPES ty_action TYPE zwm_stk_act_1t.
    TYPES tt_action TYPE STANDARD TABLE OF ty_action WITH EMPTY KEY.

    "! One configured block reason code (row of ZWM_BLOCK_RSN_1T).
    TYPES ty_reason TYPE zwm_block_rsn_1t.
    TYPES tt_reason TYPE STANDARD TABLE OF ty_reason WITH EMPTY KEY.

    "! All active actions, ordered by SORT_NO.
    "! An action with LGNUM filled is returned only for that warehouse; an
    "! action with LGNUM empty applies to every warehouse.
    METHODS get_actions
      IMPORTING iv_lgnum          TYPE lgnum DEFAULT space
      RETURNING VALUE(rt_actions) TYPE tt_action.

    "! A single action by its identifier, regardless of the ACTIVE flag, so a
    "! caller can explain why a configured action is not being offered.
    METHODS get_action
      IMPORTING iv_action_id      TYPE zwm_action_id
      RETURNING VALUE(rs_action)  TYPE ty_action.

    "! Active reason codes of one department and one block layer.
    METHODS get_reasons
      IMPORTING iv_dept           TYPE zwm_dept
                iv_layer          TYPE zwm_layer
                iv_lgnum          TYPE lgnum DEFAULT space
      RETURNING VALUE(rt_reasons) TYPE tt_reason.

    "! A single reason code, used to validate what the user entered.
    METHODS get_reason
      IMPORTING iv_dept         TYPE zwm_dept
                iv_layer        TYPE zwm_layer
                iv_reason_code  TYPE zwm_blcreason
                iv_lgnum        TYPE lgnum DEFAULT space
      RETURNING VALUE(rs_reason) TYPE ty_reason.

    "! Authorization check driven by the action configuration.
    "! An action without AUTH_OBJECT is deliberately open and returns abap_true.
    METHODS is_authorized
      IMPORTING is_action           TYPE ty_action
      RETURNING VALUE(rv_authorized) TYPE abap_bool.
ENDCLASS.


CLASS zcl_wm_action_config IMPLEMENTATION.

  METHOD get_actions.
    SELECT * FROM zwm_stk_act_1t
      WHERE active = @abap_true
      ORDER BY sort_no, action_id
      INTO TABLE @rt_actions.

    IF iv_lgnum IS NOT INITIAL.
      " A warehouse-specific action belongs to exactly one warehouse.
      DELETE rt_actions WHERE lgnum IS NOT INITIAL AND lgnum <> iv_lgnum.
    ENDIF.
  ENDMETHOD.


  METHOD get_action.
    SELECT SINGLE * FROM zwm_stk_act_1t
      WHERE action_id = @iv_action_id
      INTO @rs_action.
  ENDMETHOD.


  METHOD get_reasons.
    SELECT * FROM zwm_block_rsn_1t
      WHERE dept  = @iv_dept
        AND layer = @iv_layer
        AND active = @abap_true
      ORDER BY reason_code
      INTO TABLE @rt_reasons.

    IF iv_lgnum IS NOT INITIAL.
      DELETE rt_reasons WHERE lgnum IS NOT INITIAL AND lgnum <> iv_lgnum.
    ENDIF.
  ENDMETHOD.


  METHOD get_reason.
    SELECT SINGLE * FROM zwm_block_rsn_1t
      WHERE dept        = @iv_dept
        AND layer       = @iv_layer
        AND reason_code = @iv_reason_code
      INTO @rs_reason.
  ENDMETHOD.


  METHOD is_authorized.
    IF is_action-auth_object IS INITIAL.
      " No object configured: the action is open to everybody.
      rv_authorized = abap_true.
      RETURN.
    ENDIF.

    " AUTHORITY-CHECK requires literal field names, but the field name comes
    " from customizing. The function module AUTHORITY_CHECK (SAPLSUSR) runs the
    " very same check with dynamic field names, so it is used here.
    " Its protocol is inverted: it raises USER_IS_AUTHORIZED when the check
    " SUCCEEDS, which is why subrc 1 means authorized.
    DATA(lv_field) = COND xufield(
      WHEN is_action-auth_field IS INITIAL THEN 'ACTVT'
      ELSE is_action-auth_field ).

    CALL FUNCTION 'AUTHORITY_CHECK'
      EXPORTING
        object = is_action-auth_object
        field1 = lv_field
        value1 = is_action-auth_value
      EXCEPTIONS
        user_is_authorized  = 1
        user_not_authorized = 2
        user_dont_exist     = 3
        user_is_locked      = 4
        OTHERS              = 5.

    rv_authorized = xsdbool( sy-subrc = 1 ).
  ENDMETHOD.

ENDCLASS.
