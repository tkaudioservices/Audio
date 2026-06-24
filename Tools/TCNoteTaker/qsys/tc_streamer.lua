--[[
  tk Note Taker — QSys Core Timecode Streamer
  =============================================
  tk Audio Services

  Drop this script into a Text Controller component in your QSys design.

  Controls to add to the Text Controller:
    • TCin   (Text)  — wire from your timecode source (LTC decoder,
                       Media Player TC output, etc.)
    • Status (Text)  — read-only status display for the operator

  The script sends a sync packet every INTERVAL seconds, but ONLY when
  the TC has actually moved since the last send. If TC stops (show paused
  or stopped), packets stop and the web browser freezes its free-roll clock.

  The web browser free-rolls between packets so the display stays smooth.
  If packets stop arriving for more than ~4 s, the browser clock freezes.

  Packet format (one line per send):   HH:MM:SS:FF\n

  Adjust PORT and INTERVAL below to match your setup.
--]]

local PORT     = 1710   -- TCP port (match the web tool's Port field)
local INTERVAL = 2      -- seconds between sync packets

local clients    = {}
local lastSentTc = ""

-- ── helpers ──────────────────────────────────────────────────────────
local function clientCount() return #clients end

local function removeClient(sock)
  for i = #clients, 1, -1 do
    if clients[i] == sock then table.remove(clients, i); return end
  end
end

local function updateStatus()
  local n  = clientCount()
  local tc = Controls["TCin"].String
  Controls["Status"].String =
    n .. " client" .. (n == 1 and "" or "s") .. " connected" ..
    (tc ~= "" and (" · " .. tc) or "")
end

local function pushToAll(msg)
  for i = #clients, 1, -1 do
    local ok = pcall(clients[i].Write, clients[i], msg)
    if not ok then table.remove(clients, i) end
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
    removeClient(sock)
    updateStatus()
  end

  -- send the current TC immediately on connect so the browser doesn't
  -- wait up to INTERVAL seconds for the first sync
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
  print("[tk Note Taker] TCP listen failed on port " .. PORT .. ": " .. tostring(listenErr))
end

-- ── sync timer ───────────────────────────────────────────────────────
-- Fires every INTERVAL seconds. Sends the current TC only if it has
-- changed since the last send — so a paused/stopped show sends nothing
-- and the browser clock correctly freezes after its stale timeout.
local syncTimer = Timer.New()

syncTimer.EventHandler = function()
  if clientCount() == 0 then return end

  local tc = Controls["TCin"].String
  if tc == "" or tc == lastSentTc then return end

  lastSentTc = tc
  pushToAll(tc .. "\n")
  updateStatus()
end

syncTimer:Start(INTERVAL)
