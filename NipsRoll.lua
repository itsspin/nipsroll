-- Nips Roll (NRG) - 3.3.5a compatible
-- Author: Spin + Alyx
-- Notes: Host simple Hi/Lo and 1v1 Death Roll games with chat-based joining and roll parsing.

-- ===========
-- SAFE GLOBALS
-- ===========
NipsRollDB = NipsRollDB or {}

-- Early slash so you can at least open/verify even if later code errors
SLASH_NRG1 = "/nrg"
SlashCmdList["NRG"] = function()
  if NRG and NRG.Toggle then
    NRG.Toggle()
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cFF66C7FF[NRG]|r Addon loaded. If the window didn’t open, type: /reload and try again.")
  end
end

-- ===========
-- UTIL FUNCS
-- ===========
local function trimRealm(name)
  if not name then return name end
  local base = name:match("([^%-]+)")
  return base or name
end

local function sys(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cFF66C7FF[NRG]|r "..tostring(msg))
end

-- 3.3.5 has no native string.trim; add a tiny helper
local function strtrim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$",""))
end

-- =============
-- ADDON STATE
-- =============
local NRG = {}
_G.NRG = NRG  -- expose for the early /nrg Toggle() call

local state = {
  phase   = "IDLE",         -- IDLE | JOINING | ROLLING | DEATHROLL
  mode    = "HILO",         -- HILO | DEATH
  channel = "SAY",          -- SAY | PARTY | RAID | BATTLEGROUND
  betGold = 10,
  rollMin = 1,
  rollMax = 100,
  host    = UnitName("player") or "Host",
  joiners = {},             -- [name] = {roll=nil}
  ordered = {},             -- stable order
  dr = { p1=nil, p2=nil, turn=1, max=1000, currentMax=1000, active=false },
}

local function resetGame()
  state.phase = "IDLE"
  state.joiners = {}
  state.ordered = {}
  state.dr = { p1=nil, p2=nil, turn=1, max=1000, currentMax=1000, active=false }
  if NRG.UpdateRoster then NRG.UpdateRoster() end
end

local function canUseChannel(chan)
  if chan == "SAY" then return true end
  if chan == "PARTY" then return (GetNumPartyMembers() > 0) or (GetNumRaidMembers() > 0) end
  if chan == "RAID" then return GetNumRaidMembers() > 0 end
  if chan == "BATTLEGROUND" then return true end -- harmless outside BG
  return false
end

local function say(chan, msg)
  if not canUseChannel(chan) then
    sys("Channel "..chan.." not available here. Showing locally:\n"..msg)
    return
  end
  SendChatMessage(msg, chan)
end

local function announce(msg) say(state.channel, msg) end

-- =========
-- ROSTER
-- =========
local function addJoiner(name)
  name = trimRealm(name)
  if not name or name == "" then return end
  if not state.joiners[name] then
    state.joiners[name] = { roll=nil }
    table.insert(state.ordered, name)
    NRG.UpdateRoster()
  end
end

local function setRoll(name, val)
  if state.joiners[name] and state.joiners[name].roll == nil then
    state.joiners[name].roll = val
    NRG.UpdateRoster()
  end
end

local function everyoneRolled()
  if #state.ordered == 0 then return false end
  for _,n in ipairs(state.ordered) do
    if not state.joiners[n].roll then return false end
  end
  return true
end

-- =====
-- UI
-- =====
local ui = {}

local function MakeFS(parent, text, size)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetText(text or "")
  if size then
    local font, _, flags = fs:GetFont()
    fs:SetFont(font, size, flags)
  end
  return fs
end

local function MakeBtn(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function MakeCheck(parent, text, onClick)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetScript("OnClick", function(self) PlaySound("igMainMenuOptionCheckBoxOn"); if onClick then onClick(self) end end)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("LEFT", c, "RIGHT", 4, 0)
  label:SetText(text)
  c._label = label
  return c
end

local function MakeEdit(parent, w, h, numeric)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, h)
  e:SetAutoFocus(false)
  e:SetTextInsets(6,6,2,2)
  if numeric then e:SetNumeric(true) end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

function NRG.UpdateRoster()
  if not ui.roster then return end
  local lines = {}
  if state.mode == "HILO" then
    table.insert(lines, string.format("|cFFFFFF55Mode:|r Hi/Lo  |  Range: %d-%d  |  Bet: %dg  |  Chan: %s", state.rollMin, state.rollMax, state.betGold, state.channel))
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
    table.insert(lines, string.format("|cFFFFFF55Mode:|r Death Roll  |  Start Max: %d  |  Bet: %dg  |  Chan: %s",
      state.dr.max, state.betGold, state.channel))
    table.insert(lines, string.format("|cFFAAAAAAPlayers:|r %s vs %s   | Current Max: %d | Turn: %s",
      state.dr.p1 or "(p1?)", state.dr.p2 or "(p2?)", state.dr.currentMax,
      (state.dr.turn == 1) and (state.dr.p1 or "?") or (state.dr.p2 or "?")))
  end
  ui.roster:SetText(table.concat(lines, "\n"))
end

local function UpdateModeUI()
  if not ui.frame then return end
  local hilo = (state.mode == "HILO")
  if hilo then
    ui.rollMin:Enable(); ui.rollMax:Enable()
    ui.drMax:Disable()
    ui.p1Edit:Disable(); ui.p2Edit:Disable()
  else
    ui.rollMin:Disable(); ui.rollMax:Disable()
    ui.drMax:Enable()
    ui.p1Edit:Enable(); ui.p2Edit:Enable()
  end
  NRG.UpdateRoster()
end

local function BuildUI()
  if ui.frame then return end
  local f = CreateFrame("Frame", "NipsRollFrame", UIParent)
  ui.frame = f
  f:SetSize(460, 360)
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
    insets={left=8,right=8,top=8,bottom=8}
  })
  f:Hide()

  local title = MakeFS(f, "NIPS ROLL (NRG) - Host Panel", 14)
  title:SetPoint("TOP", 0, -12)

  local chanLbl = MakeFS(f, "Channel:", 12); chanLbl:SetPoint("TOPLEFT", 18, -40)
  local chans = {"SAY","PARTY","RAID","BATTLEGROUND"}
  ui.chanChecks = {}
  local last
  for i,c in ipairs(chans) do
    local ck = MakeCheck(f, c, function(self)
      for _,o in ipairs(ui.chanChecks) do o:SetChecked(false) end
      self:SetChecked(true)
      state.channel = c
      NRG.UpdateRoster()
    end)
    table.insert(ui.chanChecks, ck)
    if not last then ck:SetPoint("LEFT", chanLbl, "RIGHT", 10, 0)
    else ck:SetPoint("LEFT", last._label, "RIGHT", 20, 0) end
    last = ck
  end
  ui.chanChecks[1]:SetChecked(true)

  local modeLbl = MakeFS(f, "Mode:", 12); modeLbl:SetPoint("TOPLEFT", 18, -70)
  ui.hilo = MakeCheck(f, "Hi/Lo", function(self)
    ui.hilo:SetChecked(true); ui.death:SetChecked(false); state.mode = "HILO"; UpdateModeUI()
  end)
  ui.hilo:SetPoint("LEFT", modeLbl, "RIGHT", 10, 0)
  ui.hilo:SetChecked(true)

  ui.death = MakeCheck(f, "Death Roll (1v1)", function(self)
    ui.hilo:SetChecked(false); ui.death:SetChecked(true); state.mode = "DEATH"; UpdateModeUI()
  end)
  ui.death:SetPoint("LEFT", ui.hilo._label, "RIGHT", 20, 0)

  local betLbl = MakeFS(f, "Bet (gold):", 12); betLbl:SetPoint("TOPLEFT", 18, -100)
  ui.betEdit = MakeEdit(f, 60, 20, true); ui.betEdit:SetPoint("LEFT", betLbl, "RIGHT", 10, 0)
  ui.betEdit:SetText(tostring(state.betGold))
  ui.betEdit:SetScript("OnTextChanged", function(self)
    local v = tonumber(self:GetText()) or state.betGold
    state.betGold = math.max(0, math.floor(v))
    NRG.UpdateRoster()
  end)

  local rollLbl = MakeFS(f, "Roll Range:", 12); rollLbl:SetPoint("TOPLEFT", 18, -130)
  ui.rollMin = MakeEdit(f, 50, 20, true); ui.rollMin:SetPoint("LEFT", rollLbl, "RIGHT", 10, 0)
  ui.rollMin:SetText(tostring(state.rollMin))
  ui.rollMin:SetScript("OnTextChanged", function(self)
    local v = tonumber(self:GetText()) or state.rollMin
    state.rollMin = math.max(1, math.floor(v))
    if state.rollMax < state.rollMin then state.rollMax = state.rollMin end
    ui.rollMax:SetText(tostring(state.rollMax))
    NRG.UpdateRoster()
  end)

  local dash = MakeFS(f, " - ", 12); dash:SetPoint("LEFT", ui.rollMin, "RIGHT", 5, 0)

  ui.rollMax = MakeEdit(f, 50, 20, true); ui.rollMax:SetPoint("LEFT", dash, "RIGHT", 5, 0)
  ui.rollMax:SetText(tostring(state.rollMax))
  ui.rollMax:SetScript("OnTextChanged", function(self)
    local v = tonumber(self:GetText()) or state.rollMax
    state.rollMax = math.max(state.rollMin, math.floor(v))
    NRG.UpdateRoster()
  end)

  local drLbl = MakeFS(f, "Death Roll Start Max:", 12); drLbl:SetPoint("TOPLEFT", 18, -160)
  ui.drMax = MakeEdit(f, 80, 20, true); ui.drMax:SetPoint("LEFT", drLbl, "RIGHT", 10, 0)
  ui.drMax:SetText("1000")
  ui.drMax:SetScript("OnTextChanged", function(self)
    local v = tonumber(self:GetText()) or 1000
    v = math.max(2, math.floor(v))
    state.dr.max = v
    if state.phase ~= "DEATHROLL" then state.dr.currentMax = v end
    NRG.UpdateRoster()
  end)

  local p1Lbl = MakeFS(f, "P1:", 12); p1Lbl:SetPoint("TOPLEFT", 18, -190)
  ui.p1Edit = MakeEdit(f, 120, 20, false); ui.p1Edit:SetPoint("LEFT", p1Lbl, "RIGHT", 10, 0)
  ui.p1Edit:SetScript("OnTextChanged", function(self)
    local v = strtrim(self:GetText()); if v=="" then v=nil end
    state.dr.p1 = v; NRG.UpdateRoster()
  end)

  local p2Lbl = MakeFS(f, "P2:", 12); p2Lbl:SetPoint("LEFT", ui.p1Edit, "RIGHT", 20, 0)
  ui.p2Edit = MakeEdit(f, 120, 20, false); ui.p2Edit:SetPoint("LEFT", p2Lbl, "RIGHT", 10, 0)
  ui.p2Edit:SetScript("OnTextChanged", function(self)
    local v = strtrim(self:GetText()); if v=="" then v=nil end
    state.dr.p2 = v; NRG.UpdateRoster()
  end)

  ui.newBtn = MakeBtn(f, "New Game", 100, 22, function()
    resetGame()
    if state.mode == "HILO" then
      state.phase = "JOINING"
      announce(string.format("NIPS ROLL GAME STARTED, PRESS 1 TO JOIN (%d-%d) - Bet %dg", state.rollMin, state.rollMax, state.betGold))
      announce("Type 1 in "..state.channel.." to join!")
    else
      state.phase = "DEATHROLL"
      state.dr.currentMax = state.dr.max
      announce(string.format("NIPS DEATH ROLL STARTED! Set P1/P2, Start Max %d, then press Start.", state.dr.max))
    end
    NRG.UpdateRoster()
  end))
  ui.newBtn:SetPoint("TOPLEFT", 18, -220)

  ui.lastBtn = MakeBtn(f, "Last Call", 100, 22, function()
    if state.phase ~= "JOINING" then sys("You can only Last Call while JOINING.") return end
    announce("LAST CALL to join! Type 1 now!")
  end)
  ui.lastBtn:SetPoint("LEFT", ui.newBtn, "RIGHT", 10, 0)

  ui.joinSelf = MakeBtn(f, "Join (You)", 100, 22, function()
    if state.mode ~= "HILO" or state.phase ~= "JOINING" then sys("You can only join during Hi/Lo JOINING.") return end
    addJoiner(state.host)
  end)
  ui.joinSelf:SetPoint("LEFT", ui.lastBtn, "RIGHT", 10, 0)

  ui.startBtn = MakeBtn(f, "Start Rolling!", 120, 24, function()
    if state.mode == "HILO" then
      if state.phase ~= "JOINING" then sys("You must be in JOINING to start.") return end
      if #state.ordered < 2 then sys("Need at least 2 players.") return end
      state.phase = "ROLLING"
      announce(string.format("ROLL NOW! Use /roll %d-%d", state.rollMin, state.rollMax))
      announce("Lowest pays Highest the bet. Good luck!")
    else
      if not state.dr.p1 or not state.dr.p2 or state.dr.p1 == state.dr.p2 then
        sys("Set P1 and P2 (distinct names) before starting Death Roll.")
        return
      end
      state.phase = "DEATHROLL"
      state.dr.currentMax = state.dr.max
      state.dr.turn = 1
      state.dr.active = true
      announce(string.format("DEATH ROLL: %s vs %s. Start at %d. %s rolls first: /roll 1-%d",
        state.dr.p1, state.dr.p2, state.dr.max, state.dr.p1, state.dr.currentMax))
    end
    NRG.UpdateRoster()
  end))
  ui.startBtn:SetPoint("TOPLEFT", ui.newBtn, "BOTTOMLEFT", 0, -10)

  ui.cancelBtn = MakeBtn(f, "Cancel/Reset", 120, 24, function()
    announce("Game cancelled by host.")
    resetGame()
  end)
  ui.cancelBtn:SetPoint("LEFT", ui.startBtn, "RIGHT", 10, 0)

  local box = CreateFrame("Frame", nil, f)
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

  local hint = MakeFS(f, "|cFFAAAAAA/nrg to show/hide|r", 11)
  hint:SetPoint("BOTTOMRIGHT", -12, 10)

  UpdateModeUI()
  NRG.UpdateRoster()
