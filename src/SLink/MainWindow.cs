using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using IOPath = System.IO.Path;

namespace SLink {
internal sealed class MainWindow {
    public readonly Window Window;
    readonly Forms.NotifyIcon tray;
    readonly DispatcherTimer poll, probeTimer, progress;
    Dictionary<string,object> state=new Dictionary<string,object>(), proxy=new Dictionary<string,object>(), prefs=Core.Load("preferences.json");
    Dictionary<string,object> aliases;
    Dictionary<string,object> deviceAddresses;
    bool rediscoverQobuz, restartingQobuz;
    readonly Dictionary<string,Button> deviceRows=new Dictionary<string,Button>();
    readonly List<string> events=new List<string>();
    readonly HealthMonitor healthMonitor=new HealthMonitor();
    List<Dictionary<string,object>> sources=new List<Dictionary<string,object>>();
    Task<Dictionary<string,object>> operation;
    bool polling, probing, exiting, allowClose, showPassword, checking=true;
    int epoch, stage;
    DateTime operationStarted;
    string error="", operationName="", stageText="", lastProgress="", dialog="", deviceKey="", lastMode="";
    readonly Brush blue=new SolidColorBrush(Color.FromRgb(0,102,204));
    readonly Brush muted=new SolidColorBrush(Color.FromRgb(110,110,115));
    static readonly Dictionary<string,string> Paths=new Dictionary<string,string> {
        {"power","M12,3 L12,11 M6.2,5.5 A8,8 0 1 0 17.8,5.5"},
        {"close","M6,6 L18,18 M18,6 L6,18"},{"minus","M5,12 L19,12"},
        {"wifi","M3,8 Q12,1 21,8 M6,12 Q12,7 18,12 M9,16 Q12,13 15,16 M12,19 L12.01,19"},
        {"edit","M14,5 L19,10 M5,19 L6,14 L16,4 Q18,2 20,4 Q22,6 20,8 L10,18 Z"},
        {"eye","M2,12 Q12,0 22,12 Q12,24 2,12 M15,12 A3,3 0 1 0 9,12 A3,3 0 1 0 15,12"},
        {"eye-off","M3,3 L21,21 M8,6 Q16,3 22,12 Q20,16 18,17 M5,8 Q3,10 2,12 Q7,20 15,18 M10,10 A3,3 0 0 0 14,14"},
        {"lock","M5,10 L19,10 L19,21 L5,21 Z M8,10 L8,7 A4,4 0 0 1 16,7 L16,10 M12,14 L12,17"},
        {"copy","M8,8 L20,8 L20,21 L8,21 Z M4,16 L4,3 L16,3"},
        {"refresh","M20,9 A8,8 0 1 0 20,15 M20,3 L20,9 L14,9"},
        {"info","M12,11 L12,17 M12,7 L12.01,7 M22,12 A10,10 0 1 0 2,12 A10,10 0 1 0 22,12"},
        {"music","M9,17 L9,5 L20,3 L20,15 M9,17 A3,2 0 1 0 3,17 A3,2 0 1 0 9,17 M20,15 A3,2 0 1 0 14,15 A3,2 0 1 0 20,15"},
        {"speaker","M5,3 L19,3 L19,21 L5,21 Z M12,7 L12.01,7 M16,15 A4,4 0 1 0 8,15 A4,4 0 1 0 16,15"},
        {"phone","M7,2 L17,2 Q19,2 19,4 L19,20 Q19,22 17,22 L7,22 Q5,22 5,20 L5,4 Q5,2 7,2 Z M10,18 L14,18"},
        {"device","M3,4 L21,4 L21,17 L3,17 Z M12,17 L12,21 M8,21 L16,21"},
        {"check","M5,12 L10,17 L20,6"}
    };
    public T Get<T>(string name) where T:class { return Window.FindName(name) as T; }
    static UIElement Icon(string name,Brush color,double size=19) {
        var path=new System.Windows.Shapes.Path { Data=Geometry.Parse(Paths[name]),Stroke=color,StrokeThickness=1.7,StrokeStartLineCap=PenLineCap.Round,StrokeEndLineCap=PenLineCap.Round,StrokeLineJoin=PenLineJoin.Round };
        var grid=new Grid {Width=24,Height=24};grid.Children.Add(path);
        return new Viewbox {Width=size,Height=size,Child=grid};
    }
    void ButtonIcon(string name,string glyph,string text="",bool primary=false) {
        var stack=new StackPanel {Orientation=Orientation.Horizontal}; stack.Children.Add(Icon(glyph,primary?Brushes.White:blue,Get<Button>(name).Style==Window.Resources["CardIconButton"]?18:19));
        if(text.Length>0) stack.Children.Add(new TextBlock {Text=text,Foreground=primary?Brushes.White:blue,Margin=new Thickness(8,0,0,0),VerticalAlignment=VerticalAlignment.Center});
        Get<Button>(name).Content=stack;
    }
    void Click(string name,RoutedEventHandler handler) { Get<Button>(name).Click+=handler; }
    public MainWindow(bool preview=false) {
        using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("Main.xaml")) Window=(Window)XamlReader.Load(stream);
        using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico")) Window.Icon=System.Windows.Media.Imaging.BitmapFrame.Create(stream);
        aliases=Core.Text(prefs,"aliases").Length>0 && prefs["aliases"] is Dictionary<string,object> ? (Dictionary<string,object>)prefs["aliases"] : new Dictionary<string,object>();
        prefs["aliases"]=aliases;
        object savedAddresses;
        deviceAddresses=prefs.TryGetValue("device_addresses",out savedAddresses) && savedAddresses is Dictionary<string,object>?(Dictionary<string,object>)savedAddresses:new Dictionary<string,object>();
        prefs["device_addresses"]=deviceAddresses;
        ButtonIcon("Minimize","minus");ButtonIcon("HideButton","close");ButtonIcon("EditHotspot","edit");ButtonIcon("ShowPassword","eye");ButtonIcon("CopyPassword","copy");ButtonIcon("Refresh","refresh");ButtonIcon("Diagnostics","info");ButtonIcon("Qobuz","music","Qobuz");
        Get<Viewbox>("WifiGlyph").Child=Icon("wifi",blue,24);
        Get<Viewbox>("PasswordGlyph").Child=Icon("lock",muted,18);
        Get<Grid>("Chrome").MouseLeftButtonDown+=(s,e)=> { if(e.ClickCount==1 && e.OriginalSource is Grid) Window.DragMove(); };
        Click("Minimize",(s,e)=>Window.WindowState=WindowState.Minimized);
        Click("HideButton",(s,e)=>Window.Hide());
        Window.Closing+=(s,e)=> { if(!allowClose) { e.Cancel=true; Window.Hide(); } };
        Window.SourceInitialized+=(s,e)=> { try { int preference=2; DwmSetWindowAttribute(new System.Windows.Interop.WindowInteropHelper(Window).Handle,33,ref preference,4); } catch(DllNotFoundException) {} };
        Click("Primary",async(s,e)=>await Primary());
        Click("Refresh",async(s,e)=> { await Poll(); await Probe(); });
        Click("EditHotspot",(s,e)=>Open("ms-settings:network-mobilehotspot"));
        Click("ShowPassword",(s,e)=> { showPassword=!showPassword; RenderPassword(); });
        Click("CopyPassword",async(s,e)=> { try { Clipboard.SetText(Core.Text(state,"password"));ButtonIcon("CopyPassword","check");await Task.Delay(1200);ButtonIcon("CopyPassword","copy"); } catch(ExternalException) { SetError("剪贴板暂时不可用，请重试"); } });
        Click("Qobuz",async(s,e)=>await OpenQobuz());
        var qobuzMenu=new ContextMenu();var rediscover=new MenuItem {Header="重新发现音响（重启 Qobuz）"};
        rediscover.Click+=async(s,e)=> {rediscoverQobuz=true;await OpenQobuz();};qobuzMenu.Items.Add(rediscover);Get<Button>("Qobuz").ContextMenu=qobuzMenu;
        Click("PortButton",(s,e)=>ShowDialog("port","代理端口",Core.Port.ToString()));
        Click("Diagnostics",(s,e)=>ShowDialog("logs","诊断",string.Join(Environment.NewLine,events)+(error.Length>0?Environment.NewLine+error:"")+Environment.NewLine+Core.Json(proxy)));
        Click("DialogCancel",(s,e)=>Get<Grid>("Overlay").Visibility=Visibility.Collapsed);
        Click("DialogSave",async(s,e)=>await SaveDialog());
        Click("DialogExtra",async(s,e)=> {
            if(dialog=="logs") { var d=new Microsoft.Win32.SaveFileDialog {FileName="SLink-诊断.txt",Filter="文本|*.txt"}; if(d.ShowDialog(Window)==true) try {File.WriteAllText(d.FileName,"SLink "+Core.Version+Environment.NewLine+Get<TextBox>("DialogLogs").Text);} catch(IOException ex) {Get<TextBlock>("DialogError").Text=ex.Message;} return; }
            Get<Button>("DialogExtra").IsEnabled=false; int port=await Task.Run(()=>Core.DetectPort());
            if(port>0) Get<TextBox>("DialogInput").Text=port.ToString(); else Get<TextBlock>("DialogError").Text="未发现可用端口";
            Get<Button>("DialogExtra").IsEnabled=true;
        });
        tray=new Forms.NotifyIcon(); using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico")) tray.Icon=new System.Drawing.Icon(stream);
        tray.Text="SLink";var menu=new Forms.ContextMenuStrip();menu.Items.Add("打开",null,(s,e)=>Reveal());menu.Items.Add("停止连接",null,async(s,e)=> { if(Core.Yes(state,"owned") || Core.Yes(state,"recovery")) await Operate("Stop"); });menu.Items.Add(new Forms.ToolStripSeparator());menu.Items.Add("退出 SLink",null,async(s,e)=>await Exit());tray.ContextMenuStrip=menu;tray.DoubleClick+=(s,e)=>Reveal();tray.Visible=!preview;
        poll=Timer(4,async()=>await Poll());probeTimer=Timer(30,async()=>await Probe());progress=Timer(.3,ReadProgress);
        Window.IsVisibleChanged+=(s,e)=>Render();
        if(preview) { state=Core.Object("{\"ok\":true,\"hotspot\":\"On\",\"owned\":true,\"adapter\":true,\"managed\":true,\"ssid\":\"音响热点\",\"password\":\"preview\",\"devices\":[{\"mac\":\"00:01:02:03:04:05\",\"names\":[\"JBL Authentics 300\",\"192.168.137.2\"]}]}");state["pid"]=1;state["adapterGuid"]="preview";proxy=new Dictionary<string,object>{{"ok",true},{"pid",1},{"adapterGuid","preview"},{"checkedAt",DateTime.UtcNow.ToString("o")}};checking=false; }
        else { poll.Start();probeTimer.Start();progress.Start();Window.Loaded+=async(s,e)=> {await Poll();await Probe();}; }
        Render();
    }
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd,int attribute,ref int value,int size);
    DispatcherTimer Timer(double seconds,Action callback) { var t=new DispatcherTimer {Interval=TimeSpan.FromSeconds(seconds)};t.Tick+=(s,e)=>callback();return t; }
    public void Reveal() { if(exiting)return;Window.Show();Window.WindowState=WindowState.Normal;Window.Activate(); }
    void Open(string target) { try { Process.Start(new ProcessStartInfo(target){UseShellExecute=true}); } catch(Exception e) {SetError(e.Message);} }
    async Task OpenQobuz() {
        if(restartingQobuz)return;
        string folder=IOPath.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Qobuz");
        string exe=Directory.Exists(folder)?Directory.GetDirectories(folder,"app-*").Select(p=>IOPath.Combine(p,"Qobuz.exe")).Where(File.Exists).OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault():null;
        if(!rediscoverQobuz || exe==null){Open(exe??"https://play.qobuz.com/");return;}
        restartingQobuz=true;Get<Button>("Qobuz").IsEnabled=false;
        try {
            foreach(var process in Process.GetProcessesByName("Qobuz"))using(process) {
                if(process.MainWindowHandle==IntPtr.Zero)continue;
                if(!string.Equals(process.MainModule.FileName,exe,StringComparison.OrdinalIgnoreCase))continue;
                if(!process.CloseMainWindow())throw new InvalidOperationException("请先退出 Qobuz，再重新发现音响。");
                bool ended=await Task.Run(()=>process.WaitForExit(10000));
                if(!ended)throw new InvalidOperationException("Qobuz 尚未退出，请关闭后重试。");
            }
            if(exiting)return;
            Open(exe);rediscoverQobuz=false;Note("已重启 Qobuz，重新发现音响地址");
        }catch(Exception e){SetError(e.Message);}
        finally{restartingQobuz=false;Get<Button>("Qobuz").IsEnabled=true;Render();}
    }
    void Note(string message) { events.Add(DateTime.Now.ToString("HH:mm:ss")+"  "+message);if(events.Count>120)events.RemoveAt(0);Core.Log(message); }
    void SetError(string message) {error=message;Note(message);Render();}
    async Task Poll() {
        if(polling || exiting || operationName.Length>0)return;polling=true;int generation=epoch;
        try { var next=await Task.Run(()=>Core.Native("Inspect"));if(generation!=epoch || exiting || operationName.Length>0)return;if(!Core.Yes(next,"ok"))next["recovery"]=File.Exists(IOPath.Combine(Core.Data,"session.json"));state=next;checking=false;if(!Core.Yes(next,"ok")) error=Core.Text(next,"error");
            if(Core.Yes(next,"ok") && Core.Yes(next,"owned") && Core.Text(next,"hotspot")=="On") {
                string before=Core.Json(deviceAddresses);var changes=Core.RememberDeviceAddresses(deviceAddresses,Core.Rows(next,"devices"));
                if(changes.Count>0){rediscoverQobuz=true;Note("设备地址已变化："+string.Join("；",changes)+"。若 Qobuz 无法连接，可点击重新发现。");}
                if(before!=Core.Json(deviceAddresses))Core.Save("preferences.json",prefs);
            }
            Render(); }
        finally {polling=false;}
    }
    async Task Probe() {
        if(probing || exiting || operationName.Length>0)return;probing=true;int generation=epoch;int port=Core.Port;
        try {
            var next=await Task.Run(()=>Core.Probe(port));if(generation!=epoch || exiting)return;
            if(Core.Text(next,"code")=="busy")return;
            bool repair=healthMonitor.Observe(state,next,DateTime.UtcNow);
            if(Core.Yes(proxy,"ok")!=Core.Yes(next,"ok") || Core.Text(proxy,"code")!=Core.Text(next,"code"))Note(Core.Yes(next,"ok")?"链路检查通过":Core.Text(next,"error"));
            proxy=next;if(Core.Yes(next,"ok") && Core.Yes(state,"owned") && Core.Yes(state,"managed"))error="";Render();
            if(repair) {Note("连续检测到本地热点故障，正在恢复；保留代理进程");await Operate("Repair");}
        }
        finally {probing=false;if(generation!=epoch && !exiting && operationName.Length==0) ScheduleProbe();}
    }
    void ScheduleProbe() { Window.Dispatcher.BeginInvoke(new Action(async()=>await Probe())); }
    public async Task Primary() {
        if(exiting || operationName.Length>0 || checking)return;
        if(Core.Yes(state,"owned") || Core.Yes(state,"recovery")) {await Operate(Core.Text(state,"hotspot")=="Off" && Core.Yes(state,"owned") && Core.Yes(state,"adapter")?"Resume":"Stop");return;}
        if(!Core.Yes(state,"ok")) {await Poll();await Probe();return;}
        if(Core.Text(state,"hotspot")=="On" && !Core.Yes(state,"sourceVerified")) {
            sources=Core.Rows(state,"sources").ToList();string previous=Core.Text(prefs,"previous_guid");
            if(!sources.Any(x=>Core.Text(x,"guid").Trim('{','}').Equals(previous.Trim('{','}'),StringComparison.OrdinalIgnoreCase))) {ShowDialog("source","当前热点来源","");return;}
        }
        await Operate("Start");
    }
    async Task Operate(string action) {
        if(exiting || operationName.Length>0)return;operationName=action;operationStarted=DateTime.UtcNow;epoch++;Core.Cancel("inspect","probe","check");stage=action=="Start"?0:2;stageText=action=="Start"?"检测代理":"正在处理热点";error="";lastProgress="";Render();
        bool takeover=Core.Text(state,"hotspot")=="On";string previous=Core.Text(prefs,"previous_guid");
        operation=Task.Run(()=> {
            if(action=="Start") {var p=Core.Probe(Core.Port);if(!Core.Yes(p,"ok"))return p;}
            return Core.Native(action,takeover,previous);
        });
        var result=await operation;
        operationName=""; if(exiting)return;
        if(!Core.Yes(result,"ok"))error=Core.Text(result,"error");Note(Core.Text(result,"message",error));
        checking=true;Render();await Poll();await Probe();
    }
    void ReadProgress() {
        if(operationName.Length==0 || exiting)return;
        try { string path=IOPath.Combine(Core.Data,"progress.json");if(File.GetLastWriteTimeUtc(path)<operationStarted)return;var data=Core.Object(File.ReadAllText(path));string text=Core.Text(data,"message");if(text==lastProgress)return;lastProgress=text;Note(text);stage=text.Contains("热点")?2:text.Contains("网卡") || text.Contains("转发")?1:stage;stageText=operationName=="Stop"?"停止热点与网卡":stage==2?"开启热点":stage==1?"启动网卡":"检测代理";Render();}catch(IOException){}catch(ArgumentException){}
    }
    public async Task Exit() {
        if(exiting)return;exiting=true;epoch++;poll.Stop();probeTimer.Stop();progress.Stop();Get<Grid>("Overlay").Visibility=Visibility.Collapsed;
        try {Core.RequestExit();} catch(IOException e) {Core.Log(e.Message);Core.CancelAll();} catch(UnauthorizedAccessException e) {Core.Log(e.Message);Core.CancelAll();} Render();
        if(operation!=null && !operation.IsCompleted) { if(await Task.WhenAny(operation,Task.Delay(12000))!=operation) Core.Cancel("start","resume","repair","stop"); await Task.WhenAny(operation,Task.Delay(2500)); }
        var cleanup=Task.Run(()=>Core.Native("Stop"));
        Dictionary<string,object> result;
        if(await Task.WhenAny(cleanup,Task.Delay(12000))!=cleanup) {Core.Cancel("stop");await Task.WhenAny(cleanup,Task.Delay(1500));result=await Task.Run(()=>Core.Native("Stop",false,"",true));}
        else {result=await cleanup;if(!Core.Yes(result,"ok")) result=await Task.Run(()=>Core.Native("Stop",false,"",true));}
        try {Core.Save("last-exit.json",new {ok=Core.Yes(result,"ok"),message=Core.Text(result,"error"),time=DateTime.UtcNow.ToString("o")});} catch(IOException e) {Core.Log(e.Message);} catch(UnauthorizedAccessException e) {Core.Log(e.Message);}
        Core.CancelAll();tray.Visible=false;tray.Dispose();allowClose=true;Window.Close();Application.Current.Shutdown(Core.Yes(result,"ok")?0:2);
    }
    void ShowDialog(string kind,string title,string value) {
        dialog=kind;Get<TextBlock>("DialogTitle").Text=title;Get<TextBlock>("DialogError").Text="";
        Get<TextBox>("DialogInput").Visibility=kind=="port" || kind=="rename"?Visibility.Visible:Visibility.Collapsed;
        Get<ComboBox>("DialogSources").Visibility=kind=="source"?Visibility.Visible:Visibility.Collapsed;
        Get<TextBox>("DialogLogs").Visibility=kind=="logs"?Visibility.Visible:Visibility.Collapsed;
        Get<Button>("DialogExtra").Visibility=kind=="port" || kind=="logs"?Visibility.Visible:Visibility.Collapsed;
        Get<Button>("DialogExtra").Content=kind=="logs"?"导出":"自动检测";
        Get<Button>("DialogSave").Content=kind=="logs"?"完成":kind=="source"?"继续":"保存";
        Get<TextBox>("DialogInput").Text=value;Get<TextBox>("DialogLogs").Text=value;
        Get<ComboBox>("DialogSources").ItemsSource=sources.Select(x=>Core.Text(x,"name")).ToList();Get<ComboBox>("DialogSources").SelectedIndex=0;
        Get<Grid>("Overlay").Visibility=Visibility.Visible;
        Get<TextBox>("DialogInput").Focus();Get<TextBox>("DialogInput").SelectAll();
    }
    async Task SaveDialog() {
        try {
            if(dialog=="port") {int port;if(!int.TryParse(Get<TextBox>("DialogInput").Text,out port)||!Core.ValidPort(port))throw new ArgumentException("请输入 1–65535 的端口");Core.SavePort(port);epoch++;proxy.Clear();}
            if(dialog=="rename") {string name=Get<TextBox>("DialogInput").Text.Trim();if(name.Length>40)throw new ArgumentException("名称最多 40 个字");if(name.Length==0)aliases.Remove(deviceKey);else aliases[deviceKey]=name;Core.Save("preferences.json",prefs);deviceRows.Clear();Get<StackPanel>("Devices").Children.Clear();}
            if(dialog=="source") {int index=Get<ComboBox>("DialogSources").SelectedIndex;if(index<0||index>=sources.Count)throw new ArgumentException("请选择热点原来的网络来源");prefs["previous_guid"]=Core.Text(sources[index],"guid");Core.Save("preferences.json",prefs);}
            Get<Grid>("Overlay").Visibility=Visibility.Collapsed;Render();if(dialog=="port")await Probe();if(dialog=="source")await Operate("Start");
        } catch(Exception e) {Get<TextBlock>("DialogError").Text=e.Message;}
    }
    void RenderPassword() {
        Get<TextBlock>("Password").Text=showPassword?Core.Text(state,"password"):"••••••••";
        ButtonIcon("ShowPassword",showPassword?"eye-off":"eye");
        Get<Button>("ShowPassword").ToolTip=showPassword?"隐藏密码":"显示密码";
        System.Windows.Automation.AutomationProperties.SetName(Get<Button>("ShowPassword"),showPassword?"隐藏密码":"显示密码");
    }
    void Render() {
        ButtonIcon("Qobuz",rediscoverQobuz?"refresh":"music",rediscoverQobuz?"重新发现":"Qobuz");
        Get<Button>("Qobuz").ToolTip=rediscoverQobuz?"重启 Qobuz，清除旧音响地址；不会重启热点":"打开 Qobuz；右键可重新发现音响";
        bool owned=Core.Yes(state,"owned"), on=Core.Text(state,"hotspot")=="On", good=Core.Healthy(state,proxy), active=operationName.Length>0;
        string mode=exiting?"exit":active?"busy":checking || (owned && proxy.Count==0)?"checking":Core.Yes(state,"recovery")?"recovery":!Core.Yes(state,"ok")?"error":owned?(on && Core.Yes(state,"managed") && good && (!state.ContainsKey("routeOk")||Core.Yes(state,"routeOk"))?"online":!on?"paused":"degraded"):"idle";
        string title=mode=="exit"?"正在退出":mode=="busy"?(operationName=="Stop"?"正在关闭":operationName=="Repair"?"正在恢复":"正在连接"):mode=="checking"?"正在检测":mode=="online"?"热点就绪":mode=="paused"?"热点已暂停":mode=="idle"?"准备连接":mode=="recovery"?"需要恢复":mode=="degraded" && healthMonitor.Failures>0 && healthMonitor.Failures<3?"正在复查":"连接需检查";
        Get<TextBlock>("StatusTitle").Text=title;Get<TextBlock>("StatusDetail").Text=exiting?"清理网卡与热点":active?stageText:mode=="online"?"音响热点已就绪":mode=="idle"?"开启热点，让设备连接":mode=="paused"?"恢复后可继续使用":"检查代理与网络状态";
        if(mode!=lastMode){Note(title);lastMode=mode;}
        string action=mode=="paused"?"恢复连接":owned||Core.Yes(state,"recovery")?"断开连接":mode=="error"?"重新检测":"开启连接";
        ButtonIcon("Primary",mode=="paused"||mode=="error"?"refresh":"power",active||exiting?"正在处理":action,true);
        Get<Button>("Primary").IsEnabled=!(active||exiting||checking);System.Windows.Automation.AutomationProperties.SetName(Get<Button>("Primary"),action);
        for(int i=0;i<3;i++){var bar=Get<ProgressBar>("Progress"+i);bool busy=Window.IsVisible && (active?i==stage:checking&&i==0);bar.IsIndeterminate=busy;double value=active?(i<stage?100:0):i==0?(good?100:0):i==1?(owned&&Core.Yes(state,"adapter")?100:0):(owned&&on?100:0);if(!busy && Math.Abs(bar.Value-value)>.1)bar.BeginAnimation(ProgressBar.ValueProperty,new DoubleAnimation(value,TimeSpan.FromMilliseconds(240)));}
        Get<TextBlock>("HotspotName").Text=Core.Text(state,"ssid","Wi-Fi 热点");Get<TextBlock>("Broadcast").Text=on?"正在广播":"尚未开启";RenderPassword();
        Get<Viewbox>("WifiGlyph").BeginAnimation(UIElement.OpacityProperty,on&&Window.IsVisible?new DoubleAnimation(.5,1,TimeSpan.FromSeconds(1.6)){AutoReverse=true,RepeatBehavior=RepeatBehavior.Forever}:null);
        Get<Button>("PortButton").Content="127.0.0.1 : "+Core.Port;Get<Button>("PortButton").IsEnabled=!(active||owned||exiting||Core.Yes(state,"recovery"));
        Get<Button>("EditHotspot").IsEnabled=!(active||exiting);Get<Button>("Refresh").IsEnabled=!(active||exiting);
        string visibleError=error.Length>0?error:owned&&!good?Core.Text(proxy,"error"):"";
        Get<TextBlock>("ErrorText").Text=visibleError;Get<Border>("ErrorPanel").Visibility=visibleError.Length==0?Visibility.Collapsed:Visibility.Visible;
        RenderDevices();
    }
    void RenderDevices() {
        var items=Core.Rows(state,"devices").ToList();
        var panel=Get<StackPanel>("Devices");
        var keys=new HashSet<string>();
        bool live=Core.Yes(state,"ok") && Core.Text(state,"hotspot")=="On";
        foreach(var item in items) {
            string mac=Core.Text(item,"mac").ToLowerInvariant().Replace('-',':');
            object names; item.TryGetValue("names",out names);
            var list=names is System.Collections.IEnumerable
                ? ((System.Collections.IEnumerable)names).Cast<object>().Select(Convert.ToString).ToList()
                : new List<string>();
            string key=mac.Length>0?mac:string.Join("|",list);
            keys.Add(key);
            System.Net.IPAddress ip;
            string host=list.FirstOrDefault(n=>!System.Net.IPAddress.TryParse(n,out ip))??"设备";
            string address=list.FirstOrDefault(n=>System.Net.IPAddress.TryParse(n,out ip))??mac;
            string name=aliases.ContainsKey(key)?Convert.ToString(aliases[key]):host;
            Button row;
            if(!deviceRows.TryGetValue(key,out row)) {
                row=new Button {Style=(Style)Window.Resources["DeviceCard"]};
                string captured=key;
                row.Click+=(sender,e)=> {
                    deviceKey=captured;
                    ShowDialog("rename","设备名称",aliases.ContainsKey(captured)?Convert.ToString(aliases[captured]):"");
                };
                deviceRows[key]=row;
                panel.Children.Add(row);
                row.BeginAnimation(UIElement.OpacityProperty,new DoubleAnimation(0,1,TimeSpan.FromMilliseconds(250)));
            }
            string signature=name+"|"+address+"|"+host+"|"+live;
            if(Convert.ToString(row.Tag)==signature)continue;
            row.Tag=signature;
            row.ToolTip=name+Environment.NewLine+address;
            System.Windows.Automation.AutomationProperties.SetName(row,name+"，"+address);

            // Match the hotspot card: 44 px icon tile, 14 px gap, shared text edge.
            var grid=new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(44)});
            grid.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(14)});
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            grid.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(12)});
            grid.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(32)});
            string raw=host.ToLowerInvariant();
            string glyph=raw.Contains("jbl") || raw.Contains("speaker") || raw.Contains("audiocast")
                ? "speaker"
                : new[]{"phone","android","vivo","pixel","samsung","huawei","xiaomi"}.Any(raw.Contains)?"phone":"device";
            var tile=new Border {
                Width=44,Height=44,CornerRadius=new CornerRadius(12),
                Background=new SolidColorBrush(Color.FromRgb(245,245,247)),
                Child=Icon(glyph,new SolidColorBrush(Color.FromRgb(77,80,87)),22)
            };
            grid.Children.Add(tile);
            var label=new StackPanel {VerticalAlignment=VerticalAlignment.Center};
            label.Children.Add(new TextBlock {
                Text=name,FontSize=15,FontWeight=FontWeights.Medium,
                TextTrimming=TextTrimming.CharacterEllipsis
            });
            label.Children.Add(new TextBlock {
                Text=address,FontFamily=new FontFamily("Segoe UI"),FontSize=12,
                Foreground=muted,Margin=new Thickness(0,4,0,0),
                TextTrimming=TextTrimming.CharacterEllipsis
            });
            Grid.SetColumn(label,2);grid.Children.Add(label);
            var check=Icon("check",live?blue:muted,16);
            check.Opacity=live?1:.4;
            Grid.SetColumn(check,4);grid.Children.Add(check);
            row.Content=grid;
        }
        foreach(string key in deviceRows.Keys.Where(k=>!keys.Contains(k)).ToArray()) {
            panel.Children.Remove(deviceRows[key]);deviceRows.Remove(key);
        }
        Get<TextBlock>("DeviceCount").Text=items.Count.ToString();
        Get<TextBlock>("Empty").Visibility=items.Count==0?Visibility.Visible:Visibility.Collapsed;
    }

}
}
