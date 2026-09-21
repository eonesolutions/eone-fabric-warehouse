-- =====================================================================
-- 32 — Out-of-the-box reporting views (schema model)
--
-- The reports a customer expects to already be there on day one, built on
-- the current-state views in [bc] - one row per record, whatever bcRaw holds
-- underneath. Point Power BI at these.
--
-- They are a STARTING POINT, not the finished model: worked examples of how to
-- join a document to its lines, get the sign right on a ledger, and reach
-- dimensions through dimensionSetId. What a business actually reports on is
-- that customer's modelling exercise.
--
--   Financial      vw_trialBalance, vw_generalLedgerDetail
--   Receivables    vw_arAging, vw_customerStatement,
--                  vw_cashApplications
--   Payables       vw_apAging, vw_vendorStatement
--   Sales          vw_salesAnalysis, vw_salesByCustomer, vw_salesByItem,
--                  vw_salesByPeriod
--   Purchasing     vw_purchaseAnalysis, vw_purchasesByVendor,
--                  vw_purchasesByItem
--   Inventory      vw_inventoryValuation, vw_grossMargin,
--                  vw_inventoryOnHand
--   Operations     vw_openOrderBacklog
--
-- The dimension bridge these views join to - vw_dimensionSets and
-- vw_dimensionSetPivot - is in 21_views_dimensions.sql, not here. It has to
-- deploy before 30_view_documenthistory.sql, which also reads it.
--
-- Every view is defined at its natural grain and does NOT pre-filter by
-- date or company. Slicing is the BI tool's job; a view that takes no
-- parameters but aggregates at a fixed grain is the shape that survives
-- being pointed at by five different reports.
--
-- Two honest limits, stated here rather than buried:
--
--   * Periods are FISCAL, taken from the fiscalPeriods endpoint, which
--     publishes Business Central's own accounting calendar. Rows whose
--     posting date falls outside every declared period fall back to the
--     calendar month so nothing is silently dropped - a non-zero
--     calendarFallback count in vw_trialBalance means the fiscal calendar
--     does not cover your data yet.
--   * Costed inventory value and real cost of goods sold come from
--     vw_inventoryValuation and vw_grossMargin, which sum Value Entries.
--     vw_inventoryOnHand's indicativeValue and vw_salesByItem's
--     indicativeMargin predate those and use the item's CURRENT unit cost;
--     prefer the value-entry views.
-- =====================================================================


-- =====================================================================
-- Financial
-- =====================================================================

-- Trial balance at monthly grain, with an inception-to-date running balance.
--
-- Aggregate the months in the BI tool for any period you want; do not try to
-- parameterise the view. `balanceToDate` is cumulative from the first posting
-- ever, which is what a balance-sheet account wants. An income-statement
-- account (category Income / Cost of Goods Sold / Expense) should be read as
-- `netChange` over a chosen range instead -- there is no fiscal calendar here
-- to close the year against.
DROP VIEW IF EXISTS [bcModel].[vw_trialBalance];
GO
CREATE VIEW [bcModel].[vw_trialBalance] AS
WITH periods AS (
    SELECT
        g.[bcCompanyId],
        g.[bcCompanyName],
        g.[accountNumber],
        -- The fiscal period containing the posting date. endingDate is blank on the last declared
        -- period, which means "not bounded yet" rather than "no period" - so it is treated as open.
        COALESCE(fp.[fiscalYear],  YEAR(g.[postingDate]))                                  AS fiscalYear,
        COALESCE(fp.[periodNumber], MONTH(g.[postingDate]))                                AS fiscalPeriodNumber,
        -- DATENAME over a rebuilt first-of-month, not FORMAT over the posting date. Two reasons:
        -- FORMAT is not implemented in Fabric Warehouse at all, and g.[postingDate] itself is not
        -- in the GROUP BY - only YEAR() and MONTH() of it are - so referencing the raw column here
        -- is invalid even where FORMAT exists. DATEFROMPARTS of the two grouped expressions is.
        COALESCE(fp.[name],
                 DATENAME(month, DATEFROMPARTS(YEAR(g.[postingDate]), MONTH(g.[postingDate]), 1))) AS fiscalPeriodName,
        COALESCE(fp.[startingDate], DATEFROMPARTS(YEAR(g.[postingDate]), MONTH(g.[postingDate]), 1)) AS periodStart,
        fp.[endingDate]                                                                    AS periodEnd,
        CASE WHEN fp.[startingDate] IS NULL THEN 1 ELSE 0 END                              AS calendarFallback,
    dp.[dimension1Code],
    dp.[dimension1Name],
    dp.[dimension1ValueCode],
    dp.[dimension1ValueName],
    dp.[dimension2Code],
    dp.[dimension2Name],
    dp.[dimension2ValueCode],
    dp.[dimension2ValueName],
    dp.[dimension3Code],
    dp.[dimension3Name],
    dp.[dimension3ValueCode],
    dp.[dimension3ValueName],
    dp.[dimension4Code],
    dp.[dimension4Name],
    dp.[dimension4ValueCode],
    dp.[dimension4ValueName],
    dp.[dimension5Code],
    dp.[dimension5Name],
    dp.[dimension5ValueCode],
    dp.[dimension5ValueName],
    dp.[dimension6Code],
    dp.[dimension6Name],
    dp.[dimension6ValueCode],
    dp.[dimension6ValueName],
    dp.[dimension7Code],
    dp.[dimension7Name],
    dp.[dimension7ValueCode],
    dp.[dimension7ValueName],
    dp.[dimension8Code],
    dp.[dimension8Name],
    dp.[dimension8ValueCode],
    dp.[dimension8ValueName],
        SUM(g.[debitAmount])   AS debitAmount,
        SUM(g.[creditAmount])  AS creditAmount,
        SUM(g.[amount])        AS netChange,
        COUNT(*)               AS entryCount
    FROM [bc].[generalLedgerEntries] g
    -- The trial balance is DIMENSIONAL: the eight global dimension slots are part of the grain, so
    -- a figure can be read by department or area without dropping to the detail view. An account
    -- with no dimensions posts one row with them all NULL, exactly as before.
    LEFT JOIN [bcModel].[vw_dimensionSetPivot] dp
           ON dp.[dimensionSetId] = g.[dimensionSetId]
          AND dp.[bcCompanyId]    = g.[bcCompanyId]
    LEFT JOIN [bc].[fiscalPeriods] fp
           ON fp.[bcCompanyId] = g.[bcCompanyId]
          AND fp.[_rowState] = 'Active'
          AND g.[postingDate] >= fp.[startingDate]
          AND g.[postingDate] <= COALESCE(fp.[endingDate], CAST('9999-12-31' AS date))
    WHERE g.[_rowState] = 'Active'
    GROUP BY g.[bcCompanyId], g.[bcCompanyName], g.[accountNumber],
             fp.[fiscalYear], fp.[periodNumber], fp.[name], fp.[startingDate], fp.[endingDate],
             YEAR(g.[postingDate]), MONTH(g.[postingDate]),
         dp.[dimension1Code], dp.[dimension1Name], dp.[dimension1ValueCode], dp.[dimension1ValueName],
         dp.[dimension2Code], dp.[dimension2Name], dp.[dimension2ValueCode], dp.[dimension2ValueName],
         dp.[dimension3Code], dp.[dimension3Name], dp.[dimension3ValueCode], dp.[dimension3ValueName],
         dp.[dimension4Code], dp.[dimension4Name], dp.[dimension4ValueCode], dp.[dimension4ValueName],
         dp.[dimension5Code], dp.[dimension5Name], dp.[dimension5ValueCode], dp.[dimension5ValueName],
         dp.[dimension6Code], dp.[dimension6Name], dp.[dimension6ValueCode], dp.[dimension6ValueName],
         dp.[dimension7Code], dp.[dimension7Name], dp.[dimension7ValueCode], dp.[dimension7ValueName],
         dp.[dimension8Code], dp.[dimension8Name], dp.[dimension8ValueCode], dp.[dimension8ValueName]
)
SELECT
    p.[bcCompanyId],
    p.[bcCompanyName],
    p.[accountNumber],
    a.[displayName]  AS accountName,
    a.[category]     AS accountCategory,
    a.[subCategory]  AS accountSubCategory,
    a.[accountType],
    p.fiscalYear,
    p.fiscalPeriodNumber,
    p.fiscalPeriodName,
    p.periodStart,
    p.periodEnd,
    p.calendarFallback,
    p.[dimension1Code],
    p.[dimension1Name],
    p.[dimension1ValueCode],
    p.[dimension1ValueName],
    p.[dimension2Code],
    p.[dimension2Name],
    p.[dimension2ValueCode],
    p.[dimension2ValueName],
    p.[dimension3Code],
    p.[dimension3Name],
    p.[dimension3ValueCode],
    p.[dimension3ValueName],
    p.[dimension4Code],
    p.[dimension4Name],
    p.[dimension4ValueCode],
    p.[dimension4ValueName],
    p.[dimension5Code],
    p.[dimension5Name],
    p.[dimension5ValueCode],
    p.[dimension5ValueName],
    p.[dimension6Code],
    p.[dimension6Name],
    p.[dimension6ValueCode],
    p.[dimension6ValueName],
    p.[dimension7Code],
    p.[dimension7Name],
    p.[dimension7ValueCode],
    p.[dimension7ValueName],
    p.[dimension8Code],
    p.[dimension8Name],
    p.[dimension8ValueCode],
    p.[dimension8ValueName],
    p.debitAmount,
    p.creditAmount,
    p.netChange,
    -- Inception-to-date. Correct for a balance-sheet account; an income-statement account
    -- (category Income / Cost of Goods Sold / Expense) should be read as netChange over a chosen
    -- fiscal year instead, which is now an exact filter rather than an approximation.
    -- Partitioned by the DIMENSION grain as well as the account: without that the running total
    -- would sum across every department and read the same on each of their rows.
    SUM(p.netChange) OVER (
        PARTITION BY p.[bcCompanyId], p.[accountNumber],
                     p.[dimension1ValueCode], p.[dimension2ValueCode], p.[dimension3ValueCode],
                     p.[dimension4ValueCode], p.[dimension5ValueCode], p.[dimension6ValueCode],
                     p.[dimension7ValueCode], p.[dimension8ValueCode]
        ORDER BY p.periodStart
        ROWS UNBOUNDED PRECEDING
    ) AS balanceToDate,
    p.entryCount
