CLASS ltc_layer_arithmetic DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcl_wm_stock_block.

    METHODS setup.
    METHODS first_layer_of_empty_quant FOR TESTING.
    METHODS second_layer FOR TESTING.
    METHODS third_layer FOR TESTING.
    METHODS maximum_is_three FOR TESTING.
ENDCLASS.


CLASS ltc_layer_arithmetic IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.


  METHOD first_layer_of_empty_quant.
    " A quant without any layer gets layer 1.
    DATA(lv_layer) = mo_cut->next_free_layer( 0 ).

    cl_abap_unit_assert=>assert_equals(
      act = lv_layer
      exp = '1'
      msg = 'The first layer of an unblocked quant must be 1' ).
  ENDMETHOD.


  METHOD second_layer.
    DATA(lv_layer) = mo_cut->next_free_layer( 1 ).

    cl_abap_unit_assert=>assert_equals(
      act = lv_layer
      exp = '2'
      msg = 'A quant with one layer must get layer 2' ).
  ENDMETHOD.


  METHOD third_layer.
    DATA(lv_layer) = mo_cut->next_free_layer( 2 ).

    cl_abap_unit_assert=>assert_equals(
      act = lv_layer
      exp = '3'
      msg = 'A quant with two layers must get layer 3' ).
  ENDMETHOD.


  METHOD maximum_is_three.
    " The specification allows at most three layers per quant, so the layer
    " numbers must stop at 3.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_wm_stock_block=>c_max_layers
      exp = 3
      msg = 'The cockpit must allow exactly three block layers' ).
  ENDMETHOD.

ENDCLASS.
