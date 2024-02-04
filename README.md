<!--
  SPDX-License-Identifier: CC-BY-SA-4.0
  SPDX-FileCopyrightText: © 2024 Leo Nikkilä <hello@lnikki.la>
-->

# Nginx WebDAV quirks

This is a set of Lua scripts to work around several compatibility issues
with Nginx's WebDAV module and Finder, building upon [Rob Peck's earlier
work](https://www.robpeck.com/2020/06/making-webdav-actually-work-on-nginx/).
This includes a Lua implementation of his Nginx configuration, and my
additional workaround for Finder's Unicode issues.

[See my blog post describing this in further
detail.](https://lnikki.la/posts/using-lua-on-nginx-to-fix-finders-webdav-quirks.html)

## Installation

On the Nginx side, you'll need these modules:

- [`ngx_http_lua_module`](https://github.com/openresty/lua-nginx-module)
- [`ngx_http_dav_ext_module`](https://github.com/arut/nginx-dav-ext-module)

On the Lua side, you'll need these libraries:

- [LuaExpat](https://lunarmodules.github.io/luaexpat/)
- [LuaFileSystem](https://lunarmodules.github.io/luafilesystem/)

On Debian-based distributions for example, these are all available as
packages:

```sh
sudo apt install libnginx-mod-http-lua libnginx-mod-http-dav-ext lua-expat lua-filesystem
```

This repository also vendors in Wikimedia's
[`ustring`](https://github.com/wikimedia/mediawiki-extensions-Scribunto/tree/master/includes/Engines/LuaCommon/lualib/ustring)
string manipulation module, since I'm not currently aware of a widely
available Lua library for converting UTF-8 strings from NFC to NFD form.

## Configuration

Once you've installed the dependencies, clone this repository somewhere
convenient like `/etc/nginx/webdav-quirks`.

Make sure the files are owned and only writable by root, since they're
included in the Nginx configuration:

```sh
sudo chown -R root:root /etc/nginx/webdav-quirks
sudo chmod -R o-w /etc/nginx/webdav-quirks
```

Load the required Nginx modules in your configuration, e.g.:

```conf
load_module /etc/nginx/modules/ngx_http_lua_module.so;
load_module /etc/nginx/modules/ngx_http_dav_ext_module.so;
```

Set up `lua_package_path` and `lua_package_cpath` to load the required
Lua libraries, and also the scripts from this repository. This is
assuming Lua files are in `/usr/share/lua/5.1`, native Lua modules in
`/usr/lib/x86_64-linux-gnu/lua/5.1`, and this repository is in
`/etc/nginx/webdav-quirks`:

```conf
lua_package_path  '/usr/share/lua/5.1/?.lua;/etc/nginx/webdav-quirks/?.lua';
lua_package_cpath '/usr/lib/x86_64-linux-gnu/lua/5.1/?.so';
```

Include the `http.conf` script from this repository in the `http` block,
and also the `server.conf` script in the `server` or `location` block
handling WebDAV, similar to this:

```conf
dav_ext_lock_zone zone=dav:10m;

http {
  # ...
  include /etc/nginx/webdav-quirks/http.conf;

  server {
    # ...
    dav_methods PUT DELETE MKCOL COPY MOVE;
    dav_ext_methods PROPFIND OPTIONS LOCK UNLOCK;
    dav_ext_lock_zone zone=dav;
    create_full_put_path on;
    include /etc/nginx/webdav-quirks/server.conf;
  }
}
```

Restart Nginx, and you should have a fully functional WebDAV setup.
Check the Nginx `error.log` to troubleshoot any issues.

## Troubleshooting

### Compatibility

I believe this should work with Windows WebDAV clients as well, but I'm
unable to test this myself.

### Manual configuration

The Nginx configuration files included from this repository are only
suggestive, you can always configure things manually if needed. See the
source code of those files for details.

### Disabling Unicode mangling

If you store files using Unicode paths in NFD form instead of NFC, which
is uncommon, Finder will not be able to display those files, since paths
that it tries to access are always mangled into NFC.

You can disable this mangling with:

```conf
set $webdav_quirks_no_mangle_nfc 1;
```

This enables Finder to load NFD-encoded paths, but it also prevents it
from loading any NFC-encoded paths, since as of macOS Sonoma 14.2.1
Finder only seems to support NFD paths with WebDAV.

## License

This work is licensed under multiple licenses:

- All original source code is licensed under AGPL-3.0-or-later.
- All original documentation is licensed under CC-BY-SA-4.0.
- The `ustring` directory is licensed under MIT.

See SPDX headers in individual files for details.
