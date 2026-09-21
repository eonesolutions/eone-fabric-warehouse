# Before you start

Confirm all of these before running anything. The two that most often stop a first deployment are Document Events being off and the wrong permission set on the Entra application.

| **Where** | **What** | **Why** |
| --- | --- | --- |
| Business Central | eOne Integration extension installed and licensed | The API returns a licence error before it returns data. |
| Business Central | Document Events switched on in eOne Integration Setup | Nothing records lifecycle transitions until you do, and the feed errors rather than returning an empty page while it is off. |
| Business Central | An Entra application with the EONE Integ. Full permission set (14182001) | The lean EONE Integration set grants execute on the endpoints but not read on the base tables, and fails at runtime with a message that blames the licence. |
| Microsoft Fabric | A workspace on a capacity that can host a Warehouse | The warehouse is a workspace item; there is no T-SQL CREATE DATABASE. |
| Microsoft Fabric | An Entra identity with Contributor on the workspace | Needed to create the warehouse and to write to it. Fabric accepts Entra only - there are no SQL logins. |
| Your workstation | PowerShell with the SqlServer module, version 21.1 or newer | Install-Module SqlServer -Scope CurrentUser -AllowClobber. -AllowClobber is required on any machine with SQL Server tooling installed: the SQLPS module that ships with SSMS already exports Invoke-Sqlcmd, and the install fails with CommandAlreadyAvailable without it. SQLPS is left in place. |
| Your workstation | The Az.Accounts module | Required to create the warehouse, and preferred for authentication either way. Install-Module Az.Accounts -Scope CurrentUser |
| Your workstation | Outbound TCP 1433 to *.datawarehouse.fabric.microsoft.com | Worth confirming on a corporate network before you start. |
| SmartConnect | A REST/OData source and a Fabric Warehouse destination | Authenticating to Fabric as an Entra service principal. |

---

[Back: What you are deploying](01-what-you-are-deploying.md) | [Contents](README.md) | [Next: Create the warehouse](03-create-the-warehouse.md)
