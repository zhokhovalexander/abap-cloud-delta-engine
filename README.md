# ABAP Cloud Delta Engine

A small educational ABAP Cloud project demonstrating a stateful
delta-processing engine with packet-based processing, persistent delta
state, table-based locking, failure handling, and failed-packet replay.

The project was developed in SAP BTP ABAP Environment using ABAP
Development Tools (ADT).

## Purpose

The project demonstrates how a custom delta-processing mechanism can:

-   acquire and release an exclusive processing lock;
-   prevent concurrent delta runs from processing the same state or
    generating the same request;
-   store lock ownership and lock timestamp in persistent delta state;
-   read events incrementally from an event log;
-   maintain a persistent delta pointer;
-   split new events into processing packets;
-   group packets into requests;
-   persist packet processing status;
-   prevent the delta pointer from advancing after partial failure;
-   replay failed packets on the next run;
-   continue normal delta processing only after recovery succeeds;
-   release the processing lock after successful processing and
    controlled failure handling.

The table-based lock protects the complete processing cycle. In
particular, it prevents concurrent runs from reading and updating the
same delta pointer or generating the same `REQUEST_ID`.

The project is intended primarily as an architecture and ABAP Cloud
learning example rather than a production-ready framework.

## Processing Model

The project separates source-data changes, event logging, and delta
extraction.

``` text
ZDOC_ITEM
    |
    | INSERT / UPDATE
    v
ZCL_LOG_WRITER
    |
    v
ZDOC_ITEM_LOG
    |
    | Delta extraction
    v
ZCL_DELTA_ENGINE
    |
    +----> ZPACKET_STATE
    |
    +----> ZDELTA_STATE
```

Every source-data change used by the test scenario creates an event in
`ZDOC_ITEM_LOG`.

Each event has a unique `EVENT_ID`. The last successfully processed
event is stored in `ZDELTA_STATE`.

The Delta Engine processing cycle is:

``` text
Acquire Lock
     |
     v
Read Delta Pointer
     |
     v
Replay Failed Packets
     |
     +---- replay unsuccessful ----> Release Lock / Stop
     |
     v
Read Delta Pointer Again
     |
     v
Read New Events
     |
     v
Build Packets
     |
     v
Generate Request ID
     |
     v
Assign Request ID
     |
     v
Process Packets
     |
     v
Persist DONE / FAILED
     |
     v
Update Delta Pointer
     |
     v
Release Lock
```

## Core Design Rules

### Delta Pointer

`ZDELTA_STATE-LAST_EVENT_ID` represents the last successfully completed
event.

The pointer advances only when all expected packets of the current
request have been persisted with status `DONE`.

If any packet fails, the pointer remains unchanged.

### Requests and Packets

New events are divided into fixed-size packets.

All packets created during one processing cycle share the same
`REQUEST_ID`.

Each packet stores:

-   `REQUEST_ID`
-   `PACKET_NO`
-   `FIRST_EVENT_ID`
-   `LAST_EVENT_ID`
-   processing status
-   creation timestamp

Packet state is persisted in `ZPACKET_STATE`.

The current implementation uses two final statuses:

``` text
DONE
FAILED
```

### Locking

The engine uses a table-based lock stored in `ZDELTA_STATE`.

Only one Delta Engine processing cycle for a source may own the lock at
a time.

The lock protects the complete processing lifecycle, including:

-   reading the current delta state;
-   replaying an unfinished request;
-   reading new events;
-   generating a new `REQUEST_ID`;
-   processing packets;
-   advancing the delta pointer.

This prevents two concurrent runs from reading the same state,
generating the same request, or updating the same delta pointer
independently.

Lock ownership and lock timestamp are stored in the persistent delta
state.

The lock is released after successful completion as well as during
controlled error handling.

### Failed Packet Replay

An unfinished request must be completed before a new request can be
created.

At the beginning of a processing cycle, the engine searches
`ZPACKET_STATE` for the oldest request containing `FAILED` packets.

Failed packets are reconstructed from their persisted event boundaries:

