using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SLink {
// Owns only short-lived helper processes, never the journaled relay itself.
internal static class ProcessRunner {
    static readonly object Gate=new object();
    static readonly Dictionary<Process,string> Children=new Dictionary<Process,string>();
    static volatile bool closing;
    public static bool Closing { get { return closing; } }
    public static void BeginShutdown() { lock(Gate) closing=true; }
    public static void ResetShutdown() { lock(Gate) closing=false; }
    public static Tuple<int,string,string> Run(string file,string args,string category,int timeout,bool captureOutput=true) {
        var stdout=new StringBuilder(); var stderr=new StringBuilder();
        var outputEnded=new TaskCompletionSource<bool>(); var errorEnded=new TaskCompletionSource<bool>();
        using(var p=new Process()) {
            p.StartInfo=new ProcessStartInfo(file,args) { UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=captureOutput,RedirectStandardError=captureOutput };
            if(captureOutput){p.StartInfo.StandardOutputEncoding=Encoding.UTF8;p.StartInfo.StandardErrorEncoding=Encoding.UTF8;}
            p.OutputDataReceived+=(s,e)=> { if(e.Data==null) outputEnded.TrySetResult(true); else lock(stdout) stdout.AppendLine(e.Data); };
            p.ErrorDataReceived+=(s,e)=> { if(e.Data==null) errorEnded.TrySetResult(true); else lock(stderr) stderr.AppendLine(e.Data); };
            lock(Gate) { if(Closing && category!="stop") throw new OperationCanceledException(); p.Start(); Children[p]=category; }
            try {
                if(captureOutput){p.BeginOutputReadLine();p.BeginErrorReadLine();}
                if(!p.WaitForExit(timeout)) { p.Kill(); p.WaitForExit(2000); throw new TimeoutException("系统操作超时"); }
                // Do not wait indefinitely for EOF inherited by a detached helper.
                if(captureOutput&&!Task.WaitAll(new Task[]{outputEnded.Task,errorEnded.Task},2000)) throw new IOException("系统操作的输出未完整结束，请重新检测");
                lock(stdout) lock(stderr) return Tuple.Create(p.ExitCode,stdout.ToString(),stderr.ToString());
            } finally { lock(Gate) Children.Remove(p); }
        }
    }
    public static void Cancel(params string[] kinds) {
        lock(Gate) foreach(var item in Children.ToArray()) if(kinds.Contains(item.Value)) try { if(!item.Key.HasExited) item.Key.Kill(); } catch(InvalidOperationException) {} catch(System.ComponentModel.Win32Exception) {}
    }
    public static void CancelAll() { Cancel("inspect","probe","check","start","resume","repair","stop","testtunnel"); }
}
}
