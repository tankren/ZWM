"! <p class="shorttext synchronized">WM stock cockpit - block and unblock</p>"
"! Implements the multi-layer blocking of a quant as required by the
"! warehouse specification.
"!
"! WHY THIS CLASS EXISTS
"! A WM quant only knows two states: blocked (LQUA-BESTQ = 'S') or not blocked.
"! The specification, however, allows up to three independent block layers on
"! the same quant, each with its own department, reason code, reason text and
"! blocker. WM cannot hold that, so the layers are kept in table
"! ZWM_BLOCKLOG_1T while WM keeps the physical block:
"!
"!   * the FIRST layer of a quant is a physical block  -> posting change 344
"!   * layers two and three are pure bookkeeping       -> no WM movement
"!   * releasing a layer that is not the last one      -> no WM movement
"!   * releasing the LAST open layer                   -> posting change 343
"!
"! A posting change keeps the stock in the same storage bin: source and
"! destination of the transfer order are identical and only the stock category
"! changes.
"!
"! The two writes of one operation (transfer order + log entry) form a single
"! logical unit of work: the transfer order is created WITHOUT its own commit
"! and the class commits or rolls back once both steps are done.
CLASS zcl_wm_stock_block DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Blocked stock category, the source of a release.
    CONSTANTS c_bestq_blocked TYPE bestq VALUE 'S'.
    "! Open layer.
    CONSTANTS c_status_open TYPE zwm_blkstat VALUE 'O'.
    "! Released layer.
    CONSTANTS c_status_released TYPE zwm_blkstat VALUE 'R'.
    "! The specification allows at most three layers per quant.
    CONSTANTS c_max_layers TYPE i VALUE 3.
    "! Movement type of the first block: unrestricted -> blocked.
    CONSTANTS c_bwart_block TYPE bwart VALUE '344'.
    "! Movement type of the last release: blocked -> unrestricted.
    CONSTANTS c_bwart_unblock TYPE bwart VALUE '343'.

    "! A block layer, as stored in ZWM_BLOCKLOG_1T.
    TYPES ty_layer TYPE zwm_blocklog_1t.
    TYPES tt_layer TYPE STANDARD TABLE OF ty_layer WITH EMPTY KEY.

    "! What the user entered to block a quant. The reason is a movement
    "! reason (T157E-GRUND); the text is the snapshot of T157E-GRTXT, kept so
    "! that the log stays readable when customizing is changed later.
    TYPES: BEGIN OF ty_block_request,
             dept        TYPE zwm_dept,
             reason_code TYPE mb_grbew,
             reason_text TYPE grtxt,
           END OF ty_block_request.

    "! What the user entered to release one layer.
    TYPES: BEGIN OF ty_release_request,
             layer       TYPE zwm_layer,
             reason_code TYPE mb_grbew,
             reason_text TYPE grtxt,
           END OF ty_release_request.

    "! Outcome of an operation. SUCCESS decides whether MSG_NO is a success or
    "! a failure message.
    TYPES: BEGIN OF ty_result,
             success TYPE abap_bool,
             tanum   TYPE tanum,
             msg_no  TYPE symsgno,
             msg_v1  TYPE symsgv,
             msg_v2  TYPE symsgv,
           END OF ty_result.

    "! IO_CONFIG is injected so the class can be unit tested with prepared
    "! customizing instead of reading the database.
    METHODS constructor
      IMPORTING io_config TYPE REF TO zcl_wm_action_config OPTIONAL.

    "! Adds a block layer to the quant. The layer number is derived from the
    "! number of open layers, it is not taken from the caller.
    METHODS block
      IMPORTING is_stock          TYPE zwm_quan_1s
                is_request        TYPE ty_block_request
                iv_bwart          TYPE bwart DEFAULT c_bwart_block
      RETURNING VALUE(rs_result)  TYPE ty_result.

    "! Releases one open layer. The release reason must repeat the block
    "! reason, as the specification demands.
    METHODS release
      IMPORTING is_stock          TYPE zwm_quan_1s
                is_request        TYPE ty_release_request
                iv_bwart          TYPE bwart DEFAULT c_bwart_unblock
      RETURNING VALUE(rs_result)  TYPE ty_result.

    "! Replaces the reason of an existing open layer. Bookkeeping only, the
    "! physical block is not touched.
    METHODS modify_reason
      IMPORTING is_stock          TYPE zwm_quan_1s
                iv_layer          TYPE zwm_layer
                is_request        TYPE ty_block_request
                iv_bwart          TYPE bwart DEFAULT c_bwart_block
      RETURNING VALUE(rs_result)  TYPE ty_result.

    "! The open layers of a quant, for display.
    METHODS get_open_layers
      IMPORTING is_stock          TYPE zwm_quan_1s
      RETURNING VALUE(rt_layers)  TYPE tt_layer.

    "! Pure function: which layer number follows a given number of open
    "! layers. Kept free of database access so it can be unit tested.
    METHODS next_free_layer
      IMPORTING iv_open_layers    TYPE i
      RETURNING VALUE(rv_layer)   TYPE zwm_layer.

  PRIVATE SECTION.
    DATA mo_config TYPE REF TO zcl_wm_action_config.

    METHODS count_open_layers
      IMPORTING is_stock        TYPE zwm_quan_1s
      RETURNING VALUE(rv_count) TYPE i.

    METHODS read_layer
      IMPORTING is_stock      TYPE zwm_quan_1s
                iv_layer      TYPE zwm_layer
      RETURNING VALUE(rs_layer) TYPE ty_layer.

    "! The single place in this class that talks to the transfer-order
    "! function module. I_BESTQ is the stock category BEFORE the change.
    METHODS post_posting_change
      IMPORTING is_stock      TYPE zwm_quan_1s
                iv_bwlvs      TYPE bwlvs
                iv_bestq      TYPE bestq
      EXPORTING ev_tanum      TYPE tanum
                ev_subrc      TYPE sysubrc.

    METHODS insert_layer
      IMPORTING is_stock      TYPE zwm_quan_1s
                iv_layer      TYPE zwm_layer
                iv_dept       TYPE zwm_dept
                iv_reason_code TYPE mb_grbew
                iv_reason_text TYPE grtxt
                iv_tanum      TYPE tanum
      RETURNING VALUE(rv_subrc) TYPE sysubrc.

    METHODS set_layer_released
      IMPORTING is_stock      TYPE zwm_quan_1s
                iv_layer      TYPE zwm_layer
                iv_reason_code TYPE mb_grbew
                iv_reason_text TYPE grtxt
                iv_tanum      TYPE tanum
      RETURNING VALUE(rv_subrc) TYPE sysubrc.
