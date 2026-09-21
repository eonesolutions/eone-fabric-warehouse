# Create the warehouse

Deploy-EOneWarehouse.ps1 runs on your own machine. It connects out to Fabric over the SQL endpoint and runs DDL; nothing is installed inside Fabric. Hand the script and the sql folder to a customer together, because the script reads the SQL from .\sql beside itself.

To create the warehouse item and deploy into it in one command:

```
.\Deploy-EOneWarehouse.ps1 -CreateWarehouse -WorkspaceId <workspace-guid> -Database BCWarehouse
```

Against a warehouse that already exists, take the SQL connection string from the warehouse's Settings page in Fabric:

```
.\Deploy-EOneWarehouse.ps1 -Server abc123.datawarehouse.fabric.microsoft.com -Database BCWarehouse
```

To see which files would run without connecting to anything:

```
.\Deploy-EOneWarehouse.ps1 -Database BCWarehouse -ListOnly
```

It signs you in interactively through Entra. Fabric Warehouse does not accept SQL logins. For unattended use, obtain a token yourself and pass -AccessToken; the script then does no interactive sign-in at all.

### Run -CreateWarehouse in a fresh PowerShell window

Only -CreateWarehouse needs an Azure sign-in, and on Windows PowerShell 5.1 it needs a session in which the SqlServer module has not yet been loaded.

The reason is worth knowing, because the error blames the wrong thing. Loading SqlServer makes an older Microsoft.Identity.Client available to the process; Azure PowerShell then binds to it and fails with a missing-type error followed by advice to try -DeviceCode. The browser is fine and -DeviceCode fails identically. Nothing can undo it within that session - Remove-Module does not unbind it.

The script checks for this and stops with an explanation rather than letting the Azure error surface. Open a new window and run it again.

Deploying to a warehouse that already exists is unaffected: that path passes -Server, never loads Az, and works in any session.

**-Force discards data.**The table DDL drops and recreates, so re-running against a loaded warehouse throws away every row. The script refuses without -Force for that reason. A reload recovers current state, but it does not recover two things: documents that have already exited, because Business Central deletes an open document when it posts, and the version history accumulated in bcRaw, which exists only in the warehouse.

---

[Back: Before you start](02-before-you-start.md) | [Contents](README.md) | [Next: Turn on Document Events](04-turn-on-document-events.md)
