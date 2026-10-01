// Matcha helper 1.2.0. Readable native host with signed, idle-only GitHub updates.
// No obfuscation, elevation or telemetry. Update verification is in Updater.cs.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
[assembly: AssemblyTitle("Matcha helper")]
[assembly: AssemblyDescription("Optional local Windows features for Matcha scripts")]
[assembly: AssemblyVersion("1.2.0.0")]
[assembly: AssemblyFileVersion("1.2.0.0")]

static class Program {
    internal static readonly string Root = Path.Combine(KnownFolder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"), "matcha-helper");
    internal static readonly string Exe = Path.Combine(Root, "matcha-helper.exe");
    internal static readonly string Sid = WindowsIdentity.GetCurrent().User.Value;
    internal static string PS { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe"); } }
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid id, uint flags, IntPtr token, out IntPtr path);
    internal static string KnownFolder(string guid) {
        var id = new Guid(guid); IntPtr pointer;
        int hr = SHGetKnownFolderPath(ref id, 0x00010000, IntPtr.Zero, out pointer);
        if (hr != 0) Marshal.ThrowExceptionForHR(hr);
        try { return Marshal.PtrToStringUni(pointer); } finally { Marshal.FreeCoTaskMem(pointer); }
    }
    [STAThread] static void Main(string[] args) {
        SetProcessDPIAware(); Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        try {
            if (Array.IndexOf(args, "--quit") >= 0) { Signal("Exit"); return; }
            bool created;
            using (var singleton = new Mutex(true, "Local\\MatchaHelper-" + Sid, out created)) {
                if (!created) { if (Array.IndexOf(args, "--tray") < 0) Signal("Open"); return; }
                try { Application.Run(new HelperWindow(args)); } finally { singleton.ReleaseMutex(); }
            }
        } catch (Exception e) { MessageBox.Show(e.Message, "Matcha helper", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }
    static void Signal(string name) { try { using (var ev = EventWaitHandle.OpenExisting("Local\\MatchaHelper" + name + "-" + Sid)) ev.Set(); } catch (WaitHandleCannotBeOpenedException) {} }
    internal static void CheckPath(string path) {
        string full = Path.GetFullPath(path);
        if (!full.Equals(Root, StringComparison.OrdinalIgnoreCase) && !full.StartsWith(Root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new IOException("Path is outside the helper installation.");
        for (string p = full; !String.IsNullOrEmpty(p); p = Path.GetDirectoryName(p))
            if ((Directory.Exists(p) || File.Exists(p)) && (File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0) throw new IOException("Linked installation folders are not supported.");
    }
    internal static string Resource(string name) { using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) using (var reader = new StreamReader(stream)) return reader.ReadToEnd(); }
    internal static void Write(string path, string content) { CheckPath(path); File.WriteAllText(path, content, new System.Text.UTF8Encoding(false)); }
    internal static string Shortcut { get { return Path.Combine(KnownFolder("B97D20BB-F46A-4C97-BA10-5E3608430854"), "Matcha helper.lnk"); } }
    internal static object Property(object obj, string name, object value) { return obj.GetType().InvokeMember(name, BindingFlags.SetProperty, null, obj, new object[] {value}); }
    internal static void Startup(bool enabled) {
        if (!enabled) {
            if (File.Exists(Shortcut)) {
                object shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
                object shortcut = shell.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] {Shortcut});
                string target = (string)shortcut.GetType().InvokeMember("TargetPath", BindingFlags.GetProperty, null, shortcut, null);
                Marshal.FinalReleaseComObject(shortcut); Marshal.FinalReleaseComObject(shell);
                if (!target.Equals(Exe, StringComparison.OrdinalIgnoreCase)) throw new IOException("The startup shortcut belongs to another program.");
                Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(Shortcut, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
            }
            return;
        }
        object ws = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
        object link = ws.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, ws, new object[] {Shortcut});
        Property(link, "TargetPath", Exe); Property(link, "Arguments", "--tray"); Property(link, "WorkingDirectory", Root);
        Property(link, "IconLocation", Exe + ",0"); Property(link, "Description", "Matcha helper — sleeps until a script is active; quit from the tray.");
        link.GetType().InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
        Marshal.FinalReleaseComObject(link); Marshal.FinalReleaseComObject(ws);
    }
}

sealed class HelperWindow : Form {
    readonly Color Ink = Color.FromArgb(235, 239, 236), Muted = Color.FromArgb(137, 148, 143), Mint = Color.FromArgb(160, 225, 193);
    readonly JavaScriptSerializer json = new JavaScriptSerializer();
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly EventWaitHandle openEvent = new EventWaitHandle(false, EventResetMode.AutoReset, "Local\\MatchaHelperOpen-" + Program.Sid);
    readonly EventWaitHandle exitEvent = new EventWaitHandle(false, EventResetMode.AutoReset, "Local\\MatchaHelperExit-" + Program.Sid);
    NotifyIcon tray; Process backend; bool exiting, paused, installed, initializing = true, startHidden;
    string workspace = "C:\\matcha\\workspace", mode = "sleeping";
    Label heading, detail, scripts, pathLabel, updateLabel; Button pauseButton, installButton; CheckBox startup, updates;
    DateTime nextCheck = DateTime.UtcNow.AddSeconds(10); bool checking, applying, requestedUpdate;
    string pendingStage;
    readonly string runtime = Path.Combine(Program.Root, "runtime");
    public HelperWindow(string[] args) {
        Text = "matcha helper"; BackColor = Color.FromArgb(14, 18, 16); ForeColor = Ink;
        Font = new Font("Segoe UI", 10); ClientSize = new Size(520, 656); MinimumSize = MaximumSize = Size;
        FormBorderStyle = FormBorderStyle.FixedSingle; MaximizeBox = false; StartPosition = FormStartPosition.CenterScreen;
        Icon = MakeIcon(); installed = Application.ExecutablePath.Equals(Program.Exe, StringComparison.OrdinalIgnoreCase);
        startHidden = Array.IndexOf(args, "--tray") >= 0;
        Program.CheckPath(runtime); Directory.CreateDirectory(runtime);
        if (File.Exists(Path.Combine(Program.Root, "workspace.txt"))) workspace = File.ReadAllText(Path.Combine(Program.Root, "workspace.txt")).Trim();
        int wi = Array.IndexOf(args, "--workspace"); if (wi >= 0 && wi + 1 < args.Length) workspace = Path.GetFullPath(args[wi+1]);
        Program.Write(Path.Combine(runtime, "backend.ps1"), Program.Resource("Backend"));
        Program.Write(Path.Combine(runtime, "source-code.txt"), Program.Resource("Source"));
        BuildUI(); BuildTray();
        timer.Interval = 1000; timer.Tick += delegate { RefreshStatus(); }; timer.Start();
        FormClosing += delegate(object sender, FormClosingEventArgs e) {
            if (!exiting && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        };
        Shown += delegate { if (startHidden) Hide(); };
        if (installed || Array.IndexOf(args, "--portable") >= 0) StartBackend();
        else { heading.Text = "ready when you are"; detail.Text = "install once, or run just for this session."; scripts.Text = "your scripts keep working without the helper."; }
        initializing = false;
    }
    Label LabelAt(string text, int x, int y, int w, int h, float size, Color color) {
        var l = new Label {Text = text, Location = new Point(x,y), Size = new Size(w,h), Font = new Font("Segoe UI",size), ForeColor = color, BackColor = Color.Transparent}; Controls.Add(l); return l;
    }
    Button ButtonAt(string text, int x, int y, int w, EventHandler action, bool primary) {
        var b = new Button {Text = text, Location = new Point(x,y), Size = new Size(w,38), FlatStyle = FlatStyle.Flat, BackColor = primary ? Mint : Color.FromArgb(23,29,26), ForeColor = primary ? Color.FromArgb(14,24,18) : Ink, Cursor = Cursors.Hand};
        b.FlatAppearance.BorderColor = Color.FromArgb(53,65,58); b.FlatAppearance.BorderSize = primary ? 0 : 1;
        b.Click += action; Controls.Add(b); return b;
    }
    void BuildUI() {
        LabelAt("adorablewhale / windows",28,25,440,22,9,Muted);
        LabelAt("matcha helper",28,56,440,46,25,Ink);
        LabelAt("a quiet companion for your scripts.",30,109,440,24,10,Muted);
        heading = LabelAt("starting…",52,173,410,40,23,Mint);
        detail = LabelAt("checking the local connection",52,225,410,40,10,Ink);
        scripts = LabelAt("",52,271,410,36,9,Muted);
        LabelAt("LOCAL WORKSPACE",30,336,440,20,8,Muted);
        pathLabel = LabelAt(workspace,30,364,354,36,9,Ink);
        ButtonAt("change",392,355,98,ChooseWorkspace,false);
        startup = new CheckBox {Text = "start in the tray when i sign in", Location = new Point(30,411), Size = new Size(390,28), ForeColor = Ink, Checked = installed && File.Exists(Program.Shortcut), Visible = installed};
        startup.CheckedChanged += delegate { if (!initializing) try { Program.Startup(startup.Checked); } catch (Exception e) { Error(e); } }; Controls.Add(startup);
        if (!installed) LabelAt("install for this windows user · start in the tray at login",30,411,460,28,9,Muted);
        if (installed) pauseButton = ButtonAt("pause helper",30,459,148,TogglePause,false);
        else {
            installButton = ButtonAt("install and start",30,459,174,Install,true);
            pauseButton = ButtonAt("run once",214,459,124,delegate { if (backend == null) StartBackend(); else TogglePause(null,EventArgs.Empty); },false);
        }
        ButtonAt("view source",installed ? 188 : 348,459,installed ? 142 : 142,delegate { OpenSource(); },false);
        if (installed) ButtonAt("quit",340,459,150,delegate { Quit(); },false);
        LabelAt("closing this window keeps the helper in your tray.\nright-click its whale icon to pause or quit.",30,515,460,36,9,Muted);
        updates = new CheckBox {Text = "automatically update from signed GitHub releases", Location = new Point(30,560), Size = new Size(460,28), Checked = !File.Exists(Path.Combine(Program.Root,"updates-disabled.txt")), Visible = installed};
        updates.CheckedChanged += delegate { if (!initializing) { Program.Write(Path.Combine(Program.Root,"updates-disabled.txt"),updates.Checked ? "enabled" : "disabled"); if (updates.Checked) nextCheck = DateTime.UtcNow; } }; Controls.Add(updates);
        if (File.Exists(Path.Combine(Program.Root,"updates-disabled.txt"))) updates.Checked = File.ReadAllText(Path.Combine(Program.Root,"updates-disabled.txt")).Trim() != "disabled";
        updateLabel = LabelAt("v1.2.0 · updates apply only while sleeping",30,600,330,35,9,Muted);
        if (installed) ButtonAt("check updates",366,599,124,delegate { CheckUpdates(true); },false);
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e); e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var b = new SolidBrush(Color.FromArgb(22,29,25))) e.Graphics.FillRectangle(b,30,154,460,160);
        using (var pen = new Pen(Color.FromArgb(48,65,55))) e.Graphics.DrawRectangle(pen,30,154,459,159);
        using (var pen = new Pen(Color.FromArgb(44,54,48))) e.Graphics.DrawLine(pen,30,321,490,321);
    }
    void BuildTray() {
        var menu = new ContextMenuStrip {BackColor = Color.FromArgb(23,29,26), ForeColor = Ink, ShowImageMargin = false};
        menu.Items.Add("open helper",null,delegate { Reveal(); });
        menu.Items.Add("pause / resume",null,TogglePause);
        menu.Items.Add("open dashboard",null,delegate { Process.Start("https://adorablewhale.world/dashboard"); });
        menu.Items.Add("view source",null,delegate { OpenSource(); });
        if (installed) menu.Items.Add("check for updates",null,delegate { CheckUpdates(true); });
        menu.Items.Add(new ToolStripSeparator());
        if (installed) menu.Items.Add("uninstall helper",null,Uninstall);
        menu.Items.Add("quit helper",null,delegate { Quit(); });
        tray = new NotifyIcon {Icon = Icon, Text = "matcha helper — sleeping", ContextMenuStrip = menu, Visible = true};
        tray.DoubleClick += delegate { Reveal(); };
    }
    void Reveal() { Show(); WindowState = FormWindowState.Normal; Activate(); }
    void Error(Exception e) { MessageBox.Show(this,e.Message,"Matcha helper",MessageBoxButtons.OK,MessageBoxIcon.Error); }
    void ChooseWorkspace(object sender, EventArgs e) {
        using (var dialog = new FolderBrowserDialog {Description = "choose your Matcha workspace", SelectedPath = workspace}) {
            if (dialog.ShowDialog(this) != DialogResult.OK) return;
            workspace = Path.GetFullPath(dialog.SelectedPath); pathLabel.Text = workspace;
            Program.Write(Path.Combine(Program.Root,"workspace.txt"),workspace);
            if (backend != null) { StopBackend(); StartBackend(); }
        }
    }
    void StartBackend() {
        if (!Directory.Exists(workspace)) { heading.Text = "choose your workspace"; detail.Text = "select the folder Matcha uses for its script files."; return; }
        try {
            var info = new ProcessStartInfo(Program.PS,"-STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + Path.Combine(runtime,"backend.ps1") + "\"") {UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = runtime};
            info.EnvironmentVariables["FH_ARG"] = workspace;
            info.EnvironmentVariables["MATCHA_HELPER_NO_BROWSER"] = "1";
            info.EnvironmentVariables["MATCHA_HELPER_HOST_PID"] = Process.GetCurrentProcess().Id.ToString();
            info.EnvironmentVariables["MATCHA_HELPER_HOST_CREATED"] = Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks.ToString();
            backend = Process.Start(info);
            // Consume output without logging request data, tokens or file contents.
            backend.OutputDataReceived += delegate {}; backend.ErrorDataReceived += delegate {};
            backend.BeginOutputReadLine(); backend.BeginErrorReadLine();
            paused = false; pauseButton.Text = "pause helper";
            Program.Write(Path.Combine(Program.Root,"process.json"), json.Serialize(new {pid = Process.GetCurrentProcess().Id, created = Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks, backend = backend.Id, workspace = workspace}));
            heading.Text = "connecting…"; detail.Text = "the local helper is starting.";
        } catch (Exception e) { Error(e); }
    }
    void StopBackend() {
        if (backend == null) return;
        int own = backend.Id;
        try { if (!backend.HasExited) { backend.Kill(); backend.WaitForExit(3000); } } catch (InvalidOperationException) {}
        backend.Dispose(); backend = null;
        string beat = Path.Combine(workspace,"INSUI\\helper\\helper.json");
        try {
            var value = json.Deserialize<Dictionary<string,object>>(File.ReadAllText(beat));
            if (Convert.ToInt32(value["pid"]) == own) { value["beat"] = 0; File.WriteAllText(beat,json.Serialize(value),new System.Text.UTF8Encoding(false)); }
        } catch (IOException) {} catch (ArgumentException) {} catch (KeyNotFoundException) {}
    }
    void TogglePause(object sender, EventArgs e) {
        if (backend == null) { StartBackend(); return; }
        StopBackend(); paused = true; pauseButton.Text = "resume helper"; RefreshStatus();
    }
    void RefreshStatus() {
        if (exitEvent.WaitOne(0)) { Quit(); return; }
        if (openEvent.WaitOne(0)) Reveal();
        if (installed && updates.Checked && DateTime.UtcNow >= nextCheck && !checking && pendingStage == null) CheckUpdates(false);
        if (backend == null) {
            if (paused) { mode = "paused"; heading.Text = "paused"; detail.Text = "windows features are paused. your scripts can continue."; scripts.Text = "resume whenever you need the helper again."; }
            tray.Text = "matcha helper — " + (paused ? "paused" : "ready"); return;
        }
        if (backend.HasExited) { mode = "offline"; heading.Text = "helper stopped"; detail.Text = "another helper may be using port 47210. close it, then resume."; scripts.Text = ""; StopBackend(); paused = true; pauseButton.Text = "resume helper"; return; }
        try {
            var value = json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(workspace,"INSUI\\helper\\helper.json")));
            if (Convert.ToInt32(value["pid"]) != backend.Id) return;
            mode = Convert.ToString(value["mode"]);
            var names = json.ConvertToType<string[]>(value["active"]);
            heading.Text = mode == "awake" ? "awake" : "sleeping";
            detail.Text = mode == "awake" ? "connected. enabled windows features are ready." : "waiting for a script. automatic features are resting.";
            scripts.Text = names.Length > 0 ? String.Join(" · ",names) : "load a script in Matcha — i'll wake up automatically.";
            tray.Text = "matcha helper — " + heading.Text;
            if (pendingStage != null && HelperUpdater.CanApply(installed,backend != null,paused,mode,updates.Checked,requestedUpdate)) ApplyUpdate();
        } catch (IOException) {} catch (ArgumentException) {} catch (KeyNotFoundException) {}
    }
    void CheckUpdates(bool manual) {
        if (checking || applying) return;
        if (pendingStage != null) { requestedUpdate |= manual; updateLabel.Text = "update ready · waiting for scripts to sleep"; return; }
        checking = true; requestedUpdate = manual; nextCheck = DateTime.UtcNow.AddHours(4); updateLabel.Text = "checking signed GitHub releases…";
        Task.Run(delegate {
            string stage = null, message = "v1.2.0 · up to date";
            try {
                var candidate = HelperUpdater.Check(Assembly.GetExecutingAssembly().GetName().Version, Program.Resource("UpdateKey"));
                if (candidate != null) { stage = HelperUpdater.Stage(candidate,HelperUpdater.Download(candidate.Url,HelperUpdater.MaxPackage)); message = "v"+candidate.Manifest.version+" ready · waiting for sleep"; }
            } catch { message = "update unavailable · current version keeps working"; }
            try { if (!exiting && !IsDisposed) BeginInvoke((Action)delegate { checking = false; pendingStage = stage; updateLabel.Text = message; }); } catch (InvalidOperationException) {}
        });
    }
    void ApplyUpdate() {
        if (applying || pendingStage == null || !HelperUpdater.CanApply(installed,backend != null,paused,mode,updates.Checked,requestedUpdate)) return;
        applying = true;
        try {
            var info = new ProcessStartInfo(Program.PS,"-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \""+Path.Combine(pendingStage,"install.ps1")+"\" -Update -Tray -WaitPid "+Process.GetCurrentProcess().Id) {UseShellExecute = false, CreateNoWindow = true};
            Process.Start(info); Quit();
        } catch { applying = false; updateLabel.Text = "update could not start · try again later"; }
    }
    void OpenSource() { Process.Start("notepad.exe","\"" + Path.Combine(runtime,"source-code.txt") + "\""); }
    string SetupStage() {
        string stage = Path.Combine(Program.Root,"setup"); Program.CheckPath(stage); Directory.CreateDirectory(stage);
        File.Copy(Application.ExecutablePath,Path.Combine(stage,"matcha-helper.exe"),true);
        Program.Write(Path.Combine(stage,"install.ps1"),Program.Resource("Installer"));
        Program.Write(Path.Combine(stage,"source-code.txt"),Program.Resource("Source"));
        Program.Write(Path.Combine(stage,"README.txt"),Program.Resource("Readme"));
        return stage;
    }
    void Install(object sender, EventArgs e) {
        try { string stage = SetupStage(); StopBackend(); Process.Start(new ProcessStartInfo(Program.PS,"-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + Path.Combine(stage,"install.ps1") + "\" -Workspace \"" + workspace + "\" -WaitPid " + Process.GetCurrentProcess().Id) {UseShellExecute = false, CreateNoWindow = true}); Quit(); }
        catch (Exception error) { Error(error); }
    }
    void Uninstall(object sender, EventArgs e) {
        if (MessageBox.Show(this,"remove the helper and its login shortcut?\nmanaged files go to the recycle bin. script settings stay in place.","uninstall matcha helper",MessageBoxButtons.OKCancel,MessageBoxIcon.Question) != DialogResult.OK) return;
        try { string stage = SetupStage(); Process.Start(new ProcessStartInfo(Program.PS,"-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + Path.Combine(stage,"install.ps1") + "\" -Uninstall -WaitPid " + Process.GetCurrentProcess().Id) {UseShellExecute = false, CreateNoWindow = true}); Quit(); }
        catch (Exception error) { Error(error); }
    }
    void Quit() { exiting = true; timer.Stop(); StopBackend(); tray.Visible = false; Close(); }
    protected override void Dispose(bool disposing) {
        if (disposing) { timer.Dispose(); openEvent.Dispose(); exitEvent.Dispose(); if (tray != null) tray.Dispose(); if (backend != null) StopBackend(); }
        base.Dispose(disposing);
    }
    static Icon MakeIcon() {
        using (var bitmap = new Bitmap(32,32)) using (var g = Graphics.FromImage(bitmap)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var brush = new SolidBrush(Color.FromArgb(160,225,193))) {
                g.FillEllipse(brush,3,12,24,15); g.FillPolygon(brush,new Point[] {new Point(24,20),new Point(29,7),new Point(31,13),new Point(29,23)});
                g.FillRectangle(brush,11,6,2,7); g.FillEllipse(brush,8,4,5,3); g.FillEllipse(brush,13,3,5,3);
            }
            using (var eye = new SolidBrush(Color.FromArgb(14,18,16))) g.FillEllipse(eye,8,17,3,3);
            IntPtr handle = bitmap.GetHicon(); try { return (Icon)Icon.FromHandle(handle).Clone(); } finally { DestroyIcon(handle); }
        }
    }
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
}
