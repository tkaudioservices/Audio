--[[
  tk TC Note Taker — QSys Core Timecode Streamer
  ================================================
  tk Audio Services

  Drop this script into a Text Controller component in your QSys design.

  Controls to add to the Text Controller:
    • TCin   (Text)  — wire from your timecode source (LTC decoder,
                       Media Player TC output, etc.)
    • Status (Text)  — read-only status display for the operator

  The script opens a TCP server on PORT. The tk TC Note Taker web page
  connects to  <Core IP>:<PORT>  (Timecode mode, Host/Port fields)
  and receives the current timecode as a newline-delimited stream:

      HH:MM:SS:FF\n

  To feed TCin:
    • LTC input: wire the LTC Decoder component's "TC String" output → TCin
    • Media Player: wire the player's "Position" string output → TCin
    • Custom script: set Controls["TCin"].String = "01:00:00:00" from
      another script component

  Adjust PORT and RATE below to match your show.
--]]

local PORT = 1710    -- TCP port (match the web tool's Port field)
local RATE = 1/25    -- broadcast interval in seconds — set to 1/fps
                     -- e.g. 1/25 = 25fps,  1/30 = 30fps,  1/50 = 50fps


-- ── connected clients ────────────────────────────────────────────────
local clients = {}

local function clientCount()
  return #clients
end

local function removeClient(sock)
  for i = #clients, 1, -1 do
    if clients[i] == sock then
      table.remove(clients, i)
      return
    end
  end
end

local function updateStatus()
  local n    = clientCount()
  local tc   = Controls["TCin"].String
  local conn = n .. " client" .. (n == 1 and "" or "s") .. " connected"
  Controls["Status"].String = conn .. (tc ~= "" and (" · " .. tc) or "")
end

local function pushToAll(msg)
  for i = #clients, 1, -1 do
    local ok = pcall(clients[i].Write, clients[i], msg)
    if not ok then
      table.remove(clients, i)
    end
  end
end


-- ── TCP server ───────────────────────────────────────────────────────
local server = TcpSocketServer.New()

server.ConnectionHandler = function(sock)
  table.insert(clients, sock)

  sock.DataHandler = function(sock, data)
    -- web client may send keep-alive bytes; nothing to do
  end

  sock.EventHandler = function(sock, event, err)
    -- any event (Disconnected, Error, Timeout) → clean up
    removeClient(sock)
    updateStatus()
  end

  -- send the current TC immediately on connect
  local tc = Controls["TCin"].String
  if tc ~= "" then
    pcall(sock.Write, sock, tc .. "\n")
  end

  updateStatus()
end

local listenOk, listenErr = pcall(function() server:Listen(PORT) end)

if listenOk then
  Controls["Status"].String = "Listening on :" .. PORT
else
  Controls["Status"].String = "LISTEN ERROR: " .. tostring(listenErr)
  print("[tk TC] TCP listen failed on port " .. PORT .. ": " .. tostring(listenErr))
end


-- ── broadcast timer ──────────────────────────────────────────────────
-- Pushes the current TC to every connected client at RATE Hz.
local broadcastTimer = Timer.New()

broadcastTimer.EventHandler = function()
  if clientCount() == 0 then return end

  local tc = Controls["TCin"].String
  if tc == "" then return end

  pushToAll(tc .. "\n")
end

broadcastTimer:Start(RATE)


-- ── TCin change event ────────────────────────────────────────────────
-- Also push immediately whenever the source updates TCin, so clients
-- get the change without waiting for the next broadcast tick.
Controls["TCin"].EventHandler = function(ctrl)
  updateStatus()
  if clientCount() == 0 or ctrl.String == "" then return end
  pushToAll(ctrl.String .. "\n")
end
