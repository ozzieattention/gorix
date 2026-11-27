' Gorix'i konsol penceresi acmadan baslatir
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\Gorix.ps1"""
CreateObject("WScript.Shell").Run cmd, 0, False
