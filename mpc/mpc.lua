-- https://mpd.readthedocs.io/en/latest/protocol.html
local mpd = require('mpd')

local function format_time(secs)
  return string.format("%02d:%02d", math.floor(secs/60), secs % 60)
end

local mpc = mpd.new {
  hostname = 'localhost',
  port = 6600,
  desc = 'localhost',
  password = nil,
  timeout = 1,
  retry = 60,
}


function mpc:currentsong()
  local req = self:send('currentsong')
  return {
    ["title"] = req.title and req.title or 'nil',
    ["album"] = req.album and req.album or 'nil',
    ["artist"] = req.artist and req.artist or 'nil',
    ["album_artist"] = req.albumartist and req.albumartist or 'nil',
    ["time"] = req.time and format_time(req.time) or '0',
  }
end

function mpc:status()
  return self:send('status')
end

local function main()
  for k, v in pairs(mpc:send(arg[1])) do
    print(k, v)
  end
end

main()
