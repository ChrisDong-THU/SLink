using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace SLink {
// Keep clocks independent of polling: only state and interaction changes start motion.
internal sealed class PrimaryButtonMotion {
    readonly Button button;
    readonly Window window;
    readonly Func<bool> animationEnabled;
    readonly DependencyPropertyDescriptor pressed=DependencyPropertyDescriptor.FromProperty(Button.IsPressedProperty,typeof(Button));
    readonly RotateTransform rotation=new RotateTransform();
    readonly ScaleTransform plateScale=new ScaleTransform(), glyphScale=new ScaleTransform();
    readonly ScaleTransform revealScale=new ScaleTransform(), echoScale=new ScaleTransform();
    Ellipse plate,ring,echo;
    ContentPresenter glyph;
    string state="",icon="";
    string spinning="";
    bool Visible { get { return button.IsVisible&&window.WindowState!=WindowState.Minimized; } }
    bool Animate { get { return animationEnabled()&&Visible; } }
    public PrimaryButtonMotion(Button button,Window window,Func<bool> animationEnabled=null) {
        this.button=button;this.window=window;
        this.animationEnabled=animationEnabled??(()=>SystemParameters.ClientAreaAnimation);
        button.MouseEnter+=Interaction;button.MouseLeave+=Interaction;
        button.IsEnabledChanged+=Activity;button.IsVisibleChanged+=Activity;
        button.Loaded+=Interaction;window.StateChanged+=Interaction;
        pressed.AddValueChanged(button,Interaction);
        SystemParameters.StaticPropertyChanged+=SystemSettingChanged;
        window.Closed+=(s,e)=> {pressed.RemoveValueChanged(button,Interaction);SystemParameters.StaticPropertyChanged-=SystemSettingChanged;Stop();};
    }
    void Parts() {
        button.ApplyTemplate();
        if(plate!=null)return;
        plate=button.Template.FindName("Plate",button) as Ellipse;
        ring=button.Template.FindName("Ring",button) as Ellipse;
        echo=button.Template.FindName("Echo",button) as Ellipse;
        glyph=button.Template.FindName("Glyph",button) as ContentPresenter;
        if(plate==null||ring==null||glyph==null)return;
        plate.RenderTransform=plateScale;
        var transforms=new TransformGroup();transforms.Children.Add(glyphScale);transforms.Children.Add(revealScale);glyph.RenderTransform=transforms;
        echo.RenderTransform=echoScale;
        ring.RenderTransformOrigin=new Point(.5,.5);ring.RenderTransform=rotation;
    }
    public void Update(string next,string nextIcon,Func<Brush,UIElement> createIcon) {
        Parts();
        if(next==state&&nextIcon==icon)return;
        bool initial=state.Length==0;
        var old=plate==null?null:plate.Fill as SolidColorBrush;
        Color from=old==null?Colors.White:old.Color;
        state=next;icon=nextIcon;button.Tag=next;
        button.Content=createIcon(button.Foreground);
        if(plate!=null) {
            var target=(SolidColorBrush)button.Background;
            var fill=new SolidColorBrush(target.Color);plate.Fill=fill;
            if(!initial&&Animate)fill.BeginAnimation(SolidColorBrush.ColorProperty,new ColorAnimation(from,target.Color,TimeSpan.FromMilliseconds(220)){FillBehavior=FillBehavior.Stop});
            glyph.BeginAnimation(UIElement.OpacityProperty,null);
            if(!initial&&Animate) {
                glyph.BeginAnimation(UIElement.OpacityProperty,new DoubleAnimation(.25,1,TimeSpan.FromMilliseconds(200)){FillBehavior=FillBehavior.Stop});
                foreach(var property in new[]{ScaleTransform.ScaleXProperty,ScaleTransform.ScaleYProperty})
                    revealScale.BeginAnimation(property,new DoubleAnimation(.86,1,TimeSpan.FromMilliseconds(220)){EasingFunction=new CubicEase{EasingMode=EasingMode.EaseOut},FillBehavior=FillBehavior.Stop});
            }
        }
        Refresh();
        if(!initial&&next=="online"&&Animate)Echo(false);
    }
    void Activity(object sender,DependencyPropertyChangedEventArgs e) { Refresh(); }
    void Interaction(object sender,EventArgs e) { Refresh(); }
    void SystemSettingChanged(object sender,PropertyChangedEventArgs e) {
        if(e.PropertyName=="ClientAreaAnimation")window.Dispatcher.BeginInvoke(new Action(Refresh));
    }
    void Refresh() {
        Parts();if(plate==null)return;
        bool busy=state=="connecting"||state=="checking"||state=="closing";
        // The ring conveys ongoing work, like an indeterminate progress bar.
        // Windows' decorative animation preference must not make it look stalled.
        bool run=Visible&&busy;
        string motion=run?state:"";
        if(motion!=spinning) {
            rotation.BeginAnimation(RotateTransform.AngleProperty,null);rotation.Angle=0;
            StopEcho();
            if(run) {
                rotation.BeginAnimation(RotateTransform.AngleProperty,new DoubleAnimation(0,state=="closing"?-360:360,TimeSpan.FromSeconds(state=="closing"?2.8:state=="checking"?2.4:1.8)){RepeatBehavior=RepeatBehavior.Forever});
                if(state=="closing"&&Animate)Echo(true);
            }
            spinning=motion;
        }
        double scale=button.IsEnabled?(button.IsPressed?.94:button.IsMouseOver?1.025:1):1;
        Scale(plateScale,scale);Scale(glyphScale,scale);
        if(!Animate)StopTransient();
        else if(run&&state=="closing"&&!echo.HasAnimatedProperties)Echo(true);
    }
    void Scale(ScaleTransform transform,double value) {
        foreach(var property in new[]{ScaleTransform.ScaleXProperty,ScaleTransform.ScaleYProperty}) {
            double from=(double)transform.GetValue(property);
            transform.BeginAnimation(property,null);transform.SetValue(property,value);
            if(Animate&&Math.Abs(from-value)>.001)transform.BeginAnimation(property,new DoubleAnimation(from,value,TimeSpan.FromMilliseconds(button.IsPressed?90:160)){EasingFunction=new CubicEase{EasingMode=EasingMode.EaseOut},FillBehavior=FillBehavior.Stop});
        }
    }
    void StopTransient() {
        if(plate==null)return;
        var fill=plate.Fill as SolidColorBrush;if(fill!=null&&!fill.IsFrozen)fill.BeginAnimation(SolidColorBrush.ColorProperty,null);
        glyph.BeginAnimation(UIElement.OpacityProperty,null);
        revealScale.BeginAnimation(ScaleTransform.ScaleXProperty,null);revealScale.BeginAnimation(ScaleTransform.ScaleYProperty,null);
        StopEcho();
    }
    void Echo(bool closing) {
        StopEcho();
        var duration=TimeSpan.FromMilliseconds(closing?1400:520);
        var repeat=closing?RepeatBehavior.Forever:new RepeatBehavior(1);
        echo.BeginAnimation(UIElement.OpacityProperty,new DoubleAnimation(closing?.35:.5,0,duration){RepeatBehavior=repeat,FillBehavior=FillBehavior.Stop});
        foreach(var property in new[]{ScaleTransform.ScaleXProperty,ScaleTransform.ScaleYProperty})
            echoScale.BeginAnimation(property,new DoubleAnimation(closing?1.14:.98,closing?.94:1.2,duration){RepeatBehavior=repeat,EasingFunction=new CubicEase{EasingMode=EasingMode.EaseOut},FillBehavior=FillBehavior.Stop});
    }
    void StopEcho() {
        if(echo==null)return;
        echo.BeginAnimation(UIElement.OpacityProperty,null);
        echoScale.BeginAnimation(ScaleTransform.ScaleXProperty,null);echoScale.BeginAnimation(ScaleTransform.ScaleYProperty,null);
    }
    void Stop() {rotation.BeginAnimation(RotateTransform.AngleProperty,null);spinning="";StopTransient();}
}
}
