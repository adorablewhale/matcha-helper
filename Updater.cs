// Only stable releases from the fixed owner repository, signed by the pinned release key.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

sealed class ReleaseAsset { public string name {get;set;} public string browser_download_url {get;set;} }
sealed class ReleaseInfo { public string tag_name {get;set;} public bool draft {get;set;} public bool prerelease {get;set;} public ReleaseAsset[] assets {get;set;} }
sealed class UpdateManifest { public int schema {get;set;} public string version {get;set;} public string package {get;set;} public long size {get;set;} public string sha256 {get;set;} public long expires {get;set;} }
sealed class UpdateCandidate { public UpdateManifest Manifest; public string Url; }
static class HelperUpdater {
    internal const string Repository = "adorablewhale/matcha-helper";
    internal const int MaxPackage = 8 * 1024 * 1024;
    internal static bool CanApply(bool installed, bool backendRunning, bool paused, string mode, bool automatic, bool manual) {
        return installed && backendRunning && !paused && mode == "sleeping" && (automatic || manual);
    }
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 262144 };
    static readonly HashSet<string> Files = new HashSet<string>(StringComparer.Ordinal) {
        "matcha-helper.exe", "installer.exe", "source-code.txt", "README.txt", "install.ps1", "MatchaHelper.cs", "Installer.cs", "Updater.cs",
        "backend.ps1", "build.ps1", "sign-release.ps1", "publish.ps1", "update-public-key.xml", "SHA256SUMS.txt", "uninstall.cmd", "matcha.ico"
    };
    internal static Version Normalize(string s) {
        Version v; if (!Version.TryParse(s, out v)) throw new InvalidDataException("Invalid release version.");
        return new Version(v.Major, v.Minor, Math.Max(0,v.Build), Math.Max(0,v.Revision));
    }
    internal static byte[] Download(string url, int maximum) {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        Uri uri = new Uri(url); var clock = Stopwatch.StartNew();
        for (int redirect = 0; redirect < 5; redirect++) {
            if (uri.Scheme != "https" || !String.IsNullOrEmpty(uri.UserInfo) || !uri.IsDefaultPort ||
                !(uri.Host == "api.github.com" || uri.Host == "github.com" || uri.Host == "release-assets.githubusercontent.com" || uri.Host == "objects.githubusercontent.com"))
                throw new InvalidDataException("Update host is not allowed.");
            var request = (HttpWebRequest)WebRequest.Create(uri); request.AllowAutoRedirect = false;
            request.Timeout = 15000; request.ReadWriteTimeout = 15000; request.UserAgent = "MatchaHelper/1.2";
            using (var response = (HttpWebResponse)request.GetResponse()) {
                if ((int)response.StatusCode >= 300 && (int)response.StatusCode < 400) {
                    uri = new Uri(uri, response.Headers["Location"]); continue;
                }
                if (response.StatusCode != HttpStatusCode.OK || response.ContentLength > maximum) throw new InvalidDataException("Update download rejected.");
                using (var output = new MemoryStream()) using (var stream = response.GetResponseStream()) {
                    byte[] chunk = new byte[16384]; int count;
                    while ((count = stream.Read(chunk,0,chunk.Length)) > 0) {
                        if (output.Length + count > maximum || clock.Elapsed.TotalSeconds > 60) throw new InvalidDataException("Update download exceeded its limit.");
                        output.Write(chunk,0,count);
                    }
                    return output.ToArray();
                }
            }
        }
        throw new InvalidDataException("Too many update redirects.");
    }
    internal static UpdateManifest Verify(byte[] manifest, byte[] signature, string publicKey, Version current) {
        if (manifest.Length > 16384 || signature.Length > 2048) throw new InvalidDataException("Invalid update metadata size.");
        using (var rsa = new RSACryptoServiceProvider()) {
            rsa.PersistKeyInCsp = false; rsa.FromXmlString(publicKey);
            if (!rsa.VerifyData(manifest,"SHA256",Convert.FromBase64String(Encoding.UTF8.GetString(signature).Trim()))) throw new InvalidDataException("Update signature is invalid.");
        }
        var m = Json.Deserialize<UpdateManifest>(Encoding.UTF8.GetString(manifest));
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        if (m == null || m.schema != 1 || m.package != "matcha-helper.zip" || m.size < 1 || m.size > MaxPackage ||
            !System.Text.RegularExpressions.Regex.IsMatch(m.sha256 ?? "", "^[a-f0-9]{64}$") || m.expires < now || m.expires > now + 370L*86400)
            throw new InvalidDataException("Invalid or expired update manifest.");
        if (Normalize(m.version) <= current) return null;
        return m;
    }
    internal static UpdateCandidate Check(Version current, string publicKey) {
        return Check(Download("https://api.github.com/repos/"+Repository+"/releases/latest",262144), current, publicKey, Download);
    }
    internal static UpdateCandidate Check(byte[] releaseJson, Version current, string publicKey, Func<string,int,byte[]> fetch) {
        var release = Json.Deserialize<ReleaseInfo>(Encoding.UTF8.GetString(releaseJson));
        if (release == null || release.draft || release.prerelease || release.assets == null || release.assets.Length > 20) throw new InvalidDataException("Not a stable helper release.");
        string version = (release.tag_name ?? "").TrimStart('v'); Normalize(version);
        string prefix = "https://github.com/"+Repository+"/releases/download/v"+version+"/";
        var assets = new Dictionary<string,string>(StringComparer.Ordinal);
        foreach (var a in release.assets) {
            if (a.name == "update.json" || a.name == "update.sig" || a.name == "matcha-helper.zip") {
                if (assets.ContainsKey(a.name) || a.browser_download_url != prefix + a.name) throw new InvalidDataException("Unexpected release asset.");
                assets.Add(a.name,a.browser_download_url);
            }
        }
        if (assets.Count != 3) throw new InvalidDataException("The release is incomplete.");
        var m = Verify(fetch(assets["update.json"],16384),fetch(assets["update.sig"],2048),publicKey,current);
        if (m == null) return null;
        if (Normalize(m.version) != Normalize(version)) throw new InvalidDataException("Release version mismatch.");
        return new UpdateCandidate {Manifest = m, Url = assets["matcha-helper.zip"]};
    }
    internal static string Stage(UpdateCandidate update, byte[] package) {
        ValidatePackage(update.Manifest,package);
        string stage = Path.Combine(Program.Root,"updates",Guid.NewGuid().ToString("N")); Program.CheckPath(stage); Directory.CreateDirectory(stage);
        using (var zip = new ZipArchive(new MemoryStream(package),ZipArchiveMode.Read)) {
            foreach (var entry in zip.Entries) {
                string path = Path.Combine(stage,entry.FullName); Program.CheckPath(path);
                using (var source = entry.Open()) using (var dest = File.Create(path)) source.CopyTo(dest);
            }
        }
        if (Normalize(FileVersionInfo.GetVersionInfo(Path.Combine(stage,"matcha-helper.exe")).FileVersion) != Normalize(update.Manifest.version)) throw new InvalidDataException("Helper binary version mismatch.");
        return stage;
    }
    internal static void ValidatePackage(UpdateManifest m, byte[] package) {
        if (package.LongLength != m.size || package.Length > MaxPackage) throw new InvalidDataException("Update size mismatch.");
        using (var hash = SHA256.Create()) {
            string digest = BitConverter.ToString(hash.ComputeHash(package)).Replace("-","").ToLowerInvariant();
            if (digest != m.sha256) throw new InvalidDataException("Update checksum mismatch.");
        }
        var found = new HashSet<string>(StringComparer.Ordinal); long total = 0;
        using (var zip = new ZipArchive(new MemoryStream(package),ZipArchiveMode.Read)) {
            foreach (var entry in zip.Entries) {
                total += entry.Length;
                if (!Files.Contains(entry.FullName) || !found.Add(entry.FullName) || entry.Length > MaxPackage || total > 32*1024*1024 ||
                    ((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000) throw new InvalidDataException("Unsafe update package contents.");
            }
        }
        foreach (var name in new[] {"matcha-helper.exe","install.ps1","source-code.txt","README.txt","SHA256SUMS.txt"})
            if (!found.Contains(name)) throw new InvalidDataException("Update package is missing a required file.");
    }
}
