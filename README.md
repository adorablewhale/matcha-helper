<div align="center">

<img src="https://adorablewhale.world/brand/matcha.png" width="72" alt="">

# matcha helper

**a tiny tray app that gives your matcha scripts a few windows powers.**

[download the installer](https://github.com/adorablewhale/matcha-helper/releases/latest)

**new in 1.3:** roblox screenshots on your discord stats message, auto rejoin after a kick
(your private server, or any public one) that starts matcha again for you, and an auto rejoin switch.

</div>

### what it does

- **screenshots, focus, clipboard and files** for scripts that ask for them
- **auto rejoin** after a kick: back into your server, then it starts matcha again (usermode or kernel)
- **sleeps when no script is running** — no input, no screenshots, nothing
- **lives in the tray** — double-click the whale for status, right-click to pause or quit
- **updates itself** safely — signed releases only, applied while it's asleep
- **no admin rights**, starts at login only if you want it to

### open source, not a black box

everything it runs is readable: the c# app, the powershell backend and the installer are in this
repo and bundled as `source-code.txt` in every download. nothing is obfuscated. when a script
requests a screenshot, it uploads only the roblox window to your dashboard so it
can appear on your discord stats message. it never uploads your desktop or passwords.
full details are in [README.txt](README.txt).

<sub>part of [insui](https://github.com/adorablewhale/insui) · dashboard at [adorablewhale.world](https://adorablewhale.world)</sub>