FROM periods p
LEFT JOIN [bc].[glAccounts] a
       ON a.[number] = p.[accountNumber]
      AND a.[bcCompanyId] = p.[bcCompanyId]
      AND a.[_rowState] = 'Active';
GO

-- The drill-down behind the trial balance: every G/L entry with its account
-- name and category, and the two global dimensions BC carries inline.
DROP VIEW IF EXISTS [bcModel].[vw_generalLedgerDetail];
GO
CREATE VIEW [bcModel].[vw_generalLedgerDetail] AS
SELECT
    g.[id],
    g.[entryNumber],
    g.[postingDate],
    DATEFROMPARTS(YEAR(g.[postingDate]), MONTH(g.[postingDate]), 1) AS periodStart,
    g.[documentType],
    g.[documentNumber],
    g.[externalDocumentNumber],
    g.[transactionNumber],
    g.[accountNumber],
    a.[displayName] AS accountName,
    a.[category]    AS accountCategory,
    a.[subCategory] AS accountSubCategory,
    g.[description],
    g.[debitAmount],
    g.[creditAmount],
    g.[amount],
    -- Source Type / Source No. is how BC says "this line came from customer
    -- C0010" or "vendor V0020" -- it is derived by BC at posting, so it is the
    -- reliable way back to the party from a G/L entry.
    g.[sourceType],
    g.[sourceNumber],
    g.[sourceCode],
    g.[dimensionSetId],
    dp.[dimension1Code],
    dp.[dimension1Name],
    dp.[dimension1ValueCode],
    dp.[dimension1ValueName],
    dp.[dimension2Code],
    dp.[dimension2Name],
    dp.[dimension2ValueCode],
    dp.[dimension2ValueName],
    dp.[dimension3Code],
    dp.[dimension3Name],
    dp.[dimension3ValueCode],
    dp.[dimension3ValueName],
    dp.[dimension4Code],
    dp.[dimension4Name],
    dp.[dimension4ValueCode],
    dp.[dimension4ValueName],
    dp.[dimension5Code],
    dp.[dimension5Name],
    dp.[dimension5ValueCode],
    dp.[dimension5ValueName],
    dp.[dimension6Code],
    dp.[dimension6Name],
    dp.[dimension6ValueCode],
    dp.[dimension6ValueName],
    dp.[dimension7Code],
    dp.[dimension7Name],
    dp.[dimension7ValueCode],
    dp.[dimension7ValueName],
    dp.[dimension8Code],
    dp.[dimension8Name],
    dp.[dimension8ValueCode],
    dp.[dimension8ValueName],
    g.[integrationId],
    g.[bcCompanyId],
    g.[bcCompanyName]
FROM [bc].[generalLedgerEntries] g
LEFT JOIN [bc].[glAccounts] a
       ON a.[number] = g.[accountNumber]
      AND a.[bcCompanyId] = g.[bcCompanyId]
      AND a.[_rowState] = 'Active'
-- One row per dimension set, so this cannot multiply entries. LEFT because an entry posted with no
-- dimensions has a dimensionSetId of 0 and no rows in the bridge.
LEFT JOIN [bcModel].[vw_dimensionSetPivot] dp
       ON dp.[dimensionSetId] = g.[dimensionSetId]
      AND dp.[bcCompanyId]    = g.[bcCompanyId]
WHERE g.[_rowState] = 'Active';
GO



-- =====================================================================
-- Receivables and payables
-- =====================================================================

