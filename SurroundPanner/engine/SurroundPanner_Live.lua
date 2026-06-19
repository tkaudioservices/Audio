--[[
  SurroundPanner_Live.lua  --  tk Audio Services   (JSFX edition)  ·  v0.8.0
  ==================================================================
  Live link between REAPER and the tkSurroundPanner web UI, now driving our
  own  tk SurroundPanner  JSFX instead of ReaSurroundPan.

  Why: ReaSurroundPan ignores parameter writes from outside until its puck is
  touched by hand. Our JSFX has normal sliders that accept TrackFX_SetParam
  instantly, so control is reliable on every track.

  Run this once (Actions -> Load ReaScript) and leave it running. It:
    • finds every track with the "tk SurroundPanner" JSFX,
    • sets each one's X / Y / Z / Gain sliders from the web UI,
    • publishes session.json (objects, colours, folder groups, live positions).

  Setup: copy  tk_SurroundPanner.jsfx  into REAPER's  Effects  folder
  (Options -> Show REAPER resource path -> Effects), then add
  "JS: tk SurroundPanner" to each object track (in place of ReaSurroundPan).

  Run the action again to stop. No OSC, no Import/Export.
--]]

local NS    = "tkSurroundPanner"
local _, SELF, SEC, CMD = reaper.get_action_context()
local IPC   = reaper.GetResourcePath() .. "/tkSurroundPanner"   -- shared with the bridge, wherever this script lives
reaper.RecursiveCreateDirectory(IPC, 0)
local CMDS   = IPC .. "/cmds.json"
local SESS   = IPC .. "/session.json"
local ROOM   = IPC .. "/room.json"
local LEVELS = IPC .. "/levels.json"
local MATCH = "surroundpanner"   -- matches "JS: tk SurroundPanner", not "ReaSurroundPan"
local MB    = 100                -- gmem meter base, matches the JSFX (gmem[MB+ch] = peak per output)
local MAXSPK = 16                -- matches the JSFX MAXOUT; keeps the layout (gmem[1+i*4..]) clear of MB

local function setstate(on)
  reaper.SetExtState(NS, "live", on and "1" or "0", false)
  reaper.SetToggleCommandState(SEC, CMD, on and 1 or 0); reaper.RefreshToolbar2(SEC, CMD)
end

-- toggle on/off (no console window) -------------------------------
if reaper.GetExtState(NS, "live") == "1" then setstate(false); return end
setstate(true)
reaper.gmem_attach("tkSurroundPanner")   -- shared speaker layout for the JSFX

-- helpers ---------------------------------------------------------
local function jstr(s) return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end
local function readfile(p) local f = io.open(p, "r"); if not f then return nil end local s = f:read("*a"); f:close(); return s end
local function writefile_atomic(p, s)
  local t = p .. ".tmp"; local f = io.open(t, "w"); if not f then return end
  f:write(s); f:close(); os.rename(t, p)
end
local function track_name(tr)
  local _, n = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  if not n or n == "" then n = "Track " .. math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) end
  return n
end
local function track_color(tr)
  local c = reaper.GetTrackColor(tr); if c == 0 then return "" end
  local r, g, b = reaper.ColorFromNative(c); return string.format("#%02x%02x%02x", r, g, b)
end
local function find_fx(tr)
  local n = reaper.TrackFX_GetCount(tr)
  for i = 0, n - 1 do
    local _, nm = reaper.TrackFX_GetFXName(tr, i, "")
    if nm:lower():find(MATCH) then return i end
  end
  return -1
end

-- map: OSC track number (1-based) -> { tr, fx }  for every instance of our JSFX
local function instances()
  local list = {}
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    local fx = find_fx(tr)
    if fx >= 0 then
      list[math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))] = { tr = tr, fx = fx }
    end
  end
  return list
end

