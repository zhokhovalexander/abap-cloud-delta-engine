CLASS zcl_delta_state_init DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_DELTA_STATE_INIT IMPLEMENTATION.


    METHOD if_oo_adt_classrun~main.

    DATA ls_delta_state TYPE zdelta_state.

    SELECT SINGLE
        FROM zdelta_state
        FIELDS source_name
        WHERE source_name = 'ZCDS_DOC_LOG'
        INTO @DATA(lv_source_name).

    IF sy-subrc = 0.
        out->write( 'Delta state already exists.' ).
        RETURN.
    ENDIF.

    ls_delta_state = VALUE #(
        source_name     = 'ZCDS_DOC_LOG'
        last_event_id   = 0
        last_request_id = '0000000000'
        ).


    INSERT zdelta_state FROM @ls_delta_state.

    IF sy-subrc = 0.
        COMMIT WORK AND WAIT.
        out->write( 'Delta state initialized successfully.' ).
    ELSE.
        ROLLBACK WORK.
        out->write( 'Delta state initialization failed.' ).
    ENDIF.


   ENDMETHOD.
ENDCLASS.