-- Aged receivables, from Business Central's own subledger.
--
-- The source is bc.custLedgerEntries, NOT the postedCustomer* feeds. Those project onto
-- EONE Posted Ledger Doc, which Business Central purges by posting date after
-- 7/14/28 days whether or not the document is still open -- so an invoice on
-- normal terms left them while unpaid and then aged forever. The subledger is
-- never purged, and `remainingAmount` and `open` are maintained by Business
-- Central itself as payments are applied.
--
-- The LCY twins are published beside every amount, so a multi-currency total
-- needs no exchange rate at all. That is the usual reason a warehouse aging
-- disagrees with Business Central.
--
-- `receivablesAccount` comes along so a total by posting group can be tied
-- straight back to its control account in vw_trialBalance.
--
-- Buckets are by DUE date (standard aged receivables). Dimensions are expanded,
-- as on every view whose underlying data carries a dimensionSetId.
DROP VIEW IF EXISTS [bcModel].[vw_arAging];
GO
CREATE VIEW [bcModel].[vw_arAging] AS
SELECT
    e.[id],
    e.[entryNumber],
    e.[documentType],
    e.[documentNumber],
    e.[externalDocumentNumber],
    e.[customerNumber],
    COALESCE(e.[customerName], m.[displayName]) AS customerName,
    m.[salespersonCode],
    m.[paymentTermsCode],
    m.[creditLimit],
    e.[customerPostingGroup],
    pg.[receivablesAccount],
    e.[currencyCode],
    e.[postingDate],
    e.[documentDate],
    e.[dueDate],
    e.[originalAmount],
    e.[amount],
    e.[amountLcy],
    e.[remainingAmount],
    e.[remainingAmountLcy],
    e.[onHold],
    DATEDIFF(day, e.[dueDate], CAST(SYSUTCDATETIME() AS date)) AS daysPastDue,
    CASE
        WHEN e.[dueDate] IS NULL                                              THEN 'No due date'
        WHEN DATEDIFF(day, e.[dueDate], CAST(SYSUTCDATETIME() AS date)) <=  0 THEN 'Current'
        WHEN DATEDIFF(day, e.[dueDate], CAST(SYSUTCDATETIME() AS date)) <= 30 THEN '1-30'
        WHEN DATEDIFF(day, e.[dueDate], CAST(SYSUTCDATETIME() AS date)) <= 60 THEN '31-60'
        WHEN DATEDIFF(day, e.[dueDate], CAST(SYSUTCDATETIME() AS date)) <= 90 THEN '61-90'
        ELSE '90+'
    END AS ageBucket,
    e.[dimensionSetId],
    dp.[dimension1Code],
    dp.[dimension1Name],
    dp.[dimension1ValueCode],
    dp.[dimension1ValueName],
    dp.[dimension2Code],
    dp.[dimension2Name],
    dp.[dimension2ValueCode],
    dp.[dimension2ValueName],
    dp.[dimension3Code],
    dp.[dimension3Name],
    dp.[dimension3ValueCode],
    dp.[dimension3ValueName],
    dp.[dimension4Code],
    dp.[dimension4Name],
    dp.[dimension4ValueCode],
    dp.[dimension4ValueName],
    dp.[dimension5Code],
    dp.[dimension5Name],
    dp.[dimension5ValueCode],
    dp.[dimension5ValueName],
    dp.[dimension6Code],
    dp.[dimension6Name],
    dp.[dimension6ValueCode],
    dp.[dimension6ValueName],
    dp.[dimension7Code],
    dp.[dimension7Name],
    dp.[dimension7ValueCode],
    dp.[dimension7ValueName],
    dp.[dimension8Code],
    dp.[dimension8Name],
    dp.[dimension8ValueCode],
    dp.[dimension8ValueName],
    e.[bcCompanyId],
    e.[bcCompanyName]
FROM [bc].[custLedgerEntries] e
LEFT JOIN [bc].[customers] m
       ON m.[number] = e.[customerNumber]
      AND m.[bcCompanyId] = e.[bcCompanyId]
      AND m.[_rowState] = 'Active'
LEFT JOIN [bc].[customerPostingGroups] pg
       ON pg.[code] = e.[customerPostingGroup]
      AND pg.[bcCompanyId] = e.[bcCompanyId]
      AND pg.[_rowState] = 'Active'
LEFT JOIN [bcModel].[vw_dimensionSetPivot] dp
       ON dp.[dimensionSetId] = e.[dimensionSetId]
      AND dp.[bcCompanyId]    = e.[bcCompanyId]
WHERE e.[_rowState] = 'Active'
  AND e.[open] = 1
  AND COALESCE(e.[remainingAmount], 0) <> 0;
GO

-- Aged payables, from Business Central's own subledger.
--
-- The source is bc.vendorLedgerEntries, NOT the postedVendor* feeds. Those project onto
-- EONE Posted Ledger Doc, which Business Central purges by posting date after
-- 7/14/28 days whether or not the document is still open -- so an invoice on
-- normal terms left them while unpaid and then aged forever. The subledger is
-- never purged, and `remainingAmount` and `open` are maintained by Business
-- Central itself as payments are applied.
--
-- The LCY twins are published beside every amount, so a multi-currency total
-- needs no exchange rate at all. That is the usual reason a warehouse aging
-- disagrees with Business Central.
--
-- `payablesAccount` comes along so a total by posting group can be tied
-- straight back to its control account in vw_trialBalance.
--
-- Buckets are by DUE date (standard aged payables). Dimensions are expanded,
-- as on every view whose underlying data carries a dimensionSetId.
DROP VIEW IF EXISTS [bcModel].[vw_apAging];
GO
CREATE VIEW [bcModel].[vw_apAging] AS
SELECT
    e.[id],
    e.[entryNumber],
    e.[documentType],
    e.[documentNumber],
    e.[externalDocumentNumber],
    e.[vendorNumber],
    COALESCE(e.[vendorName], m.[displayName]) AS vendorName,
    m.[purchaserCode],
    m.[paymentTermsCode],
    e.[vendorPostingGroup],
    pg.[payablesAccount],
    e.[currencyCode],
    e.[postingDate],
    e.[documentDate],
    e.[dueDate],
    e.[originalAmount],
    e.[amount],
    e.[amountLcy],
    e.[remainingAmount],
    e.[remainingAmountLcy],
    e.[onHold],
    DATEDIFF(day, e.[dueDate], CAST(SYSUTCDATETIME() AS date)) AS daysPastDue,
    CASE
        WHEN e.[dueDate] IS NULL                                              THEN 'No due date'
        WHEN DATEDIFF(day, e.[dueDate], CAST(SYSUTCDATETIME() AS date)) <=  0 THEN 'Current'
        WHEN DATEDIFF(day, e.[dueDate], CAST(SYSUTCDATETIME() AS date)) <= 30 THEN '1-30'
        WHEN DATEDIFF(day, e.[dueDate], CAST(SYSUTCDATETIME() AS date)) <= 60 THEN '31-60'
        WHEN DATEDIFF(day, e.[dueDate], CAST(SYSUTCDATETIME() AS date)) <= 90 THEN '61-90'
        ELSE '90+'
    END AS ageBucket,
    e.[dimensionSetId],
    dp.[dimension1Code],
    dp.[dimension1Name],
    dp.[dimension1ValueCode],
    dp.[dimension1ValueName],
    dp.[dimension2Code],
    dp.[dimension2Name],
    dp.[dimension2ValueCode],
    dp.[dimension2ValueName],
    dp.[dimension3Code],
    dp.[dimension3Name],
    dp.[dimension3ValueCode],
    dp.[dimension3ValueName],
    dp.[dimension4Code],
    dp.[dimension4Name],
    dp.[dimension4ValueCode],
    dp.[dimension4ValueName],
    dp.[dimension5Code],
    dp.[dimension5Name],
    dp.[dimension5ValueCode],
    dp.[dimension5ValueName],
    dp.[dimension6Code],
    dp.[dimension6Name],
    dp.[dimension6ValueCode],
    dp.[dimension6ValueName],
    dp.[dimension7Code],
    dp.[dimension7Name],
    dp.[dimension7ValueCode],
    dp.[dimension7ValueName],
    dp.[dimension8Code],
    dp.[dimension8Name],
    dp.[dimension8ValueCode],
    dp.[dimension8ValueName],
    e.[bcCompanyId],
    e.[bcCompanyName]
FROM [bc].[vendorLedgerEntries] e
LEFT JOIN [bc].[vendors] m
       ON m.[number] = e.[vendorNumber]
      AND m.[bcCompanyId] = e.[bcCompanyId]
      AND m.[_rowState] = 'Active'
LEFT JOIN [bc].[vendorPostingGroups] pg
       ON pg.[code] = e.[vendorPostingGroup]
      AND pg.[bcCompanyId] = e.[bcCompanyId]
      AND pg.[_rowState] = 'Active'
LEFT JOIN [bcModel].[vw_dimensionSetPivot] dp
       ON dp.[dimensionSetId] = e.[dimensionSetId]
      AND dp.[bcCompanyId]    = e.[bcCompanyId]
