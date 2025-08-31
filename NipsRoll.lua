-- Nips Roll (NRG) - 3.3.5a (Project Epoch) - v1.0.4
-- Fixes: removed parse-time bug, no SetNumeric/SetEnabled on EditBoxes, UI builds on PLAYER_LOGIN, dual slash commands.

NipsRollDB = NipsRollDB or {}

-- Early slashes so you always get feedback even if something else breaks later.
SLASH_NRG1 = "/nrg"
SLASH_NRG2 = "/nips"
SlashCmdList["NRG"] = function()
  if NRG and NRG.Toggle then NRG.Toggle()
  else DEFAULT_CHAT_FRAME:AddMessage("|cFF66C7FF[NRG]|r Loaded. If the panel didn’t open, type /reload then /nrg again.") end
end
SlashCmdList["NIPS"] = SlashCmdList["NRG"]

local function sys(msg) DEFAULT_CHAT_FRAME:AddMessage("|cFF66C7FF[NRG]|r "..tostring(msg)) end
local function trimRealm(name) return name and name:match("([^%-]+)") or name end
local function strtrim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end

-- ---------------- State ----------------
local NRG = {} _G.NRG = NRG

local state = {
  phase="IDLE",          -- IDLE | JOINING | ROLLING | DEATHROLL
  mode="HILO",           -- HILO | DEATH
  channel="SAY",         -- SAY | PARTY | RAID | BATTLEGROUND
  betGold=10,
  rollMin=1, rollMax=100,
  host=UnitName("player") or "Host",
  joiners={}, ordered={},
  dr={p1=nil,p2=nil,turn=1,max=1000,currentMax=1000,active=false},
}

local function resetGame()
  state.phase="IDLE"
  state.joiners={}; state.ordered={}
  state.dr={p1=nil,p2=nil,turn=1,max=1000,currentMax=1000,active=false}
  if NRG.UpdateRoster then NRG.UpdateRoster() end
end

local function canUseChannel(chan)
  if chan=="SAY" then return true end
  if chan=="PARTY" then return (GetNumPartyMembers()>0) or (GetNumRaidMembers()>0) end
  if chan=="RAID" then return GetNumRaidMembers()>0 end
  if chan=="BATTLEGROUND" then return true end
  return false
end

local function say(chan,msg)
  if not canUseChannel(chan) then sys("Channel "..chan.." not available here; showing locally:\n"..msg); return end
  SendChatMessage(msg, chan)
end
local function announce(msg) say(state.channel, msg) end

-- ---------------- Roster ----------------
local function addJoiner(name)
  name = trimRealm(name)
  if not name or name=="" then return end
  if not state.joiners[name] then
    state.joiners[name] = { roll=nil }
    table.insert(state.ordered, name)
    NRG.UpdateRoster()
  end
end

local function setRoll(name,val)
  if state.joiners[name] and state.joiners[name].roll==nil then
    state.joiners[name].roll = val
    NRG.UpdateRoster()
  end
end

local function everyoneRolled()
  if #state.ordered==0 then return false end
  for _,n in ipairs(state.ordered) do if not state.joiners[n].roll then return false end end
  return true
end

-- ---------------- UI ----------------
local ui = {}

local function FS(parent,text,size)
  local fs=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
  fs:SetText(text or "")
  if size then local f,_,fl=fs:GetFont(); fs:SetFont(f,size,fl) end
  return fs
end

local function Btn(parent,text,w,h,onClick)
  local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
  b:SetSize(w,h); b:SetText(text); b:SetScript("OnClick",onClick)
  return b
end

local function Check(parent,text,onClick)
  local c=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate")
  c:SetScript("OnClick",function(self) PlaySound("igMainMenuOptionCheckBoxOn"); if onClick then onClick(self) end end)
  local l=parent:CreateFontString(nil,"OVERLAY","GameFontNormal"); l:SetPoint("LEFT",c,"RIGHT",4,0); l:SetText(text); c._label=l
  return c
end

local function Edit(parent,w,h,initial,onChanged)
  local e=CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
  e:SetSize(w,h); e:SetAutoFocus(false); e:SetTextInsets(6,6,2,2)
  e:SetText(initial or "")
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  if onChanged then e:SetScript("OnTextChanged", function(self) onChanged(self:GetText()) end) end
  return e
end

