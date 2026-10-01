# Keep the signing key outside Git, protected by Windows DPAPI for the owner account.
[CmdletBinding()]
param([switch]$Initialize, [string]$ReleaseDirectory)
$ErrorActionPreference='Stop'
if(-not $ReleaseDirectory){$ReleaseDirectory=Join-Path $PSScriptRoot 'release'}
Add-Type -AssemblyName System.Security
$KeyPath=Join-Path $env:USERPROFILE '.j5cks\matcha-helper-signing.dpapi'
$PublicPath=Join-Path $PSScriptRoot 'update-public-key.xml'
$RSA=[Security.Cryptography.RSACryptoServiceProvider]::new(3072)
$RSA.PersistKeyInCsp=$false
try {
 if(Test-Path -LiteralPath $KeyPath) {
  $plain=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($KeyPath),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $RSA.FromXmlString([Text.Encoding]::UTF8.GetString($plain)); [Array]::Clear($plain,0,$plain.Length)
 } elseif($Initialize) {
  [void][IO.Directory]::CreateDirectory((Split-Path $KeyPath))
  $plain=[Text.Encoding]::UTF8.GetBytes($RSA.ToXmlString($true))
  $protected=[Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  [IO.File]::WriteAllBytes($KeyPath,$protected); [Array]::Clear($plain,0,$plain.Length)
 } else {throw 'Signing key missing. Initialize it once under the owner Windows account.'}
 $public=$RSA.ToXmlString($false)
 if(Test-Path -LiteralPath $PublicPath) {
  if([IO.File]::ReadAllText($PublicPath).Trim() -ne $public){throw 'Signing key does not match the pinned public key. Refusing key replacement.'}
 } elseif($Initialize){[IO.File]::WriteAllText($PublicPath,$public,[Text.UTF8Encoding]::new($false))}
 else {throw 'Pinned public key missing'}
 if($Initialize){Write-Output 'Signing key initialized privately; only the public key is in source.'; return}
 $Manifest=Join-Path $ReleaseDirectory 'update.json'
 $bytes=[IO.File]::ReadAllBytes($Manifest)
 $sig=$RSA.SignData($bytes,'SHA256')
 [IO.File]::WriteAllText((Join-Path $ReleaseDirectory 'update.sig'),[Convert]::ToBase64String($sig),[Text.UTF8Encoding]::new($false))
 Write-Output 'Release manifest signed.'
} finally {$RSA.Dispose()}
