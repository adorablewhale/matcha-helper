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
