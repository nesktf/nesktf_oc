-- STEAM VALUES:
-- 4480
-- 4800

local sides = require("sides")
local component = require("component")
local term = require("term")
local event = require("event")
local computer = require("computer")
local serialization = require("serialization")

local gpu = component.gpu
local modem = component.modem

-- Consts
DISTILL_MIN   = 100000
IC2_COOL_MIN  = 50000
LSC_MAX_RATIO = 0.8
LSC_MIN_RATIO = 0.2
RESTOCK_DELAY = 10
PORT          = 123
SLEEP_TIME    = 0.5

-- Screen size
WIDTH, HEIGHT = gpu.getResolution()

-- Status enums
STATUS_OK             = 0
STATUS_ITEM_INVALID   = 1
STATUS_FLUID_LESSMIN  = 2
STATUS_STRING = {
  [STATUS_OK]             = "OK",
  [STATUS_ITEM_INVALID]   = "Invalid item",
  [STATUS_FLUID_LESSMIN]  = "Not enough fluid",
}

-- Item enums
FUEL_QUAD_DEPLETED  = 1
FUEL_QUAD           = 2
FUEL_DUAL_DEPLETED  = 3
FUEL_DUAL           = 4
ITEM_ENUM = {
  ["IC2:reactorUraniumQuadDepleted"] = FUEL_QUAD_DEPLETED,
  ["gregtech:gt.reactorUraniumQuad"] = FUEL_QUAD,
  ["IC2:reactorUraniumDualDepleted"] = FUEL_DUAL_DEPLETED,
  ["gregtech:gt.reactorUraniumDual"] = FUEL_DUAL
}

-- Element enums
FLUID_COOL    = 1
FLUID_HOT     = 2
FLUID_DISTILL = 3
INV_REACTOR   = 4
INV_INTERFACE = 5
LSC_STORED    = 6
LSC_MAX       = 7
LSC_RATIO     = 8
LSC_PLOSS     = 9
LSC_AVGIN     = 10
LSC_AVGOUT    = 11
LSC_MAINT     = 12
LSC_AVAIL     = 13

-- Daemon states
DAEMON_STATE_IDLE = 0
DAEMON_STATE_RUNNING = 1
DAEMON_STATE_STOPPED = 2
DAEMON_STATE = DAEMON_STATE_STOPPED

-- Global state object
local state = {
  message = "Waiting for command",
  handle = {
    tank      = component.tank_controller,
    inv       = component.transposer,
    redstone  = component.redstone
  },
  tank = {
    [FLUID_COOL] = {
      name    = "IC2 Coolant",
      amount  = 0,
      side    = -1,
      min     = IC2_COOL_MIN,
      status  = STATUS_FLUID_LESSMIN,
    },
    [FLUID_HOT] = {
      name    = "IC2 Hot Coolant",
      amount = 0,
      side    = -1,
      min     = 0,
      status  = STATUS_FLUID_LESSMIN,
    },
    [FLUID_DISTILL] = {
      name    = "Distilled water",
      amount = 0,
      side    = sides.up,
      min     = DISTILL_MIN,
      status  = STATUS_FLUID_LESSMIN,
    }
  },
  inv = {
    [INV_REACTOR] = {
      name = "Reactor",
      side = sides.down,
      stack = {
        {
          damage  = -1,
          count   = 0,
          status  = STATUS_ITEM_INVALID,
          slot    = 1,
          item    = FUEL_QUAD
        },
        {
          damage  = -1,
          count   = 0,
          status  = STATUS_ITEM_INVALID,
          slot    = 10,
          item    = FUEL_QUAD
        },
        {
          damage  = -1,
          count   = 0,
          status  = STATUS_ITEM_INVALID,
          slot    = 11,
          item    = FUEL_QUAD
        },
        {
          damage  = -1,
          count   = 0,
          status  = STATUS_ITEM_INVALID,
          slot    = 19,
          item    = FUEL_DUAL
        }
      }
    },
    [INV_INTERFACE] = {
      name = "Interface",
      side = sides.up,
      stack = {
        {
          damage  = -1,
          count   = 0,
          status  = STATUS_ITEM_INVALID,
          slot    = 1,
          item    = FUEL_QUAD
        },
        {
          damage  = -1,
          count   = 0,
          status  = STATUS_ITEM_INVALID,
          slot    = 2,
          item    = FUEL_QUAD
        },
        {
          damage  = -1,
          count   = 0,
          status  = STATUS_ITEM_INVALID,
          slot    = 3,
          item    = FUEL_QUAD
        },
        {
          damage  = -1,
          count   = 0,
          status  = STATUS_ITEM_INVALID,
          slot    = 4,
          item    = FUEL_DUAL
        },
      }
    }
  },
  lsc = {
    [LSC_STORED]  = 0,
    [LSC_MAX]     = 0,
    [LSC_RATIO]   = 0,
    [LSC_PLOSS]   = 0,
    [LSC_AVGIN]   = 0,
    [LSC_AVGOUT]  = 0,
    [LSC_MAINT]   = true,
    [LSC_AVAIL]   = false
  }
}