function NRG.UpdateRoster()
  if not ui.roster then return end
  local t={}
  if state.mode=="HILO" then
    table.insert(t,("|cFFFFFF55Mode:|r Hi/Lo  |  Range: %d-%d  |  Bet: %dg  |  Chan: %s"):format(state.rollMin,state.rollMax,state.betGold,state.channel))
    table.insert(t,"|cFFAAAAAAPlayers (name - roll)|r")
    if #state.ordered==0 then table.insert(t,"  (none yet)") else
      for _,n in ipairs(state.ordered) do table.insert(t,("  %s%s"):format(n, state.joiners[n].roll and (" - "..state.joiners[n].roll) or "")) end
    end
  else
    table.insert(t,("|cFFFFFF55Mode:|r Death Roll  |  Start Max: %d  |  Bet: %dg  |  Chan: %s"):format(state.dr.max,state.betGold,state.channel))
    table.insert(t,( "|cFFAAAAAAPlayers:|r %s vs %s   | Current Max: %d | Turn: %s" )
      :format(state.dr.p1 or "(p1?)", state.dr.p2 or "(p2?)", state.dr.currentMax,
              (state.dr.turn==1) and (state.dr.p1 or "?") or (state.dr.p2 or "?")))
  end
  ui.roster:SetText(table.concat(t,"\n"))
end

