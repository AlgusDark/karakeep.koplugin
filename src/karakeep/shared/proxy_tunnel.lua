local socket = require('socket')
local ssl = require('ssl')
local logger = require('logger')

local try = socket.try

---HTTPS through an HTTP CONNECT proxy.
---
---LuaSec's own https module refuses to combine TLS with a proxy ("proxy not
---supported"), and LuaSocket's http module has no CONNECT tunnelling. That
---leaves no way to reach an HTTPS service that is only routable through a
---local proxy -- which is exactly the situation on e-reader devices where
---Tailscale runs in userspace-networking mode and exposes 127.0.0.1:1056
---instead of creating a TUN interface.
---
---This module supplies a `create` function for LuaSocket's http.request that
---dials the proxy, issues CONNECT for the real target, and only then upgrades
---the tunnelled socket to TLS (with SNI set to the target host, not the proxy).
---@class ProxyTunnel
local ProxyTunnel = {}

local BASE_TLS_PARAMS = {
    mode = 'client',
    protocol = 'any',
    options = { 'all', 'no_sslv2', 'no_sslv3' },
}

---Forward socket methods onto the wrapper once the underlying socket has been
---replaced by its TLS-wrapped counterpart. Same approach LuaSec uses.
---@param conn table
local function forwardSocketMethods(conn)
    local mt = getmetatable(conn.sock).__index
    for name, method in pairs(mt) do
        if type(method) == 'function' then
            conn[name] = function(self, ...)
                return method(self.sock, ...)
            end
        end
    end
end

---@class ProxyTunnelOptions
---@field proxy_host string Proxy host, e.g. '127.0.0.1'
---@field proxy_port number Proxy port, e.g. 1056
---@field timeout? number Socket timeout in seconds
---@field cafile? string Path to a CA bundle; enables peer verification

---Build a LuaSocket `create` function that tunnels TLS through an HTTP proxy
---@param options ProxyTunnelOptions
---@return function create Function suitable for request.create
function ProxyTunnel.createFactory(options)
    local proxy_host = options.proxy_host
    local proxy_port = options.proxy_port
    local timeout = options.timeout or 30

    local params = {}
    for k, v in pairs(BASE_TLS_PARAMS) do
        params[k] = v
    end

    -- Verify the peer whenever we have a CA bundle. This carries a bearer
    -- token, so an unverified tunnel would be a meaningful downgrade.
    if options.cafile then
        params.cafile = options.cafile
        params.verify = 'peer'
    else
        logger.warn('[ProxyTunnel] no CA bundle available; peer verification disabled')
        params.verify = 'none'
    end

    return function()
        local conn = {}
        conn.sock = try(socket.tcp())

        local settimeout = getmetatable(conn.sock).__index.settimeout
        function conn:settimeout()
            return settimeout(self.sock, timeout)
        end

        ---Connect to the proxy, CONNECT to the target, then start TLS.
        ---@param host string Target host (not the proxy)
        ---@param port number Target port (not the proxy)
        function conn:connect(host, port)
            try(self.sock:connect(proxy_host, proxy_port))

            local connect_request = ('CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n\r\n'):format(
                host,
                port,
                host,
                port
            )
            try(self.sock:send(connect_request))

            local status_line = try(self.sock:receive('*l'))
            local code = tonumber(status_line:match('^HTTP/%d%.%d%s+(%d+)') or '')
            if code ~= 200 then
                self.sock:close()
                return nil, 'proxy refused CONNECT: ' .. tostring(status_line)
            end

            -- Drain the remaining proxy response headers.
            repeat
                local line = self.sock:receive('*l')
            until not line or line == ''

            -- SNI must name the target, otherwise the server cannot pick the
            -- right certificate.
            self.sock = try(ssl.wrap(self.sock, params))
            self.sock:sni(host)
            self.sock:settimeout(timeout)
            try(self.sock:dohandshake())

            forwardSocketMethods(self)
            return 1
        end

        return conn
    end
end

---Parse a 'host:port' proxy string
---@param address string
---@return string|nil host, number|nil port
function ProxyTunnel.parseAddress(address)
    if not address or address == '' then
        return nil, nil
    end
    local host, port = address:match('^%s*([^:%s]+):(%d+)%s*$')
    if not host then
        return nil, nil
    end
    return host, tonumber(port)
end

return ProxyTunnel
