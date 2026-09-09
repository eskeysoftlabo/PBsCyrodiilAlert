-- Stub of just enough ESO client to exercise PBsCyrodiilAlert.
--
-- The interesting part is the keep table. It is modelled on what the client actually reports:
-- the same keep appears twice, once for the campaign you are standing in (BGQUERY_LOCAL) and
-- once for the campaign you are homed to (BGQUERY_ASSIGNED_CAMPAIGN), and only the local rows
-- are what the map in front of you draws. A build that forgot IsLocalBattlegroundContext would
-- alert twice for every siege here, and the tests say so.
--
-- The clock is ours, so a minute of siege costs no wall time.
local DIR = ADDON_DIR

-- ---- string table -------------------------------------------------------------------
local stringValues = {}
local nextId = 1
function ZO_CreateStringId(id, value) if not _G[id] then _G[id] = nextId; nextId = nextId + 1 end; stringValues[_G[id]] = value end
function SafeAddVersion() end
function SafeAddString(id, value) stringValues[id] = value end
function GetString(id, index)
	-- The client's own two shapes: GetString(SI_FOO) and GetString("SI_FOO", 2) -> SI_FOO2.
	if type(id) == "string" then
		local resolved = _G[id .. tostring(index)]
		return resolved and stringValues[resolved] or ""
	end
	return stringValues[id] or ("<missing " .. tostring(id) .. ">")
end

-- ---- enums --------------------------------------------------------------------------
-- Non-contiguous and out of order on purpose: nothing in the add-on may do arithmetic on them.
KEEPTYPE_KEEP = 3
KEEPTYPE_OUTPOST = 5
KEEPTYPE_TOWN = 9
KEEPTYPE_RESOURCE = 11
KEEPTYPE_BORDER_KEEP = 14
KEEPTYPE_ARTIFACT_KEEP = 17
KEEPTYPE_ARTIFACT_GATE = 19
KEEPTYPE_BRIDGE = 21
KEEPTYPE_MILEGATE = 23
KEEPTYPE_IMPERIAL_CITY_DISTRICT = 27

ALLIANCE_NONE = 0
ALLIANCE_ALDMERI_DOMINION = 1
ALLIANCE_EBONHEART_PACT = 2
ALLIANCE_DAGGERFALL_COVENANT = 3

local ALLIANCE_NAMES = {
	[ALLIANCE_ALDMERI_DOMINION] = "Aldmeri Dominion",
	[ALLIANCE_EBONHEART_PACT] = "Ebonheart Pact",
	[ALLIANCE_DAGGERFALL_COVENANT] = "Daggerfall Covenant",
}
function GetAllianceName(alliance) return ALLIANCE_NAMES[alliance] or "" end

BGQUERY_UNKNOWN = 0
BGQUERY_LOCAL = 1
BGQUERY_ASSIGNED_CAMPAIGN = 2
function IsLocalBattlegroundContext(bgContext) return bgContext == BGQUERY_LOCAL end
function IsAssignedBattlegroundContext(bgContext) return bgContext == BGQUERY_ASSIGNED_CAMPAIGN end

-- ---- objectives: the Daedric artifact and the scrolls -------------------------------
OBJECTIVE_DAEDRIC_WEAPON = 31
OBJECTIVE_ARTIFACT_OFFENSIVE, OBJECTIVE_ARTIFACT_DEFENSIVE = 32, 33
OBJECTIVE_CONTROL_STATE_UNKNOWN = 0
OBJECTIVE_CONTROL_STATE_FLAG_AT_BASE, OBJECTIVE_CONTROL_STATE_FLAG_HELD = 1, 2
OBJECTIVE_CONTROL_EVENT_FLAG_TAKEN = 11
OBJECTIVE_CONTROL_EVENT_CAPTURED = 12
OBJECTIVE_CONTROL_EVENT_FLAG_RETURNED = 13
OBJECTIVE_CONTROL_EVENT_FLAG_RETURNED_BY_TIMER = 14
OBJECTIVE_CONTROL_EVENT_FLAG_DROPPED = 15
OBJECTIVE_CONTROL_EVENT_LOST = 16
MAP_PIN_TYPE_AVA_DAEDRIC_ARTIFACT_VOLENDRUNG_ALDMERI = 101
MAP_PIN_TYPE_AVA_DAEDRIC_ARTIFACT_VOLENDRUNG_EBONHEART = 102
MAP_PIN_TYPE_AVA_DAEDRIC_ARTIFACT_VOLENDRUNG_DAGGERFALL = 103
MAP_PIN_TYPE_AVA_DAEDRIC_ARTIFACT_VOLENDRUNG_NEUTRAL = 104

