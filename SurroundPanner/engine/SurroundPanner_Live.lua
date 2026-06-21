--[[
  SurroundPanner_Live.lua  --  tk Audio Services   (JSFX edition)  ·  v0.23.0
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
local BAKE   = IPC .. "/bake.json"
local AUTO   = IPC .. "/automation.json"
local RENAME = IPC .. "/rename.json"
local MATCH = "surroundpanner"   -- matches "JS: tk SurroundPanner", not "ReaSurroundPan"
local MB     = 1000              -- gmem meter base, matches the JSFX (gmem[MB+ch] = peak per output)
local MAXSPK = 16                -- matches the JSFX MAXOUT
local STRIDE = 9                 -- per-speaker gmem block: x, y, z, lfe, cw, cd, ca, type, beamwidth (matches the JSFX)

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
      elseif pp == 11 then slider = 7; sval = val           -- Effect type (0..4)      per object
      elseif pp == 12 then slider = 8; sval = val           -- FX rate (Hz)            per object
      elseif pp == 13 then slider = 9; sval = val           -- FX depth (0..1)         per object
      elseif pp == 14 then slider = 10; sval = val          -- FX axis (0..2)          per object
      elseif pp == 15 then slider = 11; sval = val          -- FX phase (0..1)         per object
      elseif pp == 16 then slider = 12; sval = val          -- Depth cue (0..1)        panner law (all objects)
      end
      if slider then setparam(inst.tr, inst.fx, slider, sval) end
    end
  end
end

-- bake the per-object effect (Orbit/Oscillate/Drift) into X/Y/Z FX-parameter envelopes, so an
-- offline render reads automation instead of running the live LFO (full-speed, not realtime).
-- bake.json = {"seq":N,"action":"bake"|"clear","items":[{t,x,y,z},...]} (x/y/z = base). Mirrors the JSFX math.
local lastBakeSeq = -1
local BAKE_DT = 1/50          -- envelope resolution (s); plenty for the slow movement effects
local BAKE_MAXPTS = 60000     -- safety cap on points per envelope

-- normalized 0..1 value for an FX slider's native value (FX-param envelopes are normalized)
local function normParam(tr, fx, slider, val)
  local _, mn, mx = reaper.TrackFX_GetParam(tr, fx, slider)
  if mn and mx and mx > mn then
    local nv = (val - mn) / (mx - mn)
    return nv < 0 and 0 or (nv > 1 and 1 or nv)
  end
  return val
end

-- write one track's effect motion to its X/Y/Z envelopes over the time selection (whole project
-- if none), then turn the live Effect off. Returns true if it baked anything.
local function bakeTrack(inst, bx, by, bz)
  local tr, fx = inst.tr, inst.fx
  local ft = math.floor(reaper.TrackFX_GetParam(tr, fx, 7) + 0.5)   -- Effect type
  if ft <= 0 or ft == 3 then return false end                      -- Off / Spread: nothing to bake to a position
  local rate  = reaper.TrackFX_GetParam(tr, fx, 8)
  local depth = reaper.TrackFX_GetParam(tr, fx, 9)
  local ax    = math.floor(reaper.TrackFX_GetParam(tr, fx, 10) + 0.5)
  local phase = reaper.TrackFX_GetParam(tr, fx, 11)                 -- per-object cycle offset
  -- bx/by/bz: the object's BASE position, sent by the UI (the X/Y/Z sliders hold the live, moving
  -- value while an effect runs, so we can't read the base off the plug-in)
  local t0, t1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if t1 <= t0 then t0 = 0; t1 = reaper.GetProjectLength(0) end
  if t1 <= t0 then return false end
  local dt = BAKE_DT
  local nsteps = math.floor((t1 - t0) / dt)
  if nsteps > BAKE_MAXPTS then dt = (t1 - t0) / BAKE_MAXPTS; nsteps = BAKE_MAXPTS end
  local envX = reaper.GetFXEnvelope(tr, fx, 0, true)
  local envY = reaper.GetFXEnvelope(tr, fx, 1, true)
  local envZ = reaper.GetFXEnvelope(tr, fx, 2, true)
  local scX, scY, scZ = reaper.GetEnvelopeScalingMode(envX), reaper.GetEnvelopeScalingMode(envY), reaper.GetEnvelopeScalingMode(envZ)
  reaper.DeleteEnvelopePointRange(envX, t0 - 1e-9, t1 + 1e-9)        -- overwrite any previous bake in range
  reaper.DeleteEnvelopePointRange(envY, t0 - 1e-9, t1 + 1e-9)
  reaper.DeleteEnvelopePointRange(envZ, t0 - 1e-9, t1 + 1e-9)
  -- deterministic smoothed random for Drift (character match; the live one is true-random)
  local seed = (math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) * 2654435761) % 2147483647 + 1
  local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
  local drx, dry, dtx, dty, nextDrift = 0, 0, 0, 0, 0
  local k = 0
  while k <= nsteps do
    local rt = k * dt                       -- phase time, relative to the range start
    local ph = 2 * math.pi * (rate * rt + phase)
    local ex, ey, ez = bx, by, bz
    if ft == 1 then                         -- Orbit
      ex = bx + depth * math.cos(ph); ey = by + depth * math.sin(ph)
    elseif ft == 2 then                     -- Oscillate
      local o = depth * math.sin(ph)
      if ax == 0 then ex = bx + o elseif ax == 1 then ey = by + o else ez = bz + o end
    elseif ft == 4 then                     -- Drift
      if rt >= nextDrift then nextDrift = rt + 0.5; dtx = (rnd() * 2 - 1) * depth; dty = (rnd() * 2 - 1) * depth end
      drx = drx + 0.08 * (dtx - drx); dry = dry + 0.08 * (dty - dry)
      ex = bx + drx; ey = by + dry
    end
    ex = ex < -1 and -1 or (ex > 1 and 1 or ex)
    ey = ey < -1 and -1 or (ey > 1 and 1 or ey)
    ez = ez < 0 and 0 or (ez > 1 and 1 or ez)
    local t = t0 + rt
    -- ScaleToEnvelopeMode keeps the value correct whether the FX envelope is linear or fader-scaled
    reaper.InsertEnvelopePoint(envX, t, reaper.ScaleToEnvelopeMode(scX, normParam(tr, fx, 0, ex)), 0, 0, false, true)
    reaper.InsertEnvelopePoint(envY, t, reaper.ScaleToEnvelopeMode(scY, normParam(tr, fx, 1, ey)), 0, 0, false, true)
    reaper.InsertEnvelopePoint(envZ, t, reaper.ScaleToEnvelopeMode(scZ, normParam(tr, fx, 2, ez)), 0, 0, false, true)
    k = k + 1
  end
  reaper.Envelope_SortPoints(envX); reaper.Envelope_SortPoints(envY); reaper.Envelope_SortPoints(envZ)
  setparam(tr, fx, 7, 0)                    -- live Effect -> Off, so it doesn't double the baked move
  return true
