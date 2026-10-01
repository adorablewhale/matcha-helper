using System;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
static class Program {
    internal static string Root;
    internal static void CheckPath(string p) {if(!Path.GetFullPath(p).StartsWith(Root+Path.DirectorySeparatorChar))throw new Exception("Test extraction escaped root");}
    static int checks;
    static void Check(bool ok,string name){if(!ok)throw new Exception(name);checks++;}
    static void Denied(Action action,string name){try{action();}catch(InvalidDataException){checks++;return;}catch(CryptographicException){checks++;return;}throw new Exception("Accepted "+name);}
    static UpdateManifest ForZip(byte[] data){using(var hash=SHA256.Create())return new UpdateManifest {size=data.Length,sha256=BitConverter.ToString(hash.ComputeHash(data)).Replace("-","").ToLower()};}
    static byte[] Zip(string[] names){using(var m=new MemoryStream()){using(var z=new ZipArchive(m,ZipArchiveMode.Create,true))foreach(var n in names){using(var s=z.CreateEntry(n).Open())s.WriteByte(42);}return m.ToArray();}}
    static void Main(string[] args) {
        Root=Path.GetFullPath(args[1]);Directory.CreateDirectory(Root);
        string source=args[0], release=Path.Combine(source,"release");
        var manifest=File.ReadAllBytes(Path.Combine(release,"update.json"));var sig=File.ReadAllBytes(Path.Combine(release,"update.sig"));
        string key=File.ReadAllText(Path.Combine(source,"update-public-key.xml"));var current=new Version(1,1,1,0);
        var valid=HelperUpdater.Verify(manifest,sig,key,current);
        var expected=HelperUpdater.Normalize(System.Diagnostics.FileVersionInfo.GetVersionInfo(Path.Combine(source,"package","matcha-helper.exe")).FileVersion);
        Check(HelperUpdater.Normalize(valid.version)==expected,"Valid signed update matches built helper");
        Check(HelperUpdater.Verify(manifest,sig,key,expected)==null,"Already current");
        Check(HelperUpdater.Verify(manifest,sig,key,new Version(expected.Major+1,0,0,0))==null,"No downgrade");
        var changed=(byte[])manifest.Clone();changed[changed.Length-2]^=1;Denied(()=>HelperUpdater.Verify(changed,sig,key,current),"modified manifest");
        var badSig=Encoding.UTF8.GetBytes(Convert.ToBase64String(new byte[384]));Denied(()=>HelperUpdater.Verify(manifest,badSig,key,current),"bad signature");
        using(var rsa=new RSACryptoServiceProvider(2048)) {
            rsa.PersistKeyInCsp=false;string otherKey=rsa.ToXmlString(false);
            Denied(()=>HelperUpdater.Verify(manifest,sig,otherKey,current),"different signing key");
            var json=new JavaScriptSerializer();var m=json.Deserialize<UpdateManifest>(Encoding.UTF8.GetString(manifest));
            m.expires=0;byte[] expired=Encoding.UTF8.GetBytes(json.Serialize(m));var signed=Encoding.UTF8.GetBytes(Convert.ToBase64String(rsa.SignData(expired,"SHA256")));
            Denied(()=>HelperUpdater.Verify(expired,signed,otherKey,current),"expired manifest");
        }
        var package=File.ReadAllBytes(Path.Combine(release,"matcha-helper.zip"));HelperUpdater.ValidatePackage(valid,package);checks++;
        var altered=(byte[])package.Clone();altered[100]^=1;Denied(()=>HelperUpdater.ValidatePackage(valid,altered),"modified package");
        Denied(()=>HelperUpdater.ValidatePackage(valid,new byte[0]),"wrong size");
        foreach(var names in new[] {new[]{"../escape.exe"},new[]{"matcha-helper.exe","matcha-helper.exe"},new[]{"install.ps1"},new[]{"evil.exe"}}) {
            var zip=Zip(names);Denied(()=>HelperUpdater.ValidatePackage(ForZip(zip),zip),"unsafe/incomplete/duplicate ZIP");
        }
        string prefix="https://github.com/adorablewhale/matcha-helper/releases/download/v"+valid.version+"/";
        var metadata=new ReleaseInfo {tag_name="v"+valid.version,assets=new[]{new ReleaseAsset {name="update.json",browser_download_url=prefix+"update.json"},new ReleaseAsset {name="update.sig",browser_download_url=prefix+"update.sig"},new ReleaseAsset {name="matcha-helper.zip",browser_download_url=prefix+"matcha-helper.zip"}}};
        var serializer=new JavaScriptSerializer();Func<string,int,byte[]> fetch=(url,max)=>url.EndsWith("update.json")?manifest:sig;
        var candidate=HelperUpdater.Check(Encoding.UTF8.GetBytes(serializer.Serialize(metadata)),current,key,fetch);Check(candidate!=null,"Complete release");
        metadata.prerelease=true;Denied(()=>HelperUpdater.Check(Encoding.UTF8.GetBytes(serializer.Serialize(metadata)),current,key,fetch),"prerelease");metadata.prerelease=false;
        metadata.assets[0].browser_download_url="https://github.com/attacker/else/releases/download/v1.2.0/update.json";
        Denied(()=>HelperUpdater.Check(Encoding.UTF8.GetBytes(serializer.Serialize(metadata)),current,key,fetch),"other repository");
        Denied(()=>HelperUpdater.Download("http://github.com/",1),"HTTP");Denied(()=>HelperUpdater.Download("https://evil.example/",1),"other host");
        string staged=HelperUpdater.Stage(candidate,package);Check(File.Exists(Path.Combine(staged,"matcha-helper.exe")),"Verified extraction and binary version");
        Check(HelperUpdater.CanApply(true,true,false,"sleeping",true,false),"Automatic while asleep");
        Check(!HelperUpdater.CanApply(true,true,false,"awake",true,false),"Wait while active");
        Check(!HelperUpdater.CanApply(true,true,true,"sleeping",true,true),"Pause respected");
        Check(!HelperUpdater.CanApply(false,true,false,"sleeping",true,true),"Portable never replaced");
        Check(!HelperUpdater.CanApply(true,false,false,"sleeping",true,true),"Offline never restarted");
        Check(!HelperUpdater.CanApply(true,true,false,"sleeping",false,false),"Disabled respected");
        Check(HelperUpdater.CanApply(true,true,false,"sleeping",false,true),"Manual check allowed");
        Console.WriteLine(checks+" updater checks passed");
    }
}
