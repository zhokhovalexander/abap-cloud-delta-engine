# Delta Engine Testing Guide

This document describes the manual test scenarios used to validate the ABAP Cloud Delta Engine.

The tests cover:

- initial test-data preparation;
- normal delta processing;
- processing-lock behavior;
- packet failure handling;
- delta-pointer protection;
- successful failed-packet replay;
- repeated replay failure;
- prevention of new processing while an earlier request remains incomplete;
- repeated extraction using the same persistent event set.

The tests are designed for execution from ABAP Development Tools (ADT).

## 1. Test Environment

The standard test scenario uses one document item:

```text
DOCUMENT_ID = 0000001001
ITEM_ID     = 000001
CURRENCY    = EUR
```

The event log used by the Delta Engine is:

```text
ZDOC_ITEM_LOG
```

Persistent Delta Engine state is stored in:

```text
ZDELTA_STATE
ZPACKET_STATE
```

The standard packet size is:

```text
2 events
```

The basic four-event test set therefore produces two packets.

## 2. Initial Delta State

Before using the Delta Engine for the first time, run:

```text
ZCL_DELTA_STATE_INIT
```

The class creates the initial state for:

```text
ZDELTA_STATE
SOURCE_NAME = ZCDS_DOC_LOG
```

with:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
```

### Expected Console Output

For a new environment:

Delta state initialized successfully.

If the state already exists:

Delta state already exists.

If initialization fails:

Delta state initialization failed.

### Database Verification

Open ZDELTA_STATE.

Locate the row:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
```

The existing row is not overwritten if it was already present.

## 3. Initial Test Data Setup

Test events need to be generated only once.

```text
ZDOC_ITEM and ZDOC_ITEM_LOG are treated as persistent source data and are reused during repeated Delta Engine tests.
```

3.1 Create the Initial Document Item

Run:

```text
ZCL_TEST_DATA_RUN
```

The runner calls:

```text
ZCL_TEST_DATA=>INSERT_TEST_DATA
```

which creates:

```text
ZDOC_ITEM
DOCUMENT_ID = 0000001001
ITEM_ID     = 000001
AMOUNT      = 1000.00
CURRENCY    = EUR
```

It also calls:

```text
ZCL_LOG_WRITER=>WRITE_EVENT
```

to create the first event.

### Expected Console Output

Test item 0000001001 / 000001 inserted successfully.

### Database Verification

Open ZDOC_ITEM.

Locate:

```text
DOCUMENT_ID = 0000001001
ITEM_ID     = 000001
```

Verify:

```text
AMOUNT   = 1000.00
CURRENCY = EUR
```

Open ZDOC_ITEM_LOG.

Locate:

```text
EVENT_ID = 1
```

Verify:

```text
DOCUMENT_ID = 0000001001
ITEM_ID     = 000001
AMOUNT      = 1000.00
CURRENCY    = EUR
CHANGE_TYPE = I
```

## 4. Generate the Standard Four-Event Set

Run:

```text
ZCL_TEST_DATA_UPDATE_RUN
```

three times.

Each execution:

- reads the current test item;
- increases AMOUNT by 100;
- updates CHANGED_AT;
- updates ZDOC_ITEM;
- creates a new U event through ZCL_LOG_WRITER.

### Expected Console Output

After the first update:

Item 0000001001 / 000001 updated successfully.

New amount: 1100.00 EUR

Changed at: <timestamp>

The second and third executions produce the same message structure with amounts:

1200.00 EUR

1300.00 EUR

and their corresponding timestamps.

### Database Verification

Open ZDOC_ITEM.

Locate:

```text
DOCUMENT_ID = 0000001001
ITEM_ID     = 000001
```

Verify the final amount:

```text
AMOUNT = 1300.00 EUR
```

Open ZDOC_ITEM_LOG.

Verify:

```text
EVENT_ID   CHANGE_TYPE   AMOUNT
1          I             1000.00 EUR
2          U             1100.00 EUR
3          U             1200.00 EUR
4          U             1300.00 EUR
```

This four-event sequence is the standard source data used by the following tests.

## 5. Test 1 — Normal End-to-End Processing

### Purpose

Verify that a complete request containing two successful packets is processed and persisted correctly.

### Preparation

Verify that ZDOC_ITEM_LOG contains:

```text
EVENT_ID = 1
EVENT_ID = 2
EVENT_ID = 3
EVENT_ID = 4
```

Ensure that the test-only error injection in PROCESS_PACKET is disabled by using an unreachable packet number:

```text
IF is_packet-packet_no = 452.
```

Run:

```text
ZCL_DELTA_LOCK_TEST_CLR
```

### Expected Reset Console Output

Delta test state reset successfully.

### Database Verification After Reset

Open ZPACKET_STATE.

Verify that no rows exist with:

```text
REQUEST_ID = 0000000001
```

