# What you get

32 views in bcModel, over 137 tables in bc.

| **View** | **What it is** |
| --- | --- |
| vw_apAging | Aged payables, from Business Central's own subledger. |
| vw_arAging | Aged receivables, from Business Central's own subledger. |
| vw_cashApplications | Cash application detail: which payment settled which invoice, when, and for how much. |
| vw_customerStatement | Customer statement: every subledger entry in posting-date order, with a running balance. Open and closed entries both, because a statement that hides settled documents cannot be reconciled against. |
| vw_dataQuality | - |
| vw_dimensionSetPivot | One row per dimension set, with the eight global dimension slots pivoted into columns. |
| vw_dimensionSets | Dimensions, resolved. |
| vw_documentExit | One row per document that has left the open feed, resolved from the event stream. |
| vw_documentHistory | Every in-flight document ever seen, open or exited, on one column vocabulary, with its dimensions already expanded. The three views in 31_views_lifecycle.sql are built on this one, so they inherit the dimension columns without joining anything themselves. |
| vw_documentLifecycle | - |
| vw_dqDanglingDimSets | - |
| vw_dqDuplicateKeys | - |
| vw_dqEventsWithoutDocument | - |
| vw_dqOrphanLines | One row per failing thing. NO ROWS MEANS CLEAN: a check that finds nothing contributes nothing, so there is no "passed" row to read and no check history to maintain. |
| vw_generalLedgerDetail | The drill-down behind the trial balance: every G/L entry with its account name and category, and the two global dimensions BC carries inline. |
| vw_grossMargin | Gross margin at real cost, by item and month. |
| vw_inventoryOnHand | On hand by item and location, with reorder context. |
| vw_inventoryValuation | Inventory valuation, the way Business Central computes it. |
| vw_ledgerDocuments | Every posted customer, vendor and employee ledger document on one column vocabulary. |
| vw_loadHealth | One row per (entity set x company): how many records, how many versions behind them, how many have exited, when a map last wrote, and how current the source data is. Alert on lastLoadedUtc going stale. |
| vw_openDocumentAging | - |
| vw_openDocuments | 31 - Lifecycle views (schema model) Point Power BI here, not at [bc]. |
| vw_openOrderBacklog | Open order backlog: what is committed but not yet posted, by document type and age. The counterpart to the posted reports above -- and the number no BC report can give you historically: BC deletes the open document, so once it is gone the backlog it was part of cannot be reconstructed. If you need backlog OVER TIME rather than as of now, capture this view on a schedule - nothing here does that for you. |
| vw_purchaseAnalysis | - |
| vw_purchasesByItem | - |
| vw_purchasesByVendor | - |
| vw_salesAnalysis | The sales fact: one row per posted sales invoice or credit memo LINE, with its header's customer and dates, and credit memos negated so the view sums to net revenue without anyone having to remember the sign. |
| vw_salesByCustomer | - |
| vw_salesByItem | - |
| vw_salesByPeriod | - |
| vw_trialBalance | Trial balance at monthly grain, with an inception-to-date running balance. |
| vw_vendorStatement | Vendor statement: every subledger entry in posting-date order, with a running balance. Open and closed entries both, because a statement that hides settled documents cannot be reconciled against. |

---

[Back: Confirm it is working](09-confirm-it-is-working.md) | [Contents](README.md) | [Next: Known limits](11-known-limits.md)
