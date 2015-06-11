LUWSE_VERSION = "Ducks"

local socket = require("socket")
if not socket then
  return nil, "Required library 'socket' not found."
end

----------------
-- Misc Stuff --
----------------

local statusCodes = {
  --Info
  [100] = "Continue",
  [101] = "Switching Protocols",
  [102] = "Processing",
  --Success
  [200] = "OK",
  [201] = "Created",
  [202] = "Accepted",
  [203] = "Non-Authoritative Information",
  [204] = "No Content",
  [205] = "Reset Content",
  [206] = "Partial Content",
  [207] = "Multi-Status", --WebDAV
  [210] = "Content Different", --WebDAV
  [226] = "IM Used", --RFC 3229
  --Redirection
  [300] = "Multiple Choices",
  [301] = "Moved Permanently",
  [302] = "Moved Temporarily",
  [303] = "See Other",
  [304] = "Not Modified",
  [305] = "Use Proxy",
  [306] = "", --reserved
  [307] = "Temporary Redirect",
  [308] = "Permanent Redirect",
  [310] = "Too many Redirects",
  --Client error
  [400] = "Bad Request",
  [401] = "Unauthorized",
  [402] = "Payment Required",
  [403] = "Forbidden",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [406] = "Not Acceptable",
  [407] = "Proxy Authentication Required",
  [408] = "Request Time-out",
  [409] = "Conflict",
  [410] = "Gone",
  [411] = "Lenght Required",
  [412] = "Precondition Failed",
  [413] = "Request Entity Too Large",
  [414] = "Request-URI Too Long",
  [415] = "Unsupported Media Type",
  [416] = "Requested range unsatisfiable",
  [417] = "Expectation failed",
  [418] = "I'm a teapot", --RFC 2324
  [422] = "Unprocessable entity", --WebDAV
  [423] = "Locked", --WebDAV
  [424] = "Method failure", --WebDAV
  [425] = "Unordered Collection", --WebDAV/RFC 3648
  [426] = "Upgrade Required", --RFC 2817
  [428] = "Precondition Required", --RFC 6585
  [429] = "Too Many Requests", --RFC 6585
  [431] = "Request Header Fields Too Large", --RFC 6585
  [449] = "Retry With", --M$
  [450] = "Blocked by Windows Parental Controls", --M$
  [456] = "Unrecoverable Error", --WebDAV
  [499] = "client has closed connection", --nginx
  --Server error
  [500] = "Internal Server Error",
  [501] = "Not Implemented",
  [502] = "Bad Gateway",
  [503] = "Service Unvavailable",
  [504] = "Gateway Time-out",
  [505] = "HTTP Version not supported",
  [506] = "Variant also negociate", --RFC 2295
  [507] = "Insufficient storage", --WebDAV
  [508] = "Loop detected", --WebDAV
  [509] = "Bandwidth Limit Exceeded",
  [510] = "Not extended", --RFC 2774
  [520] = "Web server is returning an unknown error",
  --Developer Errors, RFC 7XX
  [701] = "Meh",
  [702] = "Emacs",
  [703] = "Explosion",
  [704] = "Goto Fail",
  [705] = "I wrote the code and missed the necessary validation by an oversight", --see 795
  [710] = "PHP",
  [711] = "Convenience Store",
  [712] = "NoSQL",
  [719] = "I am not a teapot",
  --TODO add all the 7XX codes
  [799] = "End of the world",
}

errPage = {}
route = {}

--------------------
-- Misc functions --
--------------------

function string.replace(str, from ,to)
  from = from:gsub("%W", "%%%1")
  to = to:gsub("%W", "%%%1")
  return str:gsub(from, to)
end

------------
-- Client --
------------

local function getClient(server, timeout)
  print("Waiting ...")
  local client = server:accept()
  client:settimeout(timeout or 10)
  
  return client
end

local function clientReceive(client)
  local data = ""
  local buff = client:receive()
  while buff and buff ~= "" do
    data = (data..buff.."\n")
    buff = client:receive()
  end
  return data
end

local function clientSend(client, data)
  return client:send(data.."\n")
end

