local component = require("component")
local term = require("term")
local event = require("event")
local serialization = require("serialization")

local lsc = component.gt_machine
local modem = component.modem
local serialize = serialization.serialize

-- Consts
PORT = 123
SLEEP_SECS = 1

-- Enums
LSC_STORED    = 6
LSC_MAX       = 7
LSC_RATIO     = 8
LSC_PLOSS     = 9
LSC_AVGIN     = 10
LSC_AVGOUT    = 11
LSC_MAINT     = 12

local function parseLSC(sensor)
  local function parse_fuzzy_int(str)
    local filtered_str = string.gsub(str, "([^0-9]+)", "")
    return math.floor(tonumber(filtered_str))
  end
  local function avg_str(str)
    return string.gsub(str, "(last 5 seconds)","")
  end

  local stored = parse_fuzzy_int(string.gsub(sensor[2], "EU stored (exact):", ""))
  local max = parse_fuzzy_int(string.gsub(sensor[5], "Total Capacity (exact):", ""))

  local data = {
    [LSC_STORED]  = stored,
    [LSC_MAX]     = max,
    [LSC_PLOSS]   = parse_fuzzy_int(sensor[4]),
    [LSC_AVGIN]   = parse_fuzzy_int(avg_str(sensor[7])),
    [LSC_AVGOUT]  = parse_fuzzy_int(avg_str(sensor[8])),
    [LSC_RATIO]   = stored / max,
    [LSC_MAINT]   = (string.find(sensor[9], "Has Problems") ~= nil)
  }
  return data
end

local function printData(data)
  term.clear()
  local perc = string.format("%.2f", data[LSC_RATIO]*100)

  print("Lapotronic supercapacitor")
  print("Stored:\t\t\t" .. data[LSC_STORED])
  print("Max:\t\t\t" .. data[LSC_MAX])
  print("Percentage used:\t" .. perc)
  print("Passive Loss:\t\t" .. data[LSC_PLOSS])
  print("Average Input:\t\t" .. data[LSC_AVGIN])
  print("Average Output:\t\t" .. data[LSC_AVGOUT])
  print("Needs maintenance:\t" .. (data[LSC_MAINT] and "true" or "false"))
end

local function main()
  modem.open(PORT)
  local keep_alive = true
  event.listen("interrupted", function() keep_alive = false end)

  while keep_alive do
    local lsc_sensor = lsc.getSensorInformation()
    local data = parseLSC(lsc_sensor)

    printData(data)
    modem.broadcast(PORT, serialize(data))
    os.sleep(SLEEP_SECS)
  end

  term.clear()
  print("Sript interrupted")
end

term.clear()
main()
