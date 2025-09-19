module("luci.controller.modemwebui", package.seeall)

function index()
 if not (luci.sys.call("ps w | grep '/server.py' | grep -v grep | grep -q python") == 0) then
  return
 end
 entry({"admin", "modem"}, firstchild(), _("Modem"), 25).dependent = false
 
 -- 直接访问入口
 entry({"admin", "modem","modemwebui"}, template("modemwebui/modemwebui"), _("WEB Panel"), 100)

end