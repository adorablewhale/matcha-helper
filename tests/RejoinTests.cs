using System;
using System.IO;
using System.Web.Script.Serialization;

static class RejoinTests {
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
    static string root, dir;
    static int checks;
    static void Check(bool ok, string label) { if (!ok) throw new Exception(label); checks++; }
    static void Write(string file, object value) { File.WriteAllText(Path.Combine(dir, file), Json.Serialize(value)); }
    static void State(bool on, bool unloaded) {
        Write("state.json", new {features = new {dashboard = true}, unloaded = unloaded,
            rows = new System.Collections.Generic.Dictionary<string,object> {{"Teleports/Private server/Auto rejoin after a kick", on}},
            cmd = new {results = new[] {new {id = "123", ok = true, msg = "applied"}}}});
    }
    static object Row(bool disabled) { return new {kind = "toggle", name = "Auto rejoin after a kick", path = "Teleports/Private server/Auto rejoin after a kick", disabled = disabled, risk = true}; }
    public static void Main(string[] args) {
        root = Path.GetFullPath(args[0]); dir = Path.Combine(root,"INSUI","helper","scripts","Fixture"); Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(root,"INSUI","helper","config.json"),"{}");
        Write("controls.json", new {controls = new[] {Row(false)}}); State(true, false);
        var target = RejoinControl.Find(root, new[] {"Fixture"});
        Check(target != null && target.Enabled && target.Risk && target.Results.Length == 1, "reads current live setting and ack");
        var emptyAckState = Json.Deserialize<System.Collections.Generic.Dictionary<string,object>>(File.ReadAllText(Path.Combine(dir,"state.json")));
        emptyAckState["cmd"] = new {results = new {}}; Write("state.json",emptyAckState);
        Check(RejoinControl.Find(root,new[] {"Fixture"}) != null, "empty Luau ack table {} does not disable the control");
        var command = Json.Deserialize<System.Collections.Generic.Dictionary<string,object>>(target.Command(false));
        Check((string)command["script"] == "Fixture" && (string)command["set"] == target.Path && command["value"].Equals(false), "off queues the exact live control");
        State(false, false); Check(!RejoinControl.Find(root, new[] {"Fixture"}).Enabled, "script changes reflect back");
        State(true, true); Check(RejoinControl.Find(root, new[] {"Fixture"}) == null, "unloaded cannot be controlled");
        State(true, false); File.SetLastWriteTimeUtc(Path.Combine(dir,"state.json"),DateTime.UtcNow.AddSeconds(-16));
        Check(RejoinControl.Find(root, new[] {"Fixture"}) == null, "stale script cannot be controlled");
        State(true, false); Write("controls.json",new {controls = new[] {Row(true)}});
        Check(RejoinControl.Find(root, new[] {"Fixture"}) == null, "disabled control hidden");
        Write("controls.json",new {controls = new[] {Row(false),Row(false)}});
        Check(RejoinControl.Find(root, new[] {"Fixture"}) == null, "ambiguous controls refused");
        Write("controls.json",new {controls = new[] {Row(false)}});
        File.WriteAllText(Path.Combine(root,"INSUI","helper","config.json"),"{\"scripts\":{\"Fixture\":{\"dashboard\":false}}}");
        Check(RejoinControl.Find(root, new[] {"Fixture"}) == null, "helper off switch respected");
        Check(RejoinControl.Find(root, new[] {"../Fixture"}) == null, "path traversal refused");
        Check(RejoinControl.Find(root, new string[0]) == null, "sleeping has no control");
        Console.WriteLine(checks+" auto rejoin control checks passed");
    }
}