function state:init()
  self.setSides(self)
  -- self.update(self)
end

function state:setSides()
  local h = self.handle.tank
  local side, sensor

  side   = sides.north
  sensor = h.getFluidInTank(side)[1]
  -- if (sensor.capacity == nil) then
  if (sensor == nil) then
    side   = sides.west
    sensor = h.getFluidInTank(side)
  end

  if (sensor.capacity == 128000) then
    self.tank[FLUID_HOT].side  = side
    self.tank[FLUID_COOL].side = side + 1
  else
    self.tank[FLUID_COOL].side = side
    self.tank[FLUID_HOT].side  = side + 1
  end
end

function state:update()
  self.updateItems(self)
  self.updateFluid(self)
end

function state:updateFluid()
  local h       = self.handle.tank
  local fluids  = {FLUID_COOL, FLUID_HOT, FLUID_DISTILL}

  for _,i in ipairs(fluids) do
    local fluid   = self.tank[i]
    local sensor  = h.getFluidInTank(fluid.side)[1]
    local amount  = (sensor ~= nil and sensor.amount or 0)

    fluid.status  = (amount < fluid.min and STATUS_FLUID_LESSMIN or STATUS_OK)
    fluid.amount  = amount
  end
end

function state:updateItems()
  local h     = self.handle.inv
  local invs  = {INV_REACTOR, INV_INTERFACE}

  for _,i in ipairs(invs) do
    local inv = self.inv[i]

    for j = 1, #inv.stack do
      local stack       = inv.stack[j]
      local sensor      = h.getStackInSlot(inv.side, stack.slot)
      local sensor_item

      if (sensor == nil) then
        stack.status  = STATUS_ITEM_INVALID
        stack.damage  = -1
        stack.count   = 0
        break
      end

      sensor_item   = ITEM_ENUM[sensor.name]
      stack.status  = (sensor_item == stack.item and STATUS_OK or STATUS_ITEM_INVALID)
      stack.damage  = sensor.damage
      stack.count   = sensor.size
    end
  end
end

local function drawWindow(title, min_x, min_y, max_x, max_y)
  local charset = {
    vert    = "│",
    hor     = "─",
    t_right = "╮",
    b_left  = "╰",
    t_left  = "╭",
    b_right = "╯"
  }

  gpu.set(min_x, min_y, charset.t_left)
  gpu.set(min_x, max_y, charset.b_left)
  gpu.set(max_x, min_y, charset.t_right)
  gpu.set(max_x, max_y, charset.b_right)
  gpu.fill(min_x + 1, min_y, max_x - min_x - 1, 1, charset.hor)
  gpu.fill(min_x + 1, max_y, max_x - min_x - 1, 1, charset.hor)
  gpu.fill(min_x, min_y + 1, 1, max_y - min_y - 1, charset.vert)
  gpu.fill(max_x, min_y + 1, 1, max_y - min_y - 1, charset.vert)

  -- TODO: trim, maybe center
  gpu.set(min_x + 2, min_y, title)
