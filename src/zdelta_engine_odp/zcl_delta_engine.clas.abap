CLASS zcl_delta_engine DEFINITION

"!
"! Purpose
"! -------
" ! ----------------------------------------------------------------------
"! Executes one complete delta processing cycle.
"! Coordinates locking, normal and replay delta processing.
"! ----------------------------------------------------------------------
"!
"! Responsibilities
"! ----------------
"! - Acquire processing lock
"! - Read current delta pointer
"! - Replay failed packets
"! - Read new events from ZDOC_ITEM_LOG
"! - Split events into processing packets
"! - Process packets
"! - Update packet status
"! - Advance delta pointer
"! - Release processing lock
"!
"! Database Tables
"! ---------------
"! ZDOC_ITEM_LOG
"! ZDELTA_STATE
"! ZPACKET_STATE
"!
"! Public API
"! ----------
"! RUN_DELTA( )
"! ----------------------------------------------------------------------

  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
  "!----------------------------------------------------------------------
  "Coordinates one complete delta processing cycle.
  "
  "!---------------------------------------------------------------------
  CLASS-METHODS run_delta.

  PROTECTED SECTION.

  PRIVATE SECTION.

  CONSTANTS:
       gc_source_name TYPE zdelta_state-source_name VALUE 'ZCDS_DOC_LOG',
       gc_packet_size TYPE i VALUE 2.

TYPES:
       tt_delta_events TYPE STANDARD TABLE OF zdoc_item_log
        WITH EMPTY KEY,

       BEGIN OF ts_packet,
                request_id     TYPE zpacket_state-request_id,
                packet_no     TYPE zpacket_state-packet_no,
                first_event_id TYPE zpacket_state-first_event_id,
                last_event_id  TYPE zpacket_state-last_event_id,
                events         TYPE tt_delta_events,
       END OF ts_packet,

       tt_packets TYPE STANDARD TABLE OF ts_packet WITH EMPTY KEY.


CLASS-DATA:
        mv_last_event_id   TYPE zdelta_state-last_event_id,
        mv_last_request_id TYPE zdelta_state-last_request_id,
        mv_new_request_id TYPE zdelta_state-last_request_id,
        mt_delta_events TYPE tt_delta_events,
        mt_packets TYPE tt_packets,
        mv_lock_token TYPE zdelta_state-lock_token.



 " Lock handling
"! ----------------------------------------------------------------------
"! Acquires exclusive processing lock.
"! Prevents parallel execution of RUN_DELTA.
"! ----------------------------------------------------------------------
    CLASS-METHODS acquire_lock RETURNING VALUE(rv_acquired) TYPE abap_bool.

"! ----------------------------------------------------------------------
"!  Releases processing lock.
"! ----------------------------------------------------------------------
    CLASS-METHODS release_lock.


" Delta state handling
"! ----------------------------------------------------------------------
"! Reads the current delta pointer from ZDELTA_STATE.
"! Returns the last successfully processed EVENT_ID.
"! ----------------------------------------------------------------------
    CLASS-METHODS read_delta_pointer.

"-----------------------------------------------------------------------
"! Updates the processing status of an existing delta packet.
"! Used when a previously failed packet is reprocessed.
"------------------------------------------------------------------------
    CLASS-METHODS update_packet_state
        IMPORTING
            is_packet TYPE ts_packet
            iv_status TYPE zpacket_state-status.


 "Event and packet preparation
"!-----------------------------------------------------------------------
"! Reads all events with EVENT_ID greater than LAST_EVENT_ID.
"! Does not modify database state.
"! ----------------------------------------------------------------------
    CLASS-METHODS read_new_events.

"! ----------------------------------------------------------------------
"! Builds processing packets from delta events.
"! Stores packet metadata in ZPACKET_STATE.
"! ----------------------------------------------------------------------
    CLASS-METHODS build_packets.

"----------------------------------------------------------------------
"! Generates the identifier for the current delta request.
"! Uses the last successfully completed request as the starting point.
"! ----------------------------------------------------------------------
   CLASS-METHODS generate_request_id.

   CLASS-METHODS assign_request_id.


" Request processing
"! ----------------------------------------------------------------------
"! Processes a single packet of delta events.
"! ----------------------------------------------------------------------
   CLASS-METHODS process_packet
        IMPORTING
            is_packet TYPE ts_packet
        RETURNING VALUE(rv_success) TYPE abap_bool.