end

function NRG.Toggle()
  BuildUI()
  if ui.frame:IsShown() then ui.frame:Hide() else ui.frame:Show() end
end

-- ============
-- ROLL LOGIC
-- ============
local function announceHiLoResult()
  if #state.ordered < 2 then return end
  local highN, highV, lowN, lowV = nil, -1, nil, math.huge
  for _,n in ipairs(state.ordered) do
    local r = state.joiners[n].roll
    if r then
      if r > highV then highV = r; highN = n end
      if r < lowV then lowV = r; lowN = n end
    end
  end
  if not highN or not lowN then return end
  announce(string.format("Results: High %s (%d) | Low %s (%d)", highN, highV, lowN, lowV))
  if highN == lowN then
    announce("Tie detected. Host: run a quick tie-break between the tied players.")
    resetGame(); return
  end
  announce(string.format("Settlement: %s pays %s %dg.", lowN, highN, state.betGold))
  sys(string.format("Settlement: %s -> %s (%dg)", lowN, highN, state.betGold))
  resetGame()
end

local function handleHiLoRoll(name, roll, rmin, rmax)
  if state.phase ~= "ROLLING" then return end
  if rmin ~= state.rollMin or rmax ~= state.rollMax then return end
  if not state.joiners[name] then return end
  if state.joiners[name].roll then return end -- already rolled
  setRoll(name, roll)
  if everyoneRolled() then announceHiLoResult() end