end

local function rectHasPoint(min_x, min_y, max_x, max_y, x, y)
    return x >= min_x and y >= min_y and x <= max_x and y <= max_y
end

local function widgetHasPoint(widget, x, y)
    return rectHasPoint(widget.min_x, widget.min_y, widget.max_x, widget.max_y, x, y)
end

local reactor = {
  isOperating = false,
  checkStatuses = function(thing)
    local c = STATUS_OK
    for _, i in ipairs(thing) do
      c = c + i.status
    end
    return (c == STATUS_OK)
  end,
  areTanksReady = function(this)
    return this.checkStatuses(state.tank)
  end,
  isInterfaceReady = function(this)
    return this.checkStatuses(state.inv[INV_INTERFACE].stack)
  end,
  isReactorReady = function(this)
    return this.checkStatuses(state.inv[INV_REACTOR].stack)
  end,
  canOperate = function(this)
    return (this.isReactorReady(this) and this.areTanksReady(this))
  end,
  canStart = function(this)
    return (this.isInterfaceReady(this) and this.areTanksReady(this))
  end,
  restock = function(this)
    if (this.isInterfaceReady(this)) then
      local inv_int = state.inv[INV_INTERFACE]
      local inv_reac = state.inv[INV_REACTOR]
      for i = 1,4 do
        if(inv_reac.stack[i].status == STATUS_ITEM_INVALID) then
          state.handle.inv.transferItem(inv_reac.side, inv_int.side, 1, inv_reac.stack[i].slot, inv_int.stack[i].slot+4)
        end
        state.handle.inv.transferItem(inv_int.side, inv_reac.side, 1, inv_int.stack[i].slot, inv_reac.stack[i].slot)
      end
      return true
    end
    return false
  end,
  start = function(this)
    if (this.canStart(this)) then
      if (this.restock(this)) then
        DAEMON_STATE = DAEMON_STATE_RUNNING
        state.handle.redstone.setOutput(sides.down, 15)
        computer.beep(95, 0.25)
      end

      state.message = "Reactor operating"
      this.isOperating = true
    else
      state.message = "Can't start the reactor, check values"
      this.isOperating = false
    end
  end,
  stop = function(this)
    -- state.message = "Stopping..."
    this.isOperating = false
    state.handle.redstone.setOutput(sides.down, 0)
    -- DAEMON_STATE = DAEMON_STATE_IDLE
    computer.beep(21, 0.25)
  end
}


