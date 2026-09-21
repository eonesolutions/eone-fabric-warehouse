# Build the maps

One map per entity set. manifest.json is the checklist: it lists every published entity set with the tier, strategy, watermark column and key the map needs.

Two properties hold across the whole surface and simplify every map:

| **Property** | **Consequence** |
| --- | --- |
| Every entity set is flat and top-level | Document lines are their own entity sets, not nested collections, so each map moves one flat row shape. This is the only shape SmartConnect moves comfortably. |
| Almost every feed publishes lastModifiedDateTime | Bound to SystemModifiedAt, line feeds included, so every map is the same incremental pattern with no header-drives-lines special case. |

### The maps insert; they do not update

Every map INSERTS into bcRaw and never updates. Landing is append-only, so bcRaw accumulates every version of every record the maps have ever seen, and the bc views resolve the latest one per id. Configure the destination as an insert, not an upsert, and do not set a match key on it.

That is why bcRaw must not be read expecting one row per record. Reports read bc.

The views resolve a version by ordering on the source timestamp (lastModifiedDateTime) and using _loadedAt only to break a tie, so a record that arrives twice in one cycle resolves to the version Business Central changed last rather than the one that happened to land last.

### The key

The key is id: the Business Central SystemId, a GUID assigned on insert that never changes, unique on its own across companies and environments. It is what the bc views partition on, and the join key for everything downstream. PRIMARY KEY in Fabric Warehouse is only accepted as NONCLUSTERED NOT ENFORCED, so it informs the optimizer and does not deduplicate - which is exactly why version resolution is done in the view rather than relied on at the destination.

Two things to know about id: it is per record rather than per business document, so posting a sales order creates a new record with a new id, and it does not identify a company. Every endpoint publishes bcCompanyId and bcCompanyName for that.

### Columns the map stamps

Three columns on every landing table come from the map rather than from Business Central. There are no others to supply: _rowState is computed by the bc views, and company arrives in the payload as bcCompanyId and bcCompanyName rather than being stamped from whichever URL the map believed it called.

| **Column** | **Value** | **Why** |
| --- | --- | --- |
| _environment | production / sandbox | So two environments can share one warehouse. |
| _loadedAt | current UTC, per row | What vw_loadHealth measures staleness from, and the tie-break when two versions of a record carry the same source timestamp. |
| _runNumber | the map run's own identifier | Constant for every row one execution writes. It is what makes a bad load undoable: a DELETE with a WHERE clause rather than a full reload. |

---

[Back: Turn on Document Events](04-turn-on-document-events.md) | [Contents](README.md) | [Next: The documentEvents map](06-the-documentevents-map.md)
