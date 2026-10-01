"""Extract the reviewed BAT backend once; do not alter the original fallback BAT."""
from pathlib import Path
p = Path(__file__).parent
s = (p.parents[1] / 'shared/INSUI/helper/matcha-helper.bat').read_text(encoding='utf-8-sig')
s = s.split('#>\n', 1)[1].replace("$Version = '1.0.0'", "$Version = '1.1.1'")
s = s.replace('function Universal-Tick {\n  $rb = Get-Roblox', '''$script:ActiveNames = @()
function Universal-Tick {
  $states = @{}
  $script:ActiveNames = @()
  $needsRoblox = $false
  foreach ($name in (Get-Scripts)) {
    $state = Script-State $name
    $states[$name] = $state
    if ($state.state -and -not $state.state.unloaded -and $state.age -lt 15) {
      $script:ActiveNames += $name
      if ($state.features.afk) { $needsRoblox = $true }
    }
  }
  # No process scan, focus, keyboard input or automatic screenshot while sleeping.
  $rb = if ($needsRoblox) { Get-Roblox } else { $null }''')
s = s.replace('  foreach ($name in (Get-Scripts)) {\n    $s = Script-State $name; $st=$s.state; $f=$s.features', '  foreach ($name in $states.Keys) {\n    $s = $states[$name]; $st=$s.state; $f=$s.features')
s = s.replace('  while($true){\n    if((Get-Date) -ge $nextBeat)', '''  while($true){
    # An orphaned backend stops even if the tray host crashes or is force-closed.
    if($env:MATCHA_HELPER_HOST_PID -and (Get-Date) -ge $nextTick) {
      try {$owner=[Diagnostics.Process]::GetProcessById([int]$env:MATCHA_HELPER_HOST_PID)} catch {break}
      try {if($owner.StartTime.ToUniversalTime().Ticks -ne [long]$env:MATCHA_HELPER_HOST_CREATED){break}} finally {$owner.Dispose()}
    }
    if((Get-Date) -ge $nextBeat)''')
s = s.replace('$nextBeat=(Get-Date).AddSeconds(5);Write-Json', '$nextBeat=(Get-Date).AddSeconds(2);Write-Json')
s = s.replace('pid=$PID;beat=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()', "pid=$PID;beat=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();mode=$(if($script:ActiveNames.Count){'awake'}else{'sleeping'});active=@($script:ActiveNames)")
s = s.replace('$nextTick=(Get-Date).AddSeconds(1);try{Universal-Tick}', '$nextTick=(Get-Date).AddSeconds($(if($script:ActiveNames.Count){1}else{2}));try{Universal-Tick}')
s = s.replace('    Start-Sleep -Milliseconds 15', '    Start-Sleep -Milliseconds $(if($script:ActiveNames.Count){50}else{200})')
p.joinpath('backend.ps1').write_text(s, encoding='utf-8')
print('Reviewed backend extracted with sleep and host-lifecycle support')
