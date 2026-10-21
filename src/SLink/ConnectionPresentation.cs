using System.Collections.Generic;

namespace SLink {
internal enum ConnectionAction { Start, Resume, Stop, Inspect }

// Pure presentation model. It never starts a process or changes networking.
internal sealed class ConnectionPresentation {
    public string Mode { get; private set; }
    public string Title { get; private set; }
    public string ControlState { get; private set; }
    public string Glyph { get; private set; }
    public string Status { get; private set; }
    public string ToolTip { get; private set; }
    public string AccessibleName { get; private set; }
    public bool Enabled { get; private set; }
    public ConnectionStage[] Stages { get; private set; }

    public static ConnectionAction ActionFor(IDictionary<string,object> state) {
        bool owned=Core.Yes(state,"owned");
        if(owned || Core.Yes(state,"recovery")) {
            if(owned && Core.Text(state,"hotspot")=="Off" && Core.Yes(state,"adapter"))return ConnectionAction.Resume;
            return ConnectionAction.Stop;
        }
        return Core.Yes(state,"ok") ? ConnectionAction.Start : ConnectionAction.Inspect;
    }

    public static ConnectionPresentation Create(IDictionary<string,object> state,IDictionary<string,object> health,
        string operation,int phase,bool checking,bool exiting,int failures) {
        bool owned=Core.Yes(state,"owned"), on=Core.Text(state,"hotspot")=="On";
        bool good=Core.Healthy(state,health), inspected=Core.Yes(state,"ok"), recovery=Core.Yes(state,"recovery");
        bool active=operation.Length>0, routeOk=!state.ContainsKey("routeOk")||Core.Yes(state,"routeOk");
        var view=new ConnectionPresentation();
        if(exiting)view.Mode="exit";
        else if(active)view.Mode="busy";
        else if(checking || (owned&&health.Count==0))view.Mode="checking";
        else if(recovery)view.Mode="recovery";
        else if(!inspected)view.Mode="error";
        else if(!owned)view.Mode="idle";
        else if(on&&Core.Yes(state,"managed")&&good&&routeOk)view.Mode="online";
        else view.Mode=on?"degraded":"paused";

        switch(view.Mode) {
            case "exit": view.Title="正在退出";break;
            case "busy": view.Title=operation=="Stop"?"正在关闭":operation=="Repair"?"正在恢复":"正在连接";break;
            case "checking": view.Title="正在检测";break;
            case "online": view.Title="热点就绪";break;
            case "paused": view.Title="热点已暂停";break;
            case "idle": view.Title="准备连接";break;
            case "recovery": view.Title="需要恢复";break;
            default: view.Title=failures>0&&failures<3?"正在复查":"连接需检查";break;
        }

        var action=ActionFor(state);
        string actionName;
        switch(action) {
            case ConnectionAction.Resume: actionName="恢复连接";break;
            case ConnectionAction.Stop: actionName="断开连接";break;
            case ConnectionAction.Inspect: actionName="重新检测";break;
            default: actionName="开启连接";break;
        }
        if(exiting||operation=="Stop")view.ControlState="closing";
        else if(active)view.ControlState="connecting";
        else if(view.Mode=="checking")view.ControlState="checking";
        else if(view.Mode=="online")view.ControlState="online";
        else if(action==ConnectionAction.Resume)view.ControlState="paused";
        else view.ControlState=view.Mode=="idle"?"waiting":"attention";

        view.Status=view.Title;
        view.Glyph=action==ConnectionAction.Stop?"stop":action==ConnectionAction.Inspect?"refresh":"play";
        if(view.ControlState=="closing")view.Glyph="stop";
        else if(view.ControlState=="checking")view.Glyph=checking?"search":action==ConnectionAction.Stop?"stop":"refresh";
        else if(view.ControlState=="connecting") {
            if(operation=="Repair") {view.Glyph="refresh";view.Status="正在修复热点";}
            else if(operation=="Resume") {view.Glyph="wifi";view.Status="正在恢复热点";}
            else {
                int index=System.Math.Max(0,System.Math.Min(phase,3));
                view.Glyph=new[]{"search","network","wifi","check"}[index];
                view.Status=new[]{"正在检测代理","正在配置网卡","正在开启热点","正在完成连接"}[index];
            }
        }
        view.Enabled=!(active||exiting||checking);
        view.AccessibleName=view.Enabled?actionName:view.Status;
        view.ToolTip=view.Enabled?actionName+" · "+view.Title:view.Status+"，请稍候";
        bool[] ready={good,inspected&&owned&&Core.Yes(state,"adapter"),inspected&&owned&&on&&Core.Yes(state,"managed")&&routeOk};
        view.Stages=new ConnectionStage[3];
        for(int i=0;i<view.Stages.Length;i++) {
            bool needsCheck=!ready[i]&&(recovery||!inspected||owned||(i==0&&health.Count>0));
            view.Stages[i]=ConnectionStage.Describe(i,operation,phase,checking,exiting,ready[i],needsCheck,view.Mode=="paused");
        }
        return view;
    }
}
}
