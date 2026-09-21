-- =====================================================================
-- eOne Integration for Business Central -> Microsoft Fabric Warehouse
-- 21 - The dimension bridge
--
-- Numbered 21 because ORDER MATTERS here, and the number is the only thing
-- enforcing it: the deploy runs sql\*.sql in filename order, and these two
-- views are read by 30_view_documenthistory.sql and by nearly every view in
-- 32_views_reporting.sql. They lived in 32 and therefore deployed AFTER their
-- first consumer, which fails at CREATE VIEW with
--
--     Msg 208, Invalid object name 'bcModel.vw_dimensionSetPivot'
--
-- They read bc.dimensionSetEntries, which is a current-state view from
-- 20_views_current.sql, so 21 is the first slot they can occupy.
-- =====================================================================


-- Dimensions, resolved.
--
-- Business Central stores a document's dimensions as an integer - a Dimension Set ID naming a set
-- of (dimension, value) pairs - not as columns on the document. This is the bridge: join any fact's
-- dimensionSetId to it and you get that record's full dimension picture, however many dimensions
-- the company uses.
--
-- Deliberately LONG, one row per dimension per set, not pivoted into eight columns. Pivoting would
-- reintroduce exactly the limit this replaces: the flat shortcutDimension1..8Code columns on the
-- documents stop at eight, carry no names, and mean something different at every customer because
-- which dimension sits in which slot is a per-company setup choice. Let the BI tool pivot on
-- dimensionCode, and a customer who adds a ninth dimension needs no change here.
--
-- globalDimensionNumber is the shortcut slot a dimension occupies, or 0 when it is not one of them,
-- which is what lines this view up with those flat columns when you need both.
DROP VIEW IF EXISTS [bcModel].[vw_dimensionSets];
GO
CREATE VIEW [bcModel].[vw_dimensionSets] AS
SELECT
    d.[dimensionSetId],
    d.[dimensionCode],
    d.[dimensionName],
    d.[dimensionValueCode],
    d.[dimensionValueName],
    d.[globalDimensionNumber],
    d.[bcCompanyId],
    d.[bcCompanyName]
FROM [bc].[dimensionSetEntries] d
WHERE d.[_rowState] = 'Active';
GO


