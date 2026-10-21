using System;
using System.Collections.Generic;
using System.Linq;

namespace SLink {
internal static partial class Tests {
    static void RunPresentationChecks() {
        var emptyHealth=new Dictionary<string,object>();
        string[] states={
            "{\"ok\":true}",
            "{\"ok\":false}",
            "{\"ok\":true,\"owned\":true,\"hotspot\":\"Off\",\"adapter\":true}",
            "{\"ok\":true,\"owned\":true,\"hotspot\":\"Off\",\"adapter\":false}",
            "{\"ok\":true,\"recovery\":true}",
            "{\"ok\":false,\"owned\":true}"
        };
        var actions=new[]{ConnectionAction.Start,ConnectionAction.Inspect,ConnectionAction.Resume,ConnectionAction.Stop,ConnectionAction.Stop,ConnectionAction.Stop};
        var names=new[]{"开启连接","重新检测","恢复连接","断开连接","断开连接","断开连接"};
        var glyphs=new[]{"play","refresh","play","stop","stop","stop"};
        var unhealthy=Core.Object("{\"ok\":false}");
        for(int i=0;i<states.Length;i++) {
            var state=Core.Object(states[i]);
            var view=ConnectionPresentation.Create(state,unhealthy,"",0,false,false,0);
            Check(ConnectionPresentation.ActionFor(state)==actions[i]&&view.Enabled&&view.AccessibleName==names[i]&&view.Glyph==glyphs[i],"visual action matches command for state "+i);
            foreach(string operation in new[]{"Start","Resume","Repair","Stop"}) {
                view=ConnectionPresentation.Create(state,emptyHealth,operation,1,false,false,0);
                Check(!view.Enabled&&view.AccessibleName==view.Status&&view.ControlState==(operation=="Stop"?"closing":"connecting"),"active command disables repeat action: "+operation);
            }
        }
        var owned=Core.Object("{\"ok\":true,\"owned\":true,\"managed\":true,\"hotspot\":\"On\",\"adapter\":true,\"pid\":10,\"adapterGuid\":\"abc\"}");
        var healthy=Core.Object("{\"ok\":true,\"pid\":10,\"adapterGuid\":\"abc\"}");healthy["checkedAt"]=DateTime.UtcNow.ToString("o");
        var online=ConnectionPresentation.Create(owned,healthy,"",3,false,false,0);
        Check(online.Mode=="online"&&online.Stages.All(s=>s.Complete)&&online.Glyph=="stop","validated connection has completed stages and stop action");
        owned["routeOk"]=false;
        var degraded=ConnectionPresentation.Create(owned,healthy,"",3,false,false,0);
        Check(degraded.Mode=="degraded"&&!degraded.Stages[2].Complete,"route failure cannot present a ready hotspot");
        var pending=ConnectionPresentation.Create(owned,emptyHealth,"",0,false,false,0);
        Check(pending.Enabled&&pending.Glyph=="stop"&&pending.AccessibleName=="断开连接","background check retains stop action");
        Check(!ConnectionPresentation.Create(owned,healthy,"",0,true,false,0).Enabled,"explicit checking disables primary action");
        Check(!ConnectionPresentation.Create(owned,healthy,"",0,false,true,0).Enabled,"shutdown disables primary action");
        for(int phase=0;phase<3;phase++)for(int i=0;i<3;i++) {
            var display=ConnectionStage.Describe(i,"Start",phase,false,false,false,false,false);
            Check(display.Complete==(i<phase)&&display.Busy==(i==phase),"startup stages complete in order");
            Check(display.Label==(i<phase?new[]{"代理","网卡","热点"}[i]:i==phase?new[]{"检测代理","启动网卡","开启热点"}[i]:"等待"+new[]{"代理","网卡","热点"}[i]),"stage description becomes short title on completion");
        }
        foreach(string operation in new[]{"Resume","Repair"}) {
            var display=ConnectionStage.Describe(2,operation,2,false,false,true,false,false);
            Check(display.Busy&&!display.Complete&&display.Label==(operation=="Resume"?"恢复热点":"修复热点"),"resume and repair remain pending until inspected");
            Check(!ConnectionStage.Describe(0,operation,2,false,false,false,true,false).Complete,"repair does not imply proxy is healthy");
        }
        for(int i=1;i<3;i++)foreach(bool exiting in new[]{false,true}) {
            var display=ConnectionStage.Describe(i,exiting?"":"Stop",2,false,exiting,true,false,false);
            Check(display.Busy&&!display.Complete,"cleanup never displays completed startup stages");
        }
        Check(ConnectionStage.Describe(2,"",0,false,false,false,true,true).Label=="热点已暂停","paused hotspot has specific status");
        Check(ConnectionStage.Describe(0,"",0,false,false,false,true,false).Label=="代理需检查","proxy failure remains visible");
    }
}
}
