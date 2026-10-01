// Single-file per-user installer; its resources contain the complete helper and readable source.
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
[assembly: AssemblyTitle("Matcha helper installer")]
[assembly: AssemblyVersion("1.3.0.0")]
[assembly: AssemblyFileVersion("1.3.0.0")]
static class InstallerMain {
    [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath(ref Guid id,uint flags,IntPtr token,out IntPtr path);
    internal static string Folder(string name) {
        var id=new Guid(name); IntPtr ptr; int hr=SHGetKnownFolderPath(ref id,0x10000,IntPtr.Zero,out ptr);
        if(hr!=0) Marshal.ThrowExceptionForHR(hr);
        try{return Marshal.PtrToStringUni(ptr);}finally{Marshal.FreeCoTaskMem(ptr);}
    }
    internal static readonly string Root=Path.Combine(Folder("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"),"matcha-helper");
    internal static string Workspace {
        get { string f=Path.Combine(Root,"workspace.txt"); return File.Exists(f) ? File.ReadAllText(f).Trim() : "C:\\matcha\\workspace"; }
    }
    [STAThread] static void Main(string[] args) {
        Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        try {
            if(Array.IndexOf(args,"--install")>=0){Install(Workspace,Array.IndexOf(args,"--no-startup")<0,Array.IndexOf(args,"--no-launch")>=0); return;}
            Application.Run(new InstallerWindow());
        } catch(Exception e){Environment.ExitCode=1; if(Array.IndexOf(args,"--install")<0)MessageBox.Show(e.Message,"Matcha helper setup",MessageBoxButtons.OK,MessageBoxIcon.Error);}
    }
    internal static void Install(string workspace,bool startup,bool noLaunch) {
        if(!Directory.Exists(workspace))throw new IOException("Choose the workspace folder used by Matcha.");
        string stage=Path.Combine(Root,"setup",Guid.NewGuid().ToString("N"));
        for(string p=stage;!String.IsNullOrEmpty(p);p=Path.GetDirectoryName(p))
            if((Directory.Exists(p)||File.Exists(p))&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new IOException("Linked installation folders are not supported.");
        Directory.CreateDirectory(stage);
        foreach(var item in new[] {new[] {"HelperBinary","matcha-helper.exe"},new[] {"Source","source-code.txt"},new[] {"Installer","install.ps1"},new[] {"Readme","README.txt"}}) {
            using(var source=Assembly.GetExecutingAssembly().GetManifestResourceStream(item[0]))using(var dest=File.Create(Path.Combine(stage,item[1])))source.CopyTo(dest);
        }
        string ps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe");
        var info=new ProcessStartInfo(ps,"-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \""+Path.Combine(stage,"install.ps1")+"\" -Workspace \""+workspace+"\""+(startup?"":" -NoStartup")+(noLaunch?" -NoLaunch":"")) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
        using(var proc=Process.Start(info)) {
            var output=proc.StandardOutput.ReadToEndAsync();var error=proc.StandardError.ReadToEndAsync();
            if(!proc.WaitForExit(90000))throw new IOException("Setup is taking longer than expected. Close the helper and try again.");
            Task.WaitAll(output,error);if(proc.ExitCode!=0)throw new IOException("Setup could not finish. Check your workspace and close any older helper, then try again.");
        }
    }
}
sealed class InstallerWindow:Form {
    TextBox workspace;CheckBox startup;Button install;Label status;
    readonly Color ink=Color.FromArgb(235,239,236),mint=Color.FromArgb(160,225,193);
    public InstallerWindow() {
        Text="Matcha helper setup";ClientSize=new Size(540,460);BackColor=Color.FromArgb(14,18,16);ForeColor=ink;Font=new Font("Segoe UI",10);
        FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;StartPosition=FormStartPosition.CenterScreen;
        var iconStream=Assembly.GetExecutingAssembly().GetManifestResourceStream("Icon");if(iconStream!=null)using(iconStream)Icon=new Icon(iconStream);
        LabelAt("adorablewhale / windows",28,22,460,22,9);
        LabelAt("install matcha helper",28,62,480,44,25);
        LabelAt("one install. a quiet tray icon. ready when your scripts are.",30,113,480,28,10);
        LabelAt("YOUR MATCHA WORKSPACE",30,169,450,22,9);
        workspace=new TextBox {Text=InstallerMain.Workspace,Location=new Point(30,199),Size=new Size(363,30),BackColor=Color.FromArgb(23,29,26),ForeColor=ink};Controls.Add(workspace);
        ButtonAt("browse",404,194,106,delegate {using(var d=new FolderBrowserDialog {SelectedPath=workspace.Text,Description="Select Matcha's workspace folder"})if(d.ShowDialog(this)==DialogResult.OK)workspace.Text=d.SelectedPath;},false);
        startup=new CheckBox {Text="start in the system tray when i sign in",Location=new Point(30,251),Size=new Size(480,30),Checked=true};Controls.Add(startup);
        LabelAt("adds a Start menu shortcut — search “matcha helper”.\nsigned GitHub updates apply while sleeping; you can turn them off.\nreadable source is included. no administrator rights needed.",30,299,480,70,10);
        install=ButtonAt("install and open",30,386,225,async delegate {
            install.Enabled=false;workspace.Enabled=false;startup.Enabled=false;status.Text="installing…";
            string folder=workspace.Text;bool login=startup.Checked;
            try {await Task.Run(delegate {InstallerMain.Install(folder,login,false);});status.Text="installed · ready in your tray";install.Text="installed";}
            catch(Exception e){status.Text="setup needs attention";install.Enabled=true;MessageBox.Show(this,e.Message,"Matcha helper setup");}
        },true);
        status=LabelAt("v1.3.0 · windows 10 / 11",274,397,245,35,9);
    }
    Label LabelAt(string text,int x,int y,int w,int h,float size){var l=new Label {Text=text,Location=new Point(x,y),Size=new Size(w,h),Font=new Font("Segoe UI",size),ForeColor=ink};Controls.Add(l);return l;}
    Button ButtonAt(string text,int x,int y,int width,EventHandler click,bool primary){var b=new Button {Text=text,Location=new Point(x,y),Size=new Size(width,38),FlatStyle=FlatStyle.Flat,BackColor=primary?mint:Color.FromArgb(23,29,26),ForeColor=primary?Color.FromArgb(14,18,16):ink};b.FlatAppearance.BorderSize=primary?0:1;b.Click+=click;Controls.Add(b);return b;}
}
