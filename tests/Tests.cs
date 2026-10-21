using System;
using System.IO;
using System.Linq;
using System.Threading;

namespace SLink {
internal static partial class Tests {
    [STAThread] static int Main(string[] args) {
        if(args.Contains("--hold-output")){Thread.Sleep(8000);return 0;}
        if(args.Contains("--result-fixture")) {
            string path=args[Array.IndexOf(args,"-ResultPath")+1];
            if(args.Contains("--missing"))return 3;
            if(args.Contains("--failure")){File.WriteAllText(path,"{\"ok\":false,\"error\":\"fixture failure\"}");return 0;}
            if(args.Contains("--invalid")){File.WriteAllText(path,"{\"ok\":\"true\"}");return 0;}
            if(args.Contains("--crashed")){File.WriteAllText(path,"{\"ok\":true}");return 7;}
            var child=System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(System.Reflection.Assembly.GetExecutingAssembly().Location,"--hold-output"){UseShellExecute=false,CreateNoWindow=true});
            File.WriteAllText(path,Core.Json(new {ok=true,childPid=child.Id}));child.Dispose();return 0;
        }
        return Run(args);
    }
    static int count;
    static void Check(bool value,string message) {if(!value)throw new Exception(message);count++;}
    static void Pump(int milliseconds) {
        var frame=new System.Windows.Threading.DispatcherFrame();
        var timer=new System.Windows.Threading.DispatcherTimer {Interval=TimeSpan.FromMilliseconds(milliseconds)};
        timer.Tick+=(s,e)=> {timer.Stop();frame.Continue=false;};timer.Start();System.Windows.Threading.Dispatcher.PushFrame(frame);
    }
    public static int Run(string[] args) {
        string output=args.Length>1?Path.GetFullPath(args[1]):Path.Combine(Core.Root,"test-result.json");
        string temp=Path.Combine(Path.GetDirectoryName(output),"test-data");Directory.CreateDirectory(temp);Core.Data=temp;
        try {
            RunCoreChecks(temp);
            RunPresentationChecks();
            RunUiChecks(output,temp);
            File.WriteAllText(output,Core.Json(new {ok=true,passed=count,version=Core.Version}));return 0;
        } catch(Exception e) {File.WriteAllText(output,Core.Json(new {ok=false,passed=count,error=e.ToString()}));return 1;}
    }
}
}
