# Schedule

Group the maps so each group can be scheduled, ordered and switched off on its own.

| **Group** | **Cadence** | **Notes** |
| --- | --- | --- |
| documentEvents map | every 5-15 minutes | Must finish before every other map in the cycle. See "Order matters" below. |
| open, posted, ledger | every 15-30 minutes | In-flight documents, posted documents and the subledgers. |
| staging | every 15-30 minutes, optional | eOne's own staged documents. Switch it off if you do not report on integration health. |
| master | hourly | Customers, vendors, items and the rest of the mutable master data. |
| reference, snapshot | nightly, full refresh | Small lookup lists and computed current-state feeds. |

---

[Back: The documentEvents map](06-the-documentevents-map.md) | [Contents](README.md) | [Next: The first load](08-the-first-load.md)