local widgets = {
  {
    name  = "lsc_status",
    min_x = 2,
    min_y = 1,
    max_x = WIDTH - 1,
    max_y = 7,
    onTouch = function(widget, x, y) end,
    draw = function (this)
      local lsc = state.lsc
      local x = this.min_x + 2
      local y = this.min_y

      local net_eu = lsc[LSC_AVGIN] - lsc[LSC_AVGOUT] - lsc[LSC_PLOSS]
      local str =   "I: " .. lsc[LSC_AVGIN]   .. " EU/t | "
      str = str ..  "O: " .. lsc[LSC_AVGOUT]  .. " EU/t | "
      str = str ..  "P: " .. lsc[LSC_PLOSS]   .. " EU/t"

      local time
      if (net_eu < 0) then
        local secs = math.floor(lsc[LSC_STORED]/(net_eu*-20))
        local hours = string.format("%.2f", secs / 3600)
        time = "Empty in:      " .. secs .. " secs | " .. hours .. " hours"
      elseif (net_eu > 0) then
        local secs = math.floor((lsc[LSC_MAX]-lsc[LSC_STORED])/(net_eu*20))
        local hours = string.format("%.2f", secs / 3600)
        time = "Full in:       " .. secs .. " secs | " .. hours .. " hours"
      else
        time = ""
      end

      local perc = string.format("%.2f", lsc[LSC_RATIO]*100)
      local eu_str = lsc[LSC_STORED] .. "EU / " .. lsc[LSC_MAX] .. "EU (" .. perc .. "%)"

      drawWindow("Lapotronic Supercapacitor", this.min_x, this.min_y, this.max_x, this.max_y)
      gpu.set(x, y+1, "Stored Energy: " .. eu_str)
      gpu.set(x, y+2, "EU I/O:        " .. net_eu .. " EU/t")
      gpu.set(x, y+3, "               " .. str)
      gpu.set(x, y+4, "Maintenance:   " .. (lsc[LSC_MAINT] and "true" or "false"))
      gpu.set(x, y+5, time)
    end
  },
  {
    name = "reactor_status",
    min_x = 2,
    min_y = 8,
    max_x = WIDTH/2 - 12,
    max_y = 8+5,
    onTouch = function(widget, x, y) end,
    draw = function (this)
      local x = this.min_x + 2
      local y = this.min_y

      drawWindow("Reactor Status", this.min_x, this.min_y, this.max_x, this.max_y)
      -- gpu.set(x, y+1, "LSC Present:     " .. (state.lsc[LSC_AVAIL] and "true" or "false"))
      gpu.set(x, y+1, "Can start:       " .. (reactor.canStart(reactor) and "true" or "false"))
      gpu.set(x, y+2, "Is Operating:    " .. (reactor.isOperating and "true" or "false"))
      if (reactor.isOperating) then
        gpu.set(x, y+3, "Can continue:    "..(reactor.canOperate(reactor) and "true" or "false"))
      end
    end
  },
  {
    name = "buffer_status",
    min_x = WIDTH/2 - 11,
    min_y = 8,
    max_x = WIDTH - 1,
    max_y = 8+5,
    onTouch = function(widget, x, y) end,
    draw = function(this)
      local x = this.min_x + 2
      local y = this.min_y

      drawWindow("Buffer status", this.min_x, this.min_y, this.max_x, this.max_y)
      gpu.set(x, y+1, "Has fuel stock:  " .. (reactor.isInterfaceReady(reactor) and "true" or "false"))
      gpu.set(x, y+2, "Distilled Water: " .. state.tank[FLUID_DISTILL].amount .. "L")
      gpu.set(x, y+3, "IC2 Coolant:     " .. state.tank[FLUID_COOL].amount .. "L")
      gpu.set(x, y+4, "IC2 Hot Coolant: " .. state.tank[FLUID_HOT].amount .. "L")
    end
  },
  {
    name = "controls_container",
    min_x = 2,
    min_y = 14,
    max_x = WIDTH - 1,
    max_y = HEIGHT - 3,
    onTouch = function(widget, x, y) end,
    draw = function(this)
      drawWindow("Controls", this.min_x, this.min_y, this.max_x, this.max_y)
    end
  },
  {
    name = "button_start",
    min_x = 4,
    min_y = 16,
    max_x = 4 + 12,
    max_y = 16 + 4,
    onTouch = function(widget, x, y) reactor.start(reactor) end,
    draw = function(this)
      drawWindow("", this.min_x, this.min_y, this.max_x, this.max_y)
      gpu.set(this.min_x + 4, this.min_y + 2, "START")
    end
  },
  {
    name = "button_stop",
    min_x = (4+12) + 2,
    min_y = 16,
    max_x = (4 + 12) + 2 + 12,
    max_y = 16 + 4,
    onTouch = function(widget, x, y)
      DAEMON_STATE = DAEMON_STATE_STOPPED
      state.message = "Reactor manually stopped"
      reactor.stop(reactor)
    end,
    draw = function(this)
      drawWindow("", this.min_x, this.min_y, this.max_x, this.max_y)
      gpu.set(this.min_x + 4, this.min_y + 2, "STOP")
    end
  },
  {
    name = "button_idle",
    min_x = (4+12+2+12) + 2,
    min_y = 16,
    max_x = (4+12+2+12) + 2 + 12,
    max_y = 16+4,
    onTouch = function(widget, x, y)
      reactor.stop(reactor)
      DAEMON_STATE = DAEMON_STATE_IDLE
      state.message = "Reactor is now on idle"
    end,
    draw = function(this)
      drawWindow("", this.min_x, this.min_y, this.max_x, this.max_y)
      gpu.set(this.min_x + 2, this.min_y + 2, "SET IDLE")
    end
  },
  {
    name = "message",
    min_x = 2,
    min_y = HEIGHT - 2,
    max_x = WIDTH - 1,
    max_y = HEIGHT,
    onTouch = function(widget, x, y) end,
    draw = function(this)
      local x = this.min_x + 2
      local y = this.min_y

      drawWindow("Message", this.min_x, this.min_y, this.max_x, this.max_y)
      gpu.set(x, y+1, state.message)
    end
  }
}