end

local function currentDR()
  return (state.dr.turn == 1) and state.dr.p1 or state.dr.p2
end

local function swapDRTurn() state.dr.turn = (state.dr.turn == 1) and 2 or 1 end

local function handleDeathRoll(name, roll, rmin, rmax)
  if state.phase ~= "DEATHROLL" or not state.dr.active then return end
  if rmin ~= 1 then return end
  if rmax ~= state.dr.currentMax then return end
  local expected = currentDR()
  if trimRealm(name) ~= trimRealm(expected) then return end

  announce(string.format("%s rolled %d (1-%d)", name, roll, rmax))

  if roll == 1 then
    local winner = (state.dr.turn == 1) and state.dr.p2 or state.dr.p1
    announce(string.format("DEATH ROLL: %s rolled 1 and loses! %s pays %s %dg.", name, name, winner, state.betGold))
    sys(string.format("Death Roll settled: %s -> %s (%dg)", name, winner, state.betGold))
    resetGame()
    return
  end

  state.dr.currentMax = roll
  swapDRTurn()
  announce(string.format("Next: %s to /roll 1-%d", currentDR(), state.dr.currentMax))
  NRG.UpdateRoster()
end

-- ==========
-- EVENTS
-- ==========
local evt = CreateFrame("Frame")