Open ZDELTA_STATE.

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

### Execution

Run:

```text
ZCL_DELTA_ENGINE_RUN
```

### Expected Console Output

Lock cycle completed successfully.

### Database Verification

Open ZPACKET_STATE.

Locate the rows with:

```text
REQUEST_ID = 0000000001
```

Verify packet 1:

```text
PACKET_NO      = 1
STATUS         = DONE
FIRST_EVENT_ID = 1
LAST_EVENT_ID  = 2
```

Verify packet 2:

```text
PACKET_NO      = 2
STATUS         = DONE
FIRST_EVENT_ID = 3
LAST_EVENT_ID  = 4
```

Open ZDELTA_STATE.

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 4
LAST_REQUEST_ID = 0000000001
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

### Result Validated

This test confirms:

- lock acquisition and release;
- delta-pointer reading;
- event reading;
- packet construction;
- request generation;
- request assignment;
- packet processing;
- packet-state persistence;
- successful delta-pointer advancement.

## 6. Test 2 — Existing Processing Lock

### Purpose

Verify that the Delta Engine does not start processing when another processing lock already exists.

### Preparation

Run:

```text
ZCL_DELTA_LOCK_TEST_CLR
```

### Expected Console Output

Delta test state reset successfully.

Then run:

```text
ZCL_DELTA_LOCK_TEST_SET
ZCL_DELTA_LOCK_TEST_SET does not write a console message.
```

### Database Verification Before Engine Run

Open ZDELTA_STATE.

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LOCK_TOKEN = TEST_FOREIGN_LOCK
LOCKED_BY  = TEST_USER
LOCKED_AT  = 20260731120000
```

Open ZPACKET_STATE.

Verify that no packet rows for the test request have been created.

### Execution

Run:

```text
ZCL_DELTA_ENGINE_RUN
```

### Expected Console Output

With the current implementation of ZCL_DELTA_ENGINE_RUN:

Lock was not released correctly.

In this particular test this message is expected.

The Delta Engine did not acquire the lock and therefore must not remove the existing foreign/test lock. The runner only checks whether the lock fields are empty, so it reports the still-existing foreign lock with the generic message above.

### Database Verification After Engine Run

Open ZDELTA_STATE.

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify that the foreign lock is unchanged:

```text
LOCK_TOKEN = TEST_FOREIGN_LOCK
LOCKED_BY  = TEST_USER
LOCKED_AT  = 20260731120000
```

Verify:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
```

Open ZPACKET_STATE.

Verify that no new rows have been created for:

```text
REQUEST_ID = 0000000001
```

### Cleanup

Run:

```text
ZCL_DELTA_LOCK_TEST_CLR
```

Expected output:

Delta test state reset successfully.

Open ZDELTA_STATE, locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

and verify:

```text
LOCK_TOKEN = initial
LOCKED_BY  = initial
LOCKED_AT  = initial
```

### Result Validated

This test confirms that the table-based lock prevents concurrent processing and that a lock owned by another process is not removed by a rejected Delta Engine run.

## 7. Test 3 — Packet Failure and Pointer Protection

### Purpose

Verify that failure of one packet prevents the delta pointer from advancing.

### Preparation

Run:

```text
ZCL_DELTA_LOCK_TEST_CLR
```

### Expected Reset Console Output

Delta test state reset successfully.

Temporarily enable test-only error injection in PROCESS_PACKET:

```text
IF is_packet-packet_no = 2.
```

### Database Verification Before Execution

Open ZDELTA_STATE.

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 0
```

LAST_REQUEST_ID = 0000000000

```text
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

Open ZPACKET_STATE.

Verify that no rows exist with:

```text
REQUEST_ID = 0000000001
```

### Execution

Run:

```text
ZCL_DELTA_ENGINE_RUN
```

### Expected Console Output

Lock cycle completed successfully.

The message confirms that the processing lock was released. It does not mean that all packets were successful.

### Database Verification

Open ZPACKET_STATE.

Locate:

```text
REQUEST_ID = 0000000001
```

Verify packet 1:

```text
PACKET_NO      = 1
STATUS         = DONE
FIRST_EVENT_ID = 1
LAST_EVENT_ID  = 2
```

Verify packet 2:

```text
PACKET_NO      = 2
STATUS         = FAILED
FIRST_EVENT_ID = 3
LAST_EVENT_ID  = 4
```

Open ZDELTA_STATE.

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify that the pointer has not moved:

```text
LAST_EVENT_ID   = 0
```

LAST_REQUEST_ID = 0000000000

Verify that the lock has been released:

```text
LOCK_TOKEN = initial
LOCKED_BY  = initial
LOCKED_AT  = initial
```

### Result Validated

This test confirms:

The delta pointer advances only when all expected packets of the request are DONE.

