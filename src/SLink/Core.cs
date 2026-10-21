using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Text;
using System.Web.Script.Serialization;

namespace SLink {
internal static class Core {
    public const string Version = AppInfo.Version;
    public static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;
    public static string Data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SLink");
    static readonly object Gate = new object();
    public static Dictionary<string,object> Object(string json) { return new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(json) ?? new Dictionary<string,object>(); }
    public static string Json(object value) { return new JavaScriptSerializer().Serialize(value); }
    public static string Text(IDictionary<string,object> d, string key, string fallback = "") { object v; return d != null && d.TryGetValue(key,out v) && v != null ? Convert.ToString(v) : fallback; }
    public static bool Yes(IDictionary<string,object> d, string key) { object v; return d != null && d.TryGetValue(key,out v) && v is bool && (bool)v; }
    public static bool Fresh(IDictionary<string,object> health, DateTime now) {
        DateTime checkedAt;
        return DateTime.TryParse(Text(health,"checkedAt"),null,System.Globalization.DateTimeStyles.RoundtripKind,out checkedAt) && now-checkedAt.ToUniversalTime()<TimeSpan.FromMinutes(2) && checkedAt.ToUniversalTime()<=now.AddSeconds(5);
    }
    public static bool Healthy(IDictionary<string,object> state, IDictionary<string,object> health) {
        return Yes(health,"ok") && Fresh(health,DateTime.UtcNow) && (!Yes(state,"owned") || (Text(state,"pid").Length>0 && Text(state,"adapterGuid").Length>0 && Text(state,"pid")==Text(health,"pid") && Text(state,"adapterGuid").Equals(Text(health,"adapterGuid"),StringComparison.OrdinalIgnoreCase)));
    }
    public static IEnumerable<Dictionary<string,object>> Rows(IDictionary<string,object> d, string key) {
        object value; if(d == null || !d.TryGetValue(key,out value) || !(value is IEnumerable)) yield break;
        foreach(object item in (IEnumerable)value) { var row=item as Dictionary<string,object>; if(row != null) yield return row; }
    }
    public static List<string> RememberDeviceAddresses(IDictionary<string,object> addresses,IEnumerable<Dictionary<string,object>> devices) {
        var changes=new List<string>();
        foreach(var device in devices) {
            string mac=Text(device,"mac").ToLowerInvariant().Replace('-',':');
            object raw;if(mac.Length==0 || !device.TryGetValue("names",out raw) || !(raw is IEnumerable))continue;
            bool speaker=((IEnumerable)raw).Cast<object>().Select(Convert.ToString).Any(n=>n.IndexOf("audiocast",StringComparison.OrdinalIgnoreCase)>=0 || n.IndexOf("jbl",StringComparison.OrdinalIgnoreCase)>=0 || n.IndexOf("speaker",StringComparison.OrdinalIgnoreCase)>=0);
            if(!speaker)continue;
            foreach(object name in (IEnumerable)raw) {
                System.Net.IPAddress ip;
                if(!System.Net.IPAddress.TryParse(Convert.ToString(name),out ip) || ip.AddressFamily!=AddressFamily.InterNetwork)continue;
                string next=ip.ToString(),previous=Text(addresses,mac);
                if(previous.Length>0 && previous!=next)changes.Add(previous+" → "+next);
                addresses[mac]=next;break;
            }
        }
        return changes;
    }
    public static void Save(string name, object value) {
        Directory.CreateDirectory(Data); string path=Path.Combine(Data,name), temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        try {
            File.WriteAllText(temp, Json(value), new UTF8Encoding(false));
            if(File.Exists(path)) File.Replace(temp,path,null); else File.Move(temp,path);
        }
        finally { if(File.Exists(temp)) File.Delete(temp); }
    }
    public static Dictionary<string,object> Load(string name) {
        try { return Object(File.ReadAllText(Path.Combine(Data,name))); }
        catch(IOException) { return new Dictionary<string,object>(); } catch(ArgumentException) { return new Dictionary<string,object>(); } catch(InvalidOperationException) { return new Dictionary<string,object>(); }
    }
    public static int Port { get { int value; return int.TryParse(Text(Load("settings.json"),"port"),out value) && ValidPort(value) ? value : 7890; } }
    public static bool ValidPort(int port) { return port > 0 && port <= 65535; }
    public static void SavePort(int port) { if(!ValidPort(port)) throw new ArgumentException("端口应为 1–65535"); Save("settings.json",new { host="127.0.0.1", port=port }); }
    public static void Log(string message) {
        lock(Gate) { try { Directory.CreateDirectory(Data); string p=Path.Combine(Data,"app.log"); if(File.Exists(p) && new FileInfo(p).Length>512000) File.Delete(p); File.AppendAllText(p,DateTime.Now.ToString("s")+" "+message+Environment.NewLine); } catch(IOException) {} catch(UnauthorizedAccessException) {} }
    }
    public static string Quote(string value) { return "\""+value.Replace("\"", "\\\"")+"\""; }
    public static Dictionary<string,object> Error(string text) { return new Dictionary<string,object>{{"ok",false},{"error",text}}; }
    public static void RequestExit() { ProcessRunner.BeginShutdown(); Directory.CreateDirectory(Data); File.WriteAllText(Path.Combine(Data,"cancel.flag"),""); ProcessRunner.Cancel("inspect","probe","check"); }
    public static void ResetExit() { ProcessRunner.ResetShutdown(); string p=Path.Combine(Data,"cancel.flag"); if(File.Exists(p)) File.Delete(p); }
    public static bool Socks(int port,int timeout=1000) {
        try { using(var c=new TcpClient()) { var connect=c.BeginConnect("127.0.0.1",port,null,null); using(connect.AsyncWaitHandle) if(!connect.AsyncWaitHandle.WaitOne(timeout)) return false; c.EndConnect(connect); c.ReceiveTimeout=timeout;c.SendTimeout=timeout;
            var stream=c.GetStream();stream.Write(new byte[]{5,1,0},0,3);return stream.ReadByte()==5 && stream.ReadByte()==0;
        }} catch(SocketException) { return false; } catch(IOException) { return false; }
    }
    public static Dictionary<string,object> Probe(int port) {
        try {
            if(File.Exists(Path.Combine(Data,"session.json")))return NativeBridge.Execute("Check");
            if(ProcessRunner.Closing || !Socks(port)) return Error("无法连接本机代理，请检查 Clash 和端口");
            var r=ProcessRunner.Run("curl.exe","--proxy socks5h://127.0.0.1:"+port+" --head --max-time 10 --connect-timeout 4 -sS -o NUL -w %{http_code} https://www.qobuz.com/","probe",14000);
            int status; bool ok=r.Item1==0 && int.TryParse(r.Item2.Trim(),out status) && status>=200 && status<400;
            return ok?new Dictionary<string,object>{{"ok",true},{"checkedAt",DateTime.UtcNow.ToString("o")}}:Error("代理无法访问 Qobuz，请检查节点");
        } catch(Exception e) { return Error(e is OperationCanceledException?"检测已取消":e.Message); }
    }
    public static int DetectPort() {
        var ports=new List<int>();
        using(var key=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings")) {
            foreach(System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(Convert.ToString(key==null?null:key.GetValue("ProxyServer")),@"(?:127\.0\.0\.1|localhost):(\d+)")) { int p; if(int.TryParse(m.Groups[1].Value,out p) && ValidPort(p)) ports.Add(p); }
        }
        ports.AddRange(new[]{7890,7897,10808,1080});
        foreach(int port in ports.Distinct()) if(!ProcessRunner.Closing && Socks(port,400)) return port;
        return 0;
    }
}
}
