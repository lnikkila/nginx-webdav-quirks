--[[
   SPDX-License-Identifier: AGPL-3.0-or-later
   SPDX-FileCopyrightText: © 2024 Leo Nikkilä <hello@lnikki.la>

   Mangle escaped UTF-8 from NFC to NFD in PROPFIND responses.
]]
local lxp     = require("lxp")
local ustring = require("ustring/ustring")

local function assert_xml_parse(_, err, line, col)
   if err then
      error(string.format("XML error at %s:%s: %s", line, col, err))
   end
end

local function escape_xml(str)
   str = str:gsub("[\"&'<>]", {
                     ['"'] = "&quot;",
                     ["&"] = "&amp;",
                     ["'"] = "&apos;",
                     ["<"] = "&lt;",
                     [">"] = "&gt;",
   })
   return str
end

local function mangle_href(str)
   -- ngx.unescape_uri converts plus signs into spaces, we'll escape
   -- those properly to avoid this.
   str = str:gsub("%+", "%%2B")
   str = ngx.escape_uri(ustring.toNFD(ngx.unescape_uri(str)), 0)
   -- ngx.escape_uri escapes only a subset of what upstream escapes,
   -- Finder has trouble with some of these characters. See
   -- <https://github.com/openresty/lua-nginx-module/issues/1124>
   -- <https://github.com/openresty/lua-nginx-module/blob/7598ff389ef5a1a3e8949c48a6e13292fa9adc9e/src/ngx_http_lua_util.c#L2009-L2025>
   -- <https://github.com/nginx/nginx/blob/f255815f5d161fab0dd310fe826d4f7572e141f2/src/core/ngx_string.c#L1516-L1532>.
   str = str:gsub("[\"'<>\\^`{|}]", {
                     [ '"'] = "%22",
                     [ "'"] = "%27",
                     [ "<"] = "%3C",
                     [ ">"] = "%3E",
                     ["\\"] = "%5C",
                     [ "^"] = "%5E",
                     [ "`"] = "%60",
                     [ "{"] = "%7B",
                     [ "|"] = "%7C",
                     [ "}"] = "%7D",
   })
   return str
end

local function mangle_body(shm_dict, dict_key)
   local body = {}
   local path = {}
   local _H = {}

   function _H.Default(parser, str)
      table.insert(body, str)
   end

   function _H.CharacterData(parser, str)
      if path[#path] == "D:href" then
         str = mangle_href(str)
      end

      table.insert(body, escape_xml(str))
   end

   function _H.StartElement(parser, name, attrs)
      table.insert(path, name)

      -- We'd rather use XML_DefaultCurrent instead of rewriting the XML
      -- tags here, but lua-expat doesn't currently expose it.
      table.insert(body, "<")
      table.insert(body, escape_xml(name))

      for _, k in ipairs(attrs) do
         table.insert(body, " ")
         table.insert(body, k)
         table.insert(body, "=\"")
         table.insert(body, escape_xml(attrs[k]))
         table.insert(body, "\"")
      end

      table.insert(body, ">")
   end

   function _H.EndElement(parser, name)
      table.remove(path)
      table.insert(body, "</")
      table.insert(body, escape_xml(name))
      table.insert(body, ">")
   end

   local parser = lxp.new(_H)

   while true do
      local buf, err = shm_dict:lpop(dict_key)
      if err then
         error(string.format("lpop body failed: %s", err))
      end
      if buf then
         assert_xml_parse(parser:parse(buf))
      else
         break
      end
   end

   assert_xml_parse(parser:parse())
   parser:close()
   return body
end

local _M = {}

function _M.body_filter()
   if ngx.req.get_method() ~= "PROPFIND" or ngx.status ~= 207 then
      return
   end
   if ngx.var.webdav_quirks_no_mangle_nfc == "1" then
      return
   end
   -- The body filter might be called multiple times, once for each
   -- response body chunk. We buffer the body in shared memory until
   -- we've collected it all, since we can't stop and resume parsing
   -- later with lua-expat.
   local buf, eof = ngx.arg[1], ngx.arg[2]
   local shm_dict = ngx.shared.webdav_quirks
   local dict_key = ngx.var.request_id
   local _, err = shm_dict:rpush(dict_key, buf)
   if err then
      error(string.format("rpush body failed: %s", err))
   end
   if eof then
      ngx.arg[1] = mangle_body(shm_dict, dict_key)
   else
      ngx.arg[1] = nil
   end
end

function _M.header_filter()
   if ngx.req.get_method() ~= "PROPFIND" or ngx.status ~= 207 then
      return
   end
   if ngx.var.webdav_quirks_no_mangle_nfc == "1" then
      return
   end
   -- Reset the Content-Length header since we're changing the length.
   ngx.header.content_length = nil
end

return _M
