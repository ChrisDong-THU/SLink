namespace SLink {
// Presentation only: completion follows the operation phase or inspected network state.
internal sealed class ConnectionStage {
    public string Label;
    public bool Busy, Complete;
    public static ConnectionStage Describe(int index,string operation,int phase,bool checking,bool exiting,bool ready,bool needsCheck,bool paused) {
        string title=new[]{"代理","网卡","热点"}[index];
        var result=new ConnectionStage {Label=ready?title:paused&&index==2?"热点已暂停":needsCheck?title+"需检查":"等待"+title,Complete=ready};
        if(exiting || operation=="Stop") {
            if(index>0) {result.Label=index==1?"清理网卡":"关闭热点";result.Busy=true;result.Complete=false;}
        } else if(operation=="Start") {
            result.Complete=index<phase;
            result.Busy=index==phase;
            result.Label=result.Complete?title:result.Busy?new[]{"检测代理","启动网卡","开启热点"}[index]:"等待"+title;
        } else if((operation=="Resume" || operation=="Repair") && index==2) {
            result.Label=operation=="Resume"?"恢复热点":"修复热点";result.Busy=true;result.Complete=false;
        } else if(checking && index==0) {
            result.Label="检测代理";result.Busy=true;result.Complete=false;
        }
        return result;
    }
}
}