WHERE e.[_rowState] = 'Active'
  AND e.[open] = 1
  AND COALESCE(e.[remainingAmount], 0) <> 0;
GO

-- Customer statement: every subledger entry in posting-date order, with a
-- running balance. Open and closed entries both, because a statement that
-- hides settled documents cannot be reconciled against.
--
-- Two running balances, because they answer different questions: the
-- transaction-currency one only means something within a single currency, and
-- the LCY one is the figure that ties to the general ledger.
--
-- Ordered by entryNumber within a posting date rather than by document
-- number. Entry number is Business Central's own write order; document number
-- is a string, so same-day rows sorted by it put payments before the invoices
-- they settle whenever the prefixes happen to fall that way.
DROP VIEW IF EXISTS [bcModel].[vw_customerStatement];
GO
CREATE VIEW [bcModel].[vw_customerStatement] AS
SELECT
    e.[customerNumber],
    COALESCE(e.[customerName], m.[displayName]) AS customerName,
    e.[entryNumber],
    e.[documentType],
    e.[documentNumber],
    e.[externalDocumentNumber],
    e.[postingDate],
    e.[documentDate],
    e.[dueDate],
    e.[currencyCode],
    e.[amount],
    e.[amountLcy],
    e.[remainingAmount],
    e.[remainingAmountLcy],
    e.[closedAtDate],
    CASE WHEN e.[open] = 1 THEN 'Open' ELSE 'Closed' END AS openClosed,
    SUM(e.[amount]) OVER (
        PARTITION BY e.[bcCompanyId], e.[customerNumber], e.[currencyCode]
        ORDER BY e.[postingDate], e.[entryNumber]
        ROWS UNBOUNDED PRECEDING
    ) AS runningBalance,
    SUM(e.[amountLcy]) OVER (
        PARTITION BY e.[bcCompanyId], e.[customerNumber]
        ORDER BY e.[postingDate], e.[entryNumber]
        ROWS UNBOUNDED PRECEDING
    ) AS runningBalanceLcy,
    e.[dimensionSetId],
    dp.[dimension1Code],
    dp.[dimension1Name],
    dp.[dimension1ValueCode],
    dp.[dimension1ValueName],
    dp.[dimension2Code],
    dp.[dimension2Name],
    dp.[dimension2ValueCode],
    dp.[dimension2ValueName],
    dp.[dimension3Code],
    dp.[dimension3Name],
    dp.[dimension3ValueCode],
    dp.[dimension3ValueName],
    dp.[dimension4Code],
    dp.[dimension4Name],
    dp.[dimension4ValueCode],
    dp.[dimension4ValueName],
    dp.[dimension5Code],
    dp.[dimension5Name],
    dp.[dimension5ValueCode],
    dp.[dimension5ValueName],
    dp.[dimension6Code],
    dp.[dimension6Name],
    dp.[dimension6ValueCode],
    dp.[dimension6ValueName],
    dp.[dimension7Code],
    dp.[dimension7Name],
    dp.[dimension7ValueCode],
    dp.[dimension7ValueName],
    dp.[dimension8Code],
    dp.[dimension8Name],
    dp.[dimension8ValueCode],
    dp.[dimension8ValueName],
    e.[bcCompanyId],
    e.[bcCompanyName]
FROM [bc].[custLedgerEntries] e
LEFT JOIN [bc].[customers] m
       ON m.[number] = e.[customerNumber]
      AND m.[bcCompanyId] = e.[bcCompanyId]
      AND m.[_rowState] = 'Active'
LEFT JOIN [bcModel].[vw_dimensionSetPivot] dp
       ON dp.[dimensionSetId] = e.[dimensionSetId]
      AND dp.[bcCompanyId]    = e.[bcCompanyId]
WHERE e.[_rowState] = 'Active';
GO

-- Vendor statement: every subledger entry in posting-date order, with a
-- running balance. Open and closed entries both, because a statement that
-- hides settled documents cannot be reconciled against.
--
-- Two running balances, because they answer different questions: the
-- transaction-currency one only means something within a single currency, and
-- the LCY one is the figure that ties to the general ledger.
--
-- Ordered by entryNumber within a posting date rather than by document
-- number. Entry number is Business Central's own write order; document number
-- is a string, so same-day rows sorted by it put payments before the invoices
-- they settle whenever the prefixes happen to fall that way.
DROP VIEW IF EXISTS [bcModel].[vw_vendorStatement];
GO
CREATE VIEW [bcModel].[vw_vendorStatement] AS
SELECT
    e.[vendorNumber],
    COALESCE(e.[vendorName], m.[displayName]) AS vendorName,
    e.[entryNumber],
    e.[documentType],
    e.[documentNumber],
    e.[externalDocumentNumber],
    e.[postingDate],
    e.[documentDate],
    e.[dueDate],
    e.[currencyCode],
    e.[amount],
    e.[amountLcy],
    e.[remainingAmount],
    e.[remainingAmountLcy],
    e.[closedAtDate],
    CASE WHEN e.[open] = 1 THEN 'Open' ELSE 'Closed' END AS openClosed,
    SUM(e.[amount]) OVER (
        PARTITION BY e.[bcCompanyId], e.[vendorNumber], e.[currencyCode]
        ORDER BY e.[postingDate], e.[entryNumber]
        ROWS UNBOUNDED PRECEDING
    ) AS runningBalance,
    SUM(e.[amountLcy]) OVER (
        PARTITION BY e.[bcCompanyId], e.[vendorNumber]
        ORDER BY e.[postingDate], e.[entryNumber]
        ROWS UNBOUNDED PRECEDING
    ) AS runningBalanceLcy,
    e.[dimensionSetId],
    dp.[dimension1Code],
    dp.[dimension1Name],
    dp.[dimension1ValueCode],
    dp.[dimension1ValueName],
    dp.[dimension2Code],
    dp.[dimension2Name],
    dp.[dimension2ValueCode],
    dp.[dimension2ValueName],
    dp.[dimension3Code],
    dp.[dimension3Name],
    dp.[dimension3ValueCode],
    dp.[dimension3ValueName],
    dp.[dimension4Code],
    dp.[dimension4Name],
    dp.[dimension4ValueCode],
    dp.[dimension4ValueName],
    dp.[dimension5Code],
    dp.[dimension5Name],
    dp.[dimension5ValueCode],
    dp.[dimension5ValueName],
    dp.[dimension6Code],
    dp.[dimension6Name],
    dp.[dimension6ValueCode],
    dp.[dimension6ValueName],
    dp.[dimension7Code],
    dp.[dimension7Name],
    dp.[dimension7ValueCode],
    dp.[dimension7ValueName],
    dp.[dimension8Code],
    dp.[dimension8Name],
    dp.[dimension8ValueCode],
    dp.[dimension8ValueName],
    e.[bcCompanyId],
    e.[bcCompanyName]
FROM [bc].[vendorLedgerEntries] e
LEFT JOIN [bc].[vendors] m
       ON m.[number] = e.[vendorNumber]
      AND m.[bcCompanyId] = e.[bcCompanyId]
      AND m.[_rowState] = 'Active'
LEFT JOIN [bcModel].[vw_dimensionSetPivot] dp
       ON dp.[dimensionSetId] = e.[dimensionSetId]
      AND dp.[bcCompanyId]    = e.[bcCompanyId]
WHERE e.[_rowState] = 'Active';
GO