local objectives = {}
function SetObjectives(list) objectives = list or {} end
function GetNumObjectives() return #objectives end
function GetObjectiveIdsForIndex(index)
	local o = objectives[index]
	if o then return o.keepId, o.objectiveId, o.bg end
end
local function FindObjective(keepId, objectiveId)
	for _, o in ipairs(objectives) do
		if o.keepId == keepId and o.objectiveId == objectiveId then return o end
	end
end
function GetObjectiveType(keepId, objectiveId) local o = FindObjective(keepId, objectiveId); return o and o.objectiveType end
function GetObjectiveInfo(keepId, objectiveId)
	local o = FindObjective(keepId, objectiveId)
	if not o then return "", nil, OBJECTIVE_CONTROL_STATE_UNKNOWN end
	return o.name, o.objectiveType, o.state
end
function GetObjectivePinInfo(keepId, objectiveId) local o = FindObjective(keepId, objectiveId); return o and o.pinType end
function IsCarryableObjectiveCarriedByLocalPlayer(keepId, objectiveId)
	local o = FindObjective(keepId, objectiveId)
	return o and o.mine or false
end

function IsInGamepadPreferredMode() return false end

EVENT_ARTIFACT_CONTROL_STATE = "EVENT_ARTIFACT_CONTROL_STATE"
-- What the client sends when a scroll changes hands.
function EmitScroll(controlEvent, artifactName, keepId, characterName, alliance, displayName)
	Fire(EVENT_ARTIFACT_CONTROL_STATE, artifactName, keepId, characterName, alliance, controlEvent,
		OBJECTIVE_CONTROL_STATE_FLAG_HELD, 7, displayName or ("@" .. tostring(characterName)))
end

EVENT_ADD_ON_LOADED = "EVENT_ADD_ON_LOADED"
EVENT_PLAYER_ACTIVATED = "EVENT_PLAYER_ACTIVATED"

-- ---- the clock ----------------------------------------------------------------------
local clockSeconds = 0
function GetGameTimeMilliseconds() return clockSeconds * 1000 end
function ClockSeconds() return clockSeconds end

-- ---- events and the update timer -----------------------------------------------------
local handlers = {}
-- Keyed by name: the add-on runs two of these (the campaign scan and the on-screen display's
-- expiry tick), and a stub that kept only the last one registered would silently stop the scan
-- the moment an alert reached the screen.
local updates = {}
local SCAN = "PBsCyrodiilAlert"
EVENT_MANAGER = {
	RegisterForEvent = function(_, name, event, fn) handlers[event] = handlers[event] or {}; handlers[event][name] = fn end,
	UnregisterForEvent = function(_, name, event) if handlers[event] then handlers[event][name] = nil end end,
	RegisterForUpdate = function(_, name, intervalMs, fn) updates[name] = { interval = intervalMs / 1000, fn = fn, last = clockSeconds } end,
	UnregisterForUpdate = function(_, name) updates[name] = nil end,
}
function Fire(event, ...) for _, fn in pairs(handlers[event] or {}) do fn(event, ...) end end
function TimerInterval() return updates[SCAN] and updates[SCAN].interval end
function TimerRunning() return updates[SCAN] ~= nil end
function UpdateRunning(name) return updates[name] ~= nil end