local function BuildUI()
  if ui.frame then return end
  local f=CreateFrame("Frame","NipsRollFrame",UIParent); ui.frame=f
  f:SetSize(460,360); f:SetPoint("CENTER"); f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
  f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
    tile=true,tileSize=32,edgeSize=32,insets={left=8,right=8,top=8,bottom=8}})
  f:Hide()

  FS(f,"NIPS ROLL (NRG) - Host Panel",14):SetPoint("TOP",0,-12)

  local chanLbl=FS(f,"Channel:",12); chanLbl:SetPoint("TOPLEFT",18,-40)
  local chans={"SAY","PARTY","RAID","BATTLEGROUND"}; ui.chanChecks={}
  local last
  for _,c in ipairs(chans) do
    local ck=Check(f,c,function(self) for _,o in ipairs(ui.chanChecks) do o:SetChecked(false) end; self:SetChecked(true); state.channel=c; NRG.UpdateRoster() end)
    table.insert(ui.chanChecks,ck)
    if not last then ck:SetPoint("LEFT",chanLbl,"RIGHT",10,0) else ck:SetPoint("LEFT",last._label,"RIGHT",20,0) end
    last=ck
  end
  ui.chanChecks[1]:SetChecked(true)

  local modeLbl=FS(f,"Mode:",12); modeLbl:SetPoint("TOPLEFT",18,-70)
  ui.hilo=Check(f,"Hi/Lo",function() ui.hilo:SetChecked(true); ui.death:SetChecked(false); state.mode="HILO"; NRG.UpdateRoster() end)
  ui.hilo:SetPoint("LEFT",modeLbl,"RIGHT",10,0); ui.hilo:SetChecked(true)
  ui.death=Check(f,"Death Roll (1v1)",function() ui.hilo:SetChecked(false); ui.death:SetChecked(true); state.mode="DEATH"; NRG.UpdateRoster() end)
  ui.death:SetPoint("LEFT",ui.hilo._label,"RIGHT",20,0)

  local betLbl=FS(f,"Bet (gold):",12); betLbl:SetPoint("TOPLEFT",18,-100)
  ui.betEdit=Edit(f,60,20,tostring(state.betGold), function(txt)
    local v = tonumber(txt and txt:match("%d+")) or state.betGold
    state.betGold = math.max(0, math.floor(v)); NRG.UpdateRoster()
  end)
  ui.betEdit:SetPoint("LEFT",betLbl,"RIGHT",10,0)

  local rollLbl=FS(f,"Roll Range:",12); rollLbl:SetPoint("TOPLEFT",18,-130)
  ui.rollMin=Edit(f,50,20,tostring(state.rollMin), function(txt)
    local v=tonumber(txt and txt:match("%d+")) or state.rollMin
    state.rollMin=math.max(1,math.floor(v)); if state.rollMax<state.rollMin then state.rollMax=state.rollMin end
    ui.rollMax:SetText(tostring(state.rollMax)); NRG.UpdateRoster()
  end)
  ui.rollMin:SetPoint("LEFT",rollLbl,"RIGHT",10,0)

  FS(f," - ",12):SetPoint("LEFT",ui.rollMin,"RIGHT",5,0)

  ui.rollMax=Edit(f,50,20,tostring(state.rollMax), function(txt)
    local v=tonumber(txt and txt:match("%d+")) or state.rollMax
    state.rollMax=math.max(state.rollMin,math.floor(v)); NRG.UpdateRoster()
  end)
  ui.rollMax:SetPoint("LEFT",ui.rollMin,"RIGHT",25,0)

  local drLbl=FS(f,"Death Roll Start Max:",12); drLbl:SetPoint("TOPLEFT",18,-160)
  ui.drMax=Edit(f,80,20,"1000", function(txt)
    local v=tonumber(txt and txt:match("%d+")) or 1000
    v=math.max(2,math.floor(v)); state.dr.max=v; if state.phase~="DEATHROLL" then state.dr.currentMax=v end; NRG.UpdateRoster()
  end)
  ui.drMax:SetPoint("LEFT",drLbl,"RIGHT",10,0)

  local p1Lbl=FS(f,"P1:",12); p1Lbl:SetPoint("TOPLEFT",18,-190)
  ui.p1Edit=Edit(f,120,20,"", function(txt) local v=strtrim(txt or ""); if v=="" then v=nil end; state.dr.p1=v; NRG.UpdateRoster() end)
  ui.p1Edit:SetPoint("LEFT",p1Lbl,"RIGHT",10,0)
  local p2Lbl=FS(f,"P2:",12); p2Lbl:SetPoint("LEFT",ui.p1Edit,"RIGHT",20,0)
  ui.p2Edit=Edit(f,120,20,"", function(txt) local v=strtrim(txt or ""); if v=="" then v=nil end; state.dr.p2=v; NRG.UpdateRoster() end)
  ui.p2Edit:SetPoint("LEFT",p2Lbl,"RIGHT",10,0)

  ui.newBtn=Btn(f,"New Game",100,22,function()
    resetGame()
    if state.mode=="HILO" then
      state.phase="JOINING"
      announce(("NIPS ROLL GAME STARTED, PRESS 1 TO JOIN (%d-%d) - Bet %dg"):format(state.rollMin,state.rollMax,state.betGold))
      announce("Type 1 in "..state.channel.." to join!")
    else
      state.phase="DEATHROLL"; state.dr.currentMax=state.dr.max
      announce(("NIPS DEATH ROLL STARTED! Set P1/P2, Start Max %d, then press Start."):format(state.dr.max))
    end
    NRG.UpdateRoster()
  end))
  ui.newBtn:SetPoint("TOPLEFT",18,-220)

  ui.lastBtn=Btn(f,"Last Call",100,22,function()
    if state.phase~="JOINING" then sys("You can only Last Call while JOINING.") return end
    announce("LAST CALL to join! Type 1 now!")
  end)
  ui.lastBtn:SetPoint("LEFT",ui.newBtn,"RIGHT",10,0)

  ui.joinSelf=Btn(f,"Join (You)",100,22,function()
    if state.mode~="HILO" or state.phase~="JOINING" then sys("You can only join during Hi/Lo JOINING.") return end
    addJoiner(state.host)
  end)
  ui.joinSelf:SetPoint("LEFT",ui.lastBtn,"RIGHT",10,0)

  ui.startBtn=Btn(f,"Start Rolling!",120,24,function()
    if state.mode=="HILO" then
      if state.phase~="JOINING" then sys("You must be in JOINING to start.") return end
      if #state.ordered<2 then sys("Need at least 2 players.") return end
      state.phase="ROLLING"
      announce(("ROLL NOW! Use /roll %d-%d"):format(state.rollMin,state.rollMax))
      announce("Lowest pays Highest the bet. Good luck!")
    else
      if not state.dr.p1 or not state.dr.p2 or state.dr.p1==state.dr.p2 then sys("Set P1 and P2 (distinct) before starting Death Roll."); return end
      state.phase="DEATHROLL"; state.dr.currentMax=state.dr.max; state.dr.turn=1; state.dr.active=true
      announce(("DEATH ROLL: %s vs %s. Start at %d. %s rolls first: /roll 1-%d"):format(state.dr.p1,state.dr.p2,state.dr.max,state.dr.p1,state.dr.currentMax))
    end
    NRG.UpdateRoster()
  end))
  ui.startBtn:SetPoint("TOPLEFT",ui.newBtn,"BOTTOMLEFT",0,-10)

  ui.cancelBtn=Btn(f,"Cancel/Reset",120,24,function() announce("Game cancelled by host."); resetGame() end)
  ui.cancelBtn:SetPoint("LEFT",ui.startBtn,"RIGHT",10,0)

  local box=CreateFrame("Frame",nil,f); box:SetPoint("TOPLEFT",18,-260); box:SetSize(414,80)
  box:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
    tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
  box:SetBackdropColor(0,0,0,0.8)

  ui.roster=box:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  ui.roster:SetPoint("TOPLEFT",6,-6); ui.roster:SetJustifyH("LEFT"); ui.roster:SetJustifyV("TOP"); ui.roster:SetWidth(402)

  FS(f,"|cFFAAAAAA/nrg or /nips to show/hide|r",11):SetPoint("BOTTOMRIGHT",-12,10)

  NRG.UpdateRoster()
