--[[
   SPDX-License-Identifier: AGPL-3.0-or-later
   SPDX-FileCopyrightText: © 2024 Leo Nikkilä <hello@lnikki.la>

   Rewrite $uri and $http_destination for Finder.
]]
local lfs     = require("lfs")
local ustring = require("ustring/ustring")

local function is_dir(path)
   local stat = lfs.attributes(path)
   return type(stat) == "table" and stat.mode == "directory"
end

local function table_with_default(tbl)
   setmetatable(tbl, { __index = function() return tbl.default end })
end

local add_uri_slash = {
   -- GET is a special case: when autoindex is enabled, we want it to do
   -- what it normally does when serving a directory without a trailing
   -- slash and return a redirect.
   GET     = function() return false end,
   MKCOL   = function() return true  end,
   default = function(is_dir) return is_dir end,
}
table_with_default(add_uri_slash)

local add_destination_slash = {
   COPY    = function(is_dir) return is_dir end,
   MOVE    = function(is_dir) return is_dir end,
   default = function() return false end,
}
table_with_default(add_destination_slash)

local _M = {}

function _M.rewrite()
   local method           = ngx.req.get_method()
   local uri              = ngx.var.uri
   local request_filename = ngx.var.request_filename
   local http_destination = ngx.var.http_destination

   if ngx.var.webdav_quirks_no_mangle_nfc ~= "1" then
      uri              = ustring.toNFC(uri)
      request_filename = ustring.toNFC(request_filename)
      http_destination = http_destination and
         ngx.escape_uri(
            ustring.toNFC(ngx.unescape_uri(http_destination)),
            0
         )
   end

   local is_dir = is_dir(request_filename)

   if add_uri_slash[method](is_dir) then
      uri = uri:gsub("[^/]$", "%0/", 1)
   end

   ngx.req.set_uri(uri)

   if http_destination then
      if add_destination_slash[method](is_dir) then
         http_destination = http_destination:gsub("[^/]$", "%0/", 1)
      end
      ngx.req.set_header("Destination", http_destination)
   end
end

return _M