end

-- remove a baked move: clear the X/Y/Z envelope points in the time selection (or all, if none).
-- The UI re-enables the live effect afterwards.
local function clearBake(inst)
  local tr, fx = inst.tr, inst.fx
  local t0, t1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local lo, hi
  if t1 > t0 then lo, hi = t0, t1 else lo, hi = -1e6, reaper.GetProjectLength(0) + 1e6 end
  for p = 0, 2 do
    local env = reaper.GetFXEnvelope(tr, fx, p, false)
    if env then reaper.DeleteEnvelopePointRange(env, lo, hi); reaper.Envelope_SortPoints(env) end
  end
end

local function applyBake(insts)
  local s = readfile(BAKE); if not s then return end
  local seq = tonumber(s:match('"seq":(%-?%d+)')); if not seq or seq == lastBakeSeq then return end
  lastBakeSeq = seq
  local action = s:match('"action":"(%a+)"') or "bake"
  local items  = s:match('"items":%[(.*)%]') or ""
  reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)
  for blk in items:gmatch('{[^}]*}') do
    local t = tonumber(blk:match('"t":(%-?%d+)'))
    local inst = t and insts[t]
    if inst then
      if action == "clear" then
        clearBake(inst)
      else
        local bx = tonumber(blk:match('"x":(%-?[%d.]+)')) or 0
        local by = tonumber(blk:match('"y":(%-?[%d.]+)')) or 0
        local bz = tonumber(blk:match('"z":(%-?[%d.]+)')) or 0
        bakeTrack(inst, bx, by, bz)
      end
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(action == "clear" and "tkSurroundPanner: clear baked effect"
                                          or "tkSurroundPanner: bake effect to envelopes", -1)
  reaper.UpdateArrange()
end

-- trajectory recording: put each panner track into LATCH automation so dragging objects (which the
-- Live script writes to X/Y/Z) records straight to editable envelopes; 'stop' returns to read.
-- automation.json = {"seq":N,"mode":"rec"|"stop","tracks":[t,...]}
local lastAutoSeq = -1
local function envArm(env, on)
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok then return end
  if chunk:find("\nARM ") then chunk = chunk:gsub("\nARM %-?%d+", "\nARM " .. (on and 1 or 0))
  else chunk = chunk:gsub("(\nACT %-?%d+)", "%1\nARM " .. (on and 1 or 0), 1) end
  reaper.SetEnvelopeStateChunk(env, chunk, false)
