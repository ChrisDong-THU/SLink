using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;

namespace SLink {
internal static class Program {
    const string InstanceName=@"Local\SLink.Native.Desktop";
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    [STAThread] static int Main(string[] args) {
        try {
            if(args.Contains("--quit") || args.Contains("--prepare-install")) {
                bool signaled=false;
                try { using(var signal=EventWaitHandle.OpenExisting(InstanceName+".Quit")) {signal.Set();signaled=true;} } catch(WaitHandleCannotBeOpenedException) {}
                if(signaled && (args.Contains("--wait") || args.Contains("--prepare-install"))) {
                    try { using(var mutex=Mutex.OpenExisting(InstanceName)) { try {if(!mutex.WaitOne(50000))return 1;}catch(AbandonedMutexException){} mutex.ReleaseMutex();} } catch(WaitHandleCannotBeOpenedException) {}
                }
                if(!signaled && File.Exists(Path.Combine(Core.Data,"session.json"))) { var result=Core.Native("Stop"); if(!Core.Yes(result,"ok"))return 2; }
                if(args.Contains("--prepare-install")) {
                    int i=Array.IndexOf(args,"--prepare-install");if(i+1>=args.Length)return 3;
                    string old=Path.GetFullPath(args[i+1]);
                    foreach(var p in Process.GetProcessesByName("SLink")) using(p) {
                        if(p.Id==Process.GetCurrentProcess().Id)continue;
                        try { if(string.Equals(p.MainModule.FileName,old,StringComparison.OrdinalIgnoreCase) && p.MainModule.FileVersionInfo.FileMajorPart<=1 && p.MainModule.FileVersionInfo.FileMinorPart==0) {p.Kill();p.WaitForExit(5000);} }catch(InvalidOperationException){}
                    }
                }
                return File.Exists(Path.Combine(Core.Data,"session.json"))?2:0;
            }
            bool created;
            using(var mutex=new Mutex(true,InstanceName,out created)) {
                if(!created) {
                    for(int i=0;i<20;i++) {try {using(var signal=EventWaitHandle.OpenExisting(InstanceName+".Show"))signal.Set();return 0;}catch(WaitHandleCannotBeOpenedException){Thread.Sleep(100);}}
                    return 1;
                }
                try {
                    Core.ResetExit();SetCurrentProcessExplicitAppUserModelID("SLink.Desktop");
                    var app=new Application {ShutdownMode=ShutdownMode.OnExplicitShutdown};
                    app.DispatcherUnhandledException+=(s,e)=> {Core.Log(e.Exception.ToString());MessageBox.Show("操作未完成："+e.Exception.Message,"SLink");e.Handled=true;};
                    var window=new MainWindow(args.Contains("--preview"));app.MainWindow=window.Window;
                    using(var show=new EventWaitHandle(false,EventResetMode.AutoReset,InstanceName+".Show"))
                    using(var quit=new EventWaitHandle(false,EventResetMode.AutoReset,InstanceName+".Quit")) {
                        var showWait=ThreadPool.RegisterWaitForSingleObject(show,(s,t)=>app.Dispatcher.BeginInvoke(new Action(window.Reveal)),null,-1,false);
                        var quitWait=ThreadPool.RegisterWaitForSingleObject(quit,(s,t)=>app.Dispatcher.BeginInvoke(new Action(async()=>await window.Exit())),null,-1,false);
                        Core.Log("Starting SLink "+Core.Version);window.Window.Show();int result=app.Run();showWait.Unregister(null);quitWait.Unregister(null);Core.Log("Stopped SLink");return result;
                    }
                } finally {mutex.ReleaseMutex();}
            }
        } catch(Exception e) {Core.Log(e.ToString());MessageBox.Show("启动失败："+e.Message,"SLink");return 1;}
    }
}
}
