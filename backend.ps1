$ErrorActionPreference = 'Stop'
$Version = '1.3.1'
$Port = 47210
$StallSec = 120
$Workspace = 'C:\matcha\workspace'
if ($env:FH_ARG -and (Test-Path -LiteralPath $env:FH_ARG -PathType Container)) { $Workspace = [IO.Path]::GetFullPath($env:FH_ARG) }
$Token = [Guid]::NewGuid().ToString('N')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FHWin {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] struct LII { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LII p);
  public static uint IdleMs() {
    LII i = new LII();
    i.cbSize = (uint)Marshal.SizeOf(typeof(LII));
    if (!GetLastInputInfo(ref i)) return 0;
    return unchecked((uint)Environment.TickCount - i.dwTime);
  }
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
  public static bool Focus(IntPtr h) {
    for (int i = 0; i < 6; i++) {
      IntPtr fg = GetForegroundWindow();
      if (fg == h) return true;
      if (IsIconic(h)) ShowWindow(h, 9);
      uint me = GetCurrentThreadId();
      uint them = GetWindowThreadProcessId(fg, IntPtr.Zero);
      uint target = GetWindowThreadProcessId(h, IntPtr.Zero);
      AttachThreadInput(me, them, true); AttachThreadInput(me, target, true);
      try {
        if (i > 0) { keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero); }
        BringWindowToTop(h); SetForegroundWindow(h);
      } finally { AttachThreadInput(me, target, false); AttachThreadInput(me, them, false); }
      System.Threading.Thread.Sleep(60);
    }
    return GetForegroundWindow() == h;
  }
  public static void Tap(byte vk) {
    byte scan = (byte)MapVirtualKey(vk, 0);
    keybd_event(vk, scan, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(90);
    keybd_event(vk, scan, 2, UIntPtr.Zero);
  }
}
'@

# Screenshots of the Roblox window, and nothing else. PrintWindow with PW_RENDERFULLCONTENT asks
# Windows for Roblox's own picture (client area only), which works even behind other windows and
# never includes them. Only if that comes back black is the screen copied, and only when Roblox is
# the window in front AND no other window (an overlay, a popup, a notification) overlaps it.
$script:CanShot = $false
try {
  Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
public static class FHShot {
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);
  public static string Why = "";
  // True when a visible window of another program sits above Roblox over the given screen area.
  static bool Covered(IntPtr h, int l, int t, int r, int b) {
    uint mine; GetWindowThreadProcessId(h, out mine);
    for (IntPtr w = GetWindow(h, 3); w != IntPtr.Zero; w = GetWindow(w, 3)) { // 3 = GW_HWNDPREV, the next window up
      if (!IsWindowVisible(w)) continue;
      int cloaked = 0;
      if (DwmGetWindowAttribute(w, 14, out cloaked, 4) == 0 && cloaked != 0) continue; // 14 = DWMWA_CLOAKED
      uint pid; GetWindowThreadProcessId(w, out pid);
      if (pid == mine) continue;
      RECT x;
      if (!GetWindowRect(w, out x)) continue;
      if (x.R <= l || x.L >= r || x.B <= t || x.T >= b) continue;
      return true;
    }
    return false;
  }
  static bool Blank(Bitmap b) {
    for (int y = 1; y < 10; y++) for (int x = 1; x < 10; x++) {
      Color c = b.GetPixel(b.Width * x / 10, b.Height * y / 10);
      if (c.R > 8 || c.G > 8 || c.B > 8) return false;
    }
    return true;
  }
  public static byte[] Capture(IntPtr h, int maxWidth) {
    Why = "";
    if (IsIconic(h)) { Why = "Roblox is minimized"; return null; }
    RECT r;
    if (!GetClientRect(h, out r)) { Why = "no Roblox window"; return null; }
    int w = r.R - r.L, ht = r.B - r.T;
    if (w < 64 || ht < 64) { Why = "Roblox window too small"; return null; }
    Bitmap bmp = new Bitmap(w, ht, PixelFormat.Format32bppArgb);
    Bitmap small = null;
    try {
      using (Graphics g = Graphics.FromImage(bmp)) {
        IntPtr dc = g.GetHdc();
        bool ok = PrintWindow(h, dc, 3); // PW_CLIENTONLY | PW_RENDERFULLCONTENT
        g.ReleaseHdc(dc);
        if (!ok || Blank(bmp)) {
          if (GetForegroundWindow() != h) { Why = "Roblox came back black and isn't the window in front, so nothing was captured"; return null; }
          POINT p = new POINT();
          ClientToScreen(h, ref p);
          if (Covered(h, p.X, p.Y, p.X + w, p.Y + ht)) { Why = "another window is over Roblox, so nothing was captured"; return null; }
          g.CopyFromScreen(p.X, p.Y, 0, 0, new Size(w, ht));
        }
      }
      Bitmap outBmp = bmp;
      if (w > maxWidth) { small = new Bitmap(bmp, new Size(maxWidth, (int)((long)ht * maxWidth / w))); outBmp = small; }
      ImageCodecInfo jpg = null;
      foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders()) { if (c.MimeType == "image/jpeg") jpg = c; }
      EncoderParameters ep = new EncoderParameters(1);
      ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 82L);
      using (MemoryStream ms = new MemoryStream()) { outBmp.Save(ms, jpg, ep); return ms.ToArray(); }
    } catch (Exception e) { Why = e.Message; return null; }
    finally { bmp.Dispose(); if (small != null) small.Dispose(); }
  }
}
'@
  [void][FHWin]::SetProcessDPIAware()
  $script:CanShot = $true
} catch { }
$script:ShotWhy = ''
$script:LiveShot = $null
$script:LiveShotAt = [DateTime]::MinValue
$script:ShotNote = if ($script:CanShot) { 'ready (turn on "Screenshot in webhook" in FischHub)' } else { 'not available on this PC' }