-- Classic 3.3.5 roll message looks like: "Name rolls 42 (1-100)"
local ROLL_PATTERN = "^(.+) rolls (%d+) %((%d+)%-(%d+)%)$"

local function parseRoll(line)
  local pName, pRoll, pMin, pMax = string.match(line, ROLL_PATTERN)
  if pName and pRoll and pMin and pMax then
    return trimRealm(pName), tonumber(pRoll), tonumber(pMin), tonumber(pMax)
  end
end

local handlers = {}

handlers.CHAT_MSG_SYSTEM = function(msg)
  local name, roll, rmin, rmax = parseRoll(msg)
  if not name then return end
  if state.mode == "HILO" then
    handleHiLoRoll(name, roll, rmin, rmax)
  else
    handleDeathRoll(name, roll, rmin, rmax)
  end
end

local function handleJoinChat(msg, author, event)
  if state.phase ~= "JOINING" then return end
  local ok =
    (state.channel == "SAY" and event == "CHAT_MSG_SAY") or
    (state.channel == "PARTY" and (event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER")) or
    (state.channel == "RAID" and (event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER")) or
    (state.channel == "BATTLEGROUND" and (event == "CHAT_MSG_BATTLEGROUND" or event == "CHAT_MSG_BATTLEGROUND_LEADER"))

  if not ok then return end
  if strtrim(msg) == "1" then
    addJoiner(trimRealm(author))
  end
end

handlers.CHAT_MSG_SAY = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_SAY") end
handlers.CHAT_MSG_PARTY = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_PARTY") end
handlers.CHAT_MSG_PARTY_LEADER = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_PARTY_LEADER") end
handlers.CHAT_MSG_RAID = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_RAID") end
handlers.CHAT_MSG_RAID_LEADER = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_RAID_LEADER") end
handlers.CHAT_MSG_BATTLEGROUND = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_BATTLEGROUND") end
handlers.CHAT_MSG_BATTLEGROUND_LEADER = function(msg, author) handleJoinChat(msg, author, "CHAT_MSG_BATTLEGROUND_LEADER") end

handlers.ADDON_LOADED = function(name)
  if name == "NipsRoll" then
    BuildUI()
    sys("Loaded. Type |cFFFFFF00/nrg|r to open.")
  end
end

evt:SetScript("OnEvent", function(_, event, ...)
  local f = handlers[event]
  if f then f(...) end
end)

evt:RegisterEvent("ADDON_LOADED")
evt:RegisterEvent("CHAT_MSG_SYSTEM")
evt:RegisterEvent("CHAT_MSG_SAY")
evt:RegisterEvent("CHAT_MSG_PARTY")
evt:RegisterEvent("CHAT_MSG_PARTY_LEADER")
evt:RegisterEvent("CHAT_MSG_RAID")
evt:RegisterEvent("CHAT_MSG_RAID_LEADER")
evt:RegisterEvent("CHAT_MSG_BATTLEGROUND")
evt:RegisterEvent("CHAT_MSG_BATTLEGROUND_LEADER")
