using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SLink {
internal static class Tests {
    [STAThread] static int Main(string[] args) { return Run(args); }
    static int count;
    static void Check(bool value,string message) {if(!value)throw new Exception(message);count++;}
    public static int Run(string[] args) {
        string output=args.Length>1?Path.GetFullPath(args[1]):Path.Combine(Core.Root,"test-result.json");
        string temp=Path.Combine(Path.GetDirectoryName(output),"test-data");Directory.CreateDirectory(temp);Core.Data=temp;
        try {
            Check(Core.ValidPort(1)&&Core.ValidPort(65535)&&!Core.ValidPort(0)&&!Core.ValidPort(65536),"port bounds");
            Core.SavePort(1080);Check(Core.Port==1080,"settings roundtrip");
            Core.SavePort(1081);Check(Core.Port==1081,"atomic settings replacement");
            File.WriteAllText(Path.Combine(temp,"settings.json"),"corrupt");Check(Core.Port==7890,"corrupt settings");
            File.WriteAllText(Path.Combine(temp,"preferences.json"),"null");Check(Core.Load("preferences.json").Count==0,"null preferences cannot crash startup");
            var d=Core.Object("{\"ok\":true,\"devices\":[{\"mac\":\"aa\"}]}");Check(Core.Yes(d,"ok")&&Core.Rows(d,"devices").Count()==1,"JSON state");
            Check(!Core.Yes(d,"missing")&&Core.Text(d,"missing","fallback")=="fallback","missing state");
            var addresses=new Dictionary<string,object>();var devices=Core.Object("{\"devices\":[{\"mac\":\"02-00-00-00-00-01\",\"names\":[\"audiocast\",\"192.168.137.10\"]}]}");
            Check(Core.RememberDeviceAddresses(addresses,Core.Rows(devices,"devices")).Count==0,"first discovery is not an address change");
            Check(Core.RememberDeviceAddresses(addresses,Core.Rows(devices,"devices")).Count==0,"same address does not prompt restart");
            devices=Core.Object("{\"devices\":[{\"mac\":\"02:00:00:00:00:01\",\"names\":[\"audiocast\",\"192.168.137.127\"]}]}");
            Check(Core.RememberDeviceAddresses(addresses,Core.Rows(devices,"devices")).Single()=="192.168.137.10 → 192.168.137.127","DHCP address change detected across restarts");
            Core.RememberDeviceAddresses(addresses,new Dictionary<string,object>[0]);Check(Core.Text(addresses,"02:00:00:00:00:01")=="192.168.137.127","disconnect retains last known address");
            var session=Core.Object("{\"owned\":true,\"pid\":10,\"adapterGuid\":\"abc\"}");
            var health=Core.Object("{\"ok\":true,\"pid\":10,\"adapterGuid\":\"ABC\"}");health["checkedAt"]=DateTime.UtcNow.ToString("o");
            Check(Core.Healthy(session,health),"current relay health");
            health["checkedAt"]=DateTime.UtcNow.AddMinutes(-3).ToString("o");Check(!Core.Healthy(session,health),"reject stale successful check");
            Check(!Core.Healthy(session,Core.Object("{\"ok\":true,\"pid\":9,\"adapterGuid\":\"abc\"}")),"reject health from old relay");
            Check(!Core.Healthy(session,Core.Object("{\"ok\":true}")),"direct proxy test cannot validate tunnel");
            var monitor=new HealthMonitor();var now=DateTime.UtcNow;
            var failure=Core.Object("{\"ok\":false,\"pid\":10,\"adapterGuid\":\"abc\",\"code\":\"hotspot-dns\"}");
            failure["checkedAt"]=now.AddMinutes(-3).ToString("o");
            Check(!monitor.Observe(session,failure,now)&&monitor.Failures==0,"stale failure cannot trigger repair");
            failure["checkedAt"]=now.AddMinutes(1).ToString("o");
            Check(!monitor.Observe(session,failure,now)&&monitor.Failures==0,"future failure cannot trigger repair");
            Func<bool> observe=()=> {now=now.AddSeconds(30);failure["checkedAt"]=now.ToString("o");return monitor.Observe(session,failure,now);};
            Check(!observe()&&!observe(),"transient DNS failures do not restart connection");
            Check(!monitor.Observe(session,failure,now)&&monitor.Failures==2,"duplicate result does not count as a new failure");
            Check(observe(),"third confirmed DNS failure requests narrow repair");
            Check(!observe()&&!observe()&&!observe(),"repair cooldown");
            now=now.AddMinutes(6);Check(observe(),"repair may retry after cooldown");
            now=now.AddMinutes(6);Check(!observe()&&!observe()&&!observe(),"two repair limit per session");
            monitor.Observe(new Dictionary<string,object>(),failure,now);
            Check(!observe(),"failed inspection must not reset relay repair budget");
            monitor=new HealthMonitor();failure["code"]="https";
            for(int i=0;i<5;i++)Check(!observe(),"upstream failure never rebuilds hotspot");
            failure["code"]="hotspot-dns";observe();now=now.AddSeconds(30);health["checkedAt"]=now.ToString("o");monitor.Observe(session,health,now);
            Check(monitor.Failures==0,"success clears failure streak");
            failure["pid"]=9;Check(!monitor.Observe(session,failure,now)&&monitor.Failures==0,"stale PID cannot trigger repair");
            var listener=new TcpListener(IPAddress.Loopback,0);listener.Start();int port=((IPEndPoint)listener.LocalEndpoint).Port;
            var thread=new Thread(()=> {try{using(var c=listener.AcceptTcpClient()){c.ReceiveTimeout=2000;var s=c.GetStream();for(int i=0;i<3;i++)s.ReadByte();s.WriteByte(5);Thread.Sleep(15);s.WriteByte(0);}}catch(SocketException){}catch(IOException){}});thread.IsBackground=true;thread.Start();try{Check(Core.Socks(port,3000),"fragmented SOCKS response");Check(thread.Join(3000),"SOCKS test worker exits");}finally{listener.Stop();}
            var result=Core.Run("cmd.exe","/c echo slink","probe",2000);Check(result.Item1==0&&result.Item2.Trim()=="slink","child output");
            result=Core.Run("cmd.exe","/c for /L %i in (1,1,2000) do @echo slink-%i","probe",10000);
            Check(result.Item1==0&&result.Item2.TrimEnd().EndsWith("slink-2000")&&result.Item2.Split(new[]{'\n'},StringSplitOptions.RemoveEmptyEntries).Length==2000,"drain complete child output after exit");
            Core.RequestExit();bool canceled=false;try {Core.Run("cmd.exe","/c exit","probe",1000);}catch(OperationCanceledException){canceled=true;}Check(canceled,"exit cancellation");Core.ResetExit();
            var app=new Application {ShutdownMode=ShutdownMode.OnExplicitShutdown};var ui=new MainWindow(true);ui.Window.Show();ui.Window.UpdateLayout();
            Check(ui.Get<Button>("Primary")!=null&&ui.Get<Button>("PortButton")!=null,"UI controls");
            Check(ui.Get<TextBlock>("StatusTitle").Text=="热点就绪","online state");
            Check(ui.Get<StackPanel>("Devices").Children.Count==1,"device list");
            var target=new RenderTargetBitmap((int)ui.Window.ActualWidth,(int)ui.Window.ActualHeight,96,96,PixelFormats.Pbgra32);target.Render(ui.Window);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(target));using(var f=File.Create(Path.Combine(Path.GetDirectoryName(output),"native-preview.png")))encoder.Save(f);
            ui.Window.Close();Check(!ui.Window.IsVisible,"close hides to tray");ui.Reveal();Check(ui.Window.IsVisible,"reopen");ui.Window.Hide();
            File.WriteAllText(output,Core.Json(new {ok=true,passed=count,version=Core.Version}));return 0;
        } catch(Exception e) {File.WriteAllText(output,Core.Json(new {ok=false,passed=count,error=e.ToString()}));return 1;}
    }
}
}
