# Build the native tray EXE using Windows' .NET Framework compiler. No downloads.
[CmdletBinding()]
param([string]$Out)
$ErrorActionPreference='Stop'
if(-not $Out){$Out=Join-Path $PSScriptRoot 'package'}
$Out=[IO.Path]::GetFullPath($Out)
[void][IO.Directory]::CreateDirectory($Out)
$Compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$Framework=Split-Path $Compiler
$Source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'MatchaHelper.cs'))
$Backend=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'backend.ps1'))
$Installer=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'install.ps1'))
$Build=[IO.File]::ReadAllText($PSCommandPath)
$Readable="MATCHA HELPER 1.2.0 - COMPLETE SOURCE`r`n"
foreach($name in @('MatchaHelper.cs','Updater.cs','Installer.cs','backend.ps1','install.ps1','build.ps1','sign-release.ps1','publish.ps1','update-public-key.xml')) {
 $Readable+="`r`n===== $name =====`r`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))
}
[IO.File]::WriteAllText((Join-Path $Out 'source-code.txt'),$Readable,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'source-code.txt'),$Readable,[Text.UTF8Encoding]::new($false))
Add-Type -AssemblyName System.Drawing
$Bitmap=[Drawing.Bitmap]::new(32,32); $Graphics=[Drawing.Graphics]::FromImage($Bitmap)
$Graphics.SmoothingMode='AntiAlias'; $Brush=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(160,225,193))
$Graphics.FillEllipse($Brush,3,12,24,15)
$Graphics.FillPolygon($Brush,[Drawing.Point[]]@([Drawing.Point]::new(24,20),[Drawing.Point]::new(29,7),[Drawing.Point]::new(31,13),[Drawing.Point]::new(29,23)))
$Graphics.FillRectangle($Brush,11,6,2,7); $Graphics.FillEllipse($Brush,8,4,5,3); $Graphics.FillEllipse($Brush,13,3,5,3)
$Eye=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(14,18,16)); $Graphics.FillEllipse($Eye,8,17,3,3)
$Icon=[Drawing.Icon]::FromHandle($Bitmap.GetHicon()); $File=[IO.File]::Create((Join-Path $Out 'matcha.ico')); $Icon.Save($File); $File.Close()
$Graphics.Dispose(); $Bitmap.Dispose(); $Brush.Dispose(); $Eye.Dispose(); $Icon.Dispose()
& $Compiler /nologo /target:winexe /optimize+ /platform:anycpu "/out:$Out\matcha-helper.exe" "/win32icon:$Out\matcha.ico" "/reference:$Framework\System.Windows.Forms.dll" "/reference:$Framework\System.Drawing.dll" "/reference:$Framework\System.Web.Extensions.dll" "/reference:$Framework\Microsoft.VisualBasic.dll" "/reference:$Framework\System.IO.Compression.dll" "/resource:$PSScriptRoot\backend.ps1,Backend" "/resource:$Out\source-code.txt,Source" "/resource:$PSScriptRoot\install.ps1,Installer" "/resource:$PSScriptRoot\README.txt,Readme" "/resource:$PSScriptRoot\update-public-key.xml,UpdateKey" "$PSScriptRoot\MatchaHelper.cs" "$PSScriptRoot\Updater.cs"
if($LASTEXITCODE -ne 0){throw 'native compilation failed'}
& $Compiler /nologo /target:winexe /optimize+ /platform:anycpu "/out:$Out\installer.exe" "/win32icon:$Out\matcha.ico" "/reference:$Framework\System.Windows.Forms.dll" "/reference:$Framework\System.Drawing.dll" "/resource:$Out\matcha-helper.exe,HelperBinary" "/resource:$Out\source-code.txt,Source" "/resource:$PSScriptRoot\install.ps1,Installer" "/resource:$PSScriptRoot\README.txt,Readme" "/resource:$Out\matcha.ico,Icon" "$PSScriptRoot\Installer.cs"
if($LASTEXITCODE -ne 0){throw 'installer compilation failed'}
foreach($name in @('README.txt','install.ps1','MatchaHelper.cs','Updater.cs','Installer.cs','backend.ps1','build.ps1','sign-release.ps1','publish.ps1','update-public-key.xml')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $Out $name) -Force }
[IO.File]::WriteAllText((Join-Path $Out 'uninstall.cmd'),"@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0install.ps1`" -Uninstall`r`npause`r`n")
$Hashes=Get-ChildItem -LiteralPath $Out -File | Where-Object Name -ne 'SHA256SUMS.txt' | Sort-Object Name | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()+'  '+$_.Name }
[IO.File]::WriteAllLines((Join-Path $Out 'SHA256SUMS.txt'),$Hashes)
Write-Output ('built helper and single-file installer in '+$Out)
