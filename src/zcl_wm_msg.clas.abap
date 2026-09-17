"! <p class="shorttext synchronized">Message collection for the WM Stock Cockpit</p>
"! <p>Central access to message class ZWM_MSG. Business logic never contains literal
"! message texts: it collects messages here and the caller decides how to present
"! them (status bar, ALV, popup).</p>
"! <p>Rationale: keeping every user-facing text behind the message class means the
"! cockpit can be translated and its texts changed without touching logic, and unit
"! tests can assert on a message number instead of on a sentence.</p>
CLASS zcl_wm_msg DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    "! Message severity, mirroring the ABAP message types
    TYPES ty_severity TYPE c LENGTH 1.

    CONSTANTS:
      "! Message severities
      BEGIN OF cs_severity,
        success TYPE ty_severity VALUE 'S',
        info    TYPE ty_severity VALUE 'I',
        warning TYPE ty_severity VALUE 'W',
        error   TYPE ty_severity VALUE 'E',
      END OF cs_severity.

    CONSTANTS:
      "! Message numbers of message class ZWM_MSG
      BEGIN OF cs_msg,
        no_stock_found        TYPE symsgno VALUE '001',
        warehouse_not_custom  TYPE symsgno VALUE '002',
        enter_material        TYPE symsgno VALUE '003',
        enter_warehouse       TYPE symsgno VALUE '004',
        to_created            TYPE symsgno VALUE '005',
        to_create_failed      TYPE symsgno VALUE '006',
        fm_error              TYPE symsgno VALUE '007',
        qty_exceeds_stock     TYPE symsgno VALUE '008',
        qty_must_be_positive  TYPE symsgno VALUE '009',
        dest_type_required    TYPE symsgno VALUE '010',
        dest_bin_required     TYPE symsgno VALUE '011',
        bin_not_suitable      TYPE symsgno VALUE '012',
        scrap_posted          TYPE symsgno VALUE '013',
        quant_already_blocked TYPE symsgno VALUE '014',
        max_layers_reached    TYPE symsgno VALUE '015',
        reason_not_found      TYPE symsgno VALUE '016',
        reason_wrong_layer    TYPE symsgno VALUE '017',
        enter_reason          TYPE symsgno VALUE '018',
        stock_blocked         TYPE symsgno VALUE '019',
        release_reason_mismat TYPE symsgno VALUE '020',
        layer_released        TYPE symsgno VALUE '021',
        layer_released_no_to  TYPE symsgno VALUE '022',
        no_open_layer         TYPE symsgno VALUE '023',
        quant_not_blocked     TYPE symsgno VALUE '024',
        no_authority          TYPE symsgno VALUE '025',
        select_one_line       TYPE symsgno VALUE '026',
        select_any_line       TYPE symsgno VALUE '027',
        generic               TYPE symsgno VALUE '028',
        no_actions_configured TYPE symsgno VALUE '029',
        action_not_configured TYPE symsgno VALUE '030',
        to_confirmed          TYPE symsgno VALUE '031',
        to_confirm_failed     TYPE symsgno VALUE '032',
        source_equals_dest    TYPE symsgno VALUE '033',
        enter_plant           TYPE symsgno VALUE '034',
        fm_not_available      TYPE symsgno VALUE '035',
        internal_error        TYPE symsgno VALUE '036',
        bad_storage_type      TYPE symsgno VALUE '037',
        bin_does_not_exist    TYPE symsgno VALUE '038',
        block_not_allowed     TYPE symsgno VALUE '039',
        layer_not_open        TYPE symsgno VALUE '040',
      END OF cs_msg.

    "! One collected message, text already resolved
    TYPES: BEGIN OF ty_msg,
             severity TYPE ty_severity,
             number   TYPE symsgno,
             v1       TYPE symsgv,
             v2       TYPE symsgv,
             v3       TYPE symsgv,
             v4       TYPE symsgv,
             text     TYPE bapi_msg,
           END OF ty_msg.

    TYPES tt_msg TYPE STANDARD TABLE OF ty_msg WITH EMPTY KEY.

    "! Collect a success message
    METHODS add_success
      IMPORTING iv_number TYPE symsgno
                iv_v1     TYPE symsgv OPTIONAL
                iv_v2     TYPE symsgv OPTIONAL
                iv_v3     TYPE symsgv OPTIONAL
                iv_v4     TYPE symsgv OPTIONAL.

    "! Collect an information message
    METHODS add_info
      IMPORTING iv_number TYPE symsgno
                iv_v1     TYPE symsgv OPTIONAL
                iv_v2     TYPE symsgv OPTIONAL
                iv_v3     TYPE symsgv OPTIONAL
                iv_v4     TYPE symsgv OPTIONAL.

    "! Collect a warning
    METHODS add_warning
      IMPORTING iv_number TYPE symsgno
                iv_v1     TYPE symsgv OPTIONAL
                iv_v2     TYPE symsgv OPTIONAL
                iv_v3     TYPE symsgv OPTIONAL
                iv_v4     TYPE symsgv OPTIONAL.

    "! Collect an error
    METHODS add_error
      IMPORTING iv_number TYPE symsgno
                iv_v1     TYPE symsgv OPTIONAL
                iv_v2     TYPE symsgv OPTIONAL
                iv_v3     TYPE symsgv OPTIONAL
                iv_v4     TYPE symsgv OPTIONAL.

    "! All collected messages, in the order they were added
    METHODS get_messages
      RETURNING VALUE(rt_msg) TYPE tt_msg.

    "! True when at least one error was collected
    METHODS has_errors
      RETURNING VALUE(rv_has_errors) TYPE abap_bool.

    "! The first error, or an initial structure when there is none
    METHODS get_first_error
      RETURNING VALUE(rs_msg) TYPE ty_msg.

    "! Discard everything collected so far
    METHODS clear.

  PRIVATE SECTION.

    CONSTANTS c_msgid TYPE symsgid VALUE 'ZWM_MSG'.

    DATA mt_msg TYPE tt_msg.

    METHODS add
      IMPORTING iv_severity TYPE ty_severity
                iv_number   TYPE symsgno
                iv_v1       TYPE symsgv OPTIONAL
                iv_v2       TYPE symsgv OPTIONAL
                iv_v3       TYPE symsgv OPTIONAL
                iv_v4       TYPE symsgv OPTIONAL.

    "! Resolve the message text from the message class
    METHODS resolve_text
      IMPORTING iv_number      TYPE symsgno
                iv_v1          TYPE symsgv OPTIONAL
                iv_v2          TYPE symsgv OPTIONAL
                iv_v3          TYPE symsgv OPTIONAL
                iv_v4          TYPE symsgv OPTIONAL
      RETURNING VALUE(rv_text) TYPE bapi_msg.

