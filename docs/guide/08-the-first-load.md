# The first load

Load in tier order. Everything joins to tier 1, so loading it first means the reporting views resolve as the rest arrives.

| **Tier** | **Entity sets** | **What it holds** |
| --- | --- | --- |
| 1 | 38 | Master and reference data. Load first. |
| 2 | 40 | Posted transactions, the subledgers and the cost layer. |
| 3 | 32 | In-flight documents. Needs the documentEvents map to stay correct. |
| 4 | 26 | eOne's own staging layer, plus computed snapshots. Optional. |

### Bound these on the first pull

These feeds can reach tens of millions of rows at a customer with real history. An unbounded first load is not a slow afternoon, it is a load that does not finish. Filter the first pull, then let the watermark take over.

| **Entity set** | **Filter the first load on** |
| --- | --- |
| custLedgerEntries | postingDate |
| detailedCustLedgerEntries | postingDate |
| detailedVendorLedgerEntries | postingDate |
| generalLedgerEntries | postingDate |
| itemLedgerEntries | postingDate |
| valueEntries | postingDate |
| vatEntries | postingDate |
| vendorLedgerEntries | postingDate |

---

[Back: Schedule](07-schedule.md) | [Contents](README.md) | [Next: Confirm it is working](09-confirm-it-is-working.md)