-- Cash application detail: which payment settled which invoice, when, and for
-- how much.
--
-- This is the one question the parent subledger cannot answer. It collapses a
-- settlement into a single remaining amount, so a payment spread across five
-- invoices, or an invoice settled by three payments, is invisible there.
--
-- `unapplied = 0` is not optional. Unapplying in Business Central does not
-- edit the original row, it writes a reversing one -- so counting both sides
-- of a reversed settlement is the default behaviour unless this filter is
-- present.
--
-- daysToPay is the real figure: the gap between the invoice posting date and
-- the date the application actually happened. An average collection period
-- built on invoice dates alone never sees a partial settlement.
DROP VIEW IF EXISTS [bcModel].[vw_cashApplications];
GO
CREATE VIEW [bcModel].[vw_cashApplications] AS
SELECT
    CAST('Customer' AS varchar(10)) AS side,
    d.[id],
    d.[entryNumber],
    d.[custLedgerEntryNumber]        AS ledgerEntryNumber,
    d.[appliedCustLedgerEntryNumber] AS appliedLedgerEntryNumber,
    d.[applicationNumber],
    d.[entryType],
    d.[customerNumber]               AS partyNumber,
    d.[documentType],
    d.[documentNumber],
    d.[postingDate]                  AS appliedOn,
    e.[postingDate]                  AS entryPostingDate,
    e.[dueDate]                      AS entryDueDate,
    e.[documentType]                 AS entryDocumentType,
    e.[documentNumber]               AS entryDocumentNumber,
    DATEDIFF(day, e.[postingDate], d.[postingDate]) AS daysToPay,
    DATEDIFF(day, e.[dueDate],     d.[postingDate]) AS daysLate,
    d.[currencyCode],
    d.[amount],
    d.[amountLcy],
    d.[bcCompanyId],
    d.[bcCompanyName]
FROM [bc].[detailedCustLedgerEntries] d
LEFT JOIN [bc].[custLedgerEntries] e
       ON e.[entryNumber]  = d.[custLedgerEntryNumber]
      AND e.[bcCompanyId]  = d.[bcCompanyId]
      AND e.[_rowState]    = 'Active'
WHERE d.[_rowState] = 'Active'
  AND d.[unapplied] = 0
  AND d.[appliedCustLedgerEntryNumber] <> 0

UNION ALL

SELECT
    CAST('Vendor' AS varchar(10)) AS side,
    d.[id],
    d.[entryNumber],
    d.[vendorLedgerEntryNumber]      AS ledgerEntryNumber,
    d.[appliedVendLedgerEntryNumber] AS appliedLedgerEntryNumber,
    d.[applicationNumber],
    d.[entryType],
    d.[vendorNumber]                 AS partyNumber,
    d.[documentType],
    d.[documentNumber],
    d.[postingDate]                  AS appliedOn,
    e.[postingDate]                  AS entryPostingDate,
    e.[dueDate]                      AS entryDueDate,
    e.[documentType]                 AS entryDocumentType,
    e.[documentNumber]               AS entryDocumentNumber,
    DATEDIFF(day, e.[postingDate], d.[postingDate]) AS daysToPay,
    DATEDIFF(day, e.[dueDate],     d.[postingDate]) AS daysLate,
    d.[currencyCode],
    d.[amount],
    d.[amountLcy],
    d.[bcCompanyId],
    d.[bcCompanyName]
FROM [bc].[detailedVendorLedgerEntries] d
LEFT JOIN [bc].[vendorLedgerEntries] e
       ON e.[entryNumber]  = d.[vendorLedgerEntryNumber]
      AND e.[bcCompanyId]  = d.[bcCompanyId]
      AND e.[_rowState]    = 'Active'
WHERE d.[_rowState] = 'Active'
  AND d.[unapplied] = 0
  AND d.[appliedVendLedgerEntryNumber] <> 0;
GO


-- =====================================================================
-- Sales
-- =====================================================================

-- The sales fact: one row per posted sales invoice or credit memo LINE, with
-- its header's customer and dates, and credit memos negated so the view sums
-- to net revenue without anyone having to remember the sign.
--
-- This is the grain everything else in this section is built on. Keep the
-- `type` column: lines can be G/L Account, Resource or Fixed Asset as well as
-- Item, and an item-level report must filter, while a revenue total must not.
DROP VIEW IF EXISTS [bcModel].[vw_salesAnalysis];
GO
CREATE VIEW [bcModel].[vw_salesAnalysis] AS
SELECT
    CAST('Invoice' AS varchar(15)) AS docClass,
    h.[number]                AS documentNumber,
    h.[postingDate],
    DATEFROMPARTS(YEAR(h.[postingDate]), MONTH(h.[postingDate]), 1) AS periodStart,
    h.[documentDate],
    h.[orderNumber],
    h.[sellToCustomerNumber]  AS customerNumber,
    h.[sellToCustomerName]    AS customerName,
    h.[billToCustomerNumber],
    h.[salespersonCode],
    h.[currencyCode],
    l.[dimensionSetId],
    dp.[dimension1Code],
    dp.[dimension1Name],
    dp.[dimension1ValueCode],
    dp.[dimension1ValueName],
    dp.[dimension2Code],
    dp.[dimension2Name],
    dp.[dimension2ValueCode],
    dp.[dimension2ValueName],
    dp.[dimension3Code],
    dp.[dimension3Name],
    dp.[dimension3ValueCode],
    dp.[dimension3ValueName],
    dp.[dimension4Code],
    dp.[dimension4Name],
    dp.[dimension4ValueCode],
    dp.[dimension4ValueName],
    dp.[dimension5Code],
    dp.[dimension5Name],
    dp.[dimension5ValueCode],
    dp.[dimension5ValueName],
    dp.[dimension6Code],
    dp.[dimension6Name],
    dp.[dimension6ValueCode],
    dp.[dimension6ValueName],
    dp.[dimension7Code],
    dp.[dimension7Name],
    dp.[dimension7ValueCode],
    dp.[dimension7ValueName],
    dp.[dimension8Code],
    dp.[dimension8Name],
    dp.[dimension8ValueCode],
    dp.[dimension8ValueName],
    l.[lineNumber],
    l.[type]                  AS lineType,
    l.[itemNumber],
    l.[description],
    l.[variantCode],
    l.[locationCode],
    l.[unitOfMeasureCode],
    l.[quantity],
    l.[unitPrice],
    l.[lineDiscountAmount],
    l.[lineAmount],
    l.[amountIncludingTax],
    h.[bcCompanyId],
    h.[bcCompanyName]
FROM [bc].[postedSalesInvoiceLines] l
JOIN [bc].[postedSalesInvoices] h
  ON h.[number] = l.[documentNumber]
 AND h.[bcCompanyId] = l.[bcCompanyId]
LEFT JOIN [bcModel].[vw_dimensionSetPivot] dp
       ON dp.[dimensionSetId] = l.[dimensionSetId]
      AND dp.[bcCompanyId]    = l.[bcCompanyId]
WHERE l.[_rowState] = 'Active' AND h.[_rowState] = 'Active'

UNION ALL

