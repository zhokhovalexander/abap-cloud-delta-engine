CLASS zcl_delta_engine_run DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_DELTA_ENGINE_RUN IMPLEMENTATION.


    METHOD if_oo_adt_classrun~main.

        zcl_delta_engine=>run_delta( ).

        SELECT SINGLE
            FROM zdelta_state
            FIELDS lock_token, locked_by, locked_at
            WHERE source_name = 'ZCDS_DOC_LOG'
            INTO @DATA(ls_lock_state).

           IF ls_lock_state-lock_token IS INITIAL
                AND ls_lock_state-locked_by IS INITIAL
                AND ls_lock_state-locked_at IS INITIAL.

                out->write( 'Lock cycle completed successfully.' ).

            ELSE.
                out->write( 'Lock was not released correctly.' ).


            ENDIF.



    ENDMETHOD.
ENDCLASS.
