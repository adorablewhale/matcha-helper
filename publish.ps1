# Builds and signs locally. -Publish is only used with owner release authorization.
[CmdletBinding()]
param([switch]$Publish)
$ErrorActionPreference='Stop'
$version='1.3.1'
& (Join-Path $PSScriptRoot 'build.ps1')
$release=Join-Path $PSScriptRoot 'release'
[void][IO.Directory]::CreateDirectory($release)
$zip=Join-Path $release 'matcha-helper.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if(Test-Path -LiteralPath $zip){
 Add-Type -AssemblyName Microsoft.VisualBasic
 [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($zip,'OnlyErrorDialogs','SendToRecycleBin')
}
[IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $PSScriptRoot 'package'),$zip)
$manifest=[ordered]@{schema=1;version=$version;package='matcha-helper.zip';size=(Get-Item -LiteralPath $zip).Length;sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower();expires=[DateTimeOffset]::UtcNow.AddDays(365).ToUnixTimeSeconds()}
[IO.File]::WriteAllText((Join-Path $release 'update.json'),($manifest|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'sign-release.ps1') -ReleaseDirectory $release
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'package\installer.exe') -Destination (Join-Path $release 'installer.exe') -Force
& (Join-Path $PSScriptRoot 'tests\run.ps1')
if(-not $Publish){Write-Output 'Signed local candidates ready. Nothing published.';return}
# Refuse accidental release under a different account or with unrelated staged data.
if((gh api user --jq .login) -ne 'adorablewhale'){throw 'GitHub must be signed into adorablewhale'}
function Invoke-HelperGit { & git.exe -c ('safe.directory='+$PSScriptRoot.Replace('\','/')) -C $PSScriptRoot @args }
if(-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git'))){
 Invoke-HelperGit init -b main
 Invoke-HelperGit remote add origin https://github.com/adorablewhale/matcha-helper.git
}
$staged=Invoke-HelperGit diff --cached --name-only
if($staged){throw 'Review existing staged files before publishing'}
Invoke-HelperGit add -- .gitignore README.md README.txt source-code.txt MatchaHelper.cs Updater.cs Installer.cs backend.ps1 install.ps1 build.ps1 sign-release.ps1 publish.ps1 update-public-key.xml tests
if($LASTEXITCODE -ne 0){throw 'Staging failed'}
Invoke-HelperGit diff --cached --quiet
if($LASTEXITCODE -eq 1){Invoke-HelperGit commit -m "Release Matcha helper $version with signed updates and installer";if($LASTEXITCODE -ne 0){throw 'Commit failed'}}
Invoke-HelperGit push -u origin main
if($LASTEXITCODE -ne 0){throw 'Source push failed'}
gh release create "v$version" --repo adorablewhale/matcha-helper --title "Matcha helper $version" --notes-file (Join-Path $PSScriptRoot 'README.txt') --latest (Join-Path $release 'installer.exe') $zip (Join-Path $release 'update.json') (Join-Path $release 'update.sig')
if($LASTEXITCODE -ne 0){throw 'Release publication failed; do not overwrite an existing release'}