"! ----------------------------------------------------------------------
"! Updates packet processing status.
"! ----------------------------------------------------------------------
    CLASS-METHODS write_packet_state
        IMPORTING
            is_packet TYPE ts_packet
            iv_status TYPE zpacket_state-status.

"!-----------------------------------------------------------------------
"! Advances the delta pointer after successful request processing.
"! Updates the last successfully processed EVENT_ID and REQUEST_ID.
"!-----------------------------------------------------------------------
    CLASS-METHODS update_delta_pointer.


" Replay processing
"!-----------------------------------------------------------------------
"!  Reprocesses packets with status FAILED
"! and return processing status.
"! -----------------------------------------------------------------------
    CLASS-METHODS replay_failed_packets
      RETURNING
        VALUE(rv_completed) TYPE abap_bool.


ENDCLASS.



CLASS ZCL_DELTA_ENGINE IMPLEMENTATION.


METHOD acquire_lock.

" Table-based locking is used because ENQUEUE objects
" are not available in ABAP Cloud Trial.

DATA:
    lv_locked_at TYPE zdelta_state-locked_at,
    lv_locked_by TYPE zdelta_state-locked_by.
rv_acquired = abap_false.

  " Generate a unique token identifying the current engine execution.
  TRY.
      mv_lock_token =
        cl_system_uuid=>create_uuid_c32_static( ).
    CATCH cx_uuid_error.
      CLEAR mv_lock_token.
      RETURN.
  ENDTRY.

  lv_locked_by = sy-uname.

  CONCATENATE sy-datum sy-uzeit
    INTO lv_locked_at.

   " Acquire the lock only if it is currently free.
  UPDATE zdelta_state
    SET lock_token = @mv_lock_token,
        locked_by  = @lv_locked_by,
        locked_at  = @lv_locked_at
    WHERE source_name = @gc_source_name
      AND lock_token  = @space.

  IF sy-dbcnt = 1.
    rv_acquired = abap_true.
  ELSE.
    CLEAR mv_lock_token.
  ENDIF.

ENDMETHOD.


METHOD run_delta.

DATA:
    i_break TYPE int8.



" Prevent concurrent delta processing.
  IF acquire_lock( ) = abap_false.
    RETURN.
  ENDIF.

  COMMIT WORK AND WAIT.

  TRY.
" Read the last successfully completed delta state.
      read_delta_pointer( ).

" Complete an unfinished request before processing new events.
      DATA(lv_replay_completed) = replay_failed_packets( ).

      IF lv_replay_completed = abap_false.

        release_lock( ).
        COMMIT WORK AND WAIT.
        RETURN.

      ENDIF.

" Replay may have advanced the pointer.

      read_delta_pointer( ).

      read_new_events( ).

      build_packets( ).

      generate_request_id( ).

      assign_request_id( ).


 " Process and persist the final state of every packet.
      LOOP AT mt_packets INTO DATA(ls_packet).
        DATA(lv_success) = process_packet(
          is_packet = ls_packet
          ).

        IF lv_success = abap_true.

            write_packet_state(
             is_packet = ls_packet
             iv_status = 'DONE' ).

        ELSE.

            write_packet_state(
              is_packet = ls_packet
              iv_status = 'FAILED'   ).

        ENDIF.

      ENDLOOP.


    " Advance the pointer only after the whole request is successful.
    update_delta_pointer( ).


    CATCH cx_root into DATA(lx_error).

      ROLLBACK WORK.



  " Always release the processing lock after a successful cycle.
      release_lock( ).
      COMMIT WORK AND WAIT.

      RETURN.

  ENDTRY.


  release_lock( ).

  COMMIT WORK AND WAIT.

ENDMETHOD.


 METHOD release_lock.

    IF mv_lock_token IS INITIAL.
        RETURN.
    ENDIF.

    UPDATE zdelta_state
        SET lock_token = @space,
            locked_by  = @space,
            locked_at  = @space
        WHERE source_name = @gc_source_name
            AND lock_token  = @mv_lock_token.

    IF sy-dbcnt = 1.
        CLEAR mv_lock_token.
    ENDIF.

ENDMETHOD.


