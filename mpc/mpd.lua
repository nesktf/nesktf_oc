--
--  _                                       _
-- | |_   _  __ _       _ __ ___  _ __   __| |
-- | | | | |/ _` |_____| '_ ` _ \| '_ \ / _` |
-- | | |_| | (_| |_____| | | | | | |_) | (_| |
-- |_|\__,_|\__,_|     |_| |_| |_| .__/ \__,_|
--                               |_|
--
-- Small interface to MusicPD
-- use luasocket, with a persistent connection to the MPD server.
--
-- Originally based on a netcat version
-- from Steve Jothen <sjothen at gmail dot com>

-- Grab env
local socket = require("socket")

local MPD = {}

local function get_params_from_env()
    local port = tonumber(os.getenv('MPD_PORT')) or 6600
    local host = os.getenv('MPD_HOST') or 'localhost'
    local password, hostname
    if string.find(host,"@") then
        _, _, password, hostname = string.find(host, "([^@]+)@([a-zA-Z0-9.]+)")
    else
        hostname = host
    end
    return {
        hostname = hostname,
        port = port,
        password = password
    }
end

-- create and return a new mpd client.
-- the settings argument is a table with theses keys:
--      hostname: the MPD's host (default "localhost")
--      port:     MPD's port to connect to (default 6600)
--      desc:     server's description (default hostname)
--      password: the server's password (default nil, no password)
--      timeout:  time in sec to wait for connect() and receive() (default 1)
--      retry:    time in sec to wait before reconnect if error (default 60)
function MPD.new(settings)

    local env = get_params_from_env()

    local client = {}
    if settings == nil then settings = {} end

    client.hostname = settings.hostname or env.hostname
    client.port     = settings.port or env.port or 6600
    client.desc     = settings.desc or client.hostname
    client.password = settings.password or env.password
    client.timeout  = settings.timeout or 1
    client.retry    = settings.retry or 60

    setmetatable(client, { __index = MPD })

    return client
end


-- calls the action and returns the server's response.
--      Example: if the server's response to "status" action is:
--              volume: 20
--              repeat: 0
--              random: 0
--              playlist: 599
--              ...
--      then the returned table is:
--      { volume = 20, repeat = 0, random = 0, playlist = 599, ... }
--
-- if an error arise (bad password, connection failed etc.), a table with only
-- the errormsg field is returned.
--      Example: if there is no server running on host/port, then the returned
--      table is:
--              { errormsg = "could not connect" }
--
function MPD:send(action)
    local command = string.format("%s\n", action)
    local values = {}

    -- connect to MPD server if not already done.
    if not self.connected then
        local now = os.time();
        if not self.last_try or (now - self.last_try) > self.retry then
            self.socket = socket.tcp()
            self.socket:settimeout(self.timeout, 't')
            self.last_try = os.time()
            self.connected = self.socket:connect(self.hostname, self.port)
            if not self.connected then
                return { errormsg = "could not connect" }
            end
            self.last_error = nil

            -- Read the server's hello message
            local line = self.socket:receive("*l")
            if not line:match("^OK MPD") then -- Invalid hello message?
                self.connected = false
                return { errormsg = string.format("invalid hello message: %s", line) }
            else
                self.version = string.match(line, "^OK MPD ([0-9.]+)")
            end

            -- send the password if needed
            if self.password then
                local rsp = self:send(string.format("password %s", self.password))
                if rsp.errormsg then
                    return rsp
                end
            end
        else
            local retry_sec = self.retry - (now - self.last_try)
            return { errormsg = string.format("%s (retrying in %d sec)", self.last_error, retry_sec) }
        end
    end

    self.socket:send(command)

    local line = ""
    while not line:match("^OK$") do
        local err
        line, err = self.socket:receive("*l")
        if not line then -- closed,timeout (mpd killed?)
            self.last_error = err
            self.connected = false
            self.socket:close()
            return self:send(action)
        end

        if line:match("^ACK") then
            return { errormsg = line }
        end

        local _, _, key, value = string.find(line, "([^:]+):%s(.+)")
        if key then
            values[string.lower(key)] = value
        end
    end

    return values
end

function MPD:next()
    return self:send("next")
end

function MPD:previous()
    return self:send("previous")
end

function MPD:stop()
    return self:send("stop")
end

-- no need to check the new value, mpd will set the volume in [0,100]
function MPD:volume_up(delta)
    local stats = self:send("status")
    local new_volume = tonumber(stats.volume) + delta
    return self:send(string.format("setvol %d", new_volume))
end

function MPD:volume_down(delta)
    return self:volume_up(-delta)
end

function MPD:toggle_random()
    local stats = self:send("status")
    if tonumber(stats.random) == 0 then
        return self:send("random 1")
    else
        return self:send("random 0")
    end
end

function MPD:toggle_repeat()
    local stats = self:send("status")
    if tonumber(stats["repeat"]) == 0 then
        return self:send("repeat 1")
    else
        return self:send("repeat 0")
    end
end

function MPD:toggle_play()
    if self:send("status").state == "stop" then
        return self:send("play")
    else
        return self:send("pause")
    end
end

function MPD:seek(delta)
    local stats   = self:send("status")
    local current = stats.time:match("^(%d+):")
    return self:send(string.format("seek %d %d", stats.songid, current + delta))
end

function MPD:protocol_version()
    if not self.version then
        -- send a "status" command to init the connection
        local s = self:send("status")
        if s.errormsg then
            return nil, s
        end
    end
    return self.version
end

return MPD
