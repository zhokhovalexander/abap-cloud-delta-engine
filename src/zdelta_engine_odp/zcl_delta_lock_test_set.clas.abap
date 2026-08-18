CLASS zcl_delta_lock_test_set DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_DELTA_LOCK_TEST_SET IMPLEMENTATION.


    METHOD if_oo_adt_classrun~main.
        UPDATE zdelta_state
        SET lock_token = 'TEST_FOREIGN_LOCK',
            locked_by  = 'TEST_USER',
            locked_at  = '20260731120000'
        WHERE source_name = 'ZCDS_DOC_LOG'.

    COMMIT WORK AND WAIT.

    ENDMETHOD.
ENDCLASS.
