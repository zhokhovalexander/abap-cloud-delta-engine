CLASS zcl_log_writer DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
   TYPES ty_event_id TYPE zdoc_item_log-event_id.

    CLASS-METHODS write_event
      IMPORTING
        iv_document_id TYPE zdoc_item-document_id
        iv_item_id     TYPE zdoc_item-item_id
        iv_amount      TYPE zdoc_item-amount
        iv_currency    TYPE zdoc_item-currency
        iv_changed_at  TYPE zdoc_item-changed_at
        iv_change_type TYPE zdoc_item_log-change_type
      RETURNING
        VALUE(rv_event_id) TYPE ty_event_id.

ENDCLASS.



CLASS ZCL_LOG_WRITER IMPLEMENTATION.


METHOD write_event.

    DATA ls_log_event TYPE zdoc_item_log.

    " Determine the next event identifier.
    " This implementation is sufficient for the current single-process
    " learning scenario. Concurrency protection will be added later.
    SELECT SINGLE
           FROM zdoc_item_log
           FIELDS MAX( event_id )
           INTO @DATA(lv_last_event_id).

    rv_event_id = COND #(
      WHEN lv_last_event_id IS INITIAL
      THEN 1
      ELSE lv_last_event_id + 1 ).

    ls_log_event = VALUE #(
      event_id    = rv_event_id
      document_id = iv_document_id
      item_id     = iv_item_id
      amount      = iv_amount
      currency    = iv_currency
      changed_at  = iv_changed_at
      change_type = iv_change_type

      " REQUEST_ID and PACKET_NO remain initial.
      " They will be assigned by the delta extraction process.
    ).

    INSERT zdoc_item_log FROM @ls_log_event.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_sy_open_sql_db.
    ENDIF.

  ENDMETHOD.
ENDCLASS.