-- TODO: Set stop conditions
local daemon = {
  run_cycles = 0,
  [DAEMON_STATE_IDLE] = function (this)
    if (state.lsc[LSC_RATIO] < LSC_MIN_RATIO) then
      state.message = "Reactor operating"
      reactor.start(reactor) -- Implicit change to DAEMON_STATE_RUNNING
    end
  end,
  [DAEMON_STATE_RUNNING] = function (this)
    -- if (not reactor.canOperate(reactor)) then
    if (not reactor.areTanksReady(reactor)) then
      reactor.stop(reactor)
      this.run_cycles = 0
      DAEMON_STATE = DAEMON_STATE_STOPPED
      state.message = "Reactor emergency stop triggered"
      return
    end

    if (state.lsc[LSC_RATIO] > LSC_MAX_RATIO) then
      reactor.stop(reactor)
      this.run_cycles = 0
      DAEMON_STATE = DAEMON_STATE_IDLE
      state.message = "Reactor is now on idle"
      return
    end

    if (this.run_cycles > (RESTOCK_DELAY-1)) then
      reactor.restock(reactor)
      this.run_cycles = 0
    end

    this.run_cycles = this.run_cycles + 1
  end,
  [DAEMON_STATE_STOPPED] = function (this) end
}

local function eventHandler(event_id, ...)
  local handlers = setmetatable({}, { __index = function() end })

  function handlers.modem_message(_, addr, _, _, data)
    state.lsc = serialization.unserialize(data)
  end

  function handlers.touch(_, x, y, _, _)
    for _, widget in ipairs(widgets) do
      if (widgetHasPoint(widget, x, y)) then
        widget.onTouch(widget, x, y)
      end
    end
  end

  if (event_id) then
    handlers[event_id](...)
  end
end

local function main()
  state.init(state)

  local function guardedMain()
    local keep_alive = true
    event.listen("interrupted", function() keep_alive = false end)
    event.listen("modem_message", eventHandler)
    event.listen("touch", eventHandler)

    while keep_alive do
      event.pull(0)
      state.update(state)

      gpu.fill(1, 1, WIDTH, HEIGHT, " ")
      for _,widget in ipairs(widgets) do
        widget.draw(widget)
      end
      daemon[DAEMON_STATE](daemon)

      os.sleep(SLEEP_TIME)
    end
    term.clear()
    print("Script interrupted")
  end

  modem.open(PORT)
  local status, err = pcall(guardedMain)
  if not status then
    reactor.stop(reactor)
    gpu.fill(1, 1, WIDTH, HEIGHT, " ")
    print("DIED: "..err)
  end
end

term.clear()
main()