A partially successful request must not advance the extraction pointer.

## 8. Test 4 — Successful Failed-Packet Replay

### Purpose

Verify that a failed packet is reconstructed and successfully replayed during the next Delta Engine run.

### Preparation

Start from the database state produced by Test 3.

Open ZPACKET_STATE.

Verify:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 1
STATUS     = DONE
```

and:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 2
STATUS     = FAILED
```

For packet 2 also verify:

```text
FIRST_EVENT_ID = 3
LAST_EVENT_ID  = 4
```

Open ZDELTA_STATE.

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
```

Disable error injection by restoring the unreachable test condition:

```text
IF is_packet-packet_no = 452.
```

### Execution

Run:

```text
ZCL_DELTA_ENGINE_RUN
```

### Expected Console Output

Lock cycle completed successfully.

### Database Verification

Open ZPACKET_STATE.

Locate:

```text
REQUEST_ID = 0000000001
```

Verify packet 1 remains:

```text
PACKET_NO = 1
STATUS    = DONE
```

Verify packet 2 has changed:

```text
PACKET_NO = 2
STATUS    = DONE
```

Its persisted boundaries remain:

```text
FIRST_EVENT_ID = 3
LAST_EVENT_ID  = 4
```

Open ZDELTA_STATE.

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 4
LAST_REQUEST_ID = 0000000001
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

Open ZDOC_ITEM_LOG.

Verify that the original replay source events still exist:

```text
EVENT_ID = 3
EVENT_ID = 4
```

Replay reuses these original events; it does not create replacement source events.

### Expected Internal Behavior

The engine:

- finds the oldest request containing FAILED;
- selects packet 2;
- restores its metadata from ZPACKET_STATE;
- reloads events 3 and 4 from ZDOC_ITEM_LOG;
- reconstructs the packet;
- calls PROCESS_PACKET;
- changes the existing packet status from FAILED to DONE;
- advances the pointer after the complete request becomes successful;
- commits replay before normal processing continues;
- reads the updated delta pointer again.

### Result Validated

This test confirms:

- failed-request detection;
- failed-packet reconstruction;
- event reload from persisted boundaries;
- preservation of the original REQUEST_ID and PACKET_NO;
- FAILED -> DONE transition;
- pointer advancement after successful recovery;
- separate replay transaction boundary.

## 9. Test 5 — Repeated Replay Failure

### Purpose

Verify that normal processing does not continue while an earlier request still contains a failed packet.

### Preparation

First recreate the failed state.

Run:

```text
ZCL_DELTA_LOCK_TEST_CLR
```

Expected console output:

Delta test state reset successfully.

Enable error injection:

```text
IF is_packet-packet_no = 2.
```

Run:

```text
ZCL_DELTA_ENGINE_RUN
```

Expected console output:

Lock cycle completed successfully.

### Database Verification of Prepared Failed State

Open ZPACKET_STATE.

Verify:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 1
STATUS     = DONE
```

and:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 2
STATUS     = FAILED
```

Open ZDELTA_STATE.

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
```

Keep the error injection active:

```text
IF is_packet-packet_no = 2.
```

### Replay Execution

Run:

```text
ZCL_DELTA_ENGINE_RUN
```

again.

### Expected Console Output

Lock cycle completed successfully.

The lock cycle completes correctly even though replay itself remains unsuccessful.

### Database Verification After Failed Replay

Open ZPACKET_STATE.

Locate:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 2
```

Verify:

```text
STATUS = FAILED
```

Packet 1 remains:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 1
STATUS     = DONE
```

Open ZDELTA_STATE.

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

Open ZPACKET_STATE and verify that no duplicate or new request was created.

In particular, there must still be only the original packet rows for:

```text
REQUEST_ID = 0000000001
```

### Result Validated

This test confirms:

A new request must not be created while an earlier request remains incomplete.

It also confirms that unsuccessful replay leaves the packet FAILED, leaves the delta pointer unchanged, and still releases the processing lock.

## 10. Test 6 — Repeated Extraction Using the Same Event Set

### Purpose

Verify that source events can be reused without regenerating ZDOC_ITEM or ZDOC_ITEM_LOG.

### Preparation

Restore the normal unreachable error-injection condition:

```text
IF is_packet-packet_no = 452.
```

Run:

```text
ZCL_DELTA_LOCK_TEST_CLR
```

### Expected Console Output

Delta test state reset successfully.

Do not delete or recreate:

```text
ZDOC_ITEM
ZDOC_ITEM_LOG
```

### Database Verification — Preserved Source Data

Open:

```text
ZDOC_ITEM
```

Locate:

```text
DOCUMENT_ID = 0000001001
ITEM_ID     = 000001
```

For the standard four-event test set, verify:

```text
AMOUNT   = 1300.00
CURRENCY = EUR
```

Open:

```text
ZDOC_ITEM_LOG
```

