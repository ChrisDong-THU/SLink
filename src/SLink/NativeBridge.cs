using System;
using System.Collections.Generic;
using System.IO;

namespace SLink {
// Atomic per-request JSON results isolate operation completion from relay lifetime.
internal static class NativeBridge {
    public static Dictionary<string,object> RunResult(string file,string args,string category,int timeout) {
        Directory.CreateDirectory(Core.Data);
        string path=Path.Combine(Core.Data,"result-"+Guid.NewGuid().ToString("N")+".json");
        try {
            // A detached relay may inherit pipe handles. Completion belongs to the
            // command process and its atomic result file, never to the relay's EOF.
            var process=ProcessRunner.Run(file,args+" -ResultPath "+Core.Quote(path),category,timeout,false);
            if(!File.Exists(path))return Core.Error("系统操作未返回结果（退出码 "+process.Item1+"），请查看诊断日志");
            var result=Core.Object(File.ReadAllText(path));object ok;
            if(!result.TryGetValue("ok",out ok)||!(ok is bool))return Core.Error("系统操作返回了无效的连接状态");
            if(process.Item1!=0&&Core.Yes(result,"ok"))return Core.Error("系统操作异常退出（退出码 "+process.Item1+"）");
            return result;
        } finally {
            // A temporary-file cleanup failure must not turn a completed network
            // operation into a false failure. Retain diagnostics for later cleanup.
            try {if(File.Exists(path))File.Delete(path);}
            catch(IOException e) {Core.Log("Result cleanup: "+e.Message);}
            catch(UnauthorizedAccessException e) {Core.Log("Result cleanup: "+e.Message);}
        }
    }
    public static Dictionary<string,object> Execute(string action,bool takeover=false,string previous="",bool fast=false) {
        try {
            Directory.CreateDirectory(Core.Data);
            int timeout=TimeoutFor(action,fast);
            string args="-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "+Core.Quote(Path.Combine(Core.Root,"native","network.ps1"))+" -Action "+action+" -DataDir "+Core.Quote(Core.Data)+" -Engine "+Core.Quote(Path.Combine(Core.Root,"bin","hev-socks5-tunnel.exe"))+" -ProxyPort "+Core.Port;
            if(takeover) args+=" -Takeover"; if(fast) args+=" -FastExit";
            if(previous.Length>0) args+=" -PreviousGuid "+Core.Quote(Guid.Parse(previous).ToString());
            return RunResult(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell","v1.0","powershell.exe"),args,action.ToLowerInvariant(),timeout);
        } catch(Exception e) { return Core.Error(e is OperationCanceledException?"操作已取消":e.Message); }
    }
    static int TimeoutFor(string action,bool fast) {
        switch(action) {
            case "Inspect": return 25000;
            case "Check": return 90000;
            case "Stop": return fast?18000:60000;
            case "Start": case "Resume": case "Repair": case "TestTunnel": return 150000;
            default: throw new ArgumentException("未知网络操作："+action);
        }
    }
}
}