METHOD read_delta_pointer.

    CLEAR:   mv_last_event_id, mv_last_request_id.
    SELECT SINGLE
        FROM zdelta_state
        FIELDS last_event_id,
           last_request_id
        WHERE source_name = @gc_source_name
        INTO ( @mv_last_event_id,
           @mv_last_request_id ).

        IF sy-subrc <> 0.
            RAISE EXCEPTION TYPE cx_sy_open_sql_db.
        ENDIF.


ENDMETHOD.


METHOD replay_failed_packets.

      DATA:
           lt_failed_packets TYPE STANDARD TABLE OF zpacket_state
            WITH EMPTY KEY,
           ls_packet         TYPE ts_packet.
      DATA:
          i_break TYPE int8.

rv_completed = abap_true.
" Find the oldest request that still contains failed packets.
      SELECT SINGLE
        FROM zpacket_state
        FIELDS MIN( request_id )
        WHERE status = 'FAILED'
        INTO @DATA(lv_failed_request_id).
" Read failed packets of the oldest incomplete request.
" Check the aggregate result directly; SY-SUBRC does not indicate
" whether MIN( ) found a FAILED request
        IF lv_failed_request_id IS INITIAL.
            RETURN.
       ENDIF.

     SELECT
        FROM zpacket_state
        FIELDS *
      WHERE request_id = @lv_failed_request_id
         AND status     = 'FAILED'
      ORDER BY packet_no
      INTO TABLE @lt_failed_packets.

      LOOP AT lt_failed_packets INTO DATA(ls_failed_packet).

        CLEAR ls_packet.

" Rebuild the packet from persisted metadata.
        ls_packet-request_id     = ls_failed_packet-request_id.
        ls_packet-packet_no      = ls_failed_packet-packet_no.
        ls_packet-first_event_id = ls_failed_packet-first_event_id.
        ls_packet-last_event_id  = ls_failed_packet-last_event_id.

" Reload the original events using the persisted packet boundaries.
        SELECT
            FROM zdoc_item_log
            FIELDS *
            WHERE event_id >= @ls_failed_packet-first_event_id
                AND event_id <= @ls_failed_packet-last_event_id
            ORDER BY event_id
            INTO TABLE @ls_packet-events.

" Reprocess the failed packet.
         DATA(lv_success) = process_packet(
                 is_packet = ls_packet ).

          IF lv_success = abap_true.

" Mark the packet as DONE only after successful reprocessing.
                update_packet_state(
                        is_packet = ls_packet
                        iv_status = 'DONE'
                        ).

           ENDIF.


"             i_break = 0.

ENDLOOP.

" Stop normal processing if any failed packets still remain.
SELECT SINGLE
  FROM zpacket_state
  FIELDS COUNT( * )
  WHERE request_id = @lv_failed_request_id
    AND status     = 'FAILED'
  INTO @DATA(lv_failed_count).

IF lv_failed_count > 0.
  rv_completed = abap_false.
  RETURN.
ENDIF.

" Determine the final event boundary of the recovered request.
SELECT SINGLE
  FROM zpacket_state
  FIELDS MAX( last_event_id )
  WHERE request_id = @lv_failed_request_id
  INTO @DATA(lv_last_event_id).


" Complete the recovered request and advance the delta pointer.
UPDATE zdelta_state
  SET last_event_id   = @lv_last_event_id,
      last_request_id = @lv_failed_request_id
  WHERE source_name = @gc_source_name.

IF sy-dbcnt <> 1.
  RAISE EXCEPTION TYPE cx_sy_open_sql_db.
ENDIF.

" Commit replay separately before normal delta processing continues.
COMMIT WORK AND WAIT.

ENDMETHOD.


METHOD read_new_events.

     CLEAR mt_delta_events.

    SELECT
        FROM zdoc_item_log
        FIELDS *
        WHERE event_id > @mv_last_event_id
        ORDER BY event_id
        INTO TABLE @mt_delta_events.

ENDMETHOD.


