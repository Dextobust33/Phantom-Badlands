$WshShell = New-Object -ComObject WScript.Shell

# Server shortcut
$ServerShortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Phantom Badlands Server.lnk")
$ServerShortcut.TargetPath = "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$ServerShortcut.Arguments = '--path "C:\Users\Dexto\Documents\phantasia-revival" "res://server/server.tscn"'
$ServerShortcut.WorkingDirectory = "C:\Users\Dexto\Documents\phantasia-revival"
$ServerShortcut.Description = "Launch Phantom Badlands Server"
$ServerShortcut.Save()

# Client shortcut
$ClientShortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Phantom Badlands Client.lnk")
$ClientShortcut.TargetPath = "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$ClientShortcut.Arguments = '--path "C:\Users\Dexto\Documents\phantasia-revival" "res://client/client.tscn"'
$ClientShortcut.WorkingDirectory = "C:\Users\Dexto\Documents\phantasia-revival"
$ClientShortcut.Description = "Launch Phantom Badlands Client"
$ClientShortcut.Save()

Write-Host "Shortcuts created successfully!"