$Html = @'
<!doctype html>
<html lang="en" data-theme="dark"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Matcha helper</title>
<style>
:root{color-scheme:dark;--page:#0d0d0d;--surface:#1a1a19;--raised:#242423;--ink:#fff;--muted:#a3a198;--border:#333;--accent:#3987e5}
:root[data-theme=light]{color-scheme:light;--page:#f9f9f7;--surface:#fcfcfb;--raised:#f0efea;--ink:#111;--muted:#65645e;--border:#ddd}
*{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);font:14px/1.5 'Segoe UI',sans-serif}header{border-bottom:1px solid var(--border);padding:16px 24px;display:flex;gap:16px;align-items:center;flex-wrap:wrap}h1{font-size:18px;margin:0}nav{display:flex;gap:8px;flex-wrap:wrap}main{max-width:1400px;margin:auto;padding:24px;display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:16px}.card{grid-column:span 6;background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:18px;min-width:0}.full{grid-column:span 12}h2{font-size:14px;margin:0 0 12px}button,input,select{font:inherit;color:inherit;background:var(--raised);border:1px solid var(--border);border-radius:8px;padding:7px 10px;max-width:100%}button{cursor:pointer}button[aria-pressed=true]{background:var(--accent);color:white}button:disabled,input:disabled,select:disabled{opacity:.45;cursor:default}label,.row{display:flex;justify-content:space-between;gap:12px;align-items:center;padding:9px 0;border-top:1px solid var(--border)}label span{overflow-wrap:anywhere}pre{white-space:pre-wrap;overflow-wrap:anywhere;max-height:330px;overflow:auto;margin:0}.muted{color:var(--muted)}#notice{margin-left:auto}#stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:12px}.stat{padding:12px;background:var(--raised);border-radius:8px}.stat b{display:block;font-size:24px}.actions{display:flex;gap:8px;flex-wrap:wrap}#shot{width:100%;max-height:540px;object-fit:contain;background:var(--page);border-radius:8px}.help{font-size:12px;color:var(--muted)}input[type=range]{width:180px}output{min-width:44px;text-align:right}.tools{display:flex;gap:10px;flex-wrap:wrap}@media(max-width:800px){.card{grid-column:span 12}main{padding:16px}header{padding:16px}.row{flex-wrap:wrap}.row>span{width:100%}input[type=range]{width:160px}}
</style>
<header><h1>Matcha helper</h1><nav id="tabs" aria-label="Scripts"></nav><button id="theme">Theme</button><span id="notice" class="muted" role="status">Connecting</span></header>
<main>
<section class="card"><h2 id="title">Waiting for a script</h2><pre id="status">Load an INSUI script with helper support.</pre><p class="help" id="age"></p></section>
<section class="card"><h2>Stats</h2><div id="stats"></div></section>
<section class="card"><h2>Controls</h2><div id="controls"></div><div class="actions" id="actions"></div></section>
<section class="card"><h2>Features for this script</h2><div id="features"></div><label><span>Background AFK interval (minutes)</span><input id="minutes" type="number" min="1" max="120" value="10"></label><p class="help">AFK waits until you have been idle for 3 seconds. It briefly focuses Roblox, taps O/I, then restores focus. Files and clipboard tools use this computer only.</p><p id="helperNote" class="help"></p></section>
<section class="card full"><h2>Roblox view</h2><img id="shot" alt="Roblox client window" hidden><p id="shotNote" class="help">Roblox only. Matcha's overlay may be invisible.</p><button id="view">Start live view</button></section>
<section class="card"><h2>Log (last 40)</h2><pre id="log"></pre></section>
<section class="card"><h2>Tools</h2><div class="tools"><button id="install">Install autoexec loader</button><button id="clipboard">Clipboard test</button></div><p id="toolNote" class="help"></p></section>
</main>
<script>
'use strict';
const TOKEN='__HELPER_TOKEN__', $=id=>document.getElementById(id), arr=x=>Array.isArray(x)?x:[];
let selected='', state=null, spec=null, stamp='', live=false, objectUrl=null, pending=new Map();
function el(tag,text){const e=document.createElement(tag);if(text!=null)e.textContent=text;return e}
function note(t){$('notice').textContent=t}
async function api(path,body){const r=await fetch(path,{method:body===undefined?'GET':'POST',headers:{'X-Helper-Token':TOKEN,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),cache:'no-store'});const j=await r.json();if(!r.ok)throw Error(j.error||'HTTP '+r.status);return j}
async function cmd(body,label){const c=arr(spec?.controls).find(c=>c.path===body.set);if(c?.risk&&body.value!==false&&!confirm(label+'?')){document.activeElement?.blur();await poll();return}try{const j=await api('/api/cmd',{script:selected,...body});pending.set(j.id,{label,t:Date.now()});note(label+': waiting for script')}catch(e){note(e.message)}}
function control(c){const row=el('label'), name=el('span',c.tab+' / '+c.section+' / '+c.name);row.className='row';row.append(name);let inp;
if(c.kind==='toggle'){inp=el('input');inp.type='checkbox';inp.checked=c.value===true;inp.onchange=()=>cmd({set:c.path,value:inp.checked},c.name)}
else if(c.kind==='dropdown'){inp=el('select');inp.multiple=!!c.multi;for(const v of arr(c.choices)){const o=el('option',String(v));o.value=String(v);o.selected=arr(c.value).includes(v);inp.append(o)}inp.onchange=()=>cmd({set:c.path,value:Array.from(inp.selectedOptions).map(o=>o.value)},c.name)}
else{inp=el('input');inp.type=c.kind==='slider'?'range':'text';inp.value=c.value??'';if(c.kind==='slider'){inp.min=c.min;inp.max=c.max;inp.step=c.step;const out=el('output',String(c.value)+' '+(c.suffix||''));inp.oninput=()=>out.textContent=inp.value+' '+(c.suffix||'');row.append(out)}inp.onchange=()=>cmd({set:c.path,value:c.kind==='slider'?Number(inp.value):inp.value},c.name)}
inp.setAttribute('aria-label',c.name);inp.dataset.path=c.path;inp.disabled=c.disabled===true;row.append(inp);return row}
async function choose(name){selected=name;stamp='';pending.clear();$('controls').replaceChildren();$('actions').replaceChildren();await poll()}
async function poll(){try{const list=await api('/api/scripts');if(!selected&&arr(list.scripts).length)selected=list.scripts[0].name;
$('tabs').replaceChildren(...arr(list.scripts).map(s=>{const b=el('button',s.name);b.setAttribute('aria-pressed',String(s.name===selected));b.onclick=()=>choose(s.name);return b}));
if(!selected){note('Waiting for INSUI scripts');return}const name=selected,j=await api('/api/state?script='+encodeURIComponent(name));if(name!==selected)return;state=j.state;const active=!!state&&!state.unloaded&&j.age<15;
$('title').textContent=name+' '+(state?.version||'');$('status').textContent=arr(state?.status?.lines).join('\n')||'Waiting for state';$('age').textContent=state?.unloaded?'Unloaded':j.age==null?'No state':Math.round(j.age)+' seconds since last update';$('log').textContent=arr(state?.log).join('\n');$('helperNote').textContent=j.note||'';
$('stats').replaceChildren(...Object.entries(state?.stats||{}).map(([k,v])=>{const d=el('div');d.className='stat';d.append(el('span',k),el('b',String(v)));return d}));
const ctl=await api('/api/controls?script='+encodeURIComponent(name));if(name!==selected)return;spec=ctl;
const key=JSON.stringify([arr(ctl.controls).map(({value,...c})=>c),ctl.actions]);if(key!==stamp){stamp=key;const groups=new Map();for(const c of arr(ctl.controls)){const group=c.tab+' / '+c.section;if(!groups.has(group))groups.set(group,[]);groups.get(group).push(c)}$('controls').replaceChildren(...Array.from(groups,([name,cs])=>{const d=el('details');d.open=cs[0].tab!=='Settings'&&cs[0].tab!=='gear';d.append(el('summary',name),...cs.map(control));return d}));$('actions').replaceChildren(...arr(ctl.actions).map(a=>{const b=el('button',a.label);b.onclick=()=>{if(!a.risk||confirm(a.label+'?'))cmd({do:a.id},a.label)};return b}))}
for(const inp of $('controls').querySelectorAll('input,select')){const c=arr(ctl.controls).find(c=>c.path===inp.dataset.path);inp.disabled=!active||!j.features.dashboard||c?.disabled===true;if(document.activeElement!==inp){const v=state?.rows?.[inp.dataset.path];if(inp.type==='checkbox')inp.checked=v===true;else if(inp.tagName==='SELECT'){for(const o of inp.options)o.selected=arr(v).includes(o.value)}else if(v!=null){inp.value=v;const out=inp.parentElement.querySelector('output');if(out)out.textContent=v+' '+(c?.suffix||'')}}}
for(const b of $('actions').querySelectorAll('button'))b.disabled=!active||!j.features.dashboard;
$('features').replaceChildren(...Object.entries(j.features||{}).map(([k,v])=>{const l=el('label'),i=el('input');i.type='checkbox';i.checked=!!v;i.setAttribute('aria-label',k);i.onchange=async()=>{try{await api('/api/config',{script:name,features:{[k]:i.checked}});note(k+': '+(i.checked?'on':'off'))}catch(e){note(e.message)}};l.append(el('span',k),i);return l}));
if(document.activeElement!==$('minutes'))$('minutes').value=list.afkMinutes||10;
for(const [id,p] of pending){const r=arr(state?.cmd?.results).find(r=>r.id===id);if(r){note(p.label+': '+r.msg);pending.delete(id)}else if(Date.now()-p.t>15000){note(p.label+': script did not acknowledge');pending.delete(id)}}if(!pending.size)note(active?'Live':state?.unloaded?'Unloaded':'Waiting for script');
}catch(e){note(e.message)}}
$('minutes').onchange=()=>api('/api/config',{afkMinutes:Number($('minutes').value)}).catch(e=>note(e.message));
$('theme').onclick=()=>{document.documentElement.dataset.theme=document.documentElement.dataset.theme==='dark'?'light':'dark';localStorage.setItem('matcha-theme',document.documentElement.dataset.theme)};document.documentElement.dataset.theme=localStorage.getItem('matcha-theme')||'dark';
$('install').onclick=async()=>{try{await api('/api/install-loader',{});$('toolNote').textContent='Autoexec loader installed'}catch(e){$('toolNote').textContent=e.message}};
$('clipboard').onclick=async()=>{try{const j=await api('/api/clipboard');$('toolNote').textContent='Clipboard readable ('+j.text.length+' characters). Contents are not shown.'}catch(e){$('toolNote').textContent=e.message}};
async function shot(){if(!live)return;try{const r=await fetch('/api/shot?w=1280',{headers:{'X-Helper-Token':TOKEN},cache:'no-store'});if((r.headers.get('Content-Type')||'').startsWith('image/')){const u=URL.createObjectURL(await r.blob());$('shot').src=u;$('shot').hidden=false;if(objectUrl)URL.revokeObjectURL(objectUrl);objectUrl=u;$('shotNote').textContent='Roblox client window only'}else{$('shot').hidden=true;$('shotNote').textContent=(await r.json()).why||'No picture'}}catch(e){$('shotNote').textContent=e.message}}
$('view').onclick=()=>{live=!live;$('view').textContent=live?'Pause live view':'Start live view';shot()};setInterval(()=>{if(!document.hidden)shot()},3000);setInterval(poll,2000);poll();
</script></html>

'@
function Say([string]$text, [string]$color = 'Gray') {
  Write-Host ("  " + (Get-Date -Format 'HH:mm:ss') + "  " + $text) -ForegroundColor $color
}

function Read-Shared([string]$path, [long]$from = 0) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
  try {
    $len = $fs.Length
    if ($from -gt $len) { $from = 0 }
    [void]$fs.Seek($from, [IO.SeekOrigin]::Begin)
    $buf = New-Object byte[] ($len - $from)
    $got = 0
    while ($got -lt $buf.Length) {
      $n = $fs.Read($buf, $got, $buf.Length - $got)
      if ($n -le 0) { break }
      $got += $n
    }
    return @{ bytes = $buf; size = $len; from = $from }
  } finally { $fs.Close() }
}