Verify that the original four events are still present:

```text
EVENT_ID   CHANGE_TYPE   AMOUNT
1          I             1000.00 EUR
2          U             1100.00 EUR
3          U             1200.00 EUR
4          U             1300.00 EUR
```

No new source events need to be generated for this test.

### Database Verification — Reset Delta State

Open:

```text
ZPACKET_STATE
```

Verify that no rows exist for:

```text
REQUEST_ID = 0000000001
```

Open:

```text
ZDELTA_STATE
```

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

This confirms that the extraction state has been reset while the source event set has been preserved.

### Execution

Run:

```text
ZCL_DELTA_ENGINE_RUN
```

### Expected Console Output

Lock cycle completed successfully.

This confirms that the processing lock was released after the extraction cycle.

The actual extraction result must be verified in ZPACKET_STATE and ZDELTA_STATE.

### Database Verification — Packet State

Open:

```text
ZPACKET_STATE
```

Locate the rows with:

```text
REQUEST_ID = 0000000001
```

Verify packet 1:

```text
PACKET_NO      = 1
STATUS         = DONE
FIRST_EVENT_ID = 1
LAST_EVENT_ID  = 2
```

Verify packet 2:

```text
PACKET_NO      = 2
STATUS         = DONE
FIRST_EVENT_ID = 3
LAST_EVENT_ID  = 4
```

The same source events have therefore been packetized and processed again from the reset delta pointer.

### Database Verification — Delta State

Open:

```text
ZDELTA_STATE
```

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 4
LAST_REQUEST_ID = 0000000001
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

### Database Verification — Source Data After Processing

Open:

```text
ZDOC_ITEM_LOG
```

Verify that the original event set is unchanged:

```text
EVENT_ID = 1
EVENT_ID = 2
EVENT_ID = 3
EVENT_ID = 4
```

The Delta Engine reads the event log but does not delete or recreate the source events during extraction.

```text
ZDOC_ITEM should also remain unchanged by the extraction process.
```

For the standard test set:

```text
DOCUMENT_ID = 0000001001
ITEM_ID     = 000001
AMOUNT      = 1300.00
CURRENCY    = EUR
```

### Result Validated

This test confirms that:

- ZDOC_ITEM and ZDOC_ITEM_LOG are persistent source data;
- ZCL_DELTA_LOCK_TEST_CLR resets Delta Engine processing state without deleting the source event set;
- the delta pointer can be returned to the initial position independently of the source data;
- the same events can be processed repeatedly during development and debugging;
- packet state is recreated correctly from the preserved event sequence;
- successful repeated extraction advances the pointer back to EVENT_ID = 4;
- the processing lock is released after the repeated extraction cycle.

The test validates the intended separation between persistent source/event data (ZDOC_ITEM, ZDOC_ITEM_LOG) and resettable Delta Engine state (ZDELTA_STATE, ZPACKET_STATE, processing lock).

## 11. Debugging Checkpoints

ADT breakpoints can be used to inspect the internal state of the Delta Engine while executing:

```text
ZCL_DELTA_ENGINE_RUN
```

For step-by-step debugging:

- F5 — Step Into;
- F6 — Step Over;
- F7 — Step Return;
- F8 — Resume to the next breakpoint.

The checkpoints below are optional diagnostic steps and are not required for the normal test scenarios.

### 11.1 After READ_DELTA_POINTER

Inspect:

```text
MV_LAST_EVENT_ID
MV_LAST_REQUEST_ID
```

For a freshly reset standard test:

```text
MV_LAST_EVENT_ID   = 0
MV_LAST_REQUEST_ID = 0000000000
```

### Database Reference

The values originate from:

```text
Table: ZDELTA_STATE
Key:
SOURCE_NAME = ZCDS_DOC_LOG
Fields:
LAST_EVENT_ID
LAST_REQUEST_ID
```

The values in memory should correspond to the persistent delta state read from this row.

### 11.2 After READ_NEW_EVENTS

Inspect the internal table containing the newly selected events.

For the standard four-event test after resetting the pointer to 0, the table should contain:

```text
EVENT_ID = 1
EVENT_ID = 2
EVENT_ID = 3
EVENT_ID = 4
```

### Database Reference

The events originate from:

```text
Table: ZDOC_ITEM_LOG
```

Field used as the delta boundary:

```text
EVENT_ID
```

For the standard test, the engine reads events whose EVENT_ID is greater than the current LAST_EVENT_ID.

The source rows in ZDOC_ITEM_LOG must remain unchanged by the extraction process.

### 11.3 After BUILD_PACKETS

Inspect:

```text
MT_PACKETS
```

For the standard four-event scenario and packet size 2, expect:

Packet 1:

```text
PACKET_NO      = 1
FIRST_EVENT_ID = 1
LAST_EVENT_ID  = 2
```

