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

local function parsedate(txt)
	local day,month,year,time=txt:match("^%S+%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+:%S+)")
	if not day then
		day,month,year,time=txt:match("^%S+%s+(%S-)%-(%S-)%-(%S-)%s+(%S+:%S+)")
		if year then
			year=1900+tonumber(year)
		end
	end
	if not day then
		month,day,time,year=txt:match("^%S+%s+(%S+)%s+(%S+)%s+(%S+:%S+)%s+(%S+)")
	end
	if not day then
		return nil,txt
	end
	local hour,minute,second=time:match("(%d+):(%d+):(%d+)")
	if not hour then
		return nil,txt
	end
	local months={
		"jan","feb","mar","apr",
		"may","jun","jul","aug",
		"sep","oct","nov","dec",
	}
	for k,v in pairs(months) do
		months[v]=k
	end
	month=tostring(months[month:lower()])
	return ("0"):rep(4-#year)..year..("0"):rep(2-#month)..month..("0"):rep(2-#day)..day..("0"):rep(2-#hour)..hour..("0"):rep(2-#minute)..minute..("0"):rep(2-#second)..second
end

local function cmpdate(a,b)
	for l1=1,14 do
		local ca=tonumber(a:sub(l1,l1))
		local cb=tonumber(b:sub(l1,l1))
		if ca>cb then
			return -1
		elseif ca<cb then
			return 1
		end
	end
	return 0
end

do
	local exists={}
	local isdir={}
	local isfile={}
	local list={}
	local rd={}
	local last={}
	local modified={}
	local function update(tbl,ind)
		local tme=socket.gettime()
		local dt=tme-(last[tbl] or tme)
		last[tbl]=tme
		for k,v in tpairs(tbl) do
			v.time=v.time-dt
			if v.time<=0 then
				tbl[k]=nil
			end
		end
		return (tbl[ind] or {}).value
	end
	local function set(tbl,ind,val)
		tbl[ind]={time=10,value=val}
		return val
	end
	fs={
		exists=function(file)
			return lfs.attributes(file)~=nil
		end,
		isDir=function(file)
			local res=update(isdir,file)
			if res~=nil then
				return res
			end
			local dat=lfs.attributes(file)
			if not dat then
				return nil
			end
			return set(isdir,file,dat.mode=="directory")
		end,
		isFile=function(file)
			local res=update(isfile,file)
			if res~=nil then
				return res
			end
			local dat=lfs.attributes(file)
			if not dat then
				return nil
			end
			return set(isfile,file,dat.mode=="file")
		end,
		split=function(file)
			local t={}
			for dir in file:gmatch("[^/]+") do
				t[#t+1]=dir
			end
			return t
		end,
		combine=function(filea,fileb)
			local o={}
			for k,v in pairs(fs.split(filea)) do
				table.insert(o,v)
			end
			for k,v in pairs(fs.split(fileb)) do
				table.insert(o,v)
			end
			return filea:match("^/?")..table.concat(o,"/")..fileb:match("/?$")
		end,
		resolve=function(file)
			local b,e=file:match("^(/?).-(/?)$")
			local t=fs.split(file)
			local s=0
			for l1=#t,1,-1 do
				local c=t[l1]
				if c=="." then
					table.remove(t,l1)
				elseif c==".." then
					table.remove(t,l1)
					s=s+1
				elseif s>0 then
					table.remove(t,l1)
					s=s-1
				end
			end
			return b..table.concat(t,"/")..e
		end,
		list=function(dir)
			local res=update(list,dir)
			if res~=nil then
				return res
			end
			dir=dir or ""
			local o={}
			for fn in lfs.dir(dir) do
				if fn~="." and fn~=".." then
					table.insert(o,fn)
				end
			end
			return set(list,dir,o)
		end,
		read=function(file)
			local res=update(rd,file)
			if res~=nil then
				return res
			end
			local data=io.open(file,"rb"):read("*a")
			if (rd[file] or {}).data~=data then
				modified[file]=os.date()
			end
			return set(rd,file,data)
		end,
		modified=function(file)
			local res=modified[file]
			if not res then
				fs.read(file)
			end
			return modified[file]
		end
	}
end

dofile("hook.lua")
dofile("async.lua")

local sv=assert(socket.bind("*",80))
sv:settimeout(0)
hook.newsocket(sv)
local cli={}

local function close(cl)
	cl:close()
	cli[cl]=nil
	hook.remsocket(cl)
end

function urlencode(txt)
	return txt:gsub("\r?\n","\r\n"):gsub("[^%w ]",function(t) return string.format("%%%02X",t:byte()) end):gsub(" ","+")
end

function urldecode(txt)
	return txt:gsub("+"," "):gsub("%%(%x%x)",function(t) return string.char(tonumber("0x"..t)) end)
end

function htmlencode(txt)
	return txt:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub("\"","&quot;"):gsub("'","&apos;"):gsub("\r?\n","<br>")
end

function parseurl(url)
	local out={}
	for var,dat in url:gmatch("([^&]+)=([^&]+)") do
		out[urldecode(var)]=urldecode(dat)
	end
	return out
end

local ctype={
	["html"]="text/html",
	["css"]="text/css",
	["png"]="image/png",
	["txt"]="text/plain",
}

local function form(cl,res)
	local cldat=cli[cl]
	local headers=res.headers or {}
	local code=res.code or "200 Found"
	headers["ETag"]=cldat.headers["ETag"]
	headers["Server"]="Less fail lua webserver"
	headers["Content-Length"]=headers["Content-Length"] or #(res.data or "")
	if headers["Content-Length"]==0 or cldat.method=="HEAD" then
		headers["Content-Length"]=nil
	end
	headers["Content-Type"]=headers["Content-Type"] or res.type or "text/html"
	headers["Connection"]=(headers["Connection"] or "Keep-Alive"):lower()
	local o="HTTP/1.1 "..code
	for k,v in pairs(headers) do
		if v~="" then
			o=o.."\r\n"..k..": "..v
		end
	end
	o=o.."\r\n\r\n"
	if headers["Content-Length"] then
		o=o..res.data
	end
	async.new(function()
		local res,err=async.socket(cl).send(o)
		if res and headers["Connection"]=="keep-alive" then
			for k,v in pairs(cldat) do
				if k~="ip" then
					cldat[k]=nil
				end
			end
			cldat.headers={}
		else
			close(cl)
		end
	end)
end

local base="www"
local function req(cl)
	local cldat=cli[cl]
	local url=cldat.url
	cldat.urldata=parseurl(url:match(".-%?(.+)") or "")
	if cldat.post then
		cldat.postdata=parseurl(cldat.post)
	end
	url=fs.resolve(url:match("(.-)%?.+") or url)
	local res=hook.queue("page_"..url,cldat)
	url=fs.split(url)
	local file=url[#url] or ""
	url=table.concat(url,"/")
	local bse=fs.combine(base,url):gsub("/$","")
	if not res then
		res={}
		if not fs.exists(bse) then
			res.data="<center><h1>404 Not found.</h1></center>"
			res.code="404 Not found"
		else
			if fs.isDir(bse) then
				local gt=false
				for k,v in pairs(fs.list(bse)) do
					if v:match("^index%.") then
						url=fs.combine(url,v)
						gt=true
						break
					end
				end
				if not gt then
					local o=""
					for k,v in pairs(fs.list(bse)) do
						o=o.."<a href=\""..fs.combine(url,v):gsub("^/","").."\">"..htmlencode(v).."</a><br>"
					end
					res.data=o
				end
			end
			if not res.data then
				local bse=fs.combine(base,url):gsub("/$","")
				local ext=url:match(".+%.(.-)$") or ""
				res.type=ctype[ext]
				if ext=="lua" then
					local data=fs.read(bse)
					local func,err=loadstring(data,"="..url)
					if not func then
						res.data=err:gsub("\n","<br>")
						res.code="500 Internal Server Error"
						res.type="text/raw"
					else
						local o=""
						local e=setmetatable({
							print=function(...)
								o=o..table.concat({...}," ").."\r\n"
							end,
							write=function(...)
								o=o..table.concat({...}," ")
							end,
							postdata=cldat.postdata,
							urldata=cldat.urldata,
							cl=cldat,
						},{__index=_G})
						local err,out=xpcall(setfenv(func,e),debug.traceback)
						if not err then
							res.data=out
							res.code="500 Internal Server Error"
							res.type="text/raw"
						else
							res.data=o
							res.code=e.code or "200 Found"
							res.type="text/html"
						end
					end
				else
					res.headers={["Last-Modified"]=fs.modified(bse)}
					local parsed=parsedate(cldat.headers["If-Modified-Since"] or "")
					if parsed and cmpdate(parsed,parsedate(res.headers["Last-Modified"]))<1 then
						res.code="304 Not Modified"
					else
						res.data=fs.read(bse)
					end
				end
			end
		end
	end
	form(cl,res)
end

hook.new("select",function()
	local cl=sv:accept()
	while cl do
		hook.newsocket(cl)
		cl:settimeout(0)
		cli[cl]={headers={},ip=cl:getpeername()}
		cl=sv:accept()
	end
	for cl,cldat in pairs(cli) do
		local s,e=cl:receive(0)
		if not s and e=="closed" then
			close(cl)
		else
			local s,e=cl:receive(tonumber(cldat.post and cldat.headers["Content-Length"]))
			if s then
				if cldat.post then
					cldat.post=s
					req(cl)
				elseif s=="" then
					if cldat.method=="POST" then
						cldat.post=""
					elseif cldat.method=="GET" or cldat.method=="HEAD" then
						req(cl)
					else
						form(cl,{
							code="405 Method Not Allowed",
							data="<center><h1>404 Not found.</h1></center>",
							headers={
								["Allow"]="GET, POST, HEAD"
							},
						})
					end
				else
					if not s:match(":") then
						cldat.method=s:match("^(%S+)")
						cldat.url=(s:match("^%S+ (%S+)") or ""):gsub("^/","")
					else
						cldat.headers[s:match("^(.-):")]=s:match("^.-: (.+)")
					end
				end
			end
		end
	end
end)

while true do
	hook.queue("select",socket.select(hook.sel,hook.rsel,math.min(10,hook.interval or 10)))
end