' Launch monitor.ps1 without a console window (works from any folder / Startup).
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -Sta -WindowStyle Hidden -File """ & dir & "\monitor.ps1""", 0, False