end
local function recTrack(inst, on)
  local tr, fx = inst.tr, inst.fx
  for p = 0, 2 do                                    -- X/Y/Z FX-param envelopes
    local env = reaper.GetFXEnvelope(tr, fx, p, true)
    if env then envArm(env, on) end
  end
  reaper.SetTrackAutomationMode(tr, on and 4 or 1)   -- 4 = latch (record touched), 1 = read (play back)
end
local function applyAutomation(insts)
  local s = readfile(AUTO); if not s then return end
  local seq = tonumber(s:match('"seq":(%-?%d+)')); if not seq or seq == lastAutoSeq then return end
  lastAutoSeq = seq
  local mode  = s:match('"mode":"(%a+)"') or "stop"
  local tlist = s:match('"tracks":%[([%d,%s]*)%]') or ""
  reaper.PreventUIRefresh(1)
  for n in tlist:gmatch('(%d+)') do
    local inst = insts[tonumber(n)]
    if inst then recTrack(inst, mode == "rec") end
  end
  reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
end

-- set REAPER track names from the UI -----------------------------
-- rename.json = {"seq":N,"items":[{"t":T,"name":"..."}]}  (JSON-escaped by the bridge)
local lastRenameSeq = -1
local function applyRename(insts)
  local s = readfile(RENAME); if not s then return end
  local seq = tonumber(s:match('"seq":(%-?%d+)')); if not seq or seq == lastRenameSeq then return end
  lastRenameSeq = seq
  for t, name in s:gmatch('"t":(%d+),"name":"(.-)"') do   -- names rarely contain quotes; unescape \\ and \"
    local inst = insts[tonumber(t)]
    if inst then
      local nm = name:gsub('\\"', '"'):gsub('\\\\', '\\')
      reaper.GetSetMediaTrackInfo_String(inst.tr, "P_NAME", nm, true)
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
        '{%s:%s,%s:%s,%s:%s,%s:%.4f,%s:%.4f,%s:%.4f,%s:{%s:%d,%s:%d,%s:4,%s:5,%s:6,%s:7,%s:10,%s:11,%s:12,%s:13,%s:14,%s:15}}',
        jstr("name"), jstr(track_name(tr)), jstr("color"), jstr(track_color(tr)), jstr("group"), jstr(group),
        jstr("x"), x, jstr("y"), y, jstr("z"), z,
        jstr("osc"), jstr("track"), oscT, jstr("fx"), fx + 1, jstr("px"), jstr("py"), jstr("pz"), jstr("pg"), jstr("pl"),
        jstr("pe"), jstr("pr"), jstr("pd"), jstr("pa"), jstr("pph"))
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
  -- parse each speaker object on its own so field order / new keys (coverage) don't shift anything
  for blk in s:gmatch("{[^}]*}") do
    local x = tonumber(blk:match('"x":%s*(%-?[%d.]+)'))
    local y = tonumber(blk:match('"y":%s*(%-?[%d.]+)'))
    local z = tonumber(blk:match('"z":%s*(%-?[%d.]+)'))
    if x and y and z and i < MAXSPK then               -- skip the wrapper / cap at the JSFX output max
      local lf = tonumber(blk:match('"lfe":%s*(%d)')) or 0
      local cw = tonumber(blk:match('"cw":%s*([%d.]+)')) or 0   -- coverage ellipse (absent => off)
      local cd = tonumber(blk:match('"cd":%s*([%d.]+)')) or 0
      local ca = tonumber(blk:match('"ca":%s*(%-?[%d.]+)')) or 0
      local ty = tonumber(blk:match('"ty":%s*(%d)')) or 0      -- mount type: 0 ceiling, 1 wall, 2 sub
      local bw = tonumber(blk:match('"bw":%s*([%d.]+)')) or 90 -- wall wedge beam width (degrees)
      local b = 1 + i*STRIDE
      reaper.gmem_write(b + 0, x);  reaper.gmem_write(b + 1, y);  reaper.gmem_write(b + 2, z)
      reaper.gmem_write(b + 3, lf); reaper.gmem_write(b + 4, cw); reaper.gmem_write(b + 5, cd)
      reaper.gmem_write(b + 6, ca); reaper.gmem_write(b + 7, ty); reaper.gmem_write(b + 8, bw)
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
    applyBake(insts)
    applyAutomation(insts)
    applyRename(insts)
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