-- Move the clock forward one second at a time, running each registered callback whenever its
-- period has come round -- which is the only way the add-on ever gets to look at anything.
function Advance(seconds)
	for _ = 1, seconds do
		clockSeconds = clockSeconds + 1
		local due = {}
		for name, update in pairs(updates) do
			if clockSeconds - update.last >= update.interval then
				update.last = clockSeconds
				due[#due + 1] = update
			end
		end
		for _, update in ipairs(due) do update.fn() end
	end
end

-- ---- chat ---------------------------------------------------------------------------
Output = {}      -- everything the add-on said, on whichever surface
ChatOutput = {}  -- only what reached the chat window
function ClearOutput() Output = {}; ChatOutput = {} end
CHAT_ROUTER = {}
function CHAT_ROUTER:AddSystemMessage(text)
	Output[#Output + 1] = text
	ChatOutput[#ChatOutput + 1] = text
end
function ChatLines() return #ChatOutput end
function ChatSaid(needle)
	for _, line in ipairs(ChatOutput) do if Plain(line):find(needle, 1, true) then return true end end
	return false
end
function d(text) print("[d] " .. tostring(text)) end

-- Every line that came out, with the colour markup stripped, for readable assertions.
function Plain(text) return (tostring(text):gsub("|c%x%x%x%x%x%x", ""):gsub("|r", "")) end
function OutputText() local t = {} for i, line in ipairs(Output) do t[i] = Plain(line) end return table.concat(t, "\n") end
function Said(needle)
	for _, line in ipairs(Output) do if Plain(line):find(needle, 1, true) then return true end end
	return false
end
function Colour(needle)
	for _, line in ipairs(Output) do
		if Plain(line):find(needle, 1, true) then return line:match("^|c(%x%x%x%x%x%x)") end
	end
end
function Lines() return #Output end

-- ---- the world ----------------------------------------------------------------------
-- keeps[i] = { id, bg, keepType, name, alliance, attacked }
local keeps = {}
local playerAlliance = ALLIANCE_EBONHEART_PACT
local inAvA = true

function SetWorld(list) keeps = list or {} end
function SetPlayerAlliance(alliance) playerAlliance = alliance end
function SetInAvA(value) inAvA = value end

local function Find(id)
	for _, keep in ipairs(keeps) do if keep.id == id then return keep end end
end

-- Change one keep. Every row for that keep id changes together, exactly as the client's own
-- two campaign rows would.
function SetKeep(id, changes)
	for _, keep in ipairs(keeps) do
		if keep.id == id then
			for field, value in pairs(changes) do keep[field] = value end
		end
	end
end

function GetNumKeeps() return #keeps end
function GetKeepKeysByIndex(index) local keep = keeps[index]; if keep then return keep.id, keep.bg end end
function GetKeepType(id) local keep = Find(id); return keep and keep.keepType end
function GetKeepName(id) local keep = Find(id); return keep and keep.name or "" end
function GetKeepAlliance(id) local keep = Find(id); return keep and keep.alliance or ALLIANCE_NONE end
function GetKeepUnderAttack(id) local keep = Find(id); return keep and keep.attacked or false end
-- Siege weapons, per alliance. keep.sieges = { [alliance] = count }.
function GetNumSieges(id, bgContext, alliance)
	local keep = Find(id)
	return keep and keep.sieges and keep.sieges[alliance] or 0
end
-- The client only counts siege where there is a limit to count against, and the add-on has to
-- honour that gate: a resource with a siege count in this stub must still print none.
local SIEGE_LIMITED = {
	[KEEPTYPE_KEEP] = true, [KEEPTYPE_OUTPOST] = true,
	[KEEPTYPE_ARTIFACT_KEEP] = true, [KEEPTYPE_BORDER_KEEP] = true,
}
function DoesKeepTypeHaveSiegeLimit(keepType) return SIEGE_LIMITED[keepType] == true end
function GetUnitAlliance(unitTag) return unitTag == "player" and playerAlliance or ALLIANCE_NONE end
function IsInAvAZone() return inAvA end

-- ---- the campaign -------------------------------------------------------------------
-- The numbers the client's own scoreboard reads. campaignId 0 means "not in a campaign", which
-- is the case the summary has to survive by falling back to its own count.
NUM_ALLIANCES = 3
HOLDINGTYPE_KEEP, HOLDINGTYPE_OUTPOST, HOLDINGTYPE_RESOURCE = 1, 2, 3
local campaign = {
	id = 7,
	name = "Chalman",
	scores = { [ALLIANCE_ALDMERI_DOMINION] = 9000, [ALLIANCE_EBONHEART_PACT] = 12345, [ALLIANCE_DAGGERFALL_COVENANT] = 3000 },
	holdings = {
		[ALLIANCE_ALDMERI_DOMINION] = { [1] = 4, [2] = 1 },
		[ALLIANCE_EBONHEART_PACT] = { [1] = 6, [2] = 2 },
		[ALLIANCE_DAGGERFALL_COVENANT] = { [1] = 2, [2] = 0 },
	},
	emperor = nil,
}
function SetCampaign(changes)
	for field, value in pairs(changes or {}) do campaign[field] = value end
end
function GetCurrentCampaignId() return campaign.id end
-- The Imperial City has its own campaigns, and its own set of things worth counting.
function IsImperialCityCampaign(id) return campaign.imperialCity == true and id == campaign.id end
function IsInImperialCity() return campaign.imperialCity == true end
function GetCampaignName(id) return id == campaign.id and campaign.name or "" end
function GetCampaignAllianceScore(id, alliance)
	if id ~= campaign.id then return 0 end
	return campaign.scores[alliance] or 0
end
function GetTotalCampaignHoldings(id, holdingType, alliance)
	if id ~= campaign.id then return 0 end
	local row = campaign.holdings[alliance]
	return row and row[holdingType] or 0
end
function GetCampaignEmperorInfo(id)
	if id ~= campaign.id or not campaign.emperor then return ALLIANCE_NONE, "", "" end
	return campaign.emperor.alliance, campaign.emperor.name, "@" .. campaign.emperor.name
end
-- ---- campaign selection data (the population estimate) -------------------------------
-- The four buckets the campaign screen shows, and their client strings.
-- Deliberately NOT 0-based, and deliberately not matching the SI_CAMPAIGNPOPULATIONTYPE<n>
-- suffixes below. That mismatch is real -- measured on a live client, where every level came
-- out one too high -- and a build that goes back to deriving the string from the enum's number
-- reads "Medium" for CAMPAIGN_POP_LOW here and the tests say so.
CAMPAIGN_POP_LOW, CAMPAIGN_POP_MEDIUM, CAMPAIGN_POP_HIGH, CAMPAIGN_POP_FULL = 1, 2, 3, 4
ZO_CreateStringId("SI_CAMPAIGNPOPULATIONTYPE0", "Low")
ZO_CreateStringId("SI_CAMPAIGNPOPULATIONTYPE1", "Medium")
ZO_CreateStringId("SI_CAMPAIGNPOPULATIONTYPE2", "High")
ZO_CreateStringId("SI_CAMPAIGNPOPULATIONTYPE3", "Full")

EVENT_CAMPAIGN_SELECTION_DATA_CHANGED = "EVENT_CAMPAIGN_SELECTION_DATA_CHANGED"

-- The client's icon markup and its own population art. IconsBroken makes the getter fail, the
-- way a client that has moved the art would.
function zo_iconFormat(path, width, height)
	return string.format("|t%s:%s:%s|t", tostring(width), tostring(height), path)
end
IconsBroken = false
local POPULATION_ICONS = {
	[CAMPAIGN_POP_LOW] = "EsoUI/Art/Campaign/campaignBrowser_lowPop.dds",
	[CAMPAIGN_POP_MEDIUM] = "EsoUI/Art/Campaign/campaignBrowser_medPop.dds",
	[CAMPAIGN_POP_HIGH] = "EsoUI/Art/Campaign/campaignBrowser_hiPop.dds",
	[CAMPAIGN_POP_FULL] = "EsoUI/Art/Campaign/campaignBrowser_fullPop.dds",
}
function ZO_CampaignBrowser_GetPopulationIcon(population)
	if IconsBroken then return nil end
	return POPULATION_ICONS[population]
end

-- selection[i] = { id = campaignId, population = { [alliance] = CAMPAIGN_POP_* } }
local selection = {}
PopulationQueries = 0
function SetSelectionData(list) selection = list or {} end
function GetNumSelectionCampaigns() return #selection end
function GetSelectionCampaignId(index) local row = selection[index]; return row and row.id or 0 end
function GetSelectionCampaignPopulationData(index, alliance)
	local row = selection[index]
	return row and row.population and row.population[alliance]
end
-- Counts the requests, because the point of the rate limit is that there are almost none.
function QueryCampaignSelectionData() PopulationQueries = PopulationQueries + 1 end

function ZO_CommaDelimitNumber(value)
	local text = tostring(value)
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Alliance colours, as ZO_ColorDef:ToHex returns them: six lowercase hex digits.
local ALLIANCE_HEX = {
	[ALLIANCE_ALDMERI_DOMINION] = "ffd700",
	[ALLIANCE_EBONHEART_PACT] = "e2352d",
	[ALLIANCE_DAGGERFALL_COVENANT] = "3d90e2",
}
function GetAllianceColor(alliance)
	return { ToHex = function() return ALLIANCE_HEX[alliance] or "ffffff" end }
end

-- What the summary is showing, colour markup stripped.
function BoardText()
	local label = PBS_CYRODIIL_ALERT and PBS_CYRODIIL_ALERT.board.label
	if not label or not label.text then return "" end
	return Plain(label.text)
end
function BoardHidden()
	local window = PBS_CYRODIIL_ALERT and PBS_CYRODIIL_ALERT.board.window
	if not window then return true end
	return window.hidden
end
function BoardSaid(needle)
	return BoardText():find(needle, 1, true) ~= nil
end
function BoardColour(needle)
	local label = PBS_CYRODIIL_ALERT and PBS_CYRODIIL_ALERT.board.label
	local raw = label and label.text or ""
	for markup, body in raw:gmatch("|c(%x%x%x%x%x%x)([^|]*)") do
		if body:find(needle, 1, true) then return markup end
	end
end

-- ---- the window manager -------------------------------------------------------------
-- Enough of a control to answer the questions the on-screen display's tests ask: what text is
-- up, in what font, anchored where. Every setter records rather than draws.
TOP, CENTER, BOTTOM = "TOP", "CENTER", "BOTTOM"
TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = "left", "centre", "right"
TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM = "top", "bottom"
TEXT_WRAP_MODE_ELLIPSIS, TEXT_WRAP_MODE_TRUNCATE = "ellipsis", "truncate"
CT_LABEL, CT_BACKDROP = "label", "backdrop"
DL_OVERLAY, DL_CONTROLS, DL_BACKGROUND = "overlay", "controls", "background"
DT_HIGH, DT_MEDIUM, DT_LOW = "high", "medium", "low"

-- Set true to make SetDrawLayer/SetDrawTier throw, the way a client that refuses them would.
DrawOrderRefused = false
GuiRoot = { name = "GuiRoot" }

-- Set true to make CreateTopLevelWindow fail, the way a client without it would.
WindowManagerBroken = false

local function NewControl(name)
	local control = { name = name, anchors = {}, hidden = true }
	function control:SetDimensions(w, h) self.width, self.height = w, h end
	function control:SetMouseEnabled(value) self.mouseEnabled = value end
	function control:SetMovable(value) self.movable = value end
	function control:SetHidden(value) self.hidden = value end
	function control:IsHidden() return self.hidden end
	function control:ClearAnchors() self.anchors = {} end
	function control:SetAnchor(point, relativeTo, relativePoint, x, y)
		self.anchors[#self.anchors + 1] = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
	end
	function control:SetFont(font) self.font = font end
	function control:SetColor(r, g, b, a) self.colour = { r, g, b, a } end
	function control:SetText(text) self.text = text end
	function control:GetText() return self.text end
	function control:SetHorizontalAlignment(align) self.horizontal = align end
	function control:SetVerticalAlignment(align) self.vertical = align end
	function control:SetWrapMode(mode) self.wrapMode = mode end
	function control:SetMaxLineCount(count) self.maxLineCount = count end
	function control:SetCenterColor(r, g, b, a) self.colour = { r, g, b, a } end
	function control:SetEdgeColor(r, g, b, a) self.edgeColour = { r, g, b, a } end
	function control:SetDrawLayer(layer)
		if DrawOrderRefused then error("restricted") end
		self.drawLayer = layer
	end
	function control:SetDrawTier(tier)
		if DrawOrderRefused then error("restricted") end
		self.drawTier = tier
	end
	return control
end

WINDOW_MANAGER = {
	CreateTopLevelWindow = function(_, name)
		if WindowManagerBroken then error("no window manager") end
		return NewControl(name)
	end,
	CreateControl = function(_, name, parent, controlType)
		local control = NewControl(name)
		control.parent = parent
		control.controlType = controlType
		return control
	end,
}

-- What is on screen right now, with the colour markup stripped.
function HudText()
	local label = PBS_CYRODIIL_ALERT and PBS_CYRODIIL_ALERT.hud.label
	if not label or not label.text then return "" end
	return Plain(label.text)
end
function HudRaw()
	local label = PBS_CYRODIIL_ALERT and PBS_CYRODIIL_ALERT.hud.label
	return label and label.text or ""
end
function HudHidden()
	local window = PBS_CYRODIIL_ALERT and PBS_CYRODIIL_ALERT.hud.window
	if not window then return true end
	return window.hidden
end
function HudLines()
	return #(PBS_CYRODIIL_ALERT and PBS_CYRODIIL_ALERT.hud.lines or {})
end
-- The colour markup of the on-screen line containing this text.
function HudColour(needle)
	local raw = HudRaw()
    for markup, body in raw:gmatch("|c(%x%x%x%x%x%x)([^|]*)") do
		if body:find(needle, 1, true) then return markup end
	end
end

-- ---- add-on manager -----------------------------------------------------------------
function GetAddOnManager()
	return {
		GetNumAddOns = function() return 1 end,
		GetAddOnInfo = function(_, i) return "PBsCyrodiilAlert", "|cFF69B4PB's CyrodiilAlert|r 2.3.1" end,
	}
end

-- ---- saved variables ----------------------------------------------------------------
SavedStore = {}
local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = DeepCopy(v) end
	return out
end
ZO_SavedVars = {
	NewAccountWide = function(_, name, version, namespace, defaults)
		SavedStore[name] = SavedStore[name] or {}
		local store = SavedStore[name]
		for k, v in pairs(defaults or {}) do if store[k] == nil then store[k] = DeepCopy(v) end end
		return store
	end,
}

-- ---- the label controls the output window needs --------------------------------------
-- (SetWrapMode / SetMaxLineCount are recorded like every other setter, in NewControl above.)

-- ---- LibHarvensAddonSettings --------------------------------------------------------
PanelRows = {}
PanelUpdates = 0
LibHarvensAddonSettings = {
	ST_LABEL = "label", ST_SECTION = "section", ST_CHECKBOX = "checkbox",
	ST_SLIDER = "slider", ST_BUTTON = "button", ST_DROPDOWN = "dropdown",
	AddAddon = function(_, title)
		PanelTitle = title
		local panel = { title = title }
		function panel:AddSetting(row) PanelRows[#PanelRows + 1] = row end
		function panel:UpdateControls() PanelUpdates = PanelUpdates + 1 end
		return panel
	end,
}
function PanelRow(label)
	for _, row in ipairs(PanelRows) do
		if row.label == label then return row end
	end
end

-- Three rows are called "Under attack" -- the screen switch and the two colour dropdowns --
-- and in the panel the section heading above each is what tells them apart. So the tests
-- address them the same way a reader does: by the heading they sit under.
function PanelRowUnder(heading, label)
	local inSection = false
	for _, row in ipairs(PanelRows) do
		if row.type == LibHarvensAddonSettings.ST_SECTION then
			inSection = row.label == heading
		elseif inSection and row.label == label then
			return row
		end
	end
end

SLASH_COMMANDS = {}
function Slash(argumentString) SLASH_COMMANDS["/pbalert"](argumentString) end

-- ---- load the add-on ----------------------------------------------------------------
-- English strings only: jp.lua would win and the assertions below read better in English.
-- run.lua checks separately that jp.lua covers exactly the same keys.
dofile(DIR .. "/lang/strings.lua")
dofile(DIR .. "/Main.lua")
dofile(DIR .. "/Hud.lua")
dofile(DIR .. "/Settings.lua")

-- ---- what the add-on said, wherever it put it ---------------------------------------
-- Output is "everything the add-on said", not "everything that reached chat". Which surface a
-- line landed on is a question about one setting, and the assertions about wording, colour and
-- count should not have to know the answer. So a line taken by the output window is recorded
-- here too -- and one sent to both surfaces is recorded twice, because it was said twice.
do
	local realPush = PBS_CYRODIIL_ALERT.log.Push
	function PBS_CYRODIIL_ALERT.log:Push(text)
		local taken = realPush(self, text)
		if taken then
			Output[#Output + 1] = text
		end
		return taken
	end
end

-- The output window itself, for the assertions that are about the window.
function LogText()
	local label = PBS_CYRODIIL_ALERT.log.label
	if not label or not label.text then return "" end
	return Plain(label.text)
end
function LogLines() return #PBS_CYRODIIL_ALERT.log.lines end
function LogHidden()
	local window = PBS_CYRODIIL_ALERT.log.window
	if not window then return true end
	return window.hidden
end
function LogWindow() return PBS_CYRODIIL_ALERT.log.window end
function LogBackdrop() return PBS_CYRODIIL_ALERT.log.backdrop end