Packet 2:

```text
PACKET_NO      = 2
FIRST_EVENT_ID = 3
LAST_EVENT_ID  = 4
```

At this stage the packet model exists in memory.

### Database Reference

The corresponding persistent packet state does not need to exist yet in:

```text
ZPACKET_STATE
ZPACKET_STATE is populated later when packet-processing results are persisted.
```

### 11.4 After GENERATE_REQUEST_ID

Inspect:

```text
MV_LAST_REQUEST_ID
MV_NEW_REQUEST_ID
```

For a freshly reset standard test:

```text
MV_LAST_REQUEST_ID = 0000000000
MV_NEW_REQUEST_ID  = 0000000001
```

### Database Reference

The previous request identifier originates from:

```text
Table: ZDELTA_STATE
Key:
SOURCE_NAME = ZCDS_DOC_LOG
Field:
```

LAST_REQUEST_ID

The new request identifier is generated in memory and is persisted only after successful request completion.

### 11.5 After ASSIGN_REQUEST_ID

Inspect:

```text
MT_PACKETS
```

Every packet belonging to the current processing cycle should contain:

```text
REQUEST_ID = 0000000001
```

For the standard test:

Packet 1:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 1
```

Packet 2:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 2
```

### Database Reference

At this stage the assignment is still represented by the in-memory packet model.

After packet processing, the same identifiers should be persisted in:

```text
Table: ZPACKET_STATE
```

Key fields:

```text
REQUEST_ID
PACKET_NO
```

### 11.6 Inside WRITE_PACKET_STATE

Set a breakpoint immediately after:

```text
INSERT zpacket_state FROM @ls_packet_state.
```

For a successful insert, verify:

```text
SY-SUBRC = 0
SY-DBCNT = 1
```

### Database Reference

The target table is:

```text
ZPACKET_STATE
```

For the standard successful test, the final committed rows should be:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 1
STATUS     = DONE
```

```text
REQUEST_ID = 0000000001
PACKET_NO  = 2
STATUS     = DONE
```

An important transaction detail applies here:

A successful INSERT with SY-SUBRC = 0 and SY-DBCNT = 1 may still be invisible from a separate ADT Data Preview session until the current transaction is committed.

If a later exception causes:

```text
ROLLBACK WORK.
```

the previously successful uncommitted insert is rolled back.

### 11.7 Inside UPDATE_PACKET_STATE

This checkpoint is primarily useful during failed-packet replay.

Set a breakpoint immediately after the UPDATE of ZPACKET_STATE.

For a successful update, verify:

```text
SY-DBCNT = 1
```

### Database Reference

The updated row is identified by:

```text
Table: ZPACKET_STATE
Key:
REQUEST_ID = <failed request>
PACKET_NO  = <failed packet>
```

For the standard replay scenario:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 2
```

Before successful replay:

```text
STATUS = FAILED
```

After successful replay and commit:

```text
STATUS = DONE
```

CREATED_AT is not changed during replay because it represents the original creation time of the packet-state record.

### 11.8 Inside UPDATE_DELTA_POINTER

For the standard successful request, inspect:

```text
LV_EXPECTED_PACKETS = 2
LV_DONE_PACKETS     = 2
```

The method may advance the pointer.

### Database Verification After Commit

Open:

```text
ZDELTA_STATE
```

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Expected:

```text
LAST_EVENT_ID   = 4
LAST_REQUEST_ID = 0000000001
```

For the failure scenario with packet 2 in FAILED status, inspect:

```text
LV_EXPECTED_PACKETS = 2
LV_DONE_PACKETS     = 1
```

The method must return without advancing the pointer.

### Database Verification After Failed Request

Open:

```text
ZDELTA_STATE
```

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Expected:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
```

### 11.9 Inside REPLAY_FAILED_PACKETS

For the standard replay scenario, set a breakpoint after selection of the failed request.

Inspect:

```text
LV_FAILED_REQUEST_ID = 0000000001
```

Then inspect:

```text
LT_FAILED_PACKETS
```

Expected:

```text
1 row
REQUEST_ID     = 0000000001
PACKET_NO      = 2
STATUS         = FAILED
FIRST_EVENT_ID = 3
LAST_EVENT_ID  = 4
```

### Database Reference — Failed Packet

The source metadata comes from:

```text
Table: ZPACKET_STATE
Key:
REQUEST_ID = 0000000001
PACKET_NO  = 2
```

The failed packet is then reconstructed by reading:

```text
Table: ZDOC_ITEM_LOG
Rows:
EVENT_ID = 3
EVENT_ID = 4
```

After reconstruction, inspect LS_PACKET.

Expected:

```text
REQUEST_ID     = 0000000001
PACKET_NO      = 2
FIRST_EVENT_ID = 3
LAST_EVENT_ID  = 4
EVENTS:
EVENT_ID = 3
EVENT_ID = 4
```

After successful replay and commit, verify:

```text
ZPACKET_STATE
REQUEST_ID = 0000000001
PACKET_NO  = 2
STATUS     = DONE
```

and:

```text
ZDELTA_STATE
SOURCE_NAME     = ZCDS_DOC_LOG
LAST_EVENT_ID   = 4
LAST_REQUEST_ID = 0000000001
```

### 11.10 Exception and Rollback Diagnosis

If an INSERT or UPDATE appears to succeed in the debugger but its result is missing after program completion, set a breakpoint in the CATCH block of RUN_DELTA.

Inspect the caught exception object.

A useful diagnostic expression is:

```text
DATA(lv_error_text) = lx_error->get_text( ).
```

If execution reaches:

```text
ROLLBACK WORK.
```

all uncommitted database changes in the current transaction are rolled back.

### Database Verification

After rollback, inspect the tables affected by the current test, particularly:

```text
ZPACKET_STATE
ZDELTA_STATE
```

Compare their values with the expected state described in the corresponding test scenario.

### Console Output

There is no dedicated debugger console message for this checkpoint.

The final message from ZCL_DELTA_ENGINE_RUN reflects only its lock-state check and should not be used as the sole indicator of transaction success.

## 12. Test-Only Error Injection

### Purpose

PROCESS_PACKET contains a deliberately unreachable condition used as a simple manual test hook.

It allows packet-processing failure and replay behavior to be tested without introducing an actual external processing error.

This is a code-level test switch, not an independently executable test.

### 12.1 Normal Setting

During normal processing, use an unreachable packet number:

```text
IF is_packet-packet_no = 452.
```

The standard four-event test creates only:

```text
PACKET_NO = 1
PACKET_NO = 2
```

Therefore no artificial processing failure occurs.

### Console Output

Not applicable at the moment the switch is configured.

Console output is produced only when one of the executable test scenarios is subsequently run.

For a normal successful execution of:

```text
ZCL_DELTA_ENGINE_RUN
```

the expected console output is:

Lock cycle completed successfully.

### Database Verification

After a normal successful run, verify:

```text
Table: ZPACKET_STATE
Key:
REQUEST_ID = 0000000001
```

Expected:

```text
PACKET_NO = 1
STATUS    = DONE
PACKET_NO = 2
STATUS    = DONE
```

Then verify:

```text
Table: ZDELTA_STATE
Key:
SOURCE_NAME = ZCDS_DOC_LOG
```

Expected:

```text
LAST_EVENT_ID   = 4
LAST_REQUEST_ID = 0000000001
```

### 12.2 Enabling Failure for Packet 2

To simulate a processing failure, temporarily change the condition to:

```text
IF is_packet-packet_no = 2.
```

Packet 1 will process normally.

Packet 2 will return an unsuccessful processing result.

### Execution

Before running the failure scenario, reset the processing state:

```text
ZCL_DELTA_LOCK_TEST_CLR
```

Expected console output:

Delta test state reset successfully.

Then run:

```text
ZCL_DELTA_ENGINE_RUN
```

### Expected Console Output

Lock cycle completed successfully.

This message confirms lock release only.

It does not indicate that every packet finished successfully.

### Database Verification — Failed Packet

Open:

```text
ZPACKET_STATE
```

Locate:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 2
```

Expected:

```text
STATUS         = FAILED
FIRST_EVENT_ID = 3
LAST_EVENT_ID  = 4
```

Also verify packet 1:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 1
STATUS     = DONE
```

### Database Verification — Protected Pointer

Open:

```text
ZDELTA_STATE
```

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Expected:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

This state is the starting point for the replay tests.

### 12.3 Enabling Successful Replay

After creating the failed state above, restore the unreachable condition:

```text
IF is_packet-packet_no = 452.
```

Do not run ZCL_DELTA_LOCK_TEST_CLR, because that would delete the failed packet state required for replay.

Run:

```text
ZCL_DELTA_ENGINE_RUN
```

### Expected Console Output

Lock cycle completed successfully.

### Database Verification — Replayed Packet

Open:

```text
ZPACKET_STATE
```

Locate:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 2
```

Expected:

```text
STATUS = DONE
```

Packet 1 must also remain:

```text
STATUS = DONE
```

### Database Verification — Recovered Pointer

Open:

```text
ZDELTA_STATE
```

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Expected:

```text
LAST_EVENT_ID   = 4
LAST_REQUEST_ID = 0000000001
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

### 12.4 Enabling Repeated Replay Failure

To test an unsuccessful replay, first create the failed state with:

```text
IF is_packet-packet_no = 2.
```

After the initial failed run, leave the same condition active.

Do not reset ZPACKET_STATE.

Run:

```text
ZCL_DELTA_ENGINE_RUN
```

again.

Packet 2 should fail during replay for a second time.

### Expected Console Output

Lock cycle completed successfully.

The lock is released even though replay remains unsuccessful.

### Database Verification — Packet State

Open:

```text
ZPACKET_STATE
```

Locate:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 2
```