SELECT
    CAST('Credit Memo' AS varchar(15)) AS docClass,
    h.[number],
    h.[postingDate],
    DATEFROMPARTS(YEAR(h.[postingDate]), MONTH(h.[postingDate]), 1),
    h.[documentDate],
    h.[returnOrderNumber],
    h.[sellToCustomerNumber],
    h.[sellToCustomerName],
    h.[billToCustomerNumber],
    h.[salespersonCode],
    h.[currencyCode],
    l.[dimensionSetId],
    dp.[dimension1Code],
    dp.[dimension1Name],
    dp.[dimension1ValueCode],
    dp.[dimension1ValueName],
    dp.[dimension2Code],
    dp.[dimension2Name],
    dp.[dimension2ValueCode],
    dp.[dimension2ValueName],
    dp.[dimension3Code],
    dp.[dimension3Name],
    dp.[dimension3ValueCode],
    dp.[dimension3ValueName],
    dp.[dimension4Code],
    dp.[dimension4Name],
    dp.[dimension4ValueCode],
    dp.[dimension4ValueName],
    dp.[dimension5Code],
    dp.[dimension5Name],
    dp.[dimension5ValueCode],
    dp.[dimension5ValueName],
    dp.[dimension6Code],
    dp.[dimension6Name],
    dp.[dimension6ValueCode],
    dp.[dimension6ValueName],
    dp.[dimension7Code],
    dp.[dimension7Name],
    dp.[dimension7ValueCode],
    dp.[dimension7ValueName],
    dp.[dimension8Code],
    dp.[dimension8Name],
    dp.[dimension8ValueCode],
    dp.[dimension8ValueName],
    l.[lineNumber],
    l.[type],
    l.[itemNumber],
    l.[description],
    l.[variantCode],
    l.[locationCode],
    l.[unitOfMeasureCode],
    -- Negated: a credit memo reduces revenue and returns stock, and BC stores
    -- both as positive numbers on the credit memo itself.
    -l.[quantity],
    l.[unitPrice],
    -l.[lineDiscountAmount],
    -l.[lineAmount],
    -l.[amountIncludingTax],
    h.[bcCompanyId],
    h.[bcCompanyName]
FROM [bc].[postedSalesCreditMemoLines] l
JOIN [bc].[postedSalesCreditMemos] h
  ON h.[number] = l.[documentNumber]
 AND h.[bcCompanyId] = l.[bcCompanyId]
LEFT JOIN [bcModel].[vw_dimensionSetPivot] dp
       ON dp.[dimensionSetId] = l.[dimensionSetId]
      AND dp.[bcCompanyId]    = l.[bcCompanyId]
WHERE l.[_rowState] = 'Active' AND h.[_rowState] = 'Active';
GO

DROP VIEW IF EXISTS [bcModel].[vw_salesByCustomer];
GO
CREATE VIEW [bcModel].[vw_salesByCustomer] AS
SELECT
    s.[bcCompanyId],
    s.[bcCompanyName],
    s.[customerNumber],
    MAX(s.[customerName])  AS customerName,
    MAX(c.[salespersonCode]) AS salespersonCode,
    MAX(c.[countryRegionCode]) AS countryRegionCode,
    s.periodStart,
    s.[currencyCode],
    SUM(s.[lineAmount])         AS netRevenue,
    SUM(s.[amountIncludingTax]) AS revenueIncludingTax,
    SUM(s.[lineDiscountAmount]) AS discountGiven,
    COUNT(DISTINCT s.[documentNumber]) AS documentCount
FROM [bcModel].[vw_salesAnalysis] s
LEFT JOIN [bc].[customers] c
       ON c.[number] = s.[customerNumber]
      AND c.[bcCompanyId] = s.[bcCompanyId]
      AND c.[_rowState] = 'Active'
GROUP BY s.[bcCompanyId], s.[bcCompanyName], s.[customerNumber], s.periodStart, s.[currencyCode];
GO

DROP VIEW IF EXISTS [bcModel].[vw_salesByItem];
GO
CREATE VIEW [bcModel].[vw_salesByItem] AS
SELECT
    s.[bcCompanyId],
    s.[bcCompanyName],
    s.[itemNumber],
    MAX(i.[displayName])      AS itemName,
    MAX(i.[itemCategoryCode]) AS itemCategoryCode,
    MAX(i.[unitCost])         AS currentUnitCost,
    s.periodStart,
    s.[locationCode],
    s.[currencyCode],
    SUM(s.[quantity])   AS quantitySold,
    SUM(s.[lineAmount]) AS netRevenue,
    -- Margin at the item's CURRENT unit cost, not the cost actually posted:
    -- BC's posted cost lives in Value Entries, which the API does not expose.
    -- Directionally right, not audit-grade.
    SUM(s.[lineAmount]) - SUM(s.[quantity] * COALESCE(i.[unitCost], 0)) AS indicativeMargin,
    COUNT(DISTINCT s.[documentNumber]) AS documentCount
FROM [bcModel].[vw_salesAnalysis] s
LEFT JOIN [bc].[items] i
       ON i.[number] = s.[itemNumber]
      AND i.[bcCompanyId] = s.[bcCompanyId]
      AND i.[_rowState] = 'Active'
WHERE s.[lineType] = 'Item'
GROUP BY s.[bcCompanyId], s.[bcCompanyName], s.[itemNumber], s.periodStart, s.[locationCode], s.[currencyCode];
GO

DROP VIEW IF EXISTS [bcModel].[vw_salesByPeriod];
GO
CREATE VIEW [bcModel].[vw_salesByPeriod] AS
SELECT
    s.[bcCompanyId],
    s.[bcCompanyName],
    s.periodStart,
    YEAR(s.periodStart)  AS fiscalYear,
    MONTH(s.periodStart) AS fiscalMonth,
    s.[currencyCode],
    s.[salespersonCode],
    s.[locationCode],
    SUM(s.[lineAmount])         AS netRevenue,
    SUM(s.[amountIncludingTax]) AS revenueIncludingTax,
    SUM(s.[lineDiscountAmount]) AS discountGiven,
    COUNT(DISTINCT s.[documentNumber]) AS documentCount,
    COUNT(DISTINCT s.[customerNumber]) AS customerCount
FROM [bcModel].[vw_salesAnalysis] s
GROUP BY s.[bcCompanyId], s.[bcCompanyName], s.periodStart, s.[currencyCode],
         s.[salespersonCode], s.[locationCode];
GO


-- =====================================================================
-- Purchasing
-- =====================================================================

DROP VIEW IF EXISTS [bcModel].[vw_purchaseAnalysis];
GO
CREATE VIEW [bcModel].[vw_purchaseAnalysis] AS
SELECT
    CAST('Invoice' AS varchar(15)) AS docClass,
    h.[number]              AS documentNumber,
    h.[postingDate],
    DATEFROMPARTS(YEAR(h.[postingDate]), MONTH(h.[postingDate]), 1) AS periodStart,
    h.[documentDate],
    h.[orderNumber],
    h.[buyFromVendorNumber] AS vendorNumber,
    h.[buyFromVendorName]   AS vendorName,
    h.[currencyCode],
    l.[dimensionSetId],
    dp.[dimension1Code],
    dp.[dimension1Name],
    dp.[dimension1ValueCode],
    dp.[dimension1ValueName],
    dp.[dimension2Code],
    dp.[dimension2Name],
    dp.[dimension2ValueCode],
    dp.[dimension2ValueName],
    dp.[dimension3Code],
    dp.[dimension3Name],
    dp.[dimension3ValueCode],
    dp.[dimension3ValueName],
    dp.[dimension4Code],
    dp.[dimension4Name],
    dp.[dimension4ValueCode],
    dp.[dimension4ValueName],
    dp.[dimension5Code],
    dp.[dimension5Name],
    dp.[dimension5ValueCode],
    dp.[dimension5ValueName],
    dp.[dimension6Code],
    dp.[dimension6Name],
    dp.[dimension6ValueCode],
    dp.[dimension6ValueName],
    dp.[dimension7Code],
    dp.[dimension7Name],
    dp.[dimension7ValueCode],
    dp.[dimension7ValueName],
    dp.[dimension8Code],
    dp.[dimension8Name],
    dp.[dimension8ValueCode],
    dp.[dimension8ValueName],
    l.[lineNumber],
    l.[type]                AS lineType,
    l.[itemNumber],
    l.[description],
    l.[variantCode],
    l.[locationCode],
    l.[unitOfMeasureCode],
    l.[quantity],
    l.[directUnitCost],
    l.[lineDiscountPercent],
    l.[lineAmount],
    l.[amountIncludingTax],
    h.[bcCompanyId],
    h.[bcCompanyName]