end

function NRG.Toggle()
  BuildUI()
  if ui.frame:IsShown() then ui.frame:Hide() else ui.frame:Show() end
end

-- ---------------- Roll logic ----------------
local function announceHiLoResult()
  if #state.ordered<2 then return end
  local highN,highV,lowN,lowV=nil,-1,nil,math.huge
  for _,n in ipairs(state.ordered) do local r=state.joiners[n].roll
    if r then if r>highV then highV=r; highN=n end; if r<lowV then lowV=r; lowN=n end end
  end
  if not highN or not lowN then return end
  announce(("Results: High %s (%d) | Low %s (%d)"):format(highN,highV,lowN,lowV))
  if highN==lowN then announce("Tie detected. Host: run a tie-break."); resetGame(); return end
  announce(("Settlement: %s pays %s %dg."):format(lowN,highN,state.betGold))
  sys(("Settlement: %s -> %s (%dg)"):format(lowN,highN,state.betGold))
  resetGame()
end

local function handleHiLoRoll(name,roll,rmin,rmax)
  if state.phase~="ROLLING" then return end
  if rmin~=state.rollMin or rmax~=state.rollMax then return end
  if not state.joiners[name] or state.joiners[name].roll then return end
  setRoll(name,roll); if everyoneRolled() then announceHiLoResult() end
end

local function currDR() return (state.dr.turn==1) and state.dr.p1 or state.dr.p2 end
local function swapDR() state.dr.turn=(state.dr.turn==1) and 2 or 1 end

local function handleDeathRoll(name,roll,rmin,rmax)
  if state.phase~="DEATHROLL" or not state.dr.active then return end
  if rmin~=1 or rmax~=state.dr.currentMax then return end
  if trimRealm(name)~=trimRealm(currDR()) then return end
  announce(("%s rolled %d (1-%d)"):format(name,roll,rmax))
  if roll==1 then
    local winner=(state.dr.turn==1) and state.dr.p2 or state.dr.p1
    announce(("DEATH ROLL: %s rolled 1 and loses! %s pays %s %dg."):format(name,name,winner,state.betGold))
    sys(("Death Roll settled: %s -> %s (%dg)"):format(name,winner,state.betGold))
    resetGame(); return
  end
  state.dr.currentMax=roll; swapDR()
  announce(("Next: %s to /roll 1-%d"):format(currDR(),state.dr.currentMax))
  NRG.UpdateRoster()
end

-- ---------------- Events ----------------
local evt=CreateFrame("Frame")
evt:SetScript("OnEvent", function(_,event,...)
  if event=="PLAYER_LOGIN" then
    BuildUI(); sys("Loaded. Type |cFFFFFF00/nrg|r or |cFFFFFF00/nips|r to open.")
    return
  elseif event=="CHAT_MSG_SYSTEM" then
    local msg = ...
    local n, r, mn, mx = msg:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)$")
    if n then
      n=trimRealm(n); r=tonumber(r); mn=tonumber(mn); mx=tonumber(mx)
      if state.mode=="HILO" then handleHiLoRoll(n,r,mn,mx) else handleDeathRoll(n,r,mn,mx) end
    end
    return
  end
  if state.phase=="JOINING" then
    local msg, author = ...
    local e=event
    local ok = (state.channel=="SAY" and e=="CHAT_MSG_SAY")
      or (state.channel=="PARTY" and (e=="CHAT_MSG_PARTY" or e=="CHAT_MSG_PARTY_LEADER"))
      or (state.channel=="RAID" and (e=="CHAT_MSG_RAID" or e=="CHAT_MSG_RAID_LEADER"))
      or (state.channel=="BATTLEGROUND" and (e=="CHAT_MSG_BATTLEGROUND" or e=="CHAT_MSG_BATTLEGROUND_LEADER"))
    if ok and strtrim(msg)=="1" then addJoiner(trimRealm(author)) end
  end
end)

evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("CHAT_MSG_SYSTEM")
evt:RegisterEvent("CHAT_MSG_SAY")
evt:RegisterEvent("CHAT_MSG_PARTY")
evt:RegisterEvent("CHAT_MSG_PARTY_LEADER")
evt:RegisterEvent("CHAT_MSG_RAID")
evt:RegisterEvent("CHAT_MSG_RAID_LEADER")
evt:RegisterEvent("CHAT_MSG_BATTLEGROUND")
evt:RegisterEvent("CHAT_MSG_BATTLEGROUND_LEADER")
