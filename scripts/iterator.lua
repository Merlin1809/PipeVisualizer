local flib_queue = require("__flib__/queue")

local renderer = require("__PipeVisualizer__/scripts/renderer")

--- @alias PlayerIndex uint
--- @alias FluidSystemID uint
--- @alias PlayerIterators table<PlayerIndex, table<FluidSystemID, Iterator>>

--- @class Iterator
--- @field color Color
--- @field completed table<uint, LuaEntity>
--- @field id FluidSystemID
--- @field in_overlay boolean
--- @field player_index PlayerIndex
--- @field queue Queue<LuaEntity>

--- @param starting_entity LuaEntity
--- @param player_index PlayerIndex
--- @param in_overlay boolean
local function request(starting_entity, player_index, in_overlay)
  if not global.iterator then
    return
  end

  local fluidbox = starting_entity.fluidbox
  for i = 1, #fluidbox do
    --- @cast i uint
    local id = fluidbox.get_fluid_system_id(i)
    if not id then
      goto continue
    end

    local player_iterators = global.iterator[player_index]
    if not player_iterators then
      player_iterators = {}
      global.iterator[player_index] = player_iterators
    end
    local iterator = player_iterators[id]
    if iterator then
      if in_overlay and not iterator.completed[starting_entity.unit_number] then
        flib_queue.push_back(iterator.queue, starting_entity)
      end
      goto continue
    end

    local queue = flib_queue.new()
    flib_queue.push_back(queue, starting_entity)

    -- TODO: Handle when there's no fluid in the system
    local color = { r = 0.3, g = 0.3, b = 0.3 }
    local contents = fluidbox.get_fluid_system_contents(i)
    if contents and next(contents) then
      color = global.fluid_colors[next(contents)]
    end

    --- @type Iterator
    player_iterators[id] = {
      completed = {},
      color = color,
      id = id,
      in_overlay = in_overlay,
      player_index = player_index,
      queue = queue,
    }

    ::continue::
  end
end

--- @param iterator Iterator
--- @param entity LuaEntity
local function iterate_entity(iterator, entity)
  if iterator.completed[entity.unit_number] then
    return
  end

  local player_index = iterator.player_index
  local color = iterator.color

  local fluidbox = entity.fluidbox
  for i = 1, #fluidbox do
    --- @cast i uint
    local id = fluidbox.get_fluid_system_id(i)
    if id ~= iterator.id then
      goto continue
    end

    --- @type PipeConnection[]
    local existing_connections = {}
    local connections = fluidbox.get_pipe_connections(i)
    for j = 1, #connections do
      local connection = connections[j]
      if not connection.target then
        goto inner_continue
      end

      local target = connection.target.owner

      if iterator.completed[target.unit_number] then
        existing_connections[#existing_connections + 1] = connection
        goto inner_continue
      end

      renderer.draw_connection_border(connection, entity, target, iterator.id, color, player_index)
      if not iterator.in_overlay then
        flib_queue.push_back(iterator.queue, target)
      end

      ::inner_continue::
    end

    for j = 1, #existing_connections do
      local connection = existing_connections[j]
      -- TODO: Deduplicate owner indexing?
      renderer.draw_connection(connection, entity, connection.target.owner, iterator.id, color, player_index)
    end

    ::continue::
  end

  renderer.draw_entity(entity, color, iterator.id, player_index)

  iterator.completed[entity.unit_number] = entity
end

--- @param iterator Iterator
--- @param entities_per_tick integer
local function iterate(iterator, entities_per_tick)
  for _ = 1, entities_per_tick do
    local entity = flib_queue.pop_front(iterator.queue)
    if not entity then
      return
    end
    iterate_entity(iterator, entity)
  end
end

--- @param iterator Iterator
local function clear(iterator)
  for _, entity in pairs(iterator.completed) do
    renderer.clear(entity, iterator.id, iterator.player_index)
  end
  local player_iterators = global.iterator[iterator.player_index]
  player_iterators[iterator.id] = nil
  if not next(player_iterators) then
    global.iterator[iterator.player_index] = nil
  end
end

--- @param player_index PlayerIndex
local function clear_all(player_index)
  if not global.iterator then
    return
  end
  local player_iterators = global.iterator[player_index]
  if not player_iterators then
    return
  end
  for _, iterator in pairs(player_iterators) do
    clear(iterator)
  end
end

--- @param starting_entity LuaEntity
--- @param player_index PlayerIndex
local function request_or_clear(starting_entity, player_index)
  if not global.iterator then
    return
  end
  local player_iterators = global.iterator[player_index]
  if not player_iterators then
    request(starting_entity, player_index, false)
    return
  end
  local did_clear = false
  for _, iterator in pairs(player_iterators) do
    if iterator.completed[starting_entity.unit_number] then
      did_clear = true
      clear(iterator)
    end
  end
  if not did_clear then
    request(starting_entity, player_index, false)
  end
end

local function on_tick()
  if not global.iterator then
    return
  end
  local entities_per_tick = game.is_multiplayer() and 5 or 1
  for _, iterators in pairs(global.iterator) do
    for _, iterator in pairs(iterators) do
      iterate(iterator, entities_per_tick)
    end
  end
end

--- @param e EventData.CustomInputEvent
local function on_toggle_hover(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end
  local entity = player.selected
  if not entity then
    clear_all(e.player_index)
    return
  end
  request_or_clear(entity, e.player_index)
end

local iterator = {}

function iterator.on_init()
  --- @type PlayerIterators
  global.iterator = {}
end

iterator.events = {
  [defines.events.on_tick] = on_tick,
  ["pv-visualize-selected"] = on_toggle_hover,
}

iterator.clear_all = clear_all
iterator.request = request

return iterator