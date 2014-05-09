urldata=urldata or {}
if urldata.answer=="yes" then
	print("Liar!")
elseif urldata.answer=="no" then
	print("Good choice.")
else
	print("Do you like mudkips?")
end
print("<br>")
print("<a href=/example.lua?answer=yes>yes</a> <a href=/example.lua?answer=no>no</a>")