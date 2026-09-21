# What you are deploying

Three moving parts, and only the middle one runs on a schedule.

| **Part** | **What it does** |
| --- | --- |
| Business Central | Publishes the eOne Integration API, and records document lifecycle transitions on the documentEvents feed. |
| SmartConnect | Scheduled maps, one per entity set, that pull incrementally and write to the warehouse. This is where all load state lives. |
| Fabric Warehouse | 3 schemas: bc, bcModel, bcRaw. See "The schemas" below. |

### The schemas

Read from the schema a query is meant for, not from whichever one happens to hold the rows.

| **Schema** | **Holds** | **Read it for** |
| --- | --- | --- |
| bc | 136 views | Current state. One row per record, resolved to the latest version, with _rowState derived from the event feed. This is what reports should read. |
| bcModel | 1 table, 32 views | Reporting. The views Power BI points at, plus the date dimension. |
| bcRaw | 136 tables | History. Append-only landing: every version of every record the maps have seen. Do not read it expecting one row per record. |

There are no stored procedures. The warehouse holds data and views; everything that moves or maintains data belongs to the integration that owns the schedule. That is deliberate: a warehouse with no load state of its own can be rebuilt at any time without losing bookkeeping.

Delivery is scheduled maps, not webhooks. There is no listener to host and nothing to expose publicly.

---

[Contents](README.md) | [Next: Before you start](02-before-you-start.md)