-- One row per dimension set, with the eight global dimension slots pivoted into columns.
--
-- This is what lets a FACT view carry its dimensions without changing grain. vw_dimensionSets is
-- long - one row per dimension - so joining it to a fact would multiply that fact's rows and every
-- amount with them. Pivoting first keeps the join one-to-one.
--
-- Eight slots because Business Central guarantees at most eight GLOBAL dimensions and numbers them;
-- `globalDimensionNumber` is that slot. A company using more than eight dimensions still has them
-- all in vw_dimensionSets, reachable through the same dimensionSetId - they simply cannot be
-- columns on a fixed-width view, because their codes differ per customer and are unknown until the
-- data arrives.
--
-- Note this is NOT the old flat shortcutDimensionNCode shape wearing a new name. Those were codes
-- only, were stored on the document (so posted records and G/L entries carried at most two of
-- them), and meant nothing without knowing the customer's slot setup. These resolve every slot for
-- every fact that has a dimension set, and carry the NAMES as well as the codes.
DROP VIEW IF EXISTS [bcModel].[vw_dimensionSetPivot];
GO
CREATE VIEW [bcModel].[vw_dimensionSetPivot] AS
SELECT
    [dimensionSetId],
    [bcCompanyId],
    MAX([bcCompanyName]) AS bcCompanyName,
    MAX(CASE WHEN [globalDimensionNumber] = 1 THEN [dimensionCode]      END) AS dimension1Code,
    MAX(CASE WHEN [globalDimensionNumber] = 1 THEN [dimensionName]      END) AS dimension1Name,
    MAX(CASE WHEN [globalDimensionNumber] = 1 THEN [dimensionValueCode] END) AS dimension1ValueCode,
    MAX(CASE WHEN [globalDimensionNumber] = 1 THEN [dimensionValueName] END) AS dimension1ValueName,
    MAX(CASE WHEN [globalDimensionNumber] = 2 THEN [dimensionCode]      END) AS dimension2Code,
    MAX(CASE WHEN [globalDimensionNumber] = 2 THEN [dimensionName]      END) AS dimension2Name,
    MAX(CASE WHEN [globalDimensionNumber] = 2 THEN [dimensionValueCode] END) AS dimension2ValueCode,
    MAX(CASE WHEN [globalDimensionNumber] = 2 THEN [dimensionValueName] END) AS dimension2ValueName,
    MAX(CASE WHEN [globalDimensionNumber] = 3 THEN [dimensionCode]      END) AS dimension3Code,
    MAX(CASE WHEN [globalDimensionNumber] = 3 THEN [dimensionName]      END) AS dimension3Name,
    MAX(CASE WHEN [globalDimensionNumber] = 3 THEN [dimensionValueCode] END) AS dimension3ValueCode,
    MAX(CASE WHEN [globalDimensionNumber] = 3 THEN [dimensionValueName] END) AS dimension3ValueName,
    MAX(CASE WHEN [globalDimensionNumber] = 4 THEN [dimensionCode]      END) AS dimension4Code,
    MAX(CASE WHEN [globalDimensionNumber] = 4 THEN [dimensionName]      END) AS dimension4Name,
    MAX(CASE WHEN [globalDimensionNumber] = 4 THEN [dimensionValueCode] END) AS dimension4ValueCode,
    MAX(CASE WHEN [globalDimensionNumber] = 4 THEN [dimensionValueName] END) AS dimension4ValueName,
    MAX(CASE WHEN [globalDimensionNumber] = 5 THEN [dimensionCode]      END) AS dimension5Code,
    MAX(CASE WHEN [globalDimensionNumber] = 5 THEN [dimensionName]      END) AS dimension5Name,
    MAX(CASE WHEN [globalDimensionNumber] = 5 THEN [dimensionValueCode] END) AS dimension5ValueCode,
    MAX(CASE WHEN [globalDimensionNumber] = 5 THEN [dimensionValueName] END) AS dimension5ValueName,
    MAX(CASE WHEN [globalDimensionNumber] = 6 THEN [dimensionCode]      END) AS dimension6Code,
    MAX(CASE WHEN [globalDimensionNumber] = 6 THEN [dimensionName]      END) AS dimension6Name,
    MAX(CASE WHEN [globalDimensionNumber] = 6 THEN [dimensionValueCode] END) AS dimension6ValueCode,
    MAX(CASE WHEN [globalDimensionNumber] = 6 THEN [dimensionValueName] END) AS dimension6ValueName,
    MAX(CASE WHEN [globalDimensionNumber] = 7 THEN [dimensionCode]      END) AS dimension7Code,
    MAX(CASE WHEN [globalDimensionNumber] = 7 THEN [dimensionName]      END) AS dimension7Name,
    MAX(CASE WHEN [globalDimensionNumber] = 7 THEN [dimensionValueCode] END) AS dimension7ValueCode,
    MAX(CASE WHEN [globalDimensionNumber] = 7 THEN [dimensionValueName] END) AS dimension7ValueName,
    MAX(CASE WHEN [globalDimensionNumber] = 8 THEN [dimensionCode]      END) AS dimension8Code,
    MAX(CASE WHEN [globalDimensionNumber] = 8 THEN [dimensionName]      END) AS dimension8Name,
    MAX(CASE WHEN [globalDimensionNumber] = 8 THEN [dimensionValueCode] END) AS dimension8ValueCode,
    MAX(CASE WHEN [globalDimensionNumber] = 8 THEN [dimensionValueName] END) AS dimension8ValueName
FROM [bcModel].[vw_dimensionSets]
GROUP BY [dimensionSetId], [bcCompanyId];
GO