-- Set a JSFX slider by its NATIVE value, but go through the *normalized* API so it lands
-- reliably. reaper.TrackFX_SetParam's interpretation of out-of-0..1 values is the classic
-- "the parameter doesn't move" gotcha (e.g. Rolloff 0.5..4); SetParamNormalized is
-- unambiguous. We read the live min/max from the plug-in, so it tracks the JSFX ranges.
local function setparam(tr, fx, slider, nativeval)
  local _, mn, mx = reaper.TrackFX_GetParam(tr, fx, slider)
  if mn and mx and mx > mn then
    local nv = (nativeval - mn) / (mx - mn)
    nv = nv < 0 and 0 or (nv > 1 and 1 or nv)
    reaper.TrackFX_SetParamNormalized(tr, fx, slider, nv)
  else
    reaper.TrackFX_SetParam(tr, fx, slider, nativeval)
  end
end

-- apply web-UI commands to the JSFX sliders -----------------------
-- cmds.json = {"seq":N,"params":[{"t":T,"f":F,"p":P,"v":V}, ...]}
-- P is the UI's axis tag; the JSFX slider index is 0-based (slider1 = 0).
local lastSeq = -1
local function applyCmds(insts)
  local s = readfile(CMDS); if not s then return end
  local seq = tonumber(s:match('"seq":(%-?%d+)')); if not seq or seq == lastSeq then return end
  lastSeq = seq
  for t, f, p, v in s:gmatch('"t":(%-?%d+),"f":(%-?%d+),"p":(%-?%d+),"v":(%-?%d*%.?%d+)') do
    local inst = insts[tonumber(t)]
    if inst then
      local pp, val = tonumber(p), tonumber(v)
      local slider, sval
      if     pp == 4  then slider = 0; sval = 1 - 2 * val   -- X: UI sends (1-x)/2
      elseif pp == 5  then slider = 1; sval = 2 * val - 1   -- Y: UI sends (y+1)/2
      elseif pp == 6  then slider = 2; sval = val           -- Z: 0..1
      elseif pp == 7  then slider = 3; sval = val           -- Gain   (0..1)        per object
      elseif pp == 8  then slider = 4; sval = val           -- Rolloff/Focus (0.5..4)  panner law (all objects)
      elseif pp == 9  then slider = 5; sval = val           -- Spread (0.01..0.6)      panner law (all objects)
      elseif pp == 10 then slider = 6; sval = val           -- LFE send (0..1)         per object
      end
      if slider then setparam(inst.tr, inst.fx, slider, sval) end
    end
  end
end