ENDCLASS.


CLASS zcl_wm_msg IMPLEMENTATION.

  METHOD add_success.
    add( iv_severity = cs_severity-success
         iv_number   = iv_number
         iv_v1       = iv_v1
         iv_v2       = iv_v2
         iv_v3       = iv_v3
         iv_v4       = iv_v4 ).
  ENDMETHOD.


  METHOD add_info.
    add( iv_severity = cs_severity-info
         iv_number   = iv_number
         iv_v1       = iv_v1
         iv_v2       = iv_v2
         iv_v3       = iv_v3
         iv_v4       = iv_v4 ).
  ENDMETHOD.


  METHOD add_warning.
    add( iv_severity = cs_severity-warning
         iv_number   = iv_number
         iv_v1       = iv_v1
         iv_v2       = iv_v2
         iv_v3       = iv_v3
         iv_v4       = iv_v4 ).
  ENDMETHOD.


  METHOD add_error.
    add( iv_severity = cs_severity-error
         iv_number   = iv_number
         iv_v1       = iv_v1
         iv_v2       = iv_v2
         iv_v3       = iv_v3
         iv_v4       = iv_v4 ).
  ENDMETHOD.


  METHOD get_messages.
    rt_msg = mt_msg.
  ENDMETHOD.


  METHOD has_errors.
    rv_has_errors = xsdbool( line_exists( mt_msg[ severity = cs_severity-error ] ) ).
  ENDMETHOD.


  METHOD get_first_error.
    READ TABLE mt_msg INTO rs_msg WITH KEY severity = cs_severity-error.
  ENDMETHOD.


  METHOD clear.
    CLEAR mt_msg.
  ENDMETHOD.


  METHOD add.
    DATA(ls_msg) = VALUE ty_msg(
      severity = iv_severity
      number   = iv_number
      v1       = iv_v1
      v2       = iv_v2
      v3       = iv_v3
      v4       = iv_v4
      text     = resolve_text( iv_number = iv_number
                               iv_v1     = iv_v1
                               iv_v2     = iv_v2
                               iv_v3     = iv_v3
                               iv_v4     = iv_v4 ) ).

    APPEND ls_msg TO mt_msg.
  ENDMETHOD.


  METHOD resolve_text.
    MESSAGE ID c_msgid TYPE cs_severity-info NUMBER iv_number
            WITH iv_v1 iv_v2 iv_v3 iv_v4
            INTO rv_text.
  ENDMETHOD.

ENDCLASS.
