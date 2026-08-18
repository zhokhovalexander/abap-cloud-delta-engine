CLASS zcl_test_data_update_run DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

  INTERFACES if_oo_adt_classrun.

ENDCLASS.



CLASS ZCL_TEST_DATA_UPDATE_RUN IMPLEMENTATION.


 METHOD if_oo_adt_classrun~main.

    TRY.

        zcl_test_data=>update_test_data( ).

        COMMIT WORK AND WAIT.

        SELECT SINGLE
          FROM zdoc_item
          FIELDS amount, currency, changed_at
          WHERE document_id = @zcl_test_data=>gc_document_id
            AND item_id     = @zcl_test_data=>gc_item_id
          INTO @DATA(ls_result).

        out->write(
          |Item { zcl_test_data=>gc_document_id } / |
          && |{ zcl_test_data=>gc_item_id } updated successfully.|
        ).

        out->write(
          |New amount: { ls_result-amount } { ls_result-currency }|
        ).

        out->write(
          |Changed at: { ls_result-changed_at }|
        ).

      CATCH cx_root INTO DATA(lx_error).

        ROLLBACK WORK.

        out->write(
          |Update failed: { lx_error->get_text( ) }|
        ).

    ENDTRY.

  ENDMETHOD.
ENDCLASS.