-- publish session.json (positions read straight from the sliders) -
local function buildSession()
  local objs, tracks, stack = {}, {}, {}
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    local depth = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    local group = stack[#stack] or ""
    local fx = find_fx(tr)
    if fx >= 0 then
      local oscT = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
      local x = reaper.TrackFX_GetParam(tr, fx, 0)
      local y = reaper.TrackFX_GetParam(tr, fx, 1)
      local z = reaper.TrackFX_GetParam(tr, fx, 2)
      local nch = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN"))
      objs[#objs + 1] = string.format(
        '{%s:%s,%s:%s,%s:%s,%s:%.4f,%s:%.4f,%s:%.4f,%s:{%s:%d,%s:%d,%s:4,%s:5,%s:6,%s:7,%s:10}}',
        jstr("name"), jstr(track_name(tr)), jstr("color"), jstr(track_color(tr)), jstr("group"), jstr(group),
        jstr("x"), x, jstr("y"), y, jstr("z"), z,
        jstr("osc"), jstr("track"), oscT, jstr("fx"), fx + 1, jstr("px"), jstr("py"), jstr("pz"), jstr("pg"), jstr("pl"))
      tracks[#tracks + 1] = string.format('{%s:%d,%s:%s,%s:%d}',
        jstr("track"), oscT, jstr("name"), jstr(track_name(tr)), jstr("nch"), nch)
    end
    if depth >= 1 then stack[#stack + 1] = track_name(tr)
    elseif depth < 0 then for _ = 1, math.floor(-depth) do stack[#stack] = nil end end
  end
  return '{"project":"Live from REAPER","live":true,"objects":[' .. table.concat(objs, ",") ..
         '],"tracks":[' .. table.concat(tracks, ",") .. "]}"
end

-- write the web-UI room (room.json) into shared memory for the JSFX
local lastRoom, roomCount = nil, 12   -- speaker count (default 7.1.4 = 12)
local function loadRoom()
  local s = readfile(ROOM); if not s or s == lastRoom then return end
  lastRoom = s
  local i = 0
  for x, y, z, lf in s:gmatch('"x":%s*(%-?[%d.]+)%s*,%s*"y":%s*(%-?[%d.]+)%s*,%s*"z":%s*(%-?[%d.]+)%s*,%s*"lfe":%s*(%d)') do
    if i < MAXSPK then                                 -- never write past the JSFX's output cap into the meter region
      reaper.gmem_write(1 + i*4 + 0, tonumber(x))
      reaper.gmem_write(1 + i*4 + 1, tonumber(y))
      reaper.gmem_write(1 + i*4 + 2, tonumber(z))
      reaper.gmem_write(1 + i*4 + 3, tonumber(lf))
      i = i + 1
    end
  end
  reaper.gmem_write(0, i)   -- count written last so the JSFX never sees a partial layout
  roomCount = i
end

-- give each panner track (and its folder/bus) at least as many channels as there are speakers
local function setChannels(insts)
  local n = roomCount; if n < 2 then n = 2 end
  if n % 2 == 1 then n = n + 1 end                 -- REAPER track channel counts are even
  local parents = {}
  for _, inst in pairs(insts) do
    if reaper.GetMediaTrackInfo_Value(inst.tr, "I_NCHAN") < n then
      reaper.SetMediaTrackInfo_Value(inst.tr, "I_NCHAN", n)
    end
    local par = reaper.GetParentTrack(inst.tr); if par then parents[par] = true end
  end
  for par in pairs(parents) do
    if reaper.GetMediaTrackInfo_Value(par, "I_NCHAN") < n then
      reaper.SetMediaTrackInfo_Value(par, "I_NCHAN", n)
    end
  end
end

-- live output meters: peak per output channel, read straight from the panner via shared memory.
-- Decoupled from bus routing, so the web meters match the in-plugin display exactly. Each JSFX
-- instance maxes its peak into gmem[MB+ch]; we read then clear so each interval shows a fresh peak.
local function writeLevels()
  local n = roomCount; if n < 1 then n = 2 end
  local t = {}
  for c = 0, n - 1 do
    t[#t + 1] = string.format("%.4f", reaper.gmem_read(MB + c))
    reaper.gmem_write(MB + c, 0)
  end
  writefile_atomic(LEVELS, '{"levels":[' .. table.concat(t, ",") .. ']}')
end

-- main loop -------------------------------------------------------
local lastWrite, lastLevels = 0, 0
writefile_atomic(SESS, buildSession())

local function loop()
  if reaper.GetExtState(NS, "live") ~= "1" then return end
  local ok, err = pcall(function()
    local insts = instances()
    applyCmds(insts)
    loadRoom()
    local now = reaper.time_precise()
    if now - lastLevels > 0.08 then lastLevels = now; writeLevels() end   -- ~12 Hz meters
    if now - lastWrite > 0.5 then lastWrite = now; setChannels(insts); writefile_atomic(SESS, buildSession()) end
  end)
  if not ok then local lf = io.open(IPC .. "/live_error.log", "w"); if lf then lf:write(tostring(err)); lf:close() end end
  reaper.defer(loop)
end

reaper.atexit(function() setstate(false) end)
loop()   -- runs quietly; run the action again to stop (toolbar button reflects on/off state)