METHOD build_packets.


  DATA:
    ls_packet       TYPE ts_packet,
    lv_event_count  TYPE i,
    lv_packet_no    TYPE zpacket_state-packet_no.

  CLEAR mt_packets.

  IF mt_delta_events IS INITIAL.
    RETURN.
  ENDIF.

  lv_packet_no = 1.

  LOOP AT mt_delta_events INTO DATA(ls_event).

    IF ls_packet-events IS INITIAL.
      ls_packet-packet_no      = lv_packet_no.
      ls_packet-first_event_id = ls_event-event_id.
    ENDIF.

    APPEND ls_event TO ls_packet-events.

    ls_packet-last_event_id = ls_event-event_id.
    lv_event_count = lv_event_count + 1.

    IF lv_event_count = gc_packet_size.

      APPEND ls_packet TO mt_packets.

      CLEAR:
        ls_packet,
        lv_event_count.

      lv_packet_no = lv_packet_no + 1.

    ENDIF.

  ENDLOOP.

  " Append the final incomplete packet.
  IF ls_packet-events IS NOT INITIAL.
    APPEND ls_packet TO mt_packets.
  ENDIF.


ENDMETHOD.


METHOD process_packet.

  " Test-only error injection.
  " Use packet 2 to simulate failure; keep unreachable during normal runs.
    rv_success = abap_true.
" Test-only error injection.
    IF is_packet-packet_no = 452.
        rv_success = abap_false.
        RETURN.

    ENDIF.
" Actual packet processing will be implemented here.

ENDMETHOD.


METHOD write_packet_state.

    DATA ls_packet_state TYPE zpacket_state.

    ls_packet_state-request_id     = is_packet-request_id.
    ls_packet_state-packet_no      = is_packet-packet_no.
    ls_packet_state-status         = iv_status.
    ls_packet_state-first_event_id = is_packet-first_event_id.
    ls_packet_state-last_event_id  = is_packet-last_event_id.
    ls_packet_state-created_at = utclong_current( ).

" Persist the final state of a newly processed packet.
    INSERT zpacket_state FROM @ls_packet_state.

    if sy-subrc <> 0.
        RAISE EXCEPTION TYPE cx_sy_open_sql_db.
    ENDIF.

 " Actual packet processing will be implemented here later.


ENDMETHOD.


METHOD update_packet_state.

" Update an existing packet without changing its original creation time.
  UPDATE zpacket_state
    SET status = @iv_status
    WHERE request_id = @is_packet-request_id
      AND packet_no  = @is_packet-packet_no.

  IF sy-dbcnt <> 1.
    RAISE EXCEPTION TYPE cx_sy_open_sql_db.
  ENDIF.


ENDMETHOD.


METHOD update_delta_pointer.

    DATA:
        lv_expected_packets TYPE int8,
        lv_done_packets TYPE int8,
        ls_last_packet TYPE ts_packet.

  " The delta pointer can advance only if packets exist
  " and all expected packets were persisted as DONE.


    lv_expected_packets = lines( mt_packets ).

    IF lv_expected_packets = 0.
        RETURN.
    ENDIF.

    SELECT SINGLE
        FROM zpacket_state
        FIELDS COUNT( * )
        WHERE
         request_id = @mv_new_request_id
        AND status     = 'DONE'
            INTO @lv_done_packets.

    IF lv_done_packets <> lv_expected_packets.
        RETURN.
        ENDIF.

  " The last packet defines the new delta boundary.
    READ TABLE mt_packets INDEX lv_expected_packets INTO ls_last_packet.

    IF sy-subrc <> 0.
        RETURN.
    ENDIF.

  " Persist the successfully completed request and its last event.
    UPDATE zdelta_state
    SET last_event_id   = @ls_last_packet-last_event_id,
        last_request_id = @mv_new_request_id
    WHERE source_name = @gc_source_name.

  " Должна быть изменена ровно 1 запись:
  " Exactly one record must be changed
    IF sy-dbcnt <> 1.
        RAISE EXCEPTION TYPE cx_sy_open_sql_db.
    ENDIF.

ENDMETHOD.


METHOD generate_request_id.



    DATA lv_request_number TYPE int8.
    DATA i_break TYPE int8.
    lv_request_number = mv_last_request_id.
    lv_request_number = lv_request_number + 1.
    mv_new_request_id = lv_request_number.

" Breakpoint
i_break = 0.

ENDMETHOD.


METHOD assign_request_id.

  LOOP AT mt_packets ASSIGNING FIELD-SYMBOL(<ls_packet>).

    <ls_packet>-request_id = mv_new_request_id.

  ENDLOOP.

ENDMETHOD.
ENDCLASS.
