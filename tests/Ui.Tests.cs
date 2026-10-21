using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SLink {
internal static partial class Tests {
    static void RunUiChecks(string output,string temp) {
        bool animationsEnabled=true;
        var app=new Application {ShutdownMode=ShutdownMode.OnExplicitShutdown};var ui=new MainWindow(true,()=>animationsEnabled);ui.Window.Show();ui.Window.UpdateLayout();
        Check(ui.Get<Button>("Primary")!=null&&ui.Get<Button>("PortButton")!=null,"UI controls");
        Check(ui.Get<TextBlock>("StageLabel0").Text=="代理"&&ui.Get<TextBlock>("StageLabel1").Text=="网卡"&&ui.Get<TextBlock>("StageLabel2").Text=="热点","online stages have completed short titles");
        Check(ui.Get<Button>("Primary").Content is Viewbox&&System.Windows.Automation.AutomationProperties.GetName(ui.Get<Button>("Primary"))=="断开连接","icon-only control retains accessible action");
        var primary=ui.Get<Button>("Primary");
        var body=(Grid)primary.Parent;
        Check(Math.Abs(primary.TranslatePoint(new Point(primary.ActualWidth/2,0),body).X-body.ActualWidth/2)<1,"primary control centered above stages");
        Check(ui.Get<StackPanel>("Devices").Children.Count==1,"device list");
        var chrome=ui.Get<Grid>("Chrome");
        foreach(double x in new[]{16.0,chrome.ActualWidth/2,chrome.ActualWidth-4}) {
            var hit=ui.Window.InputHitTest(chrome.TranslatePoint(new Point(x,22),ui.Window));
            Check(object.ReferenceEquals(hit,chrome),"title-bar blank area receives drag input");
        }
        foreach(string name in new[]{"Minimize","HideButton"}) {
            var button=ui.Get<Button>(name);
            var hit=ui.Window.InputHitTest(button.TranslatePoint(new Point(button.ActualWidth/2,button.ActualHeight/2),ui.Window)) as DependencyObject;
            Check(hit!=null && (object.ReferenceEquals(hit,button)||button.IsAncestorOf(hit)),"title-bar button retains mouse input: "+name);
        }
        var target=new RenderTargetBitmap((int)ui.Window.ActualWidth,(int)ui.Window.ActualHeight,96,96,PixelFormats.Pbgra32);target.Render(ui.Window);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(target));using(var f=File.Create(Path.Combine(Path.GetDirectoryName(output),"native-preview.png")))encoder.Save(f);
        // Exercise presentation in preview mode; no button is clicked and no network operation runs.
        var flags=System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic;
        var stateField=typeof(MainWindow).GetField("state",flags);var operationField=typeof(MainWindow).GetField("operationName",flags);
        var savedState=stateField.GetValue(ui);var render=typeof(MainWindow).GetMethod("Render",flags);
        var sheet=new DrawingVisual();
        using(var drawing=sheet.RenderOpen()) {
            drawing.DrawRectangle(new SolidColorBrush(Color.FromRgb(245,245,247)),null,new Rect(0,0,640,380));
            string[] captions={"点击连接","检测代理","已连接 · 点击停止","正在关闭","配置网卡","开启热点","已暂停 · 点击恢复","异常 · 点击重试"};
            string[] tags={"waiting","connecting","online","closing","connecting","connecting","paused","attention"};
            for(int i=0;i<8;i++) {
                var pausedState=Core.Object(Core.Json(savedState));pausedState["hotspot"]="Off";
                stateField.SetValue(ui,i==0?Core.Object("{\"ok\":true,\"hotspot\":\"Off\"}"):i==6?pausedState:i==7?Core.Object("{\"ok\":false}"):savedState);
                bool connecting=i==1||i==4||i==5;
                typeof(MainWindow).GetField("stage",flags).SetValue(ui,i==4?1:i==5?2:0);
                operationField.SetValue(ui,connecting?"Start":i==3?"Stop":"");render.Invoke(ui,null);ui.Window.UpdateLayout();
                Check(Convert.ToString(primary.Tag)==tags[i]&&primary.IsEnabled==(!connecting&&i!=3),"primary state and repeated-click protection: "+tags[i]);
                if(i==6||i==7)Check(System.Windows.Automation.AutomationProperties.GetName(primary)==(i==6?"恢复连接":"重新检测"),"paused and error controls describe their actual action");
                Pump(260);
                var rotation=(RotateTransform)((System.Windows.Shapes.Ellipse)primary.Template.FindName("Ring",primary)).RenderTransform;
                Check(rotation.HasAnimatedProperties==(connecting||i==3),"outer ring only animates during processing");
                if((connecting||i==3)&&animationsEnabled)Check(Math.Abs(rotation.Angle)>1&&Math.Abs(rotation.Angle)<360&&(rotation.Angle>0)==connecting,"connecting advances clockwise and closing unwinds counterclockwise");
                if(i==1) {
                    var content=primary.Content;double angle=rotation.Angle;render.Invoke(ui,null);
                    Check(object.ReferenceEquals(content,primary.Content)&&rotation.Angle==angle,"poll refresh does not recreate glyph or restart animation");
                    ui.Window.Hide();Check(!rotation.HasAnimatedProperties,"hidden window releases animation clock");
                    ui.Reveal();Check(rotation.HasAnimatedProperties,"visible window resumes processing animation");
                    ui.Window.WindowState=WindowState.Minimized;Check(!rotation.HasAnimatedProperties,"minimized window releases animation clock");
                    ui.Window.WindowState=WindowState.Normal;Check(rotation.HasAnimatedProperties,"restored window resumes processing animation");
                    animationsEnabled=false;ui.Window.Hide();ui.Reveal();Check(rotation.HasAnimatedProperties,"busy indicator remains active with decorative animations disabled");
                    Pump(80);double reducedAngle=rotation.Angle;Pump(80);
                    Check(rotation.Angle>reducedAngle,"busy ring visibly advances with the user's disabled Windows animation preference");
                    var echo=(System.Windows.Shapes.Ellipse)primary.Template.FindName("Echo",primary);
                    Check(!echo.HasAnimatedProperties,"disabled decorative animations do not start a ripple");
                    ui.Window.Hide();Check(!rotation.HasAnimatedProperties,"busy ring still stops when hidden with decorative animations disabled");
                    animationsEnabled=true;ui.Reveal();Check(rotation.HasAnimatedProperties,"visible busy indicator resumes");
                }
                var buttonVisual=new DrawingVisual();using(var buttonDrawing=buttonVisual.RenderOpen())buttonDrawing.DrawRectangle(new VisualBrush(primary){Stretch=Stretch.None},null,new Rect(0,0,112,112));
                var buttonImage=new RenderTargetBitmap(112,112,96,96,PixelFormats.Pbgra32);buttonImage.Render(buttonVisual);buttonImage.Freeze();
                drawing.DrawImage(buttonImage,new Rect((i%4)*160+24,(i/4)*190+16,112,112));
                var caption=new FormattedText(captions[i],System.Globalization.CultureInfo.GetCultureInfo("zh-CN"),FlowDirection.LeftToRight,new Typeface("Microsoft YaHei UI"),12,Brushes.DimGray,1.0);
                drawing.DrawText(caption,new Point((i%4)*160+(160-caption.Width)/2,(i/4)*190+148));
            }
        }
        var statePreview=new RenderTargetBitmap(640,380,96,96,PixelFormats.Pbgra32);statePreview.Render(sheet);
        encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(statePreview));using(var f=File.Create(Path.Combine(Path.GetDirectoryName(output),"primary-states.png")))encoder.Save(f);
        stateField.SetValue(ui,savedState);operationField.SetValue(ui,"");render.Invoke(ui,null);
        var operate=typeof(MainWindow).GetMethod("Operate",flags);
        var verified=Core.Object("{\"ok\":true,\"pid\":1,\"adapterGuid\":\"preview\"}");verified["checkedAt"]=DateTime.UtcNow.ToString("o");
        Core.Save("session.json",new {fixture=true}); // Makes preflight use the isolated Check fixture.
        Core.Save("native-fixture.json",new {state=savedState,result=verified,health=verified});
        string calls=Path.Combine(temp,"native-calls.txt");File.WriteAllText(calls,"");
        var startup=(System.Threading.Tasks.Task)operate.Invoke(ui,new object[]{"Start"});
        bool sawFinalInspection=false;var deadline=DateTime.UtcNow.AddSeconds(20);
        while(!startup.IsCompleted&&DateTime.UtcNow<deadline) {
            Pump(20);
            if(Convert.ToInt32(typeof(MainWindow).GetField("stage",flags).GetValue(ui))==3&&!startup.IsCompleted) {
                sawFinalInspection=true;
                Check(ui.Get<TextBlock>("StageLabel0").Text=="代理"&&!primary.IsEnabled&&ui.Get<Border>("ErrorPanel").Visibility==Visibility.Collapsed,"final inspection retains verified stages without a new proxy phase or error");
                break;
            }
        }
        while(!startup.IsCompleted&&DateTime.UtcNow<deadline)Pump(20);
        Check(startup.IsCompleted&&sawFinalInspection,"startup publishes final state after inspection");startup.GetAwaiter().GetResult();
        Check(File.ReadAllLines(calls).SequenceEqual(new[]{"Check","Start","Inspect"}),"verified startup does not run a duplicate proxy check");
        Check(Convert.ToString(primary.Tag)=="online"&&ui.Get<Border>("ErrorPanel").Visibility==Visibility.Collapsed,"verified startup goes directly online");
        var replacedState=Core.Object(Core.Json(savedState));replacedState["pid"]=2;
        var replacementHealth=Core.Object(Core.Json(verified));replacementHealth["pid"]=2;
        Core.Save("native-fixture.json",new {state=replacedState,result=verified,health=replacementHealth});File.WriteAllText(calls,"");
        startup=(System.Threading.Tasks.Task)operate.Invoke(ui,new object[]{"Start"});deadline=DateTime.UtcNow.AddSeconds(20);
        while(!startup.IsCompleted&&DateTime.UtcNow<deadline)Pump(20);
        Check(startup.IsCompleted,"changed relay identity finishes verification");startup.GetAwaiter().GetResult();
        Check(File.ReadAllLines(calls).SequenceEqual(new[]{"Check","Start","Inspect","Check"}),"changed relay identity requires a fresh check instead of reusing startup success");
        // A genuine startup failure remains visible after subsequent successful checks.
        Core.Save("native-fixture.json",new {state=new {ok=true,owned=false,hotspot="Off"},result=new {ok=false,error="fixture startup failed"},health=verified});
        startup=(System.Threading.Tasks.Task)operate.Invoke(ui,new object[]{"Start"});deadline=DateTime.UtcNow.AddSeconds(20);
        while(!startup.IsCompleted&&DateTime.UtcNow<deadline)Pump(20);
        Check(startup.IsCompleted,"failed startup finishes bounded refresh");startup.GetAwaiter().GetResult();
        Check(ui.Get<Border>("ErrorPanel").Visibility==Visibility.Visible&&ui.Get<TextBlock>("ErrorText").Text=="fixture startup failed","real startup failure is not hidden by transport fix");
        File.Delete(Path.Combine(temp,"session.json"));
        ui.Window.Close();Check(!ui.Window.IsVisible,"close hides to tray");ui.Reveal();Check(ui.Window.IsVisible,"reopen");ui.Window.Hide();
    }
}
}