--------------
-- Requests --
--------------
local function parseRequest(request, client)
  local trequest = {}
  if not request:match("HTTP/[%d%.]+") then return nil, "Not an HTTP request", request end
  trequest.method = request:match("[%u]+") --supports everythings :)
  trequest.uri = request:match("/[^%s]*")
  trequest.httpVersion = request:match("HTTP/[%d%.]+")
  
  for s in request:gmatch("\n[^\n]+") do
    s = s:sub(3, -1) --remove \x13\x10
    trequest[s:match("[%w]+")] = s:match(":%s?[%w]+"):sub(3, -1)
  end
  
  trequest.ip = client:getsockname()
  return trequest
end

local function makeResponse(content, details)
  local details = (details or {})
  local statusCode = (details.statusCode or 200)
  details["Content-Lenght"] = (details["Content-Lenght"] or #content)
  details["Connection"] = (details["Connection"] or "Keep-Alive")
  
  local response = ("HTTP/1.1 "..statusCode.." "..statusCodes[statusCode].."\n")
  for n,v in pairs(details) do
    response = (response..n..": "..v.."\n")
  end
  response = (response.."\n"..content.."\n\n")
  return response
end

-----------------------
-- HTML page parsing --
-----------------------
local function htmlReplace(page, values)
  --Parsed
  page = page:gsub("{{![^}]+}}", function(str)
    return values[str:sub(4,-3)]:gsub("<", "&lt;"):gsub(">", "&gt;")
  end)
  --Parsing
  
  --Not parsed
  page = page:gsub("{{[^}]+}}", function(str)
    return values[str:sub(3,-3)]
  end)
  
  return page
end

local function htmlCode(page, values, ...)
  local final = page
  for c in page:gmatch("<&[^&]+&>") do
    local s = c:gsub("[<>&\n\t]", " ")
    local f, err = loadstring(s)
    local status, result = pcall(f, ...)
    final = final:gsub(c:gsub("(%W)", "%%%1"), result)
  end
  return final
end

------------
-- Errors --
------------
local function makeErrorResponse(err, details)
  local errPage = ((errPage[err] and errPage[err](details)) or (errPage["default"] and errPage["default"](details)) or [[<!DOCTYPE html>
<html>
  <head>
    <title>{{!err}}</title>
    <style type="text/css">
      html {background-color: #ddd;}
      body {background-color: #fff; border: 1px solid #ccc; margin: 10px; padding: 10px;}
      pre {background-color: #000; color: #1f0; border: 1px solid #333; padding 5px;}
    </style>
  </head>
  <body>
    <h1>Error {{!err}}: {{!statusCode}}</h1><br>
    <pre><code>{{!details}}</code></pre>
  </body>
</html>]])
  
  if type(details) == "string" then
    errPage = htmlReplace(errPage, {err=tostring(err), statusCode=statusCodes[err], details=details})
  elseif type(details) == "table" then
    errPage = htmlReplace(errPage, details)
  end
  
  return makeResponse(errPage, {statusCode = err, ["Content-Type"] = "text/html; charset=utf-8"})
end

-------------
---*******---
---* API *---
---*******---
-------------

function addError(err, page)
  if type(page) == "function" then
    errPage[err] = page
  elseif type(page) == "string" then
    errPage[err] = loadstring("return "..page)
  end
end

function addRoute(path, func)
  if type(func) == "function" then
    route[path] = func
  elseif type(func) == "string" then
    route[path] = loadstring("return [["..func.."]]")
  end
end

function server(port, ip)
  return assert(socket.bind((ip or "*"), (port or 8080)))
end

function template(tpl, values)
  local ftpl = io.open("views/"..tpl..".tpl", "r")
  local ctpl = ftpl:read("*a")
  ftpl:close()
  local page = htmlReplace(ctpl, values)
  page = htmlCode(page)
  return page
end

function startServer(server)
  --server:listen()
  while true do
    local client = getClient(server)
    print(client:getsockname())
    local request, err, what = parseRequest(clientReceive(client), client)
    if request then      
      local page = ""
      local found = false
      for n,v in pairs(route) do
        if request.uri:match(n) == request.uri then
          page = v(request)
          if not page then break end
          clientSend(client, makeResponse(page))
          found = true
          break
        end
      end
      if not found then
        local err = makeErrorResponse(404, "Not found: '"..request.uri.."'")
        clientSend(client, err)
      end
    else
      print(err.."\n"..what)
      clientSend(client, makeErrorResponse(400, err))
    end
    client:close()
  end
end
