MATCHA HELPER 1.3.0

Download and open installer.exe, then choose "install and open". No unzip step or administrator rights.
Choose whether it starts at login. Search "Matcha helper" in Windows to open it again.
The ZIP remains available: matcha-helper.exe also offers "install and start".
You can also choose "run once" without adding a login shortcut.
The installed app starts in the system tray at Windows login when that option is enabled.

AUTOMATIC UPDATES
The installed app checks the fixed adorablewhale/matcha-helper GitHub repository
on startup and every four hours for a stable release. Checks do not send script
data or credentials. A pinned RSA key verifies the release manifest; a SHA-256
digest verifies the ZIP before extraction. Unexpected hosts/files, stale metadata,
wrong versions and altered packages are refused. Normal HTTPS verification stays on.
An update waits until scripts sleep, then restarts the helper in the tray. Workspace,
startup preference and script settings are preserved. Pause delays installation.
Turn automatic updates off in the helper window, or use "check updates" manually.
If the network or validation fails, the current helper keeps working.

Double-click the mint whale icon to open its status window. Right-click to pause,
resume, view the source, open your dashboard, quit, or uninstall. Closing the
status window leaves the tray app running. Quit stops the helper immediately.

It wakes automatically while an accepted script is sending fresh local state.
When every script unloads or stops checking in, it sleeps: no automatic focus,
keyboard input or screenshots. The lightweight localhost service stays available.
Local watchdog delivery can send its one configured disconnect alert after a stall.
Pause stops all helper features; scripts and cloud dashboards can continue.

Only the features enabled in your script/helper settings are used. Screenshots
capture the Roblox window. The helper uses localhost port 47210 and a local token.
It does not upload usage tracking, credentials, school data or hardware IDs.
Cloud dashboards and reporting are controlled separately in the scripts.

Version 1.3.0 can upload a requested Roblox-window screenshot to the fixed
adorablewhale.world dashboard, for the stats message or your Discord /screenshot
reply. The installation key comes from the local script and is not logged or saved
by this operation. It does not capture your desktop or other programs; if safe
capture is unavailable, it reports why. No caller-chosen upload address is allowed.
Private-server rejoin is optional and closes/relaunches Roblox using your locally
configured server link. Turning the script's automatic rejoin off cancels its
pending kick retry; the helper itself does not decide when to reconnect.
Use "auto rejoin after a kick" in the helper window or tray menu to change the
active script's setting. It stays in sync with the script, website and Discord.
The switch is disabled when no supported script is active or local controls are
off. It does not save or upload your private server link.

source-code.txt contains the complete C# app/updater/installer, PowerShell backend,
installer/build/publish tools, and public verification key. The private signing key
is never distributed. Source is at github.com/adorablewhale/matcha-helper.
The ZIP also includes buildable source and build.ps1. Nothing is obfuscated.
Build with the Windows .NET Framework compiler; no third-party packer is used.
File SHA-256 hashes are in SHA256SUMS.txt. Source transparency lets you inspect
the program's behavior; it is not a guarantee from an antivirus provider.

Installed location: %LOCALAPPDATA%\matcha-helper
Uninstall from the tray menu, or run uninstall.cmd beside this README.
Managed files go to the Recycle Bin. Script settings remain in your workspace.
Windows 10/11 with .NET Framework 4.8 and Windows PowerShell 5.1.

OWNER RELEASE WORKFLOW
Matcha/tools/helper is the canonical source. package/ and INSUI/helper/native/ are
generated distribution copies, not independent editable implementations.
Build: powershell -NoProfile -File build.ps1
Test: powershell -NoProfile -File tests/run.ps1
Create signed local artifacts: powershell -NoProfile -File publish.ps1
With release approval: powershell -NoProfile -File publish.ps1 -Publish
Bump the assembly, UI/build labels and publisher version for every release.
The signing key is DPAPI-protected outside Git in the owner's .j5cks folder.
Back up the Windows account/key securely; losing it requires an explicit trust-key
migration and a manually installed new helper. Never initialize a replacement key silently.
Changing GitHub source alone does not distribute a binary: publish a signed stable release.