``` text
FIRST_EVENT_ID ... LAST_EVENT_ID
```

The corresponding events are re-read from `ZDOC_ITEM_LOG` and processed
again.

After successful replay:

``` text
FAILED -> DONE
```

When all packets of the recovered request are `DONE`, the delta pointer
is advanced.

Replay is committed separately before normal delta processing continues.
This prevents a later failure in normal processing from rolling back an
already recovered request.

If replay fails again:

-   the packet remains `FAILED`;
-   the delta pointer remains unchanged;
-   normal delta processing is not started;
-   the processing lock is released.

## Main Tables

### `ZDOC_ITEM`

Stores the current test document item.

The standard test record is:

``` text
DOCUMENT_ID = 0000001001
ITEM_ID     = 000001
CURRENCY    = EUR
```

### `ZDOC_ITEM_LOG`

Persistent event log used as the source for delta extraction.

Each INSERT or UPDATE performed by the test-data utilities creates a new
event through `ZCL_LOG_WRITER`.

The event sequence is ordered by `EVENT_ID`.

### `ZDELTA_STATE`

Stores persistent Delta Engine state, including:

-   last successfully processed `EVENT_ID`;
-   last successfully completed `REQUEST_ID`;
-   processing lock token;
-   lock owner;
-   lock timestamp.

### `ZPACKET_STATE`

Stores persistent packet metadata and processing status, including:

-   `REQUEST_ID`;
-   `PACKET_NO`;
-   `STATUS`;
-   `FIRST_EVENT_ID`;
-   `LAST_EVENT_ID`;
-   creation timestamp.

## Main Classes

### Delta Engine

#### `ZCL_DELTA_ENGINE`

Core delta-processing engine.

Responsibilities include:

-   acquiring and releasing the processing lock;
-   reading and updating the delta pointer;
-   reading new events;
-   packet construction;
-   request generation;
-   packet processing;
-   packet-state persistence;
-   failed-packet replay;
-   transaction coordination.

#### `ZCL_DELTA_ENGINE_RUN`

Executable runner for the Delta Engine.

Calls the public `RUN_DELTA` entry point.

After execution, it verifies that all processing-lock fields have been
cleared.

Expected successful console output:

``` text
Lock cycle completed successfully.
```

If the lock was not released correctly:

``` text
Lock was not released correctly.
```

### Event Logging

#### `ZCL_LOG_WRITER`

Utility responsible for writing events to `ZDOC_ITEM_LOG`.

Method `WRITE_EVENT`:

-   determines the next `EVENT_ID`;
-   stores document/item values and change metadata;
-   writes the event to `ZDOC_ITEM_LOG`;
-   returns the generated `EVENT_ID`.

`REQUEST_ID` and `PACKET_NO` remain initial when the event is created.
They belong to the later delta-extraction process.

The current `EVENT_ID` generation uses:

``` text
MAX(EVENT_ID) + 1
```

This is sufficient for the current single-process learning scenario. It
is not intended as a concurrency-safe event-number generator for a
production system.

### Test Data Utilities

#### `ZCL_TEST_DATA`

Provides reusable methods for creating and changing the test document
item.

`INSERT_TEST_DATA`:

-   creates document `0000001001`, item `000001`;
-   sets the initial amount to `1000.00 EUR`;
-   writes an `I` event through `ZCL_LOG_WRITER`.

`UPDATE_TEST_DATA`:

-   reads the same test item;
-   increases the amount by `100`;
-   updates the change timestamp;
-   writes a `U` event through `ZCL_LOG_WRITER`.

#### `ZCL_TEST_DATA_RUN`

Executable runner for initial test-data creation.

Calls:

``` text
ZCL_TEST_DATA=>INSERT_TEST_DATA
```

Expected successful console output:

``` text
Test item 0000001001 / 000001 inserted successfully.
```

#### `ZCL_TEST_DATA_UPDATE_RUN`

Executable runner for test-data changes.

Each execution increases the test amount by `100` and creates another
event.

Typical successful output after the first update:

