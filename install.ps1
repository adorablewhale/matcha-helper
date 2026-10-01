# Matcha helper 1.3.0 per-user installer. Readable; no elevation or network downloads.
[CmdletBinding()]
param([switch]$Uninstall, [string]$Workspace, [int]$WaitPid = 0, [switch]$Tray, [switch]$Update, [switch]$NoStartup, [switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MatchaFolders {
 [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid id,uint flags,IntPtr token,out IntPtr path);
 public static string Get(string name) {
  Guid id=new Guid(name); IntPtr ptr;
  int hr=SHGetKnownFolderPath(ref id,0x00010000,IntPtr.Zero,out ptr);
  if(hr!=0) Marshal.ThrowExceptionForHR(hr);
  try{return Marshal.PtrToStringUni(ptr);}finally{Marshal.FreeCoTaskMem(ptr);}
 }
}
'@
$InstallRoot = [IO.Path]::GetFullPath((Join-Path ([MatchaFolders]::Get('F1B32785-6FBA-4FCF-9D55-7B8E7F157091')) 'matcha-helper'))
$Exe = Join-Path $InstallRoot 'matcha-helper.exe'
$Runner = Join-Path $InstallRoot 'run.ps1'
$ShortcutPath = Join-Path ([MatchaFolders]::Get('B97D20BB-F46A-4C97-BA10-5E3608430854')) 'Matcha helper.lnk'
$MenuPath = Join-Path ([MatchaFolders]::Get('A77F5D77-2E2B-44C3-A6A2-ABA601054A51')) 'Matcha helper.lnk'
$PidFile = Join-Path $InstallRoot 'process.json'
$Managed = @('matcha-helper.exe','source-code.txt','README.txt','install.ps1','process.json','workspace.txt','updates-disabled.txt','run.ps1','matcha-helper.bat',
  'runtime\backend.ps1','runtime\source-code.txt','setup\matcha-helper.exe','setup\install.ps1','setup\source-code.txt','setup\README.txt')
function Assert-Managed([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  if ($full -ne $InstallRoot -and -not $full.StartsWith($InstallRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'path outside helper installation' }
  for ($p=$full; $p; $p=[IO.Path]::GetDirectoryName($p)) {
    if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'linked installation paths are not supported' }
  }
}
function Recycle([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path,'OnlyErrorDialogs','SendToRecycleBin')
  }
}
function Stop-Helper {
  # process.json can be stale after portable/packaged launches. Verify the actual
  # installed executable and its exact backend path, never a PID alone.
  $hosts=@(Get-CimInstance Win32_Process -Filter "Name='matcha-helper.exe'" | Where-Object { $_.ExecutablePath -ieq $Exe })
  foreach($hostProcess in $hosts) {
    $hostId=[int]$hostProcess.ProcessId
    $created=(Get-Process -Id $hostId -ErrorAction Stop).StartTime.ToUniversalTime().Ticks
    $backendPath=Join-Path $InstallRoot 'runtime\backend.ps1'
    $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$hostId) | Where-Object { $_.Name -ieq 'powershell.exe' -and $_.CommandLine -and $_.CommandLine.IndexOf('"'+$backendPath+'"',[StringComparison]::OrdinalIgnoreCase) -ge 0 })
    Start-Process -FilePath $Exe -ArgumentList '--quit' -WindowStyle Hidden -Wait
    try {Wait-Process -Id $hostId -Timeout 8 -ErrorAction Stop} catch {
      $still=Get-Process -Id $hostId -ErrorAction SilentlyContinue
      if($still -and $still.StartTime.ToUniversalTime().Ticks -eq $created){Stop-Process -Id $hostId}
    }
    foreach($child in $children) {
      $still=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$child.ProcessId) -ErrorAction SilentlyContinue
      if($still -and $still.ParentProcessId -eq $hostId -and $still.CreationDate -eq $child.CreationDate -and $still.CommandLine -eq $child.CommandLine){Stop-Process -Id $still.ProcessId}
    }
  }
  if (-not (Test-Path -LiteralPath $PidFile)) { return }
  $saved = Get-Content -LiteralPath $PidFile -Raw | ConvertFrom-Json
  $running = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$saved.pid) -ErrorAction SilentlyContinue
  if (-not $running) { return }
  if ($running.Name -ieq 'matcha-helper.exe' -and $running.ExecutablePath -ieq $Exe -and
      (Get-Process -Id $running.ProcessId).StartTime.ToUniversalTime().Ticks -eq [long]$saved.created) {
    Start-Process -FilePath $Exe -ArgumentList '--quit' -WindowStyle Hidden -Wait
    try { Wait-Process -Id $running.ProcessId -Timeout 12 -ErrorAction Stop } catch {
      $still = Get-Process -Id $running.ProcessId -ErrorAction SilentlyContinue
      if ($still -and $still.StartTime.ToUniversalTime().Ticks -eq [long]$saved.created) { Stop-Process -Id $still.Id }
    }
  } elseif ($running.Name -ieq 'powershell.exe' -and $running.CommandLine -and
      $running.CommandLine.IndexOf('"'+$Runner+'"',[StringComparison]::OrdinalIgnoreCase) -ge 0 -and
      $running.CreationDate.ToUniversalTime().Ticks -eq [long]$saved.created) {
    Stop-Process -Id $running.ProcessId
    $beatFile = Join-Path ([string]$saved.workspace) 'INSUI\helper\helper.json'
    if (Test-Path -LiteralPath $beatFile) {
      $beat = Get-Content -LiteralPath $beatFile -Raw | ConvertFrom-Json
      if ([int]$beat.pid -eq [int]$saved.pid) { $beat.beat = 0; $beat | ConvertTo-Json -Compress | Set-Content -LiteralPath $beatFile -Encoding UTF8 }
    }
  }
}
Assert-Managed $InstallRoot
foreach ($name in $Managed) { Assert-Managed (Join-Path $InstallRoot $name) }
$shell = New-Object -ComObject WScript.Shell
foreach($shortcut in @($ShortcutPath,$MenuPath)) {
 if (Test-Path -LiteralPath $shortcut) {
  $link = $shell.CreateShortcut($shortcut)
  $ours = $link.TargetPath -ieq $Exe -or ($link.Arguments.IndexOf('"'+$Runner+'"',[StringComparison]::OrdinalIgnoreCase) -ge 0)
  if (-not $ours) { throw 'shortcut belongs to another application' }
 }
}
if ($Uninstall) {
  if ($WaitPid -gt 0) { Wait-Process -Id $WaitPid -Timeout 30 -ErrorAction SilentlyContinue }
  Stop-Helper
  Recycle $ShortcutPath
  Recycle $MenuPath
  foreach ($name in $Managed) { Recycle (Join-Path $InstallRoot $name) }
  foreach($name in @('matcha-helper.exe','source-code.txt','README.txt','install.ps1')) { Recycle (Join-Path $InstallRoot ($name+'.rollback')) }
  Write-Output 'helper uninstalled; managed files recycled; script settings preserved'
  return
}
if($Update){$NoStartup=-not (Test-Path -LiteralPath $ShortcutPath)}
if(-not $Workspace){
 $savedWorkspace=Join-Path $InstallRoot 'workspace.txt'
 $Workspace=if(Test-Path -LiteralPath $savedWorkspace){[IO.File]::ReadAllText($savedWorkspace).Trim()}else{'C:\matcha\workspace'}
}
$Workspace = [IO.Path]::GetFullPath($Workspace)
if (-not (Test-Path -LiteralPath $Workspace -PathType Container)) { throw 'Matcha workspace folder not found' }
# Validate all required files before stopping the working helper.
foreach ($name in @('matcha-helper.exe','source-code.txt','README.txt','install.ps1')) {
  $src = Join-Path $PSScriptRoot $name
  if (-not (Test-Path -LiteralPath $src)) { throw ('keep the package together: missing '+$name) }
}
$sums=Join-Path $PSScriptRoot 'SHA256SUMS.txt'
if(Test-Path -LiteralPath $sums){
 foreach($line in [IO.File]::ReadAllLines($sums)){
  if($line -notmatch '^([a-f0-9]{64})  ([A-Za-z0-9_.-]+)$'){throw 'invalid package checksum list'}
  $expected=$Matches[1]; $file=Join-Path $PSScriptRoot $Matches[2]
  if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower() -ne $expected){throw 'package checksum mismatch'}
 }
}
if ($WaitPid -gt 0) { Wait-Process -Id $WaitPid -Timeout 30 -ErrorAction SilentlyContinue }
Stop-Helper
if (Get-NetTCPConnection -LocalPort 47210 -State Listen -ErrorAction SilentlyContinue) { throw 'another helper is running; quit it before installing' }
[void][IO.Directory]::CreateDirectory($InstallRoot)
$copied=@(); $backed=@()
try {
 foreach ($name in @('matcha-helper.exe','source-code.txt','README.txt','install.ps1')) {
  $src=Join-Path $PSScriptRoot $name; $dst=Join-Path $InstallRoot $name
  if ([IO.Path]::GetFullPath($src) -eq $dst){continue}
  $backup=$dst+'.rollback'; Assert-Managed $backup
  if(Test-Path -LiteralPath $dst){Copy-Item -LiteralPath $dst -Destination $backup -Force; $backed+=$name}
  Copy-Item -LiteralPath $src -Destination $dst -Force; $copied+=$name
 }
} catch {
 foreach($name in $backed){Copy-Item -LiteralPath (Join-Path $InstallRoot ($name+'.rollback')) -Destination (Join-Path $InstallRoot $name) -Force}
 foreach($name in $copied){if($name -notin $backed){Recycle (Join-Path $InstallRoot $name)}}
 if(Test-Path -LiteralPath $Exe){Start-Process -FilePath $Exe -ArgumentList '--tray' -WindowStyle Hidden}
 throw
}
[IO.File]::WriteAllText((Join-Path $InstallRoot 'workspace.txt'),$Workspace)
# Recycle superseded launcher files; never remove unfamiliar files or script data.
foreach ($name in @('run.ps1','matcha-helper.bat')) { Recycle (Join-Path $InstallRoot $name) }
foreach($shortcut in @($MenuPath,$ShortcutPath)) {
 if($shortcut -eq $ShortcutPath -and $NoStartup){Recycle $ShortcutPath; continue}
 [void][IO.Directory]::CreateDirectory((Split-Path $shortcut))
 $link = $shell.CreateShortcut($shortcut)
 $link.TargetPath=$Exe; $link.Arguments=if($shortcut -eq $ShortcutPath){'--tray'}else{''}; $link.WorkingDirectory=$InstallRoot; $link.IconLocation=$Exe+',0'; $link.WindowStyle=7
 $link.Description='Matcha helper; sleeps until a script is active; quit from the tray'; $link.Save()
}
foreach($name in $backed){Recycle (Join-Path $InstallRoot ($name+'.rollback'))}
if(-not $NoLaunch){
 if ($Tray) { Start-Process -FilePath $Exe -ArgumentList '--tray' -WindowStyle Hidden }
 else { Start-Process -FilePath $Exe -WindowStyle Hidden }
}
Write-Output 'native helper installed; Start menu shortcut created; preferences preserved on update'