ENDCLASS.


CLASS zcl_wm_stock_block IMPLEMENTATION.

  METHOD constructor.
    mo_config = COND #( WHEN io_config IS BOUND THEN io_config
                        ELSE NEW zcl_wm_action_config( ) ).
  ENDMETHOD.


  METHOD next_free_layer.
    DATA(lv_next) = iv_open_layers + 1.
    rv_layer = lv_next.
  ENDMETHOD.


  METHOD count_open_layers.
    SELECT COUNT(*) FROM zwm_blocklog_1t
      WHERE lgnum  = @is_stock-lgnum
        AND lqnum  = @is_stock-lqnum
        AND status = @c_status_open
      INTO @rv_count.
  ENDMETHOD.


  METHOD read_layer.
    SELECT SINGLE * FROM zwm_blocklog_1t
      WHERE lgnum  = @is_stock-lgnum
        AND lqnum  = @is_stock-lqnum
        AND layer  = @iv_layer
        AND status = @c_status_open
      INTO @rs_layer.
  ENDMETHOD.


  METHOD get_open_layers.
    SELECT * FROM zwm_blocklog_1t
      WHERE lgnum  = @is_stock-lgnum
        AND lqnum  = @is_stock-lqnum
        AND status = @c_status_open
      ORDER BY layer
      INTO TABLE @rt_layers.
  ENDMETHOD.


  METHOD block.
    DATA(lv_open) = count_open_layers( is_stock ).

    IF lv_open >= c_max_layers.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-max_layers_reached.
      rs_result-msg_v1 = is_stock-lqnum.
      RETURN.
    ENDIF.

    DATA(lv_layer) = next_free_layer( lv_open ).

    " Validate the reason against T157E before anything is written.
    DATA(ls_reason) = mo_config->get_reason( iv_bwart       = iv_bwart
                                             iv_reason_code = is_request-reason_code ).

    IF ls_reason IS INITIAL.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-reason_not_found.
      rs_result-msg_v1 = is_request-reason_code.
      RETURN.
    ENDIF.

    " Only the first layer is a physical block.
    DATA lv_tanum TYPE tanum.
    IF lv_open = 0.
      DATA lv_subrc TYPE sysubrc.
      post_posting_change(
        EXPORTING is_stock = is_stock
                  iv_bwlvs = CONV bwlvs( iv_bwart )
                  iv_bestq = space
        IMPORTING ev_tanum = lv_tanum
                  ev_subrc = lv_subrc ).

      IF lv_subrc <> 0.
        rs_result-msg_no = zcl_wm_msg=>cs_msg-to_create_failed.
        rs_result-msg_v1 = lv_subrc.
        RETURN.
      ENDIF.
    ENDIF.

    DATA(lv_insert) = insert_layer(
      is_stock       = is_stock
      iv_layer       = lv_layer
      iv_dept        = is_request-dept
      iv_reason_code = is_request-reason_code
      iv_reason_text = is_request-reason_text
      iv_tanum       = lv_tanum ).

    IF lv_insert <> 0.
      " Nothing was committed yet, so the transfer order can be discarded.
      ROLLBACK WORK.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-internal_error.
      rs_result-msg_v1 = lv_insert.
      RETURN.
    ENDIF.

    COMMIT WORK AND WAIT.

    rs_result-success = abap_true.
    rs_result-tanum   = lv_tanum.
    rs_result-msg_no  = zcl_wm_msg=>cs_msg-stock_blocked.
    rs_result-msg_v1  = lv_tanum.
  ENDMETHOD.


  METHOD release.
    DATA(ls_layer) = read_layer( is_stock = is_stock iv_layer = is_request-layer ).

    IF ls_layer IS INITIAL.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-layer_not_open.
      rs_result-msg_v1 = is_request-layer.
      RETURN.
    ENDIF.

    " The reason has to exist for this movement type, and releasing a layer
    " has to repeat the reason it was blocked with.
    DATA(ls_reason) = mo_config->get_reason( iv_bwart       = iv_bwart
                                             iv_reason_code = is_request-reason_code ).

    IF ls_reason IS INITIAL.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-reason_not_found.
      rs_result-msg_v1 = is_request-reason_code.
      RETURN.
    ENDIF.

    IF is_request-reason_code <> ls_layer-reason_code.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-release_reason_mismat.
      RETURN.
    ENDIF.

    DATA(lv_open) = count_open_layers( is_stock ).

    " Only releasing the last open layer removes the physical block.
    DATA lv_tanum TYPE tanum.
    IF lv_open = 1.
      DATA lv_subrc TYPE sysubrc.
      post_posting_change(
        EXPORTING is_stock = is_stock
                  iv_bwlvs = CONV bwlvs( iv_bwart )
                  iv_bestq = c_bestq_blocked
        IMPORTING ev_tanum = lv_tanum
                  ev_subrc = lv_subrc ).

      IF lv_subrc <> 0.
        rs_result-msg_no = zcl_wm_msg=>cs_msg-to_create_failed.
        rs_result-msg_v1 = lv_subrc.
        RETURN.
      ENDIF.
    ENDIF.

    DATA(lv_update) = set_layer_released(
      is_stock       = is_stock
      iv_layer       = is_request-layer
      iv_reason_code = is_request-reason_code
      iv_reason_text = is_request-reason_text
      iv_tanum       = lv_tanum ).

    IF lv_update <> 0.
      ROLLBACK WORK.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-internal_error.
      rs_result-msg_v1 = lv_update.
      RETURN.
    ENDIF.

    COMMIT WORK AND WAIT.

    rs_result-success = abap_true.
    rs_result-tanum   = lv_tanum.
    IF lv_tanum IS INITIAL.
      " Other layers are still open, so there was no physical movement.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-layer_released_no_to.
    ELSE.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-layer_released.
    ENDIF.
    rs_result-msg_v1 = is_request-layer.
  ENDMETHOD.


  METHOD modify_reason.
    DATA(ls_reason) = mo_config->get_reason( iv_bwart       = iv_bwart
                                             iv_reason_code = is_request-reason_code ).

    IF ls_reason IS INITIAL.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-reason_not_found.
      rs_result-msg_v1 = is_request-reason_code.
      RETURN.
    ENDIF.

    DATA lv_code TYPE mb_grbew.
    DATA lv_text TYPE text60.
    DATA lv_user TYPE xubname.
    DATA lv_date TYPE erdat.
    DATA lv_time TYPE erzet.
    DATA lv_lgnum TYPE lgnum.
    DATA lv_lqnum TYPE lvs_lqnum.

    lv_code = is_request-reason_code.
    lv_text = is_request-reason_text.
    lv_user = sy-uname.
    lv_date = sy-datum.
    lv_time = sy-uzeit.
    lv_lgnum = is_stock-lgnum.
    lv_lqnum = is_stock-lqnum.

    UPDATE zwm_blocklog_1t
      SET reason_code = @lv_code
          reason_text = @lv_text
          blocker     = @lv_user
          block_date  = @lv_date
          block_time  = @lv_time
      WHERE lgnum  = @lv_lgnum
        AND lqnum  = @lv_lqnum
        AND layer  = @iv_layer
        AND status = @c_status_open.

    IF sy-subrc <> 0.
      rs_result-msg_no = zcl_wm_msg=>cs_msg-layer_not_open.
      rs_result-msg_v1 = iv_layer.
      RETURN.
    ENDIF.

    COMMIT WORK AND WAIT.

    rs_result-success = abap_true.
    rs_result-msg_no  = zcl_wm_msg=>cs_msg-stock_blocked.
    rs_result-msg_v1  = iv_layer.
  ENDMETHOD.


  METHOD post_posting_change.
    " Source and destination are the same bin: a posting change only moves the
    " stock between stock categories.
    " I_COMMIT_WORK is deliberately empty - the caller owns the unit of work.
    CALL FUNCTION 'L_TO_CREATE_SINGLE'
      EXPORTING
        i_lgnum       = is_stock-lgnum
        i_bwlvs       = iv_bwlvs
        i_matnr       = is_stock-matnr
        i_werks       = is_stock-werks
        i_lgort       = is_stock-lgort
        i_charg       = is_stock-charg
        i_bestq       = iv_bestq
        i_sobkz       = is_stock-sobkz
        i_sonum       = is_stock-sonum
        i_anfme       = is_stock-gesme
        i_altme       = is_stock-meins
        i_vltyp       = is_stock-lgtyp
        i_vlpla       = is_stock-lgpla
        i_nltyp       = is_stock-lgtyp
        i_nlpla       = is_stock-lgpla
        i_kompl       = abap_true
        i_commit_work = space
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
        bestq_wrong        = 8
        OTHERS             = 99.

    ev_subrc = sy-subrc.
  ENDMETHOD.


  METHOD insert_layer.
    DATA lv_user TYPE xubname.
    DATA lv_date TYPE erdat.
    DATA lv_time TYPE erzet.

    lv_user = sy-uname.
    lv_date = sy-datum.
    lv_time = sy-uzeit.

    DATA(ls_layer) = VALUE zwm_blocklog_1t(
      lgnum         = is_stock-lgnum
      lqnum         = is_stock-lqnum
      layer         = iv_layer
      lgtyp         = is_stock-lgtyp
      lgpla         = is_stock-lgpla
      matnr         = is_stock-matnr
      werks         = is_stock-werks
      lgort         = is_stock-lgort
      charg         = is_stock-charg
      bestq         = is_stock-bestq
      sobkz         = is_stock-sobkz
      sonum         = is_stock-sonum
      meins         = is_stock-meins
      gesme         = is_stock-gesme
      dept          = iv_dept
      reason_code   = iv_reason_code
      reason_text   = iv_reason_text
      blocker       = lv_user
      block_date    = lv_date
      block_time    = lv_time
      tanum_block   = iv_tanum
      status        = c_status_open ).

    INSERT zwm_blocklog_1t FROM ls_layer.

    rv_subrc = sy-subrc.
  ENDMETHOD.


  METHOD set_layer_released.
    DATA lv_user TYPE xubname.
    DATA lv_date TYPE erdat.
    DATA lv_time TYPE erzet.
    DATA lv_lgnum TYPE lgnum.
    DATA lv_lqnum TYPE lvs_lqnum.

    lv_user = sy-uname.
    lv_date = sy-datum.
    lv_time = sy-uzeit.
    lv_lgnum = is_stock-lgnum.
    lv_lqnum = is_stock-lqnum.

    UPDATE zwm_blocklog_1t
      SET status          = @c_status_released
          rel_reason_code = @iv_reason_code
          rel_reason_text = @iv_reason_text
          releaser        = @lv_user
          rel_date        = @lv_date
          rel_time        = @lv_time
          tanum_rel       = @iv_tanum
      WHERE lgnum = @lv_lgnum
        AND lqnum = @lv_lqnum
        AND layer = @iv_layer
        AND status = @c_status_open.

    rv_subrc = sy-subrc.
  ENDMETHOD.

ENDCLASS.