function Read-Json([string]$path) {
  $r = Read-Shared $path
  if (-not $r) { return $null }
  try { return ([Text.Encoding]::UTF8.GetString($r.bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json) } catch { return $null }
}

function Send([Net.Sockets.NetworkStream]$stream, [int]$status, [string]$type, [byte[]]$body, [string]$extra = '') {
  $reason = if ($status -lt 300) { 'OK' } elseif ($status -eq 404) { 'Not Found' } else { 'Error' }
  $head = "HTTP/1.1 $status $reason`r`nContent-Type: $type`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`n$($extra)Connection: close`r`n`r`n"
  $hb = [Text.Encoding]::ASCII.GetBytes($head)
  $stream.Write($hb, 0, $hb.Length)
  if ($body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
  $stream.Flush()
}

function Send-Text($stream, [int]$status, [string]$type, [string]$text, [string]$extra = '') {
  Send $stream $status $type ([Text.Encoding]::UTF8.GetBytes($text)) $extra
}

function Read-Line($stream) {
  $sb = New-Object System.Text.StringBuilder
  while ($true) {
    $b = $stream.ReadByte()
    if ($b -lt 0) { return $null }
    if ($b -eq 10) { break }
    if ($b -ne 13) { [void]$sb.Append([char]$b) }
    if ($sb.Length -gt 16384) { return $null }
  }
  return $sb.ToString()
}

function Read-Exact($stream, [int]$count) {
  $buf = New-Object byte[] $count
  $got = 0
  while ($got -lt $count) {
    $n = $stream.Read($buf, $got, $count - $got)
    if ($n -le 0) { break }
    $got += $n
  }
  if ($got -lt $count) {
    $part = New-Object byte[] $got
    [Array]::Copy($buf, $part, $got)
    return ,$part
  }
  return ,$buf
}

function Json-Str([string]$s) {
  return '"' + $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '\n') + '"'
}

function Get-Roblox {
  return Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

# A JPEG of the Roblox window, or $null with the reason in $script:ShotWhy. Webhook pictures also
# update the note the page shows ($script:ShotNote); the page's own live view doesn't.
function Take-Shot([int]$maxWidth = 1280, [bool]$forWebhook = $true) {
  $img = $null
  if (-not $script:CanShot) { $script:ShotWhy = 'screenshots are not available on this PC' }
  else {
    $rb = Get-Roblox
    if (-not $rb) { $script:ShotWhy = 'no Roblox window' }
    else {
      $img = [FHShot]::Capture($rb.MainWindowHandle, $maxWidth)
      if (-not $img) { $script:ShotWhy = [FHShot]::Why }
    }
  }
  if ($forWebhook) {
    $script:ShotNote = if ($img) { 'last one ' + (Get-Date -Format 'HH:mm:ss') + ' (' + [int]($img.Length / 1024) + ' KB)' }
      elseif ($script:CanShot) { 'skipped - ' + $script:ShotWhy } else { 'not available on this PC' }
  }
  if ($img) { return ,$img }
  return $null
}

# Sends a webhook request to discord. With a screenshot the body becomes multipart: the JSON as
# payload_json (its first embed shows the picture) plus the file. An edit without a picture
# clears the previous one (attachments: []).
function Send-Discord([string]$method, [string]$url, [string]$json, $img, [bool]$isEdit) {
  if ($img) {
    $json = ([regex]'"embeds"\s*:\s*\[\s*\{').Replace($json, '$0"image":{"url":"attachment://fischhub.jpg"},', 1)
    $json = '{"attachments":[{"id":0,"filename":"fischhub.jpg"}],' + $json.TrimStart().Substring(1)
    $boundary = '----fischhub' + [Guid]::NewGuid().ToString('N')
    $ms = New-Object IO.MemoryStream
    $head = [Text.Encoding]::UTF8.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"payload_json`"`r`nContent-Type: application/json`r`n`r`n$json`r`n--$boundary`r`nContent-Disposition: form-data; name=`"files[0]`"; filename=`"fischhub.jpg`"`r`nContent-Type: image/jpeg`r`n`r`n")
    $tail = [Text.Encoding]::ASCII.GetBytes("`r`n--$boundary--`r`n")
    $ms.Write($head, 0, $head.Length)
    $ms.Write($img, 0, $img.Length)
    $ms.Write($tail, 0, $tail.Length)
    $body = $ms.ToArray()
    $type = "multipart/form-data; boundary=$boundary"
  } else {
    if ($isEdit) { $json = '{"attachments":[],' + $json.TrimStart().Substring(1) }
    $body = [Text.Encoding]::UTF8.GetBytes($json)
    $type = 'application/json'
  }
  $req = [System.Net.HttpWebRequest]::Create($url)
  $req.Method = $method
  $req.ContentType = $type
  $req.UserAgent = 'FischHub-helper (https://github.com/adorablewhale/fischhub, 2)'
  $req.Timeout = 20000
  $req.ContentLength = $body.Length
  $rs = $req.GetRequestStream()
  $rs.Write($body, 0, $body.Length)
  $rs.Close()
  $resp = $null
  try {
    $resp = $req.GetResponse()
  } catch {
    $ex = $_.Exception
    while ($ex -and -not ($ex -is [System.Net.WebException])) { $ex = $ex.InnerException }
    if ($ex) { $resp = $ex.Response }
  }
  if (-not $resp) { return @{ status = 502; text = '{"message":"the helper could not reach discord"}' } }
  $status = [int]$resp.StatusCode
  $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
  $text = $reader.ReadToEnd()
  $resp.Close()
  return @{ status = $status; text = $text }
}

# FischHub's webhook requests: an edit (.../messages/<id>, sent on as PATCH) or a new message
# (sent on as POST ?wait=true). ?shot=1 adds a screenshot.
function Relay($stream, [string]$path, [string]$query, [byte[]]$body) {
  $isEdit = $path -match '^/api/webhooks/\d+/[A-Za-z0-9_\-]+/messages/\d+$'
  $isNew = $path -match '^/api/webhooks/\d+/[A-Za-z0-9_\-]+$'
  if (-not ($isEdit -or $isNew) -or $body.Length -lt 2) {
    Send-Text $stream 404 'application/json' '{"message":"the FischHub helper only forwards webhook messages"}'
    return
  }
  $img = $null
  if ($query -match '(^|&)shot=1') { $img = Take-Shot }
  $json = [Text.Encoding]::UTF8.GetString($body)
  $url = 'https://discord.com' + $path + $(if ($isNew) { '?wait=true' } else { '' })
  $r = Send-Discord $(if ($isEdit) { 'PATCH' } else { 'POST' }) $url $json $img ([bool]$isEdit)
  Send-Text $stream $r.status 'application/json; charset=utf-8' $r.text
  $what = if ($isEdit) { 'edited message' } else { 'posted message' }
  if ($img) { $what += ' + screenshot' }
  Say ("$what -> discord " + $r.status) $(if ($r.status -lt 300) { 'Green' } else { 'Yellow' })
}

# Universal protocol. Native capture, Discord relay and HTTP readers below are retained from FischHub.
$Root = Join-Path $Workspace 'INSUI\helper'
$ScriptsRoot = Join-Path $Root 'scripts'
$Utf8 = New-Object Text.UTF8Encoding $false
$script:Notes = @{}
$script:Watches = @{}
$script:LastHelp = [DateTime]::MinValue
$script:BackgroundAt = Get-Date
$script:CmdLast = [long]0
$ConfigFile = Join-Path $Root 'config.json'
function Write-Json($path, $value) { [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $value -Depth 24 -Compress), $Utf8) }
function Read-Map($path) {
  $j = Read-Json $path
  $m = @{}
  if ($j) { foreach ($p in $j.PSObject.Properties) { $m[$p.Name] = $p.Value } }
  return $m
}
# ---- Matcha relaunch after a rejoin ---------------------------------------------------------------
# Matcha's binaries are packed (no version info, no readable strings), so it is recognised by how it
# runs: app.exe / loader.exe whose folder holds Matcha's imgui.ini or whose path says matcha, plus the
# process serving Matcha's MCP port if any. The path is learned while a script is live (so Matcha is
# certainly running) and saved, so a rejoin can start the same Matcha again once Roblox is back.
$MatchaFile = Join-Path $Root 'matcha.json'
$script:MatchaSeenAt = [datetime]::MinValue
$script:MatchaRelaunch = $null
function Find-Matcha {
  $mcp = $null
  try { $mcp = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction Stop | Select-Object -First 1 -ExpandProperty OwningProcess } catch {}
  $best = $null
  foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='app.exe' OR Name='loader.exe' OR Name='matcha.exe'" -ErrorAction SilentlyContinue)) {
    $path = [string]$p.ExecutablePath
    if (-not $path) { continue }   # an elevated (kernel) Matcha hides its path from this non-admin helper
    $score = 0
    if ($path -match '(?i)matcha') { $score += 2 }
    if (Test-Path -LiteralPath (Join-Path (Split-Path $path) 'imgui.ini')) { $score += 1 }
    if ($mcp -and [int]$p.ProcessId -eq [int]$mcp) { $score += 3 }
    if ($score -ge 2 -and (-not $best -or $score -gt $best.score)) { $best = @{path=$path; score=$score; pid=[int]$p.ProcessId} }
  }
  if (-not $best) { return $null }
  $dir = Split-Path $best.path
  $mode = if ($best.path -match '(?i)\\usermode\\') { 'usermode' } elseif (Test-Path -LiteralPath (Join-Path $dir 'map.exe')) { 'kernel' } else { 'unknown' }
  return @{path=$best.path; mode=$mode; pid=$best.pid}
}
function Remember-Matcha {
  if (((Get-Date) - $script:MatchaSeenAt).TotalSeconds -lt 60) { return }
  $script:MatchaSeenAt = Get-Date
  $m = Find-Matcha
  if ($m) { Write-Json $MatchaFile @{path=$m.path; mode=$m.mode; seen=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()} }
}
function Saved-Matcha {
  $m = Find-Matcha
  if ($m) { return $m }
  $saved = Read-Json $MatchaFile
  if ($saved -and $saved.path -and (Test-Path -LiteralPath ([string]$saved.path))) { return @{path=[string]$saved.path; mode=[string]$saved.mode} }
  return $null
}
# One step per main-loop tick: wait for the new Roblox window, give the game time to load, then start Matcha.
function Relaunch-Step {
  $r = $script:MatchaRelaunch
  if (-not $r) { return }
  if ((Get-Date) -gt $r.deadline) { $script:MatchaRelaunch = $null; Say 'matcha relaunch gave up: roblox did not come back' 'Yellow'; return }
  if (-not (Get-Roblox)) { $r.robloxAt = $null; return }
  if (-not $r.robloxAt) { $r.robloxAt = Get-Date; return }
  if (((Get-Date) - $r.robloxAt).TotalSeconds -lt 20) { return }
  $script:MatchaRelaunch = $null
  if (Find-Matcha) { Say 'matcha is already running' 'Gray'; return }
  try { Start-Process -FilePath $r.path -WorkingDirectory (Split-Path $r.path); Say ('started matcha again (' + $r.mode + ')') 'Cyan' }
  catch { Say ('could not start matcha (' + $r.mode + '): ' + $_.Exception.Message) 'Yellow' }
}
function Get-Config {
  $c = Read-Map $ConfigFile
  $s = @{}
  if ($c.scripts) { foreach ($p in $c.scripts.PSObject.Properties) { $s[$p.Name] = $p.Value } }
  $c.scripts = $s
  if (-not $c.afkMinutes) { $c.afkMinutes = 10 }
  return $c
}
function Script-Dir([string]$name) {
  if ($name -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'invalid script name' }
  $d = Join-Path $ScriptsRoot $name
  if (Test-Path -LiteralPath $d) { Assert-NoLink $d }
  return $d
}
function Assert-NoLink([string]$path) {
  $p = $path
  while ($p) {
    if (Test-Path -LiteralPath $p) {
      if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'junctions and symlinks are not allowed' }
    }
    $parent = Split-Path $p
    if ($parent -eq $p) { break }
    $p = $parent
  }
}
function Features($name, $state) {
  $out = @{ dashboard = $true; webhook = $false; watchdog = $false; afk = $false; files = $false }
  foreach ($k in @($out.Keys)) {
    if ($state.features -and $state.features.PSObject.Properties[$k]) { $out[$k] = $state.features.$k -eq $true }
  }
  $cfg = Get-Config
  $saved = $cfg.scripts[$name]
  foreach ($k in @($out.Keys)) { if ($saved -and $saved.PSObject.Properties[$k]) { $out[$k] = $saved.$k -eq $true } }
  return $out
}
function Get-Scripts {
  if (-not (Test-Path -LiteralPath $ScriptsRoot)) { return @() }
  return @(Get-ChildItem -LiteralPath $ScriptsRoot -Directory | Where-Object { $_.Name -match '^[A-Za-z0-9_-]{1,64}$' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object { $_.Name })
}
function Script-State($name) {
  $file = Join-Path (Script-Dir $name) 'state.json'
  $st = Read-Json $file
  $age = if ($st) { [Math]::Max(0, ((Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $file).LastWriteTimeUtc).TotalSeconds) } else { $null }
  return @{ state = $st; age = $age; features = (Features $name $st); note = $script:Notes[$name] }
}
function Is-Local($headers) {
  $h = [string]$headers['host']
  if ($h -notmatch "^(127\.0\.0\.1|localhost):$Port`$") { return $false }
  $o = [string]$headers['origin']
  if ($o -and $o -notmatch "^http://(127\.0\.0\.1|localhost):$Port`$") { return $false }
  if ($headers['sec-fetch-site'] -eq 'cross-site') { return $false }
  return $true
}
function Has-Key($headers) { return (Is-Local $headers) -and ([string]$headers['x-helper-token'] -ceq $Token) }
function Reply($stream, $status, $value) { Send-Text $stream $status 'application/json; charset=utf-8' (ConvertTo-Json -InputObject $value -Depth 24 -Compress) }
function Query-Value($query, $key) {
  foreach ($p in $query.Split('&')) { $kv = $p.Split('=',2); if ($kv.Length -eq 2 -and $kv[0] -eq $key) { return [Uri]::UnescapeDataString($kv[1].Replace('+',' ')) } }
  return ''
}
function Add-UniversalCommand($stream, $j) {
  $name = [string]$j.script
  $d = Script-Dir $name
  $s = Script-State $name
  if (-not $s.state -or $s.age -ge 15 -or $s.state.unloaded -or -not $s.features.dashboard) { Reply $stream 409 @{error='script dashboard is not active'}; return }
  $ctl = Read-Json (Join-Path $d 'controls.json')
  $c = @{id = ''}
  if ($j.set -is [string]) {
    $row = @($ctl.controls | Where-Object { $_.path -ceq $j.set })
    if ($row.Count -ne 1 -or $row[0].disabled) { throw 'unknown or disabled control' }
    $c.set = $j.set; $c.value = $j.value
  } elseif ($j.do -is [string] -and @($ctl.actions | Where-Object { $_.id -ceq $j.do }).Count -eq 1) { $c['do'] = $j.do }
  else { throw 'unknown command' }
  $script:CmdLast = [Math]::Max($script:CmdLast + 1, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
  $c.id = [string]$script:CmdLast; $c.t = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $file = Join-Path $d 'commands.txt'
  Assert-NoLink $file
  # Bound the queue by acks and age. The client also validates every value and skips the first read.
  $keep = @()
  $r = Read-Shared $file
  if ($r) { foreach ($line in ([Text.Encoding]::UTF8.GetString($r.bytes).Split("`n"))) { try { $old = $line | ConvertFrom-Json; if ([long]$old.id -gt [long]$s.state.cmd.ack -and $c.t - [long]$old.t -lt 120) { $keep += $line } } catch {} } }
  if ($keep.Count -ge 200) { throw 'command queue full' }
  $keep += (ConvertTo-Json -InputObject $c -Depth 10 -Compress)
  [IO.File]::WriteAllText($file, ($keep -join "`n") + "`n", $Utf8)
  Reply $stream 200 @{id=$c.id}
}
function Safe-Write($path, $text) {
  if ($path -notmatch '^[A-Za-z]:[\\/]') { throw 'absolute path required' }
  if ($path.Substring(2).Contains(':')) { throw 'alternate data streams are not allowed' }
  $full = [IO.Path]::GetFullPath($path)
  $allowed = $false
  foreach ($base in @('C:\matcha\autoexec','C:\matcha\workspace')) {
    if ($full.StartsWith($base + '\',[StringComparison]::OrdinalIgnoreCase)) { $allowed = $true }
  }
  if (-not $allowed) { throw 'path must be under Matcha autoexec or workspace' }
  Assert-NoLink $full
  [void][IO.Directory]::CreateDirectory((Split-Path $full))
  [IO.File]::WriteAllText($full, $text, $Utf8)
}
function Proxy-Http($j) {
  $uri = $null
  if (-not [Uri]::TryCreate([string]$j.url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo) { throw 'http/https URL required' }
  $method = [string]$j.method
  if ($method -notmatch '^[A-Z]{3,12}$') { throw 'invalid HTTP method' }
  $req = [Net.HttpWebRequest]::Create($uri); $req.Method=$method; $req.Timeout=15000; $req.AllowAutoRedirect=$false
  if ($j.headers) { foreach ($p in $j.headers.PSObject.Properties) { if ($p.Name -ieq 'Content-Type') {$req.ContentType=[string]$p.Value} elseif ($p.Name -ieq 'Accept') {$req.Accept=[string]$p.Value} else {$req.Headers[$p.Name]=[string]$p.Value} } }
  if ($null -ne $j.body -and $method -notin @('GET','HEAD')) { $b=[Text.Encoding]::UTF8.GetBytes([string]$j.body);$req.ContentLength=$b.Length;$s=$req.GetRequestStream();try{$s.Write($b,0,$b.Length)}finally{$s.Close()} }
  $resp=$null
  try { $resp=$req.GetResponse() } catch { $e=$_.Exception;while($e -and -not ($e -is [Net.WebException])){$e=$e.InnerException};if($e){$resp=$e.Response} }
  if (-not $resp) { return @{status=502;body='request failed';headers=@{}} }
  try {
    $rs=$resp.GetResponseStream();$ms=New-Object IO.MemoryStream;$buffer=New-Object byte[] 8192
    while(($n=$rs.Read($buffer,0,$buffer.Length)) -gt 0){if($ms.Length+$n -gt 1048576){throw 'response too large'};$ms.Write($buffer,0,$n)}
    $h=@{};foreach($k in $resp.Headers.AllKeys){$h[$k]=$resp.Headers[$k]}
    return @{status=[int]$resp.StatusCode;headers=$h;body=[Text.Encoding]::UTF8.GetString($ms.ToArray())}
  } finally {$resp.Close()}
}
$script:ActiveNames = @()
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
  if ($script:ActiveNames.Count) { try { Remember-Matcha } catch {} }
  # No process scan, focus, keyboard input or automatic screenshot while sleeping.
  $rb = if ($needsRoblox) { Get-Roblox } else { $null }
  if ($rb -and [FHWin]::GetForegroundWindow() -eq $rb.MainWindowHandle) { $script:BackgroundAt = Get-Date }
  foreach ($name in $states.Keys) {
    $s = $states[$name]; $st=$s.state; $f=$s.features
    if (-not $st) { continue }
    if (-not $script:Watches.ContainsKey($name)) { $script:Watches[$name]=@{alerted=$false;stamp='';note=''} }
    $w=$script:Watches[$name]
    if ($w.stamp -ne [string]$st.t) { $w.alerted=$false;$w.stamp=[string]$st.t }
    if ($f.watchdog -and $f.webhook -and $st.watch.armed -and -not $st.unloaded -and $s.age -ge $StallSec -and -not $w.alerted) {
      $w.alerted=$true
      $hook = Read-Json (Join-Path (Script-Dir $name) 'webhook.json')
      if ($hook -and $hook.alert -ne $false -and $hook.url -match '^https://discord\.com/api/webhooks/\d+/[A-Za-z0-9_-]+$') {
        $mention=if($hook.ping -eq 'everyone'){'@everyone'}elseif([string]$hook.ping -match '^\d+$'){'<@'+$hook.ping+'>'}else{''}
        $json=ConvertTo-Json -Depth 8 -Compress -InputObject @{username=$name.ToLower();content=$mention;embeds=@(@{title=$name.ToLower()+' stopped responding';color=65793;description=([string]$st.watch.label).ToLower()+' - no state updates for '+[int]$s.age+' seconds'})}
        $img=$null;if($hook.shot){$img=Take-Shot}
        $r=Send-Discord 'POST' ($hook.url+'?wait=true') $json $img $false
        $w.note='watchdog delivery: '+$r.status;Say ($name+' '+$w.note)
      } else { $w.note='watchdog: no enabled webhook configured' }
    }
    $script:Notes[$name]=(@($w.note, $w.afkNote) | Where-Object {$_}) -join '; '
    if (-not $f.afk -or $st.unloaded -or $s.age -ge 15 -or -not $rb) { continue }
    $minutes=(Get-Config).afkMinutes
    $generic=((Get-Date)-$script:BackgroundAt).TotalMinutes -ge $minutes
    if (-not $st.afk.needFocus -and -not $generic) { continue }
    if (((Get-Date)-$script:LastHelp).TotalSeconds -lt 60 -or [FHWin]::IdleMs() -lt 3000) { continue }
    $h=$rb.MainWindowHandle;$prev=[FHWin]::GetForegroundWindow();$script:LastHelp=Get-Date
    try {
      if (-not [FHWin]::Focus($h)) {$w.afkNote='AFK: Windows refused focus';continue}
      Start-Sleep -Milliseconds 300
      if ([FHWin]::GetForegroundWindow() -ne $h) {continue}
      [FHWin]::Tap(0x4F);Start-Sleep -Milliseconds 150
      if ([FHWin]::GetForegroundWindow() -eq $h) {[FHWin]::Tap(0x49)}
      Start-Sleep -Milliseconds 250
      $script:BackgroundAt=Get-Date;$w.afkNote='AFK: O/I sent at '+(Get-Date -Format HH:mm:ss)
    } finally { if ($prev -ne [IntPtr]::Zero -and $prev -ne $h) {[void][FHWin]::Focus($prev)} }
  }
}
function Handle-Client($client) {
  if (-not [Net.IPAddress]::IsLoopback($client.Client.RemoteEndPoint.Address)) { return }
  $client.ReceiveTimeout=3000;$client.SendTimeout=3000;$stream=$client.GetStream()
  $line=Read-Line $stream;if(-not $line){return}
  $headers=@{};$bytes=0
  while($true){$h=Read-Line $stream;if($null -eq $h -or $h -eq ''){break};$bytes+=$h.Length;if($bytes -gt 65536){throw 'headers too large'};$i=$h.IndexOf(':');if($i -gt 0){$key=$h.Substring(0,$i).Trim().ToLower();if($headers.ContainsKey($key)){throw 'duplicate header'};$headers[$key]=$h.Substring($i+1).Trim()}}
  if($headers['expect'] -eq '100-continue'){$b=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 100 Continue`r`n`r`n");$stream.Write($b,0,$b.Length)}
  $body=New-Object byte[] 0
  if($headers['transfer-encoding'] -eq 'chunked') {
    $ms=New-Object IO.MemoryStream
    while($true){$l=Read-Line $stream;if($null -eq $l){throw 'incomplete chunk'};$n=[Convert]::ToInt32($l.Split(';')[0].Trim(),16);if($n -lt 0 -or $ms.Length+$n -gt 1048576){throw 'body too large'};if($n -eq 0){do{$trailer=Read-Line $stream;if($null -eq $trailer){throw 'incomplete trailer'}}while($trailer -ne '');break};$b=Read-Exact $stream $n;if($b.Length -ne $n){throw 'incomplete chunk'};$ms.Write($b,0,$b.Length);[void](Read-Line $stream)}
    $body=$ms.ToArray()
  } elseif($headers['content-length']){$n=[int]$headers['content-length'];if($n -lt 0 -or $n -gt 1048576){throw 'body too large'};$body=Read-Exact $stream $n;if($body.Length -ne $n){throw 'incomplete body'}}
  if(-not (Is-Local $headers)){Reply $stream 403 @{error='localhost Host/Origin required'};return}
  $p=$line.Split(' ');if($p.Length -ne 3){throw 'bad request'};$method=$p[0];$target=$p[1];$path=($target -split '\?')[0];$query=if($target.Contains('?')){$target.Substring($target.IndexOf('?')+1)}else{''}
  if($method -eq 'GET' -and $path -eq '/'){Send $stream 200 'text/html; charset=utf-8' $HtmlBytes "X-Frame-Options: DENY`r`nReferrer-Policy: no-referrer`r`nContent-Security-Policy: default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' blob:; frame-ancestors 'none'`r`n";return}
  if($method -eq 'GET' -and $path -eq '/ping'){Reply $stream 200 @{relay='fischhub-relay';helper='matcha-helper';version=$Version};return}
  # Legacy FischHub relay keeps its exact public contract, with Host/Origin checks added before all POSTs.
  if($method -eq 'POST' -and $path.StartsWith('/api/webhooks/')){Relay $stream $path $query $body;return}
  if($path -notin @('/api/scripts','/api/state','/api/controls') -and -not (Has-Key $headers)){Reply $stream 403 @{error='helper token required'};return}
  try {
    $j=$null;if($body.Length){$j=[Text.Encoding]::UTF8.GetString($body)|ConvertFrom-Json}
    if($method -eq 'GET') {
      switch($path){
        '/api/scripts' {Reply $stream 200 @{scripts=@(Get-Scripts|ForEach-Object{@{name=$_}});afkMinutes=(Get-Config).afkMinutes};return}
        '/api/state' {$name=Query-Value $query 'script';$s=Script-State $name;if(-not $s.features.dashboard){$s.state=$null};Reply $stream 200 $s;return}
        '/api/controls' {$name=Query-Value $query 'script';$s=Script-State $name;$ctl=if($s.features.dashboard){Read-Json (Join-Path (Script-Dir $name) 'controls.json')}else{@{controls=@();actions=@()}};Reply $stream 200 $ctl;return}
        '/api/clipboard' {Add-Type -AssemblyName System.Windows.Forms;Reply $stream 200 @{text=[Windows.Forms.Clipboard]::GetText()};return}
        '/api/shot' {$w=1280;$v=Query-Value $query 'w';if($v -match '^\d+$'){$w=[Math]::Max(320,[Math]::Min(1920,[int]$v))};$img=Take-Shot $w $false;if($img){Send $stream 200 'image/jpeg' $img}else{Reply $stream 200 @{why=$script:ShotWhy}};return}
      }
    } elseif($method -eq 'POST') {
      switch($path){
        '/api/cmd' {Add-UniversalCommand $stream $j;return}
        '/api/config' {
          $cfg=Get-Config
          if($null -ne $j.afkMinutes){if($j.afkMinutes -lt 1 -or $j.afkMinutes -gt 120){throw 'AFK interval must be 1-120 minutes'};$cfg.afkMinutes=[double]$j.afkMinutes}
          if($j.script){$name=[string]$j.script;[void](Script-Dir $name);$f=Features $name (Script-State $name).state;foreach($p in $j.features.PSObject.Properties){if($p.Name -notin @('dashboard','webhook','watchdog','afk','files') -or $p.Value -isnot [bool]){throw 'invalid feature switch'};$f[$p.Name]=$p.Value};$cfg.scripts[$name]=$f}
          Write-Json $ConfigFile $cfg;Reply $stream 200 @{ok=$true};return
        }
        '/api/shot-upload' {
          # A picture of the Roblox window, sent ONLY to the fixed dashboard origin with this
          # installation's key (from the local script); never to a caller-chosen address.
          if([string]$j.key -notmatch '^[a-f0-9]{64}$' -or [string]$j.name -notmatch '^[A-Za-z0-9_-]{1,64}$'){throw 'script name and dashboard key required'}
          $img=Take-Shot 1280 $true
          if(-not $img){Reply $stream 200 @{ok=$false;why=$script:ShotWhy};return}
          $req=[Net.HttpWebRequest]::Create('https://adorablewhale.world/api/v1/shot?name='+[Uri]::EscapeDataString([string]$j.name))
          $req.Method='POST';$req.ContentType='image/jpeg';$req.UserAgent='matcha-helper/'+$Version;$req.Timeout=15000;$req.AllowAutoRedirect=$false
          $req.Headers['Authorization']='Bearer '+[string]$j.key;$req.ContentLength=$img.Length
          $out=$req.GetRequestStream();$out.Write($img,0,$img.Length);$out.Close()
          try{$resp=$req.GetResponse();$code=[int]$resp.StatusCode;$resp.Close()}catch [Net.WebException]{$code=if($_.Exception.Response){[int]$_.Exception.Response.StatusCode}else{0}}
          Reply $stream 200 @{ok=($code -eq 200);status=$code;kb=[int]($img.Length/1024)};return
        }
        '/api/rejoin' {
          # Relaunch Roblox into the user's private server after a kick. Only strict link codes are accepted.
          $uri=$null
          if([string]$j.linkCode -match '^[A-Za-z0-9_-]{8,80}$' -and [string]$j.placeId -match '^\d{1,20}$'){$uri='roblox://experiences/start?placeId='+$j.placeId+'&linkCode='+$j.linkCode}
          elseif([string]$j.shareCode -match '^[A-Za-z0-9_-]{8,80}$'){$uri='roblox://navigation/share_links?code='+$j.shareCode+'&type=Server'}
          elseif([string]$j.placeId -match '^\d{1,20}$'){$uri='roblox://experiences/start?placeId='+$j.placeId}   # no link: any public server
          else{throw 'a place id or private server link code is required'}
          $m=Saved-Matcha
          if($m){$script:MatchaRelaunch=@{path=[string]$m.path;mode=[string]$m.mode;deadline=(Get-Date).AddMinutes(4);robloxAt=$null}}
          # close the kicked client first so the relaunch starts clean
          Get-Process RobloxPlayerBeta -ErrorAction SilentlyContinue|ForEach-Object{try{[void]$_.CloseMainWindow();if(-not $_.WaitForExit(4000)){$_.Kill()}}catch{}}
          Start-Sleep -Milliseconds 1500
          Start-Process -FilePath $uri
          Say 'rejoining the private server' 'Cyan'
          Reply $stream 200 @{ok=$true;matcha=$(if($m){[string]$m.mode}else{'not found - start matcha yourself'})};return
        }
        '/api/http' {Reply $stream 200 (Proxy-Http $j);return}
        '/api/open' {$u=$null;if(-not [Uri]::TryCreate([string]$j.url,[UriKind]::Absolute,[ref]$u) -or $u.Scheme -notin @('http','https') -or $u.UserInfo){throw 'http/https URL required'};Start-Process -FilePath $u.AbsoluteUri;Reply $stream 200 @{ok=$true};return}
        '/api/file' {if($j.script -and -not (Script-State $j.script).features.files){throw 'files feature is off'};if($j.text -isnot [string]){throw 'text required'};Safe-Write ([string]$j.path) $j.text;Reply $stream 200 @{ok=$true};return}
        '/api/install-loader' {$src=Join-Path $Workspace 'INSUI\loader.lua';if(-not(Test-Path -LiteralPath $src)){throw 'INSUI/loader.lua missing'};Assert-NoLink $src;Safe-Write 'C:\matcha\autoexec\insui_loader.lua' ([IO.File]::ReadAllText($src));Reply $stream 200 @{ok=$true};return}
      }
    }
    Reply $stream 404 @{error='unknown route or method'}
  } catch { Reply $stream 400 @{error=$_.Exception.Message} }
}
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$Port)
try {$listener.Start()}catch{Write-Host 'Port 47210 is in use. Close the other helper first.';exit 1}
try {
  Assert-NoLink $Root
  [void][IO.Directory]::CreateDirectory($ScriptsRoot)
  [IO.File]::WriteAllText((Join-Path $Root 'token.txt'),$Token,$Utf8)
  $HtmlBytes=[Text.Encoding]::UTF8.GetBytes($Html.Replace('__HELPER_TOKEN__',$Token))
  $pending=New-Object Collections.ArrayList;$nextBeat=Get-Date;$nextTick=Get-Date
  Write-Host 'Matcha helper - http://127.0.0.1:47210 - close this window to stop.'
  if(-not $env:MATCHA_HELPER_NO_BROWSER){Start-Process "http://127.0.0.1:$Port/"}
  while($true){
    # An orphaned backend stops even if the tray host crashes or is force-closed.
    if($env:MATCHA_HELPER_HOST_PID -and (Get-Date) -ge $nextTick) {
      try {$owner=[Diagnostics.Process]::GetProcessById([int]$env:MATCHA_HELPER_HOST_PID)} catch {break}
      try {if($owner.StartTime.ToUniversalTime().Ticks -ne [long]$env:MATCHA_HELPER_HOST_CREATED){break}} finally {$owner.Dispose()}
    }
    if((Get-Date) -ge $nextBeat){$nextBeat=(Get-Date).AddSeconds(2);Write-Json (Join-Path $Root 'helper.json') @{version=$Version;port=$Port;pid=$PID;beat=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();mode=$(if($script:ActiveNames.Count){'awake'}else{'sleeping'});active=@($script:ActiveNames)}}
    while($listener.Pending()){[void]$pending.Add(@{c=$listener.AcceptTcpClient();at=Get-Date})}
    for($i=$pending.Count-1;$i -ge 0;$i--){$p=$pending[$i];if($p.c.Available -gt 0){$pending.RemoveAt($i);try{Handle-Client $p.c}catch{Say 'request rejected' 'Yellow'}finally{$p.c.Close()}}elseif(((Get-Date)-$p.at).TotalSeconds -gt 5){$pending.RemoveAt($i);$p.c.Close()}}
    if((Get-Date) -ge $nextTick){$nextTick=(Get-Date).AddSeconds($(if($script:ActiveNames.Count){1}else{2}));try{Universal-Tick}catch{Say 'helper tick failed' 'Yellow'};try{Relaunch-Step}catch{Say 'matcha relaunch failed' 'Yellow'}}
    Start-Sleep -Milliseconds $(if($script:ActiveNames.Count){50}else{200})
  }
} finally {
  $listener.Stop();foreach($p in $pending){$p.c.Close()}
  Write-Json (Join-Path $Root 'helper.json') @{version=$Version;port=$Port;pid=$PID;beat=0}
}
