[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$src=Split-Path $PSScriptRoot
$out=Join-Path $PSScriptRoot 'output';[void][IO.Directory]::CreateDirectory($out)
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe';$framework=Split-Path $compiler
& $compiler /nologo /target:exe "/out:$out\tests.exe" "/reference:$framework\System.Web.Extensions.dll" "/reference:$framework\System.IO.Compression.dll" (Join-Path $src 'Updater.cs') (Join-Path $PSScriptRoot 'UpdaterTests.cs')
if($LASTEXITCODE -ne 0){throw 'Test compilation failed'}
& (Join-Path $out 'tests.exe') $src (Join-Path $out 'extracted')
if($LASTEXITCODE -ne 0){throw 'Updater tests failed'}
& $compiler /nologo /target:exe /main:RejoinTests "/out:$out\rejoin-tests.exe" "/reference:$framework\System.Web.Extensions.dll" "/reference:$framework\System.Windows.Forms.dll" "/reference:$framework\System.Drawing.dll" "/reference:$framework\Microsoft.VisualBasic.dll" "/reference:$framework\System.IO.Compression.dll" (Join-Path $src 'MatchaHelper.cs') (Join-Path $src 'Updater.cs') (Join-Path $PSScriptRoot 'RejoinTests.cs')
if($LASTEXITCODE -ne 0){throw 'Rejoin test compilation failed'}
& (Join-Path $out 'rejoin-tests.exe') (Join-Path $out 'rejoin-fixture')
if($LASTEXITCODE -ne 0){throw 'Rejoin control tests failed'}
# Exercise the actual backend reader, including Windows PowerShell's UTF-8 BOM.
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $src 'backend.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Backend parse failed'}
foreach($name in @('Read-Shared','Read-Json')) {
 $fn=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)[0]
 Invoke-Expression $fn.Extent.Text
}
$fixture=Join-Path $out 'bom.json';[IO.File]::WriteAllText($fixture,'{"mode":"sleeping"}',[Text.UTF8Encoding]::new($true))
if((Read-Json $fixture).mode -ne 'sleeping'){throw 'BOM JSON failed'}
[IO.File]::WriteAllText($fixture,'{"mode":"awake"}',[Text.UTF8Encoding]::new($false))
if((Read-Json $fixture).mode -ne 'awake'){throw 'Plain JSON failed'}
Write-Output 'BOM and plain JSON checks passed'
