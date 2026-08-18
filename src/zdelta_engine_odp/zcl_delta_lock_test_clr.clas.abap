CLASS zcl_delta_lock_test_clr DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
     INTERFACES if_oo_adt_classrun.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_DELTA_LOCK_TEST_CLR IMPLEMENTATION.


    METHOD if_oo_adt_classrun~main.

      " Remove packet state created by the test request.
        DELETE FROM zpacket_state
            WHERE request_id = '0000000001'.

  " Restore the initial delta state and clear the processing lock.

        UPDATE zdelta_state
        SET last_event_id   = 0,
            last_request_id = '0000000000',
            lock_token      = @space,
            locked_by       = @space,
            locked_at       = @space
        WHERE source_name = 'ZCDS_DOC_LOG'.

    COMMIT WORK AND WAIT.
    out->write( 'Delta test state reset successfully.' ).
    ENDMETHOD.
ENDCLASS.
