local socket=require("socket")
local lfs=require("lfs")

config={
	port=8080,
	logging=false,
}

dofile("fs.lua")
dofile("hook.lua")
dofile("async.lua")
dofile("webserv.lua")

hook.new("page_hello",function(cl)
	return {data="<h1> Hello "..cl.ip.." from ".._VERSION.."</h1>"}
end)

while true do
	hook.queue("select",socket.select(hook.sel,hook.rsel,math.min(10,hook.interval or 10)))
end