``` text
Item 0000001001 / 000001 updated successfully.
New amount: 1100.00 EUR
Changed at: <timestamp>
```

Subsequent executions produce amounts `1200.00`, `1300.00`, and so on.

### State and Lock Utilities

#### `ZCL_DELTA_STATE_INIT`

Executable initialization utility.

Creates the initial `ZDELTA_STATE` record for source:

``` text
ZCDS_DOC_LOG
```

with:

``` text
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000
```

Possible console messages are:

``` text
Delta state initialized successfully.
```

``` text
Delta state already exists.
```

or, if initialization fails:

``` text
Delta state initialization failed.
```

#### `ZCL_DELTA_LOCK_TEST_SET`

Test utility for creating a processing-lock condition.

It is used to verify that the Delta Engine detects an existing lock and
does not start a concurrent processing cycle.

#### `ZCL_DELTA_LOCK_TEST_CLR`

Test/reset utility for restoring Delta Engine processing state before
another extraction test.

It resets the processing state required for repeatable Delta Engine
runs, including packet state and lock information.

It intentionally does **not** delete `ZDOC_ITEM` or `ZDOC_ITEM_LOG`.

The event log is treated as persistent source data. Once a useful set of
events has been generated, the same event sequence can be reused
repeatedly while testing and debugging the extraction engine.

## Transaction Model

Normal processing and replay use explicit transaction boundaries.

A normal request is committed only after its processing state has been
completed.

Failed replay is treated as a separate recovery transaction.

The basic rules are:

``` text
successful request
    -> all packets DONE
    -> advance pointer
    -> commit

failed request
    -> at least one packet FAILED
    -> keep pointer unchanged

successful replay
    -> FAILED becomes DONE
    -> complete old request
    -> advance pointer
    -> commit replay
    -> normal processing may continue

failed replay
    -> keep FAILED
    -> keep pointer unchanged
    -> do not start a new request
```

The processing lock protects the overall processing cycle across these
operations.

## Initial Test Data Setup

Test events need to be generated only once.

First initialize the Delta Engine state:

``` text
ZCL_DELTA_STATE_INIT
```

For a clean installation, the expected message is:

``` text
Delta state initialized successfully.
```

Next create the initial test item by running:

``` text
ZCL_TEST_DATA_RUN
```

Expected output:

``` text
Test item 0000001001 / 000001 inserted successfully.
```

This creates the first event:

``` text
EVENT_ID    = 1
CHANGE_TYPE = I
AMOUNT      = 1000.00 EUR
```

Then run:

``` text
ZCL_TEST_DATA_UPDATE_RUN
```

three times.

The three updates create:

``` text
EVENT_ID    CHANGE_TYPE    AMOUNT

1           I              1000.00 EUR
2           U              1100.00 EUR
3           U              1200.00 EUR
4           U              1300.00 EUR
```

Verify that `ZDOC_ITEM_LOG` contains these four events.

This event set can now be reused for repeated Delta Engine tests.

## Smoke Test

The Smoke Test validates one complete successful delta-processing cycle.

The standard test assumes:

``` text
4 source events
packet size = 2
```

Therefore the engine is expected to create two packets.

### 1. Reset Delta Processing State

Run:

``` text
ZCL_DELTA_LOCK_TEST_CLR
```

This resets the Delta Engine processing state but leaves `ZDOC_ITEM` and
`ZDOC_ITEM_LOG` unchanged.

Verify:

``` text
ZPACKET_STATE:
no test packet records

ZDELTA_STATE:
LAST_EVENT_ID   = 0
LAST_REQUEST_ID = 0000000000

Lock fields:
empty
```

### 2. Run the Delta Engine

Run:

``` text
ZCL_DELTA_ENGINE_RUN
```

### 3. Verify Console Output

Expected:

``` text
Lock cycle completed successfully.
```

This confirms that the processing lock was released after the Delta
Engine cycle.

Packet-processing results are verified separately in the state tables.

### 4. Verify Packet State

`ZPACKET_STATE` should contain:

``` text
REQUEST_ID   PACKET_NO   STATUS   FIRST_EVENT_ID   LAST_EVENT_ID

0000000001       1       DONE            1               2
0000000001       2       DONE            3               4
```

### 5. Verify Delta State

`ZDELTA_STATE` should contain:

``` text
LAST_EVENT_ID   = 4
LAST_REQUEST_ID = 0000000001
```

The processing-lock fields must be empty.

If these conditions are met, the normal end-to-end Delta Engine cycle
has completed successfully.

## Repeating the Smoke Test

Do not regenerate the source events for every test.

Run:

``` text
ZCL_DELTA_LOCK_TEST_CLR
```

to reset the extraction state, and then execute:

``` text
ZCL_DELTA_ENGINE_RUN
```

again.

`ZDOC_ITEM` and `ZDOC_ITEM_LOG` are deliberately preserved.

This separation allows the same event set to be processed repeatedly
while developing, debugging, or changing the Delta Engine.

## Failure and Replay Tests

The project supports controlled error injection for testing:

-   failed packet handling;
-   prevention of delta-pointer advancement after partial failure;
-   successful replay;
-   repeated replay failure;
-   prevention of a new request while an earlier request remains
    incomplete;
-   lock release after failed processing;
-   rejection of a concurrent run while the processing lock is held.

Detailed procedures are documented in
[`docs/testing.md`](docs/testing.md).

## Repository Scope

The repository contains the objects required for the Delta Engine, event
logging, test-data generation, and reproducible testing.

Objects belonging to unrelated experiments are intentionally excluded.

For example, `ZAPI_STATE`, which was created for separate API/OData
acquisition experiments, is not used by the Delta Engine and is not part
of this repository.

## Repository Structure

The ABAP sources are serialized by abapGit from the root package
`ZDELTA_ENGINE` and its development subpackages:

``` text
ZDELTA_ENGINE
├── ZDELTA_ENGINE_CORE
└── ZDELTA_ENGINE_ODP
```

The GitHub repository contains:

``` text
abap-cloud-delta-engine/
|
|-- src/
|   |-- zdelta_engine_core/
|   |-- zdelta_engine_odp/
|
|-- docs/
|   |-- testing.md
|
|-- .abapgit.xml
|-- README.md
|-- LICENSE
```

The exact ABAP object filenames inside `src` are generated and
maintained by abapGit.

## Environment

Developed and tested with:

-   SAP BTP ABAP Environment;
-   ABAP Cloud;
-   ABAP Development Tools (ADT);
-   Eclipse;
-   abapGit for ADT.

The implementation intentionally avoids dependencies on a specific
productive SAP system.

## Security and Environment Data

Repository sources must not contain environment-specific credentials or
private configuration.

Do not commit:

-   BTP service keys;
-   passwords or tokens;
-   private account or subaccount information;
-   private endpoint configuration;
-   local Eclipse credentials.

## License

The repository is intended to be published as an open-source educational
project.

A permissive license such as the MIT License is suitable for this type
of project. The final license should be selected before publication.

If the MIT License is selected, the repository root will contain a
`LICENSE` file with the standard MIT License text and the appropriate
copyright notice.

## Project Status

The following functionality has been implemented and tested:

-   event logging for source-data changes;
-   table-based processing lock;
-   concurrent-run protection;
-   delta pointer persistence;
-   incremental event reading;
-   packet construction;
-   request generation;
-   packet-state persistence;
-   protection against pointer advancement after partial failure;
-   failed-packet replay;
-   repeated replay failure handling;
-   prevention of normal processing while an earlier request remains
    incomplete;
-   transaction separation between replay and subsequent normal
    processing;
-   lock release after normal and recovery processing;
-   repeatable extraction tests using a persistent event set.

The project remains an educational implementation.

Possible future improvements include:

-   structured application logging;
-   configurable packet sizing;
-   automated unit and integration tests;
-   monitoring;
-   stale-lock recovery policy;
-   dedicated application exception classes;
-   concurrency-safe event ID generation;
-   additional production-oriented error handling.