FROM [bc].[postedPurchaseInvoiceLines] l
JOIN [bc].[postedPurchaseInvoices] h
  ON h.[number] = l.[documentNumber]
 AND h.[bcCompanyId] = l.[bcCompanyId]
LEFT JOIN [bcModel].[vw_dimensionSetPivot] dp
       ON dp.[dimensionSetId] = l.[dimensionSetId]
      AND dp.[bcCompanyId]    = l.[bcCompanyId]
WHERE l.[_rowState] = 'Active' AND h.[_rowState] = 'Active'

UNION ALL

SELECT
    CAST('Credit Memo' AS varchar(15)),
    h.[number],
    h.[postingDate],
    DATEFROMPARTS(YEAR(h.[postingDate]), MONTH(h.[postingDate]), 1),
    h.[documentDate],
    h.[returnOrderNumber],
    h.[buyFromVendorNumber],
    h.[buyFromVendorName],
    h.[currencyCode],
    l.[dimensionSetId],
    dp.[dimension1Code],
    dp.[dimension1Name],
    dp.[dimension1ValueCode],
    dp.[dimension1ValueName],
    dp.[dimension2Code],
    dp.[dimension2Name],
    dp.[dimension2ValueCode],
    dp.[dimension2ValueName],
    dp.[dimension3Code],
    dp.[dimension3Name],
    dp.[dimension3ValueCode],
    dp.[dimension3ValueName],
    dp.[dimension4Code],
    dp.[dimension4Name],
    dp.[dimension4ValueCode],
    dp.[dimension4ValueName],
    dp.[dimension5Code],
    dp.[dimension5Name],
    dp.[dimension5ValueCode],
    dp.[dimension5ValueName],
    dp.[dimension6Code],
    dp.[dimension6Name],
    dp.[dimension6ValueCode],
    dp.[dimension6ValueName],
    dp.[dimension7Code],
    dp.[dimension7Name],
    dp.[dimension7ValueCode],
    dp.[dimension7ValueName],
    dp.[dimension8Code],
    dp.[dimension8Name],
    dp.[dimension8ValueCode],
    dp.[dimension8ValueName],
    l.[lineNumber],
    l.[type],
    l.[itemNumber],
    l.[description],
    l.[variantCode],
    l.[locationCode],
    l.[unitOfMeasureCode],
    -l.[quantity],
    l.[directUnitCost],
    l.[lineDiscountPercent],
    -l.[lineAmount],
    -l.[amountIncludingTax],
    h.[bcCompanyId],
    h.[bcCompanyName]
FROM [bc].[postedPurchaseCreditMemoLines] l
JOIN [bc].[postedPurchaseCreditMemos] h
  ON h.[number] = l.[documentNumber]
 AND h.[bcCompanyId] = l.[bcCompanyId]
LEFT JOIN [bcModel].[vw_dimensionSetPivot] dp
       ON dp.[dimensionSetId] = l.[dimensionSetId]
      AND dp.[bcCompanyId]    = l.[bcCompanyId]
WHERE l.[_rowState] = 'Active' AND h.[_rowState] = 'Active';
GO

DROP VIEW IF EXISTS [bcModel].[vw_purchasesByVendor];
GO
CREATE VIEW [bcModel].[vw_purchasesByVendor] AS
SELECT
    p.[bcCompanyId],
    p.[bcCompanyName],
    p.[vendorNumber],
    MAX(p.[vendorName])     AS vendorName,
    MAX(v.[purchaserCode])  AS purchaserCode,
    MAX(v.[paymentTermsCode]) AS paymentTermsCode,
    p.periodStart,
    p.[currencyCode],
    SUM(p.[lineAmount])         AS netSpend,
    SUM(p.[amountIncludingTax]) AS spendIncludingTax,
    COUNT(DISTINCT p.[documentNumber]) AS documentCount
FROM [bcModel].[vw_purchaseAnalysis] p
LEFT JOIN [bc].[vendors] v
       ON v.[number] = p.[vendorNumber]
      AND v.[bcCompanyId] = p.[bcCompanyId]
      AND v.[_rowState] = 'Active'
GROUP BY p.[bcCompanyId], p.[bcCompanyName], p.[vendorNumber], p.periodStart, p.[currencyCode];
GO

DROP VIEW IF EXISTS [bcModel].[vw_purchasesByItem];
GO
CREATE VIEW [bcModel].[vw_purchasesByItem] AS
SELECT
    p.[bcCompanyId],
    p.[bcCompanyName],
    p.[itemNumber],
    MAX(i.[displayName])      AS itemName,
    MAX(i.[itemCategoryCode]) AS itemCategoryCode,
    p.periodStart,
    p.[locationCode],
    p.[currencyCode],
    SUM(p.[quantity])   AS quantityPurchased,
    SUM(p.[lineAmount]) AS netSpend,
    CASE WHEN SUM(p.[quantity]) <> 0
         THEN SUM(p.[lineAmount]) / SUM(p.[quantity]) END AS averageUnitCost,
    COUNT(DISTINCT p.[vendorNumber])   AS vendorCount,
    COUNT(DISTINCT p.[documentNumber]) AS documentCount
FROM [bcModel].[vw_purchaseAnalysis] p
LEFT JOIN [bc].[items] i
       ON i.[number] = p.[itemNumber]
      AND i.[bcCompanyId] = p.[bcCompanyId]
      AND i.[_rowState] = 'Active'
WHERE p.[lineType] = 'Item'
GROUP BY p.[bcCompanyId], p.[bcCompanyName], p.[itemNumber], p.periodStart, p.[locationCode], p.[currencyCode];
GO


-- =====================================================================
-- Inventory
-- =====================================================================

-- Inventory valuation, the way Business Central computes it.
--
-- Sums valueEntries rather than multiplying on-hand by a unit cost, which is
-- what makes this reconcilable: `costAmountActual` is the number BC posts to
-- the inventory accounts.
--
-- Only costAmountActual is summed. costAmountExpected is the cost of goods
-- received or shipped but not yet invoiced, and it is SUPERSEDED as invoices
-- arrive rather than added to -- totalling both double counts every receipt
-- that has since been invoiced. It is exposed separately so the not-yet-final
-- portion stays visible.
--
-- `inventoriable = 0` rows are excluded from value: an item charge on a sale
-- is a real cost but never becomes stock. They still belong in COGS, which is
-- why vw_grossMargin does not filter them.
--
-- costPostedToGl against costAmountActual is the reconciliation itself. A gap
-- means Post Inventory Cost to G/L has not been run, and it is the usual
-- reason an inventory report disagrees with the inventory account.
DROP VIEW IF EXISTS [bcModel].[vw_inventoryValuation];
GO
CREATE VIEW [bcModel].[vw_inventoryValuation] AS
SELECT
    v.[bcCompanyId],
    v.[bcCompanyName],
    v.[itemNumber],
    i.[displayName]        AS itemName,
    i.[itemCategoryCode],
    v.[variantCode],
    v.[locationCode],
    v.[inventoryPostingGroup],
    SUM(v.[valuedQuantity])                                AS quantity,
    SUM(v.[costAmountActual])                              AS costAmountActual,
    SUM(v.[costAmountExpected])                            AS costAmountExpected,
    SUM(v.[costAmountNonInvtbl])                           AS costAmountNonInventoriable,
    SUM(v.[costPostedToGl])                                AS costPostedToGl,
    SUM(v.[costAmountActual]) - SUM(v.[costPostedToGl])    AS costNotYetInGl,
    CASE WHEN SUM(v.[valuedQuantity]) <> 0
         THEN SUM(v.[costAmountActual]) / SUM(v.[valuedQuantity]) END AS averageUnitCost,
    COUNT(*)                                               AS valueEntryCount,
    MAX(v.[postingDate])                                   AS lastMovementDate
