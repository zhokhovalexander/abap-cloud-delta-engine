CLASS zcl_test_data_run DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_TEST_DATA_RUN IMPLEMENTATION.


METHOD if_oo_adt_classrun~main.

    TRY.

        zcl_test_data=>insert_test_data( ).

        COMMIT WORK AND WAIT.

        out->write(
          |Test item { zcl_test_data=>gc_document_id } / |
          && |{ zcl_test_data=>gc_item_id } inserted successfully.|
        ).

      CATCH cx_root INTO DATA(lx_error).

        ROLLBACK WORK.

        out->write(
          |Insert failed: { lx_error->get_text( ) }|
        ).

    ENDTRY.

  ENDMETHOD.
ENDCLASS.