Expected:

```text
STATUS = FAILED
```

Packet 1 remains:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 1
STATUS     = DONE
```

### Database Verification — Delta State

Open:

```text
ZDELTA_STATE
```

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Expected:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

No new request should be created while request 0000000001 remains incomplete.

### 12.5 Restore Normal Test Configuration

After completing failure/replay tests, restore:

```text
IF is_packet-packet_no = 452.
```

This is the normal configuration for subsequent smoke tests and normal development runs.

If a failed packet state remains from the previous test, run:

```text
ZCL_DELTA_LOCK_TEST_CLR
```

Expected console output:

Delta test state reset successfully.

### Database Verification

Open:

```text
ZPACKET_STATE
```

Verify that no rows remain for:

```text
REQUEST_ID = 0000000001
```

Open:

```text
ZDELTA_STATE
```

Locate:

```text
SOURCE_NAME = ZCDS_DOC_LOG
```

Verify:

```text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
LOCK_TOKEN      = initial
LOCKED_BY       = initial
LOCKED_AT       = initial
```

```text
ZDOC_ITEM and ZDOC_ITEM_LOG must remain unchanged.
```

### 12.6 Scope of the Error-Injection Mechanism

The hard-coded packet-number condition is intentionally simple and exists only for manual testing of this educational implementation.

It should not be interpreted as production error-handling logic.

A production-oriented implementation should replace it with a dedicated testing mechanism or automated test infrastructure.

The test hook must never change:

- ZDOC_ITEM;
- ZDOC_ITEM_LOG;
- packet numbering;
- request numbering;
- delta-pointer semantics.

Its only purpose is to control the success/failure result returned by PROCESS_PACKET.

## 13. Important Test Invariants

The manual test scenarios described in this document validate a set of architectural invariants of the Delta Engine.

These invariants should remain true when the implementation is modified or extended.

### 13.1 Single Processing Owner

Only one Delta Engine processing cycle for a source may own the processing lock at a time.

The lock state is stored in:

```text
Table: ZDELTA_STATE
Key:
SOURCE_NAME = ZCDS_DOC_LOG
Fields:
LOCK_TOKEN
LOCKED_BY
LOCKED_AT
```

A processing cycle that cannot acquire the lock must not modify the delta pointer or create packet state.

A foreign lock must not be removed by a processing cycle that does not own it.

### 13.2 Delta Pointer Represents Completed Processing

The persistent delta pointer represents only successfully completed processing.

It is stored in:

```text
Table: ZDELTA_STATE
Key:
SOURCE_NAME = ZCDS_DOC_LOG
Fields:
LAST_EVENT_ID
```

LAST_REQUEST_ID

The pointer must never be advanced merely because events were read or packets were created.

### 13.3 All Expected Packets Must Be DONE

The delta pointer may advance only when all expected packets of the current request have been persisted with:

```text
STATUS = DONE
```

Packet status is stored in:

```text
Table: ZPACKET_STATE
Key:
REQUEST_ID
PACKET_NO
Field:
STATUS
```

If any expected packet is FAILED or missing, the pointer must remain unchanged.

### 13.4 Failed Request Blocks New Processing

A new request must not be created while an earlier request remains incomplete.

If replay of a FAILED packet fails again:

- the packet remains FAILED;
- LAST_EVENT_ID remains unchanged;
- LAST_REQUEST_ID remains unchanged;
- normal delta processing does not start;
- no replacement request is generated.

### 13.5 Replay Preserves Request Identity

Replay completes the original request rather than creating a new one.

A replayed packet retains its original:

```text
REQUEST_ID
PACKET_NO
```

For the standard replay test:

```text
REQUEST_ID = 0000000001
PACKET_NO  = 2
```

remains unchanged while:

```text
STATUS = FAILED
```

changes to:

```text
STATUS = DONE
```

after successful replay.

### 13.6 Replay Uses Persisted Event Boundaries

A failed packet is reconstructed from the boundaries stored in:

```text
ZPACKET_STATE-FIRST_EVENT_ID
ZPACKET_STATE-LAST_EVENT_ID
```

The corresponding source events are re-read from:

```text
ZDOC_ITEM_LOG
```

For the standard failed packet:

```text
FIRST_EVENT_ID = 3
LAST_EVENT_ID  = 4
```

therefore replay must reconstruct the packet from:

```text
ZDOC_ITEM_LOG-EVENT_ID = 3
ZDOC_ITEM_LOG-EVENT_ID = 4
```

The source events are not regenerated during replay.

### 13.7 Successful Replay Is a Separate Transaction

Successful replay is committed before subsequent normal delta processing continues.

This ensures that a later failure in normal processing cannot roll back a successfully recovered request.

After successful replay:

```text
ZPACKET_STATE:
```

failed packet -> DONE

```text
ZDELTA_STATE:
LAST_EVENT_ID   -> recovered request boundary
```

LAST_REQUEST_ID -> recovered request ID

must be committed before new events are processed.

### 13.8 Delta Pointer Is Re-read After Replay

Successful replay may advance the persistent delta pointer.

Therefore normal processing must use the updated state rather than the pointer value read before replay.

For the standard replay test:

Before replay:

```text
LAST_EVENT_ID = 0
```

After successful replay:

```text
LAST_EVENT_ID = 4
```

Normal processing must therefore continue after event 4, rather than reading events 1 ... 4 again as new events.

### 13.9 Processing Lock Must Be Released

After successful processing or controlled processing failure, the Delta Engine must release the lock it owns.

For:

```text
Table: ZDELTA_STATE
Key:
SOURCE_NAME = ZCDS_DOC_LOG
```

normal completion should leave:

```text
LOCK_TOKEN = initial
LOCKED_BY  = initial
LOCKED_AT  = initial
```

The exception is the foreign-lock test: a lock belonging to another owner must remain unchanged.

### 13.10 Source Events and Extraction State Are Independent

The source/event layer consists of:

```text
ZDOC_ITEM
ZDOC_ITEM_LOG
```

The resettable Delta Engine state consists of:

```text
ZDELTA_STATE
ZPACKET_STATE
processing lock