FROM [bc].[valueEntries] v
LEFT JOIN [bc].[items] i
       ON i.[number] = v.[itemNumber]
      AND i.[bcCompanyId] = v.[bcCompanyId]
      AND i.[_rowState] = 'Active'
WHERE v.[_rowState] = 'Active'
  AND v.[inventoriable] = 1
GROUP BY v.[bcCompanyId], v.[bcCompanyName], v.[itemNumber], i.[displayName],
         i.[itemCategoryCode], v.[variantCode], v.[locationCode], v.[inventoryPostingGroup];
GO

-- Gross margin at real cost, by item and month.
--
-- salesAmountActual and costAmountActual sit on the SAME value entry row, so
-- margin comes off one table with no join to a sales document and no unit-cost
-- approximation. This supersedes `indicativeMargin` in vw_salesByItem, which
-- multiplies quantity by the item's current unit cost.
--
-- Sign: BC stores cost on an outbound movement as a negative number, so COGS
-- is negated here and margin reads the way a profit and loss statement does.
--
-- Non-inventoriable rows are INCLUDED, unlike vw_inventoryValuation: an item
-- charge on a sale is part of cost of sale even though it never became stock.
DROP VIEW IF EXISTS [bcModel].[vw_grossMargin];
GO
CREATE VIEW [bcModel].[vw_grossMargin] AS
SELECT
    v.[bcCompanyId],
    v.[bcCompanyName],
    DATEFROMPARTS(YEAR(v.[postingDate]), MONTH(v.[postingDate]), 1) AS periodStart,
    YEAR(v.[postingDate])   AS periodYear,
    MONTH(v.[postingDate])  AS periodMonth,
    v.[itemNumber],
    i.[displayName]         AS itemName,
    i.[itemCategoryCode],
    v.[variantCode],
    v.[locationCode],
    v.[sourceNumber]        AS customerNumber,
    v.[salespersonPurchaserCode],
    SUM(-v.[valuedQuantity])                                  AS quantitySold,
    SUM(v.[salesAmountActual])                                AS revenue,
    SUM(-v.[costAmountActual])                                AS costOfGoodsSold,
    SUM(v.[salesAmountActual]) + SUM(v.[costAmountActual])    AS grossMargin,
    CASE WHEN SUM(v.[salesAmountActual]) <> 0
         THEN (SUM(v.[salesAmountActual]) + SUM(v.[costAmountActual]))
              / SUM(v.[salesAmountActual]) * 100 END          AS grossMarginPercent,
    SUM(v.[discountAmount])                                   AS discountAmount,
    COUNT(*)                                                  AS valueEntryCount
FROM [bc].[valueEntries] v
LEFT JOIN [bc].[items] i
       ON i.[number] = v.[itemNumber]
      AND i.[bcCompanyId] = v.[bcCompanyId]
      AND i.[_rowState] = 'Active'
WHERE v.[_rowState] = 'Active'
  AND v.[itemLedgerEntryType] = 'Sale'
GROUP BY v.[bcCompanyId], v.[bcCompanyName],
         DATEFROMPARTS(YEAR(v.[postingDate]), MONTH(v.[postingDate]), 1),
         YEAR(v.[postingDate]), MONTH(v.[postingDate]),
         v.[itemNumber], i.[displayName], i.[itemCategoryCode],
         v.[variantCode], v.[locationCode], v.[sourceNumber], v.[salespersonPurchaserCode];
GO

-- On hand by item and location, with reorder context.
--
-- Quantities are exact: they come from the eOne availability snapshot, which
-- BC keeps current from Item Ledger and Reservation entries. `indicativeValue`
-- is on-hand x the item's CURRENT unit cost, which moves whenever somebody
-- edits the item card and never matches the general ledger.
--
-- For real cost use vw_inventoryValuation below, which sums Value Entries the
-- way Business Central does. This view is kept for its availability and
-- reorder columns, which the value entries do not carry.
DROP VIEW IF EXISTS [bcModel].[vw_inventoryOnHand];
GO
CREATE VIEW [bcModel].[vw_inventoryOnHand] AS
SELECT
    a.[itemNo]           AS itemNumber,
    a.[description]      AS itemName,
    i.[itemCategoryCode],
    i.[baseUnitOfMeasure],
    a.[locationCode],
    a.[onHandQuantity],
    a.[reservedQuantity],
    a.[qtyOnPurchaseOrder],
    a.[availableQuantity],
    a.[safetyStockQuantity],
    s.[reorderPoint],
    s.[reorderQuantity],
    s.[maximumInventory],
    CASE
        WHEN a.[availableQuantity] <= 0                                        THEN 'Out of stock'
        WHEN s.[reorderPoint] IS NOT NULL
         AND a.[availableQuantity] <= s.[reorderPoint]                         THEN 'Below reorder point'
        WHEN a.[safetyStockQuantity] > 0
         AND a.[availableQuantity] <= a.[safetyStockQuantity]                  THEN 'Below safety stock'
        ELSE 'OK'
    END AS stockStatus,
    i.[unitCost] AS currentUnitCost,
    a.[onHandQuantity] * COALESCE(i.[unitCost], 0) AS indicativeValue,
    a.[blocked],
    a.[salesBlocked],
    a.[lastModifiedDateTime],
    a.[bcCompanyId],
    a.[bcCompanyName]
FROM [bc].[itemInventoryAvailabilities] a
LEFT JOIN [bc].[items] i
       ON i.[number] = a.[itemNo]
      AND i.[bcCompanyId] = a.[bcCompanyId]
      AND i.[_rowState] = 'Active'
LEFT JOIN [bc].[stockkeepingUnits] s
       ON s.[itemNo] = a.[itemNo]
      AND s.[locationCode] = a.[locationCode]
      AND s.[bcCompanyId] = a.[bcCompanyId]
      AND s.[_rowState] = 'Active'
      -- The availability feed is item x location; a Stockkeeping Unit is item x
      -- location x VARIANT. Without this the join fans out one row per variant
      -- and every quantity is multiplied. The blank-variant SKU is the one that
      -- carries the location-level reorder policy.
      AND s.[variantCode] = ''
WHERE a.[_rowState] = 'Active';
GO


-- =====================================================================
-- Operations
-- =====================================================================

-- Open order backlog: what is committed but not yet posted, by document type
-- and age. The counterpart to the posted reports above -- and the number no
-- BC report can give you historically: BC deletes the open document, so once
-- it is gone the backlog it was part of cannot be reconstructed. If you need
-- backlog OVER TIME rather than as of now, capture this view on a schedule -
-- nothing here does that for you.
DROP VIEW IF EXISTS [bcModel].[vw_openOrderBacklog];
GO
CREATE VIEW [bcModel].[vw_openOrderBacklog] AS
SELECT
    [bcCompanyId],
    [bcCompanyName],
    [side],
    [documentType],
    [entitySet],
    [status],
    [currencyCode],
    [locationCode],
    [ageBucket],
    COUNT(*)                     AS documentCount,
    SUM([amountExcludingTax])    AS backlogValue,
    MIN([documentDate])          AS oldestDocumentDate,
    SUM([isOverdue])             AS overdueCount
FROM [bcModel].[vw_openDocumentAging]
GROUP BY [bcCompanyId], [bcCompanyName], [side], [documentType], [entitySet],
         [status], [currencyCode], [locationCode], [ageBucket];
GO
