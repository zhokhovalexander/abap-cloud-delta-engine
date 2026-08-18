CLASS zcl_test_data DEFINITION
   PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    CLASS-METHODS insert_test_data.

    CLASS-METHODS update_test_data.

*    CLASS-METHODS delete_test_data.

    CONSTANTS:
      gc_document_id TYPE zdoc_item-document_id VALUE '0000001001',
      gc_item_id     TYPE zdoc_item-item_id     VALUE '000001',
      gc_currency    TYPE zdoc_item-currency    VALUE 'EUR'.

  PROTECTED SECTION.
  PRIVATE SECTION.

ENDCLASS.



CLASS ZCL_TEST_DATA IMPLEMENTATION.


METHOD insert_test_data.

    DATA lv_changed_at TYPE zdoc_item-changed_at.

    lv_changed_at = utclong_current( ).

    DATA(ls_doc_item) = VALUE zdoc_item(
      document_id = gc_document_id
      item_id     = gc_item_id
      amount      = '1000.00'
      currency    = gc_currency
      changed_at  = lv_changed_at
    ).

    INSERT zdoc_item FROM @ls_doc_item.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_sy_open_sql_db.
    ENDIF.

    zcl_log_writer=>write_event(
      iv_document_id = ls_doc_item-document_id
      iv_item_id     = ls_doc_item-item_id
      iv_amount      = ls_doc_item-amount
      iv_currency    = ls_doc_item-currency
      iv_changed_at  = ls_doc_item-changed_at
      iv_change_type = 'I'
    ).

  ENDMETHOD.


  METHOD update_test_data.

    DATA:
      lv_changed_at TYPE zdoc_item-changed_at,
      ls_doc_item   TYPE zdoc_item.

    SELECT SINGLE
      FROM zdoc_item
      FIELDS *
      WHERE document_id = @gc_document_id
        AND item_id     = @gc_item_id
      INTO @ls_doc_item.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_sy_open_sql_db.
    ENDIF.

    lv_changed_at = utclong_current( ).

    ls_doc_item-amount     = ls_doc_item-amount + 100.
    ls_doc_item-changed_at = lv_changed_at.

    UPDATE zdoc_item FROM @ls_doc_item.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_sy_open_sql_db.
    ENDIF.

    zcl_log_writer=>write_event(
      iv_document_id = ls_doc_item-document_id
      iv_item_id     = ls_doc_item-item_id
      iv_amount      = ls_doc_item-amount
      iv_currency    = ls_doc_item-currency
      iv_changed_at  = ls_doc_item-changed_at
      iv_change_type = 'U'
    ).

  ENDMETHOD.
ENDCLASS.