Resetting extraction state must not require deleting or regenerating the source event log.

This allows the same event sequence to be used repeatedly while developing and debugging the Delta Engine.

## 14. Current Testing Scope

The current test suite is manual and is intended to validate the architecture and behavior of the educational Delta Engine implementation.

### 14.1 Functionality Currently Tested

The documented scenarios cover:

- initial Delta Engine state creation;
- test source-data creation;
- event-log generation;
- incremental event reading;
- table-based lock acquisition and release;
- rejection of processing when a foreign lock exists;
- packet construction;
- request ID generation;
- assignment of packets to a request;
- packet-state persistence;
- successful end-to-end processing;
- packet failure simulation;
- prevention of pointer advancement after partial failure;
- failed-packet detection;
- reconstruction of failed packets from persisted boundaries;
- successful failed-packet replay;
- FAILED -> DONE state transition;
- replay transaction separation;
- repeated replay failure;
- prevention of normal processing while an earlier request remains incomplete;
- repeated extraction using the same persistent event set.

### 14.2 Manual Verification

The current scenarios rely on manual verification using:

- ADT class execution;
- ADT debugger;
- Data Preview for ZDOC_ITEM;
- Data Preview for ZDOC_ITEM_LOG;
- Data Preview for ZDELTA_STATE;
- Data Preview for ZPACKET_STATE;
- console output from executable test and runner classes.

The expected database values and console messages are documented in the individual test scenarios.

### 14.3 Not Yet Automated

The project does not currently include automated:

- ABAP Unit tests;
- integration tests;
- regression-test execution;
- automated database-state assertions;
- automated failure injection.

The hard-coded packet-number condition in PROCESS_PACKET is currently used only as a simple manual failure-injection mechanism.

### 14.4 Concurrency Limitations

The Delta Engine processing cycle includes table-based locking and has been manually tested against a simulated foreign lock.

However, the project does not yet include high-concurrency or parallel-session stress testing.

In addition, ZCL_LOG_WRITER currently generates the next event identifier using:

MAX(EVENT_ID) + 1

This is sufficient for the current single-process learning scenario but is not a concurrency-safe event-number generation mechanism for a production environment.

### 14.5 Recovery Scenarios Not Yet Covered

The current manual tests cover controlled processing failure and replay.

They do not yet fully cover:

- uncontrolled runtime termination;
- process termination between database operations;
- stale locks left after an interrupted session;
- automatic stale-lock recovery;
- corrupted or manually inconsistent packet state;
- missing source events required for replay.

These scenarios require additional recovery policies and tests.

### 14.6 Performance Testing

The current tests use a small event set and are intended to validate behavior rather than performance.

The project does not yet include:

- large-volume event tests;
- packet-size performance comparisons;
- database-load measurements;
- memory-consumption measurements;
- parallel-processing benchmarks.

### 14.7 Production-Oriented Testing

Before using a similar design in a production environment, additional testing would be required for:

- concurrency;
- transactional recovery;
- authorization behavior;
- application logging;
- monitoring;
- operational restart procedures;
- configurable packet sizes;
- large data volumes;
- long-running requests;
- production-grade exception handling.

The current project should therefore be treated as a tested educational architecture and reference implementation, not as a production-ready extraction framework.
