local socket=require("socket")
local lfs=require("lfs")

function tpairs(tbl)
	local s={}
	local c=1
	for k,v in pairs(tbl) do
		s[c]=k
		c=c+1
	end
	c=0
	return function()
		c=c+1
		return s[c],tbl[s[c]]
	end
end

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