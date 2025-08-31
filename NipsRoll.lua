--[[
Nips Roll (NRG) - 3.3.5a
Author: Spin + Alyx

Features:
- Host sets bet, channel (SAY/PARTY/RAID/BATTLEGROUND), and mode (Hi/Lo or Death Roll 1v1)
- "New Game" announces: "NIPS ROLL GAME STARTED, PRESS 1 TO JOIN"
- Players join by sending '1' in the chosen channel (the addon listens and updates live)
- "Last Call" broadcast
- "Start Rolling!" then listens for /roll results and determines winners
- Hi/Lo: everyone rolls 1-100 (default). Highest ~= closest to 100. Lowest pays Highest the bet. Host pays only if Host is lowest.
- Death Roll (1v1): starts at a max (default 1000). Players alternate /roll 1-lastRoll; whoever rolls 1 loses and pays the winner.
- Simple UI + /nrg to toggle; persistent small stats DB

Notes:
- Roll parsing uses the global format "%s rolls %d (%d-%d)" for enUS. Pattern is compatible with 3.3.5a clients.
- Addon works even if only the host has it; everyone else just uses chat + /roll.

ToS/Common sense:
- Gold wagers are between players; this addon only announces and tracks rolls.
- Use responsibly; obey your server’s rules.

]]--

local ADDON, NRG = ...
NRG = {}
NipsRollDB = NipsRollDB or {}

-- ------------------------------------------------------------
-- State
-- ------------------------------------------------------------
local state = {
  phase = "IDLE",         -- IDLE | JOINING | ROLLING | DEATHROLL
  mode  = "HILO",         -- HILO | DEATH
  channel = "SAY",        -- SAY | PARTY | RAID | BATTLEGROUND
  betGold = 10,           -- integer gold
  rollMin = 1,            -- for Hi/Lo
  rollMax = 100,          -- for Hi/Lo (closest-to-100 == highest by default)
  host    = UnitName("player"),
  joiners = {},           -- [player] = {joined=true, roll=nil}
  ordered = {},           -- array of player names (for UI order)
  startedAt = 0,
  -- Death Roll
  dr = {
    p1 = nil, p2 = nil,
    turn = 1,             -- 1 or 2
    max = 1000,           -- starting cap for death roll
    currentMax = 1000,
    active = false,
  }
}

local function resetGame()
  state.phase = "IDLE"
  state.joiners = {}
  state.ordered = {}
  state.dr = { p1=nil, p2=nil, turn=1, max=1000, currentMax=1000, active=false }
  updateRosterText()
end

-- ------------------------------------------------------------
-- Utilities
-- ------------------------------------------------------------
local function trimRealm(name)
  if not name then return name end
  local base = name:match("([^%-]+)")
  return base or name
end

local function system(msg) DEFAULT_CHAT_FRAME:AddMessage("|cFF66C7FF[NRG]|r "..msg) end

local function canUseChannel(chan)
  if chan == "SAY" then return true
  elseif chan == "PARTY" then return (GetNumPartyMembers() > 0) or (GetNumRaidMembers() > 0)
  elseif chan == "RAID" then return GetNumRaidMembers() > 0
  elseif chan == "BATTLEGROUND" then return true -- client will noop outside BG
  end
  return false
end

local function send(chan, msg)
  if not canUseChannel(chan) then
    system("Selected channel not available (now). Message shown locally only:\n"..msg)
    return
  end
  if chan == "SAY" or chan == "YELL" then
    SendChatMessage(msg, chan)
  elseif chan == "PARTY" or chan == "RAID" or chan == "BATTLEGROUND" or chan == "GUILD" or chan == "RAID_WARNING" then
    SendChatMessage(msg, chan)
  else
    -- fallback
    SendChatMessage(msg, "SAY")
  end
end

local function announce(msg) send(state.channel, msg) end

-- ------------------------------------------------------------
-- Roster
-- ------------------------------------------------------------
local function inRoster(name) return state.joiners[name] ~= nil end

local function addJoiner(name)
  name = trimRealm(name)
  if not name or name == "" then return end
  if not state.joiners[name] then
    state.joiners[name] = { joined=true, roll=nil }
    table.insert(state.ordered, name)
    updateRosterText()
  end
end

local function setRoll(name, val)
  name = trimRealm(name)
  if state.joiners[name] then
    state.joiners[name].roll = val
    updateRosterText()
  end
end

local function everyoneRolled()
  if #state.ordered == 0 then return false end
  for _,n in ipairs(state.ordered) do
    if not state.joiners[n].roll then return false end
  end
  return true
end

-- ------------------------------------------------------------
-- UI
-- ------------------------------------------------------------
local ui = {}

local function label(parent, text, size)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetText(text or "")
  if size then fs:SetFont(fs:GetFont(), size) end
  return fs
end

local function makeButton(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function makeCheck(parent, text, onClick)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c.text = _G[c:GetName().."Text"] or c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c.text:SetPoint("LEFT", c, "RIGHT", 2, 0)
  c.text:SetText(text)
  c:SetScript("OnClick", function(self) PlaySound("igMainMenuOptionCheckBoxOn"); if onClick then onClick(self) end end)
  return c
end

local function makeEdit(parent, w, h, numeric)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, h)
  e:SetAutoFocus(false)
  e:SetTextInsets(6,6,2,2)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  if numeric then
    e:SetNumeric(true)
  end
  return e
end

local function updateModeUI()
  if state.mode == "HILO" then
    ui.rollMin:Enable(); ui.rollMax:Enable()
    ui.drMax:Disable()
    ui.p1Edit:Disable(); ui.p2Edit:Disable()
  else
    ui.rollMin:Disable(); ui.rollMax:Disable()
    ui.drMax:Enable()
    ui.p1Edit:Enable(); ui.p2Edit:Enable()
  end
end

function updateRosterText()
  if not ui.roster then return end
  local lines = {}
  if state.mode == "HILO" then
    table.insert(lines, string.format("|cFFFFFF55Mode:|r Hi/Lo  |  Range: %d-%d  |  Bet: %dg  |  Channel: %s",
      state.rollMin, state.rollMax, state.betGold, state.channel))
    table.insert(lines, "|cFFAAAAAAPlayers (name - roll)|r")
    if #state.ordered == 0 then
      table.insert(lines, "  (none yet)")
    else
      for _,n in ipairs(state.ordered) do
        local r = state.joiners[n].roll
        table.insert(lines, string.format("  %s%s", n, r and (" - "..r) or ""))
      end
    end
  else
    table.insert(lines, string.format("|cFFFFFF55Mode:|r Death Roll  |  Start Max: %d  |  Bet: %dg  |  Channel: %s",
      state.dr.max, state.betGold, state.channel))
    table.insert(lines, string.format("|cFFAAAAAAPlayers:|r %s vs %s   | Current Max: %d | Turn: %s",
      state.dr.p1 or "(p1?)", state.dr.p2 or "(p2?)", state.dr.currentMax,
      (state.dr.turn == 1) and (state.dr.p1 or "?") or (state.dr.p2 or "?")))
  end
  ui.roster:SetText(table.concat(lines, "\n"))
end

local function buildUI()
  if ui.frame then return end

  local f = CreateFrame("Frame", "NipsRollFrame", UIParent)
  ui.frame = f
  f:SetSize(450, 360)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({
    bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
    tile=true, tileSize=32, edgeSize=32,
    insets={left=8, right=8, top=8, bottom=8}
  })
  f:Hide()

  ui.title = label(f, "NIPS ROLL (NRG) - Host Panel", 14)
  ui.title:SetPoint("TOP", 0, -12)

  -- Channel
  ui.chanLbl = label(f, "Channel:", 12); ui.chanLbl:SetPoint("TOPLEFT", 18, -40)
  local ch = {"SAY","PARTY","RAID","BATTLEGROUND"}
  ui.chanChecks = {}
  local last
  for i,c in ipairs(ch) do
    local ck = makeCheck(f, c, function(self)
      for _,o in ipairs(ui.chanChecks) do o:SetChecked(false) end
      self:SetChecked(true)
      state.channel = c
      updateRosterText()
    end)
    table.insert(ui.chanChecks, ck)
    if not last then ck:SetPoint("LEFT", ui.chanLbl, "RIGHT", 10, 0)
    else ck:SetPoint("LEFT", last.text, "RIGHT", 20, 0) end
    last = ck
  end
  ui.chanChecks[1]:SetChecked(true)

  -- Mode
  ui.modeLbl = label(f, "Mode:", 12); ui.modeLbl:SetPoint("TOPLEFT", 18, -70)
  ui.hilo = makeCheck(f, "Hi/Lo", function(self)
    ui.hilo:SetChecked(true); ui.death:SetChecked(false)
    state.mode = "HILO"; updateModeUI(); updateRosterText()
  end)
  ui.hilo:SetPoint("LEFT", ui.modeLbl, "RIGHT", 10, 0)
  ui.hilo:SetChecked(true)

  ui.death = makeCheck(f, "Death Roll (1v1)", function(self)
    ui.hilo:SetChecked(false); ui.death:SetChecked(true)
    state.mode = "DEATH"; updateModeUI(); updateRosterText()
  end)
  ui.death:SetPoint("LEFT", ui.hilo.text, "RIGHT", 20, 0)

  -- Bet
  ui.betLbl = label(f, "Bet (gold):", 12); ui.betLbl:SetPoint("TOPLEFT", 18, -100)
  ui.betEdit = makeEdit(f, 60, 20, true); ui.betEdit:SetPoint("LEFT", ui.betLbl, "RIGHT", 10, 0)
  ui.betEdit:SetText(tostring(state.betGold))
  ui.betEdit:SetScript("OnTextChanged", function(self)
    local v = tonumber(self:GetText()) or state.betGold
    state.betGold = math.max(0, math.floor(v))
    updateRosterText()
  end)

  -- Hi/Lo range
  ui.rollLbl = label(f, "Roll Range:", 12); ui.rollLbl:SetPoint("TOPLEFT", 18, -130)
  ui.rollMin = makeEdit(f, 50, 20, true); ui.rollMin:SetPoint("LEFT", ui.rollLbl, "RIGHT", 10, 0)
  ui.rollMin:SetText(tostring(state.rollMin))
  ui.rollMin:SetScript("OnTextChanged", function(self)
    local v = tonumber(self:GetText()) or state.rollMin
    state.rollMin = math.max(1, math.floor(v))
    updateRosterText()
  end)

  ui.dash = label(f, " - "); ui.dash:SetPoint("LEFT", ui.rollMin, "RIGHT", 5, 0)

  ui.rollMax = makeEdit(f, 50, 20, true); ui.rollMax:SetPoint("LEFT", ui.dash, "RIGHT", 5, 0)
  ui.rollMax:SetText(tostring(state.rollMax))
  ui.rollMax:SetScript("OnTextChanged", function(self)
    local v = tonumber(self:GetText()) or state.rollMax
    state.rollMax = math.max(state.rollMin, math.floor(v))
    updateRosterText()
  end)

  -- Death Roll start max + players
  ui.drLbl = label(f, "Death Roll Start Max:", 12); ui.drLbl:SetPoint("TOPLEFT", 18, -160)
  ui.drMax = makeEdit(f, 80, 20, true); ui.drMax:SetPoint("LEFT", ui.drLbl, "RIGHT", 10, 0)
  ui.drMax:SetText("1000")
  ui.drMax:SetScript("OnTextChanged", function(self)
    local v = tonumber(self:GetText()) or 1000
    v = math.max(2, math.floor(v))
    state.dr.max = v
    if state.phase ~= "DEATHROLL" then state.dr.currentMax = v end
    updateRosterText()
  end)

  ui.p1Lbl = label(f, "P1:", 12); ui.p1Lbl:SetPoint("TOPLEFT", 18, -190)
  ui.p1Edit = makeEdit(f, 120, 20, false); ui.p1Edit:SetPoint("LEFT", ui.p1Lbl, "RIGHT", 10, 0)
  ui.p1Edit:SetScript("OnTextChanged", function(self)
    local v = trimRealm(self:GetText()); if v=="" then v=nil end
    state.dr.p1 = v; updateRosterText()
  end)

  ui.p2Lbl = label(f, "P2:", 12); ui.p2Lbl:SetPoint("LEFT", ui.p1Edit, "RIGHT", 20, 0)
  ui.p2Edit = makeEdit(f, 120, 20, false); ui.p2Edit:SetPoint("LEFT", ui.p2Lbl, "RIGHT", 10, 0)
  ui.p2Edit:SetScript("OnTextChanged", function(self)
    local v = trimRealm(self:GetText()); if v=="" then v=nil end
    state.dr.p2 = v; updateRosterText()
  end)

  -- Buttons
  ui.newBtn = makeButton(f, "New Game", 100, 22, function()
    resetGame()
    state.phase = (state.mode=="HILO") and "JOINING" or "DEATHROLL" -- for Death we immediately set up players
    if state.mode == "HILO" then
      announce(string.format("NIPS ROLL GAME STARTED, PRESS 1 TO JOIN (%d-%d) - Bet %dg",
        state.rollMin, state.rollMax, state.betGold))
      announce("Type 1 in "..state.channel.." to join!")
    else
      state.dr.currentMax = state.dr.max
      announce(string.format("NIPS DEATH ROLL STARTED! 1v1. Host set start max to %d. Set P1/P2 and press Start.", state.dr.max))
    end
    updateRosterText()
  end))
  ui.newBtn:SetPoint("TOPLEFT", 18, -220)

  ui.lastBtn = makeButton(f, "Last Call", 100, 22, function()
    if state.phase ~= "JOINING" then system("You can only Last Call while JOINING.") return end
    announce("LAST CALL to join! Type 1 now!")
  end)
  ui.lastBtn:SetPoint("LEFT", ui.newBtn, "RIGHT", 10, 0)

  ui.joinSelf = makeButton(f, "Join (You)", 100, 22, function()
    if state.mode ~= "HILO" then system("Join is only for Hi/Lo joining.") return end
    if state.phase ~= "JOINING" then system("You can only join while JOINING.") return end
    addJoiner(state.host)
  end)
  ui.joinSelf:SetPoint("LEFT", ui.lastBtn, "RIGHT", 10, 0)

  ui.startBtn = makeButton(f, "Start Rolling!", 120, 24, function()
    if state.mode == "HILO" then
      if state.phase ~= "JOINING" then system("You must be in JOINING to start.") return end
      if #state.ordered < 2 then system("Need at least 2 players.") return end
      state.phase = "ROLLING"
      announce(string.format("ROLL NOW! Use /roll %d-%d", state.rollMin, state.rollMax))
      announce("Lowest pays Highest the bet. Good luck!")
    else
      -- Death Roll
      if not state.dr.p1 or not state.dr.p2 or state.dr.p1 == state.dr.p2 then
        system("Set P1 and P2 (distinct names) for Death Roll.")
        return
      end
      state.phase = "DEATHROLL"
      state.dr.currentMax = state.dr.max
      state.dr.turn = 1
      state.dr.active = true
      announce(string.format("DEATH ROLL: %s vs %s. Start at %d. %s rolls first: /roll 1-%d",
        state.dr.p1, state.dr.p2, state.dr.max, state.dr.p1, state.dr.currentMax))
    end
    updateRosterText()
  end)
  ui.startBtn:SetPoint("TOPLEFT", ui.newBtn, "BOTTOMLEFT", 0, -10)

  ui.cancelBtn = makeButton(f, "Cancel/Reset", 120, 24, function()
    announce("Game cancelled by host.")
    resetGame()
  end)
  ui.cancelBtn:SetPoint("LEFT", ui.startBtn, "RIGHT", 10, 0)

  -- Roster box
  local box = CreateFrame("Frame", nil, f)
  ui.box = box
  box:SetPoint("TOPLEFT", 18, -260)
  box:SetSize(414, 80)
  box:SetBackdrop({
    bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
    tile=true, tileSize=16, edgeSize=16,
    insets={left=4,right=4,top=4,bottom=4}
  })
  box:SetBackdropColor(0,0,0,0.8)

  ui.roster = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.roster:SetPoint("TOPLEFT", 6, -6)
  ui.roster:SetJustifyH("LEFT")
  ui.roster:SetJustifyV("TOP")
  ui.roster:SetWidth(402)
  ui.roster:SetText("")

  -- Footer
  ui.hint = label(f, "|cFFAAAAAA/nrg to show/hide|r", 11)
  ui.hint:SetPoint("BOTTOMRIGHT", -12, 10)

  updateModeUI()
  updateRosterText()
end

-- ------------------------------------------------------------
-- Events (Chat + System Roll parsing)
-- ------------------------------------------------------------
local frame = CreateFrame("Frame")
local events = {}

local ROLL_PATTERN = "^(.+) rolls (%d+) %((%d+)%-(%d+)%)$"

local function parseRoll(line)
  -- returns name, roll, min, max or nil
  local pName, pRoll, pMin, pMax = string.match(line, ROLL_PATTERN)
  if not pName then
    -- Try a fallback tolerant pattern
    pName, pRoll, pMin, pMax = string.match(line, "^(.+)%srolls%s(%d+)%s%((%d+)%-(%d+)%)$")
  end
  if pName and pRoll and pMin and pMax then
    return trimRealm(pName), tonumber(pRoll), tonumber(pMin), tonumber(pMax)
  end
end

local function announceHiLoResult()
  -- Determine highest and lowest among joiners who rolled
  if #state.ordered < 2 then return end
  local highN, highV, lowN, lowV = nil, -1, nil, math.huge
  for _,n in ipairs(state.ordered) do
    local r = state.joiners[n].roll
    if r then
      if r > highV then highV = r; highN = n end
      if r < lowV  then lowV  = r; lowN  = n end
    end
  end
  if not highN or not lowN then return end
  announce(string.format("Results: High %s (%d) | Low %s (%d)", highN, highV, lowN, lowV))
  if highN == lowN then
    announce("Tie? Run-off roll between tied players!")
    return
  end
  announce(string.format("Settlement: %s pays %s %dg.", lowN, highN, state.betGold))
  system(string.format("Settlement: %s -> %s (%dg)", lowN, highN, state.betGold))
  resetGame()
end

local function handleHiLoRoll(name, roll, rmin, rmax)
  -- Only accept rolls by joiners, and within the declared range
  if state.phase ~= "ROLLING" then return end
  if rmin ~= state.rollMin or rmax ~= state.rollMax then return end
  if not inRoster(name) then return end
  if state.joiners[name].roll then return end -- already rolled
  setRoll(name, roll)
  if everyoneRolled() then
    announceHiLoResult()
  end
end

local function currentDRPlayer()
  return (state.dr.turn == 1) and state.dr.p1 or state.dr.p2
end

local function swapTurn() state.dr.turn = (state.dr.turn == 1) and 2 or 1 end

local function handleDeathRoll(name, roll, rmin, rmax)
  if state.phase ~= "DEATHROLL" or not state.dr.active then return end
  if rmin ~= 1 then return end
  if rmax ~= state.dr.currentMax then return end
  local expected = currentDRPlayer()
  if trimRealm(name) ~= trimRealm(expected) then return end

  -- Valid turn
  announce(string.format("%s rolled %d (1-%d)", name, roll, rmax))

  if roll == 1 then
    -- name loses; other wins
    local winner = (state.dr.turn == 1) and state.dr.p2 or state.dr.p1
    announce(string.format("DEATH ROLL: %s rolled 1 and loses! %s pays %s %dg.",
      name, name, winner, state.betGold))
    system(string.format("Death Roll settled: %s -> %s (%dg)", name, winner, state.betGold))
    resetGame()
    return
  end

  -- Continue with new cap
  state.dr.currentMax = roll
  swapTurn()
  announce(string.format("Next: %s to /roll 1-%d", currentDRPlayer(), state.dr.currentMax))
  updateRosterText()
end

-- Chat listeners for joins
local function handleJoinChat(msg, author, event)
  if state.phase ~= "JOINING" then return end
  local isChan =
    (state.channel == "SAY" and event == "CHAT_MSG_SAY") or
    (state.channel == "PARTY" and event == "CHAT_MSG_PARTY") or
    (state.channel == "RAID" and event == "CHAT_MSG_RAID") or
    (state.channel == "BATTLEGROUND" and event == "CHAT_MSG_BATTLEGROUND")

  if not isChan then return end
  msg = string.trim and string.trim(msg) or msg:gsub("^%s+", ""):gsub("%s+$","")
  if msg == "1" then
    addJoiner(trimRealm(author))
  end
end

-- Register event handlers
events.CHAT_MSG_SAY = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_SAY") end
events.CHAT_MSG_PARTY = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_PARTY") end
events.CHAT_MSG_RAID = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_RAID") end
events.CHAT_MSG_BATTLEGROUND = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_BATTLEGROUND") end

events.CHAT_MSG_SYSTEM = function(msg)
  -- Rolls appear here
  local name, roll, rmin, rmax = parseRoll(msg)
  if not name then return end
  if state.mode == "HILO" then
    handleHiLoRoll(name, roll, rmin, rmax)
  else
    handleDeathRoll(name, roll, rmin, rmax)
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local f = events[event]
  if f then f(...) end
end)

-- ------------------------------------------------------------
-- Slash command + init
-- ------------------------------------------------------------
SLASH_NRG1 = "/nrg"
SlashCmdList["NRG"] = function(msg)
  buildUI()
  if ui.frame:IsShown() then ui.frame:Hide() else ui.frame:Show() end
end

-- Register events
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("CHAT_MSG_SAY")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_BATTLEGROUND")

-- Basic string.trim backfill for 3.3.5 if missing
if not string.trim then
  function string.trim(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
end

-- Boot
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  buildUI()
  system("NIPS Roll loaded. Type /nrg to open.")
end)
