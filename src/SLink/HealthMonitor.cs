using System;
using System.Collections.Generic;

namespace SLink {
// A failed probe never tears down a playing device's TCP session or fake-IP map.
internal sealed class HealthMonitor {
    const int FailureThreshold = 3;
    const int RepairLimit = 2;
    static readonly TimeSpan RepairCooldown = TimeSpan.FromMinutes(5);

    string identity="", lastCode="";
    int failures, repairs;
    DateTime lastRepair=DateTime.MinValue;
    DateTime lastCheck=DateTime.MinValue;
    public int Failures { get {return failures;} }
    public bool Observe(IDictionary<string,object> state,IDictionary<string,object> health,DateTime now) {
        // A transient Inspect failure must not reset the same relay's repair budget.
        if(!Core.Yes(state,"owned"))return false;
        string current=Core.Text(state,"pid")+"|"+Core.Text(state,"adapterGuid").ToLowerInvariant();
        if(current!=identity) {
            identity=current;
            failures=0;
            repairs=0;
            lastCode="";
            lastRepair=DateTime.MinValue;
            lastCheck=DateTime.MinValue;
        }
        if(Core.Text(health,"pid")!=Core.Text(state,"pid") ||
            !Core.Text(health,"adapterGuid").Equals(Core.Text(state,"adapterGuid"),StringComparison.OrdinalIgnoreCase))return false;
        string code=Core.Text(health,"code");
        if(code=="busy")return false;
        if(!Core.Fresh(health,now))return false;
        DateTime checkedAt=DateTime.Parse(Core.Text(health,"checkedAt"),null,System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime();
        if(checkedAt<=lastCheck)return false;
        lastCheck=checkedAt;
        if(Core.Yes(health,"ok")) {
            failures=0;
            lastCode="";
            return false;
        }
        failures=code==lastCode?failures+1:1;
        lastCode=code;
        bool recoverable=code=="hotspot-dns" || code=="hotspot-off";
        if(!recoverable || failures<FailureThreshold || repairs>=RepairLimit || now-lastRepair<RepairCooldown)return false;
        repairs++;
        lastRepair=now;
        failures=0;
        return true;
    }
}
}
