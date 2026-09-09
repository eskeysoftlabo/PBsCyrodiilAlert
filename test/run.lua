-- Behavioural tests for PB's CyrodiilAlert.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload, boot
-- the PS5, log in, ride into Cyrodiil -- and then wait for somebody to attack the right keep.
-- The interesting cases (a siege that lasts past the repeat time, a keep that flips while it is
-- being hit) cannot be arranged on demand at all. harness.lua stubs the part of the client the
-- add-on actually touches -- the keep list, the alliances, the update timer and the clock --
-- so every one of those endings can be played out here in a few milliseconds.
--
--   lua test/run.lua        (from the add-on folder; any Lua 5.1+)

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."

local failures = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s got=%s want=%s", ok and "PASS" or "FAIL", label, tostring(got), tostring(want)))
end

-- Collect the keys a lang file defines without disturbing the live string table.
local function CollectStringKeys(path)
	local collected = {}
	local realCreate = ZO_CreateStringId
	local realVersion = SafeAddVersion
	ZO_CreateStringId = function(id) collected[id] = true end
	SafeAddVersion = function() end
	dofile(path)
	ZO_CreateStringId = realCreate
	SafeAddVersion = realVersion
	return collected
end

dofile(HERE .. "/harness.lua")

local CHALMAN, ARRIUS, VLASTARUS, MINE, BRIDGE = 11, 12, 20, 31, 40
local EP, AD, DC = ALLIANCE_EBONHEART_PACT, ALLIANCE_ALDMERI_DOMINION, ALLIANCE_DAGGERFALL_COVENANT

-- Deliberately shuffled, and Chalman appears twice: once in the campaign the player is standing
-- in and once in the campaign they are homed to, which is what the client really reports.
local function FreshWorld()
	return {
		{ id = ARRIUS, bg = BGQUERY_LOCAL, keepType = KEEPTYPE_KEEP, name = "Arrius Keep", alliance = AD, attacked = false },
		{ id = CHALMAN, bg = BGQUERY_ASSIGNED_CAMPAIGN, keepType = KEEPTYPE_KEEP, name = "Chalman Keep", alliance = EP, attacked = false },
		{ id = BRIDGE, bg = BGQUERY_LOCAL, keepType = KEEPTYPE_BRIDGE, name = "Alessia Bridge", alliance = EP, attacked = false },
		{ id = CHALMAN, bg = BGQUERY_LOCAL, keepType = KEEPTYPE_KEEP, name = "Chalman Keep", alliance = EP, attacked = false },
		{ id = MINE, bg = BGQUERY_LOCAL, keepType = KEEPTYPE_RESOURCE, name = "Chalman Mine", alliance = EP, attacked = false },
		{ id = VLASTARUS, bg = BGQUERY_LOCAL, keepType = KEEPTYPE_TOWN, name = "Vlastarus", alliance = EP, attacked = false },
	}
end

local addon

local function WatchCount()
	local count = 0
	for _ in pairs(addon.watch) do count = count + 1 end
	return count
end

-- Back to a world nobody is attacking, with the settings as they shipped.
local function ResetWorld()
	SetWorld(FreshWorld())
	SetPlayerAlliance(EP)
	SetInAvA(true)
	Slash("reset")
	Advance(5)
	ClearOutput()
end

print("\n== 1. load ==")
Fire(EVENT_ADD_ON_LOADED, "PBsCyrodiilAlert")
addon = PBS_CYRODIIL_ALERT
check("version read from manifest", addon.version, "2.3.1")
check("slash command registered", type(SLASH_COMMANDS["/pbalert"]), "function")
check("short slash registered", type(SLASH_COMMANDS["/pbca"]), "function")
check("no timer before the world exists", TimerRunning(), false)
check("nothing said at load", Lines(), 0)

print("\n== 2. the world comes up ==")
SetWorld(FreshWorld())
Fire(EVENT_PLAYER_ACTIVATED)
check("timer running", TimerRunning(), true)
check("timer period is the default 5 s", TimerInterval(), 5)
check("no login banner by default", Lines(), 0)
check("panel rows built", #PanelRows, 79)
check("interval slider is on the panel", PanelRow("Check every").max, 60)
check("quiet world says nothing", (Advance(20) or Lines()), 0)

print("\n== 3. a keep of ours comes under attack ==")
ClearOutput()
SetKeep(CHALMAN, { attacked = true })
Advance(5)
check("one line, not one per campaign row", Lines(), 1)
check("names the keep", Said("Chalman Keep"), true)
check("says what kind of holding it is", Said("[Keep]"), true)
check("in red", Colour("Chalman Keep"), "FF4040")
check("one holding being watched", WatchCount(), 1)

print("\n== 4. a siege that goes on ==")
ClearOutput()
Advance(55)
check("silent inside the repeat window", Lines(), 0)
Advance(5)
check("said again once the minute is up", Lines(), 1)
check("still-under-attack wording", Said("still under attack"), true)
check("with how long it has been going", Said("1:00"), true)
check("still red", Colour("still under attack"), "FF4040")

print("\n== 5. the attack is beaten off ==")
ClearOutput()
SetKeep(CHALMAN, { attacked = false })
Advance(5)
check("one line", Lines(), 1)
check("held wording", Said("still ours"), true)
check("in blue", Colour("still ours"), "66B0FF")
check("nothing left to watch", WatchCount(), 0)
ClearOutput()
Advance(30)
check("and it stays quiet afterwards", Lines(), 0)

print("\n== 6. the keep is lost ==")
ClearOutput()
SetKeep(CHALMAN, { attacked = true })
Advance(5)
check("attack alerted", Said("is under attack"), true)
ClearOutput()
-- Flipped, and still under attack -- our side is already hitting it back. The ending has to be
-- read off the owner, not off the attack flag.
SetKeep(CHALMAN, { alliance = AD })
Advance(5)
check("one line", Lines(), 1)
check("lost wording", Said("has been taken"), true)
check("names who took it", Said("Aldmeri Dominion"), true)
check("in yellow", Colour("has been taken"), "FFC820")
check("nothing left to watch", WatchCount(), 0)
ClearOutput()
Advance(120)
check("an enemy keep under attack is not our business", Lines(), 0)

print("\n== 7. only our own holdings ==")
ResetWorld()
SetKeep(ARRIUS, { attacked = true })
Advance(10)
check("an enemy keep under attack says nothing", Lines(), 0)
SetKeep(BRIDGE, { attacked = true })
Advance(10)
check("a bridge says nothing, ours or not", Lines(), 0)

print("\n== 8. which kinds are watched ==")
ResetWorld()
SetKeep(MINE, { attacked = true })
Advance(10)
check("resources are off by default", Lines(), 0)
Slash("resources on")
ClearOutput()
Advance(10)
check("and alert once switched on", Said("Chalman Mine"), true)
check("named as a resource", Said("[Resource]"), true)
ResetWorld()
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
check("towns are on by default", Said("Vlastarus"), true)
check("named as a town", Said("[Town]"), true)

print("\n== 9. leaving and re-entering the campaign ==")
ResetWorld()
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
check("attack alerted", Said("Vlastarus"), true)
ClearOutput()
SetInAvA(false)
Advance(10)
check("no ending is invented on the way out", Lines(), 0)
check("and nothing is left being watched", WatchCount(), 0)
SetInAvA(true)
Advance(10)
check("coming back re-reads the fight that is still on", Said("Vlastarus"), true)

print("\n== 10. attacks already in progress when you arrive ==")
ResetWorld()
Slash("existing off")
Slash("forget")
SetKeep(VLASTARUS, { attacked = true })
ClearOutput()
Advance(10)
check("the first pass records it silently", Lines(), 0)
check("but it is being watched", WatchCount(), 1)
Advance(55)
check("and the repeat still reports it", Said("still under attack"), true)

print("\n== 11. the settings that change the timer ==")
ResetWorld()
Slash("every 10")
check("interval taken", addon.sv.intervalSeconds, 10)
check("timer re-registered with it", TimerInterval(), 10)
ClearOutput()
Slash("every 999")
check("out-of-range interval refused", Said("between 1 and 60"), true)
check("and the old one kept", TimerInterval(), 10)
Slash("repeat 120")
check("repeat taken", addon.sv.repeatSeconds, 120)
ClearOutput()
Slash("repeat 3")
check("out-of-range repeat refused", Said("between 15 and 600"), true)
check("and the old one kept", addon:RepeatSeconds(), 120)

print("\n== 12. the master switch ==")
ResetWorld()
Slash("off")
check("timer stopped", TimerRunning(), false)
SetKeep(VLASTARUS, { attacked = true })
ClearOutput()
Advance(60)
check("and nothing is said while it is off", Lines(), 0)
ClearOutput()
Slash("on")
check("timer running again", TimerRunning(), true)
-- Switching back on prints the status, and the status is produced by running a real pass --
-- so the attack that was going on unwatched is reported there and then, before the next tick.
check("and the standing attack is picked up at once", Said("Vlastarus"), true)

print("\n== 13. the list, which is the instrument ==")
ResetWorld()
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
ClearOutput()
Slash("list")
check("counts what the client reported", Said("6 holdings reported"), true)
check("counts this campaign only", Said("5 in this campaign"), true)
check("lists a watched holding with its owner", Said("Ebonheart Pact"), true)
check("and marks the one under attack", Said("UNDER ATTACK"), true)
check("a resource is not listed while it is switched off", Said("Chalman Mine"), false)

print("\n== 14. status ==")
ClearOutput()
Slash("")
check("says the build", Said("PB\u{2019}s CyrodiilAlert 2.3.1"), true)
check("says the period", Said("watching every 5 s"), true)
check("says what it watches", Said("Keeps and outposts, Towns"), true)
check("says your alliance", Said("your alliance: Ebonheart Pact"), true)
check("counts the alerts it has given", Said("alerts this session"), true)
check("says whether enemy holdings are reported", Said("fights at enemy holdings: off"), true)

print("\n== 15. fights at enemy holdings ==")
ResetWorld()
SetKeep(ARRIUS, { attacked = true })
Advance(10)
check("an enemy keep says nothing by default", Lines(), 0)
Slash("offense on")
-- Switched on, fights are still filtered to the ones our own siege is at. Section 17 is that
-- filter; this section is what it filters, so it is taken off here.
check("the siege filter is on out of the box", addon.sv.offenseOursOnly, true)
Slash("offense ours off")
ClearOutput()
Advance(10)
check("one line once switched on", Lines(), 1)
check("names the enemy keep", Said("Arrius Keep"), true)
check("and who holds it", Said("Aldmeri Dominion"), true)
-- The client never says who is attacking, so neither does the line.
check("says a fight started, not that we started it", Said("a fight has started"), true)
check("in green", Colour("a fight has started"), "5CD65C")
ClearOutput()
Advance(60)
check("a long fight is said again", Said("the fight is still going"), true)
ClearOutput()
SetKeep(ARRIUS, { attacked = false })
Advance(10)
check("a fight that ends with nothing changing is not news", Lines(), 0)
check("and nothing is left being watched", WatchCount(), 0)
SetKeep(ARRIUS, { attacked = true })
Advance(10)
ClearOutput()
SetKeep(ARRIUS, { alliance = EP })
Advance(10)
-- Two lines, and both are wanted: we took it, and the side that lost it is already hitting it
-- back -- which makes it a holding of ours under attack, on the very next pass.
check("but taking it is", Lines(), 2)
check("taken wording", Said("is ours"), true)
check("in blue, like any good ending", Colour("is ours"), "66B0FF")
check("and it is immediately a keep of ours under attack", Said("is under attack"), true)
check("in red", Colour("is under attack"), "FF4040")
ClearOutput()
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
check("our own holdings still alert while offense is on", Colour("Vlastarus"), "FF4040")
SetKeep(ARRIUS, { alliance = AD, attacked = true })
Advance(10)
ClearOutput()
Slash("offense off")
ClearOutput()
SetKeep(ARRIUS, { alliance = EP })
Advance(10)
-- The entry made while offense was on must not survive to produce a "taken" line after it was
-- switched off. Arrius is named all the same -- it is ours now, and it is being attacked.
check("no taken line from an entry made before it was switched off", Said("is ours"), false)
check("it is simply one of ours under attack now", Colour("Arrius Keep"), "FF4040")

print("\n== 16. the siege count, which is the only hint about who ==")
ResetWorld()
Slash("offense on")
SetKeep(ARRIUS, { attacked = true, sieges = { [EP] = 2 } })
ClearOutput()
Advance(10)
check("our own siege at an enemy keep is reported", Said("your alliance has 2 siege"), true)
ClearOutput()
Slash("list")
check("and the list prints it too", Said("your siege: 2"), true)
ResetWorld()
Slash("offense on")
Slash("offense ours off")
Slash("resources on")
-- A resource has no siege limit, so the client has no count to give. The add-on must not
-- print one even when a stub offers it.
SetKeep(MINE, { alliance = AD, attacked = true, sieges = { [EP] = 3 } })
ClearOutput()
Advance(10)
check("a resource still alerts", Said("Chalman Mine"), true)
check("but carries no siege count", Said("siege"), false)

print("\n== 17. only where our own siege is standing ==")
ResetWorld()
Slash("offense on")
check("on by default", addon.sv.offenseOursOnly, true)
SetKeep(ARRIUS, { attacked = true })
ClearOutput()
Advance(10)
-- Nobody of ours is sieging it: this is somebody else's fight, and it is not reported.
check("a fight with no siege of ours is not ours", Lines(), 0)
check("but it is being watched", WatchCount(), 1)

-- Our siege goes up while the fight is already running. That is the moment it becomes a push
-- of ours, and it is said then -- as a beginning, because for us it is one.
SetKeep(ARRIUS, { sieges = { [EP] = 3 } })
Advance(10)
-- With our siege up, the line that goes out is the one that carries the count -- which is the
-- whole reason the filter let it through.
check("said the moment our siege is up", Said("Arrius Keep"), true)
check("with the count", Said("your alliance has 3 siege"), true)
check("in green", Colour("your alliance has 3 siege"), "5CD65C")
ClearOutput()
Advance(60)
check("and it repeats like any other", Said("the fight is still going"), true)

-- Taking it is reported whether or not the fight was ever ours to report.
ResetWorld()
Slash("offense on")
SetKeep(ARRIUS, { attacked = true })
Advance(10)
ClearOutput()
check("nothing said about the fight", Lines(), 0)
SetKeep(ARRIUS, { alliance = EP })
Advance(10)
check("but taking it still is", Said("is ours"), true)

-- A resource has no siege limit, so the client has no count for it and the filter can never be
-- satisfied there. That is a real cost of the setting, and it is a tested one.
ResetWorld()
Slash("offense on")
Slash("resources on")
SetKeep(MINE, { alliance = AD, attacked = true, sieges = { [EP] = 3 } })
ClearOutput()
Advance(10)
check("a holding with no siege count never passes the filter", Lines(), 0)
Slash("offense ours off")
Slash("forget")
ClearOutput()
Advance(10)
check("and reports again once the filter is off", Said("Chalman Mine"), true)

-- Our own holdings are not affected by any of this.
ResetWorld()
Slash("offense on")
SetKeep(VLASTARUS, { attacked = true })
ClearOutput()
Advance(10)
check("our own keeps alert with no siege of ours anywhere", Colour("Vlastarus"), "FF4040")

print("\n== 18. a client with no window manager ==")
-- Everything on screen is optional, and none of it may take the chat side down with it.
ResetWorld()
WindowManagerBroken = true
Slash("hud on")
ClearOutput()
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
check("chat still gets the alert", Said("Vlastarus"), true)
check("nothing is drawn", HudLines(), 0)
check("and the status says so", addon.hud:Available(), false)
ClearOutput()
Slash("")
check("out loud", Said("could not be created"), true)
WindowManagerBroken = false
addon.hud.failed = false

print("\n== 19. the on-screen display ==")
ResetWorld()
check("off by default", addon.sv.hud.enabled, false)
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
check("so nothing is drawn", HudLines(), 0)

ResetWorld()
Slash("hud on")
SetKeep(VLASTARUS, { attacked = true })
ClearOutput()
Advance(10)
check("the alert is drawn", HudLines(), 1)
check("shortened for a glance", HudText(), "UNDER ATTACK: [Town] Vlastarus")
check("chat still gets the long form", Said("is under attack!"), true)
check("the window is showing", HudHidden(), false)
check("in the attack colour", HudColour("Vlastarus"), "FF4040")

-- held is not on the screen list by default, so the ending is chat-only.
ClearOutput()
SetKeep(VLASTARUS, { attacked = false })
Advance(10)
check("an alert not on the screen list stays in chat", Said("still ours"), true)
check("and is not drawn", HudText():find("HELD", 1, true), nil)
Slash("hud held on")
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
SetKeep(VLASTARUS, { attacked = false })
Advance(10)
check("until it is switched on", HudText():find("HELD", 1, true) ~= nil, true)

print("\n== 20. lines expire, and no more than three are up ==")
ResetWorld()
Slash("hud on")
Slash("hud lost on")
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
check("one line", HudLines(), 1)
Advance(6)
check("gone once its time is up", HudLines(), 0)
check("and the window is hidden again", HudHidden(), true)
check("the expiry timer stops with it", UpdateRunning("PBsCyrodiilAlertHUDUpdate"), false)
ResetWorld()
Slash("hud on")
addon.hud:Push("attack", "one")
addon.hud:Push("attack", "two")
addon.hud:Push("attack", "three")
addon.hud:Push("attack", "four")
check("never more than three at once", HudLines(), 3)
check("and it is the oldest that goes", HudText():find("one", 1, true), nil)
check("newest kept", HudText():find("four", 1, true) ~= nil, true)

print("\n== 21. the look is settable ==")
ResetWorld()
Slash("hud on")
addon.hud:Push("attack", "sample")
check("default font descriptor", addon.hud.label.font, "$(BOLD_FONT)|32|soft-shadow-thick")
check("anchored below the compass", addon.hud.window.anchors[1].point, "TOP")
check("by the default offset", addon.hud.window.anchors[1].y, 220)
PanelRow("Typeface").setFunction(nil, nil, { data = "$(GAMEPAD_BOLD_FONT)" })
PanelRow("Size").setFunction(48)
PanelRow("Outline").setFunction(nil, nil, { data = "thick-outline" })
check("the panel rebuilds the descriptor", addon.hud.label.font, "$(GAMEPAD_BOLD_FONT)|48|thick-outline")
PanelRow("Position").setFunction(nil, nil, { data = "BOTTOM" })
PanelRow("Move sideways").setFunction(-120)
PanelRow("Move up or down").setFunction(-60)
check("and the position", addon.hud.window.anchors[1].point, "BOTTOM")
check("with both offsets", addon.hud.window.anchors[1].x, -120)
check("applied", addon.hud.window.anchors[1].y, -60)
check("the dropdown reads the stored face back", PanelRow("Typeface").getFunction(), "Gamepad bold")
-- Nonsense in the saved variables must not reach SetFont.
addon.sv.hud.face = "$(HANDWRITTEN_FONT)"
addon.sv.hud.size = 9999
check("an unknown face falls back", addon.hud:Face(), "$(BOLD_FONT)")
check("an absurd size is clamped", addon.hud:Size(), 64)

print("\n== 22. colours, per alert and per surface ==")
ResetWorld()
Slash("hud on")
-- Out of the box there is one set of colours: recolour it for chat and the screen follows.
check("the screen follows chat to begin with", addon.sv.hudFollowsChatColours, true)
Slash("colour attack chat gold")
SetKeep(VLASTARUS, { attacked = true })
ClearOutput()
Advance(10)
check("chat takes the new colour", Colour("Vlastarus"), "FFC820")
check("and the screen follows it", HudColour("Vlastarus"), "FFC820")
check("the screen row shows what is really drawn",
	PanelRowUnder("Colours on screen", "Under attack").getFunction(), "Gold")

-- Choosing a colour for the screen is how you ask for the two to differ.
ClearOutput()
Slash("colour attack hud green")
check("which is said out loud", Said("the screen now has its own colours"), true)
check("and recorded", addon.sv.hudFollowsChatColours, false)
Slash("forget")
ClearOutput()
Advance(10)
check("the screen takes the new colour", HudColour("Vlastarus"), "5CD65C")
check("and chat keeps its own", Colour("Vlastarus"), "FFC820")

-- Back to one set, and the screen goes back to chat's.
Slash("colour follow on")
Slash("forget")
ClearOutput()
Advance(10)
check("following again", HudColour("Vlastarus"), "FFC820")
check("without forgetting the screen's own choice",
	addon.sv.colours.hud.attack, "5CD65C")
Slash("colour follow off")
Slash("forget")
ClearOutput()
Advance(10)
check("which comes back when it is asked for", HudColour("Vlastarus"), "5CD65C")
Slash("colour attack chat red")
Slash("colour attack chat FF00FF")
Slash("forget")
ClearOutput()
Advance(10)
check("chat can be recoloured separately", Colour("Vlastarus"), "FF00FF")
check("with a raw hex code", addon:Colour("chat", "attack"), "FF00FF")
ClearOutput()
Slash("colour attack chat mauve")
check("a colour that is not one is refused", Said("say a colour name"), true)
check("and nothing is changed", addon:Colour("chat", "attack"), "FF00FF")
ClearOutput()
Slash("colour bogus chat red")
check("so is an alert that is not one", Said("no such alert"), true)
ClearOutput()
Slash("colour attack elsewhere red")
check("and a surface that is not one", Said("say chat or hud"), true)
check("the screen colour dropdown names its shade",
	PanelRowUnder("Colours on screen", "Under attack").getFunction(), "Green")
check("the chat one shows the raw hex it was given",
	PanelRowUnder("Colours in chat", "Under attack").getFunction(), "FF00FF")
check("the follow switch reads back", PanelRow("Use the chat colours on screen too").getFunction(), false)
check("and the screen switch of the same name is untouched",
	PanelRowUnder("On screen", "Under attack").getFunction(), true)
Slash("reset")
check("reset puts the colours back", addon:Colour("chat", "attack"), "FF4040")
check("on both surfaces", addon:Colour("hud", "attack"), "FF4040")
check("and the screen follows chat again", addon.sv.hudFollowsChatColours, true)

print("\n== 23. the test display ==")
ResetWorld()
Slash("hud on")
ClearOutput()
local beforeTest = addon.alerted.attack
Slash("test")
check("one chat line per alert, plus the note", Lines(), 7)
check("named so it cannot be mistaken for a real one", Said("Test Keep"), true)
-- attack and lost are the two on the screen list by default.
check("only the alerts on the screen list are drawn", HudLines(), 2)
check("and it does not count as a real alert", addon.alerted.attack, beforeTest)

print("\n== 24. the campaign summary ==")
ResetWorld()
check("off by default", addon.sv.board.enabled, false)
Advance(10)
check("so nothing is drawn", BoardHidden(), true)

Slash("board on")
Advance(10)
check("the summary is up", BoardHidden(), false)
check("named after the campaign", BoardSaid("Chalman"), true)
-- 6 keeps + 2 outposts, from the client's own holdings count rather than our own tally.
check("holdings from the campaign", BoardSaid("Ebonheart Pact  keeps 8"), true)
check("with the score", BoardSaid("score 12,345"), true)
check("your own alliance is marked", BoardSaid("> Ebonheart Pact"), true)
check("and the others are not", BoardSaid("> Aldmeri"), false)
-- Normalised to upper case on the way in, like every other colour the add-on stores.
check("each line in its alliance's colour", BoardColour("Ebonheart Pact"), "E2352D")
-- Score order, so the alliance in front is the top line.
check("ordered by score", BoardText():find("Ebonheart") < BoardText():find("Aldmeri"), true)

-- The under-attack column is ours: no API answers it, so it comes off the same pass.
SetKeep(ARRIUS, { attacked = true })
Advance(10)
check("counts what is being fought over", BoardSaid("Aldmeri Dominion  keeps 5  score 9,000  under attack 1"), true)
SetKeep(ARRIUS, { attacked = false })
Advance(10)
-- The column stays, at zero. A number that disappears has to be read before it can be counted.
check("and goes back to zero when the fighting stops",
	BoardSaid("Aldmeri Dominion  keeps 5  score 9,000  under attack 0"), true)
check("on every line, always", BoardSaid("Daggerfall Covenant  keeps 2  score 3,000  under attack 0"), true)

SetCampaign({ emperor = { alliance = AD, name = "Someone" } })
Advance(10)
check("an emperor is named", BoardSaid("Emperor: Someone (Aldmeri Dominion)"), true)
SetCampaign({ emperor = nil })

print("\n== 25. the summary when the campaign is not there ==")
SetCampaign({ id = 0 })
Advance(10)
-- No campaign: holdings fall back to the add-on's own count of the keep list, score to a dash.
check("still drawn from our own count", BoardSaid("keeps"), true)
check("with no score to show", BoardSaid("score -"), true)
SetCampaign({ id = 7 })

SetInAvA(false)
Advance(10)
check("out of Cyrodiil it takes itself down", BoardHidden(), true)
SetInAvA(true)
Advance(10)
check("and comes back", BoardHidden(), false)

Slash("off")
check("the master switch takes it with it", BoardHidden(), true)
Slash("on")
Advance(10)
check("and brings it back", BoardHidden(), false)

-- Switching every kind of holding off silences the alerts; it must not blank the summary,
-- which is a different question.
Slash("keeps off")
Slash("towns off")
Advance(10)
check("no alert kinds left, summary still counted", BoardSaid("Chalman"), true)

print("\n== 26. how busy each alliance is ==")
ResetWorld()
Slash("board on")
-- A fresh session, so far as the population data is concerned.
SetSelectionData({})
PopulationQueries = 0
addon.lastPopulationQuery = nil

Advance(10)
check("unknown reads as a dash", BoardSaid("pop -"), true)
check("and the server is asked", PopulationQueries, 1)
Advance(240)
check("but not again for a good while", PopulationQueries, 1)
Advance(120)
check("and only then a second time", PopulationQueries, 2)

-- The answer. It is indexed by selection index, not campaign id, so the right campaign has to
-- be picked out of the list -- and there is more than one in it.
SetSelectionData({
	{ id = 3, population = { [AD] = CAMPAIGN_POP_LOW, [EP] = CAMPAIGN_POP_LOW, [DC] = CAMPAIGN_POP_LOW } },
	{ id = 7, population = { [AD] = CAMPAIGN_POP_HIGH, [EP] = CAMPAIGN_POP_MEDIUM, [DC] = CAMPAIGN_POP_FULL } },
})
Fire(EVENT_CAMPAIGN_SELECTION_DATA_CHANGED)
-- Drawn as the game's own campaign-browser icon, not as a word.
check("the answer redraws the summary at once", BoardSaid("campaignBrowser_medPop.dds"), true)
check("as an icon, per alliance",
	BoardSaid("Aldmeri Dominion  keeps 5  score 9,000  under attack 0  pop |t100%:100%:EsoUI/Art/Campaign/campaignBrowser_hiPop.dds|t"), true)
check("all three of them", BoardSaid("campaignBrowser_fullPop.dds"), true)
check("and it is this campaign's row, not the other one", BoardSaid("campaignBrowser_lowPop.dds"), false)

-- The word is one setting away, for anyone who would rather read it. Every level is named
-- here: the enum's numbers do not line up with the string suffixes, so each one is a chance to
-- be off by one, and off by one is what a live client showed.
Slash("board pop text")
check("Medium reads as Medium", BoardSaid("Ebonheart Pact  keeps 8  score 12,345  under attack 0  pop Medium"), true)
check("High as High", BoardSaid("Aldmeri Dominion  keeps 5  score 9,000  under attack 0  pop High"), true)
check("Full as Full", BoardSaid("Daggerfall Covenant  keeps 2  score 3,000  under attack 0  pop Full"), true)
Slash("board pop icon")
check("and back to the icon", BoardSaid("campaignBrowser_medPop.dds"), true)

-- The client's getter is asked first, but the add-on knows the paths itself, so a client that
-- has dropped the getter still gets an icon.
IconsBroken = true
Fire(EVENT_CAMPAIGN_SELECTION_DATA_CHANGED)
check("a missing getter still draws the icon", BoardSaid("campaignBrowser_medPop.dds"), true)
IconsBroken = false

-- With no way to build the markup at all, the word rather than a blank column.
local realIconFormat = zo_iconFormat
zo_iconFormat = nil
Fire(EVENT_CAMPAIGN_SELECTION_DATA_CHANGED)
check("and no markup at all falls back to the word", BoardSaid("pop Medium"), true)
zo_iconFormat = realIconFormat
Fire(EVENT_CAMPAIGN_SELECTION_DATA_CHANGED)
ClearOutput()
Slash("board pop sideways")
check("a word that is neither is refused", Said("say icon or text"), true)
-- On a console the campaign screen the player came through is the gamepad one, and it uses a
-- different set of art. The summary should match what they saw.
local realMode = IsInGamepadPreferredMode
IsInGamepadPreferredMode = function() return true end
Fire(EVENT_CAMPAIGN_SELECTION_DATA_CHANGED)
check("gamepad art in gamepad mode", BoardSaid("EsoUI/Art/AvA/Gamepad/Server_One.dds"), true)
IsInGamepadPreferredMode = realMode
Fire(EVENT_CAMPAIGN_SELECTION_DATA_CHANGED)
check("and the keyboard art otherwise", BoardSaid("campaignBrowser_medPop.dds"), true)

local answered = PopulationQueries
Advance(600)
check("nothing is asked for once it is known", PopulationQueries, answered)
SetSelectionData({})

print("\n== 27. the summary is placed like the alerts ==")
ResetWorld()
Slash("board on")
Advance(10)
check("its own default corner", addon.board.window.anchors[1].point, "TOPLEFT")
check("its own default size", addon.board.label.font, "$(BOLD_FONT)|22|soft-shadow-thick")
PanelRow("Summary position").setFunction(nil, nil, { data = "TOPRIGHT" })
PanelRow("Move the summary sideways").setFunction(-40)
PanelRow("Move the summary up or down").setFunction(200)
PanelRow("Summary size").setFunction(18)
check("position follows the panel", addon.board.window.anchors[1].point, "TOPRIGHT")
check("with its offsets", addon.board.window.anchors[1].x, -40)
check("both of them", addon.board.window.anchors[1].y, 200)
check("and its own size", addon.board.label.font, "$(BOLD_FONT)|18|soft-shadow-thick")
-- The typeface is shared with the alerts on purpose.
PanelRow("Typeface").setFunction(nil, nil, { data = "$(MEDIUM_FONT)" })
check("typeface follows the alert display", addon.board.label.font, "$(MEDIUM_FONT)|18|soft-shadow-thick")
-- The draw order, which is what decides who covers whom when the corner is contested.
check("in front of everything to begin with", addon.board.window.drawLayer, "overlay")
check("on the top tier", addon.board.window.drawTier, "high")
Slash("board back")
check("moved behind everything", addon.board.window.drawLayer, "background")
check("and to the bottom tier", addon.board.window.drawTier, "low")
Slash("board normal")
check("or to an ordinary control's place", addon.board.window.drawLayer, "controls")
check("in the middle tier", addon.board.window.drawTier, "medium")
check("the panel dropdown agrees", PanelRow("Summary draw order").getFunction(), "Normal")
PanelRow("Summary draw order").setFunction(nil, nil, { data = "FRONT" })
check("and can set it back", addon.board.window.drawLayer, "overlay")
-- The alerts are not moved by any of this; only the summary has the setting.
check("the alert display stays in front", addon.hud.window == nil or addon.hud.window.drawLayer, "overlay")
ClearOutput()
Slash("board sideways")
check("a word that is neither says so", Said("say front, normal or back"), true)

-- A client that refuses the call must leave a working summary and say what happened.
DrawOrderRefused = true
ClearOutput()
Slash("board back")
check("the refusal is reported", Said("refused the draw order"), true)
check("and the summary still draws", BoardHidden(), false)
DrawOrderRefused = false
Slash("board front")

Slash("reset")
check("reset puts the summary back", addon.board:Position(), "TOPLEFT")
check("including the draw order", addon.board:Draw(), "FRONT")

print("\n== 28. the summary in chat ==")
ResetWorld()
Advance(10)
ClearOutput()
Slash("board")
check("printed on demand", Said("Ebonheart Pact  keeps 8"), true)
check("without switching the screen one on", addon.sv.board.enabled, false)

print("\n== 29. Elder Scrolls, the one thing that comes with a name ==")
ResetWorld()
check("on by default", addon.sv.scrolls, true)
ClearOutput()
EmitScroll(OBJECTIVE_CONTROL_EVENT_FLAG_TAKEN, "Ghartok", CHALMAN, "Someone", AD)
check("one line", Lines(), 1)
check("names the player", Said("Someone"), true)
check("their alliance", Said("Aldmeri Dominion"), true)
check("the scroll", Said("Ghartok"), true)
check("and where it was taken from", Said("Chalman Keep"), true)
check("in the scroll colour", Colour("Ghartok"), "C08CFF")

-- keepId 0 is how the client says "off the ground", not "out of a keep".
ClearOutput()
EmitScroll(OBJECTIVE_CONTROL_EVENT_FLAG_TAKEN, "Ghartok", 0, "Someone", AD)
check("picked up off the ground reads differently", Said("has picked up"), true)
check("and names no keep", Said("from"), false)

ClearOutput()
EmitScroll(OBJECTIVE_CONTROL_EVENT_CAPTURED, "Ghartok", VLASTARUS, "Someone", EP)
check("captured", Said("has captured"), true)
ClearOutput()
EmitScroll(OBJECTIVE_CONTROL_EVENT_FLAG_RETURNED, "Ghartok", VLASTARUS, "Someone", EP)
check("returned", Said("has returned"), true)
ClearOutput()
EmitScroll(OBJECTIVE_CONTROL_EVENT_FLAG_DROPPED, "Ghartok", 0, "Someone", EP)
check("dropped", Said("has dropped"), true)

-- Returned by the timer: nobody did it, so nobody is named.
ClearOutput()
EmitScroll(OBJECTIVE_CONTROL_EVENT_FLAG_RETURNED_BY_TIMER, "Ghartok", VLASTARUS, "", ALLIANCE_NONE)
check("the timer returning it names no one", Said("on its own"), true)
check("and no player", Said("Someone"), false)

-- An event the add-on has no wording for is not given one.
ClearOutput()
EmitScroll(OBJECTIVE_CONTROL_EVENT_LOST, "Ghartok", VLASTARUS, "Someone", EP)
check("an event with no wording says nothing", Lines(), 0)

-- Console shows the display name; the desktop client shows the character name. The add-on
-- follows the client rather than choosing.
local realMode = IsInGamepadPreferredMode
IsInGamepadPreferredMode = function() return true end
ClearOutput()
EmitScroll(OBJECTIVE_CONTROL_EVENT_FLAG_TAKEN, "Ghartok", CHALMAN, "Someone", AD, "@Somebody")
check("gamepad mode uses the display name", Said("@Somebody"), true)
IsInGamepadPreferredMode = realMode

ClearOutput()
Slash("scrolls off")
EmitScroll(OBJECTIVE_CONTROL_EVENT_FLAG_TAKEN, "Ghartok", CHALMAN, "Someone", AD)
check("switched off, nothing is said", Said("Ghartok"), false)
Slash("scrolls on")
Slash("off")
ClearOutput()
EmitScroll(OBJECTIVE_CONTROL_EVENT_FLAG_TAKEN, "Ghartok", CHALMAN, "Someone", AD)
check("the master switch silences it too", Lines(), 0)
Slash("on")

-- The screen list is per alert kind, and scrolls are a kind like any other.
ResetWorld()
Slash("hud on")
ClearOutput()
EmitScroll(OBJECTIVE_CONTROL_EVENT_FLAG_TAKEN, "Ghartok", CHALMAN, "Someone", AD)
check("not on the screen list by default", HudLines(), 0)
Slash("hud scroll on")
EmitScroll(OBJECTIVE_CONTROL_EVENT_FLAG_TAKEN, "Ghartok", CHALMAN, "Someone", AD)
check("drawn once it is", HudText(), "SCROLL TAKEN: Ghartok (Aldmeri Dominion)")

print("\n== 30. the Daedric artifact on the summary ==")
ResetWorld()
Slash("board on")
Advance(10)
check("nothing about it while it has not spawned", BoardSaid("Volendrung"), false)

-- Revealed and carried by an alliance. There is no name to be had -- the client is never told
-- who has it -- so the line says the alliance and stops there.
SetObjectives({
	{ keepId = 900, objectiveId = 1, bg = BGQUERY_LOCAL, objectiveType = OBJECTIVE_DAEDRIC_WEAPON,
	  name = "Volendrung", state = OBJECTIVE_CONTROL_STATE_FLAG_HELD,
	  pinType = MAP_PIN_TYPE_AVA_DAEDRIC_ARTIFACT_VOLENDRUNG_ALDMERI },
})
Advance(10)
check("named on the summary", BoardSaid("Volendrung: Aldmeri Dominion"), true)
check("in that alliance's colour", BoardColour("Volendrung"), "FFD700")

SetObjectives({
	{ keepId = 900, objectiveId = 1, bg = BGQUERY_LOCAL, objectiveType = OBJECTIVE_DAEDRIC_WEAPON,
	  name = "Volendrung", state = OBJECTIVE_CONTROL_STATE_FLAG_AT_BASE,
	  pinType = MAP_PIN_TYPE_AVA_DAEDRIC_ARTIFACT_VOLENDRUNG_NEUTRAL },
})
Advance(10)
check("nobody holding it says so", BoardSaid("Volendrung: unclaimed"), true)

SetObjectives({
	{ keepId = 900, objectiveId = 1, bg = BGQUERY_LOCAL, objectiveType = OBJECTIVE_DAEDRIC_WEAPON,
	  name = "Volendrung", state = OBJECTIVE_CONTROL_STATE_FLAG_HELD, mine = true,
	  pinType = MAP_PIN_TYPE_AVA_DAEDRIC_ARTIFACT_VOLENDRUNG_EBONHEART },
})
Advance(10)
check("and carrying it yourself is worth saying", BoardSaid("Volendrung: you are carrying it"), true)

-- Not spawned, and another campaign's copy: neither is ours to draw.
SetObjectives({
	{ keepId = 900, objectiveId = 1, bg = BGQUERY_LOCAL, objectiveType = OBJECTIVE_DAEDRIC_WEAPON,
	  name = "Volendrung", state = OBJECTIVE_CONTROL_STATE_UNKNOWN,
	  pinType = MAP_PIN_TYPE_AVA_DAEDRIC_ARTIFACT_VOLENDRUNG_NEUTRAL },
	{ keepId = 901, objectiveId = 1, bg = BGQUERY_ASSIGNED_CAMPAIGN, objectiveType = OBJECTIVE_DAEDRIC_WEAPON,
	  name = "Volendrung", state = OBJECTIVE_CONTROL_STATE_FLAG_HELD,
	  pinType = MAP_PIN_TYPE_AVA_DAEDRIC_ARTIFACT_VOLENDRUNG_DAGGERFALL },
})
Advance(10)
check("unspawned, and another campaign's, are both left out", BoardSaid("Volendrung"), false)
SetObjectives({})

print("\n== 31. the Imperial City is a different campaign ==")
ResetWorld()
Slash("board on")
SetSelectionData({
	{ id = 7, population = { [AD] = CAMPAIGN_POP_HIGH, [EP] = CAMPAIGN_POP_MEDIUM, [DC] = CAMPAIGN_POP_FULL } },
})
Fire(EVENT_CAMPAIGN_SELECTION_DATA_CHANGED)
SetKeep(ARRIUS, { attacked = true })
Advance(10)
check("in Cyrodiil the keep columns are there", BoardSaid("keeps 8"), true)
check("with the score", BoardSaid("score 12,345"), true)
check("and what is being fought over", BoardSaid("under attack"), true)

-- The same campaign id, now an Imperial City one. Districts are what is fought over there;
-- keeps, keep score and the keep watch's attack count are all about something else.
SetCampaign({ imperialCity = true })
Advance(10)
check("in the Imperial City the keeps are gone", BoardSaid("keeps"), false)
check("so is the score", BoardSaid("score"), false)
check("and so is under attack", BoardSaid("under attack"), false)
check("the alliances are still named", BoardSaid("Ebonheart Pact"), true)
check("yours still marked", BoardSaid("> Ebonheart Pact"), true)
check("and how busy each one is is still the point", BoardSaid("campaignBrowser_medPop.dds"), true)
-- Nothing left to sort on, so they keep their own order rather than shuffling every refresh.
check("in alliance order", BoardText():find("Aldmeri") < BoardText():find("Ebonheart"), true)

SetCampaign({ imperialCity = false })
Advance(10)
check("and Cyrodiil gets them back", BoardSaid("keeps 8"), true)
SetSelectionData({})

print("\n== 32. nothing runs outside Cyrodiil ==")
ResetWorld()
check("the timer runs in an AvA zone", TimerRunning(), true)

-- Zoning out. EVENT_PLAYER_ACTIVATED is what the client fires on every zone change, and it is
-- where the timer is decided.
SetInAvA(false)
Fire(EVENT_PLAYER_ACTIVATED)
check("and is stopped on leaving", TimerRunning(), false)
check("with nothing left being watched", WatchCount(), 0)
check("and no summary drawn from stale counts", addon.tally, nil)
ClearOutput()
Slash("")
check("the status says the timer is stopped", Said("the timer is stopped"), true)

-- Nothing at all should happen out here, however long we stand around.
ClearOutput()
SetKeep(VLASTARUS, { attacked = true })
Advance(120)
check("two minutes outside, and not a line", Lines(), 0)

SetInAvA(true)
Fire(EVENT_PLAYER_ACTIVATED)
check("running again on the way back in", TimerRunning(), true)
ClearOutput()
Advance(10)
check("and the fight that started meanwhile is picked up", Said("Vlastarus"), true)

-- The switch itself decides whether the zone matters, so it has to start and stop the timer.
SetInAvA(false)
Slash("ava on")
check("switching it on outside stops the timer", TimerRunning(), false)
Slash("ava off")
check("switching it off starts it anywhere", TimerRunning(), true)
Slash("ava on")
SetInAvA(true)
Fire(EVENT_PLAYER_ACTIVATED)

-- A pass asked for directly still answers, and still costs nothing when it cannot see.
SetInAvA(false)
local total, watched, attacked = addon:Scan()
check("a direct pass outside reads no keeps at all", total, 0)
check("and watches none", watched, 0)
SetInAvA(true)

print("\n== 33. the output window ==")
ResetWorld()
addon.log:Clear()
check("its own window by default", addon.sv.log.destination, "window")

ClearOutput()
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
check("the alert was said", Said("Vlastarus"), true)
check("but not into the chat window", ChatLines(), 0)
check("it is in the output window", LogText():find("Vlastarus", 1, true) ~= nil, true)
check("which is showing", LogHidden(), false)

-- Newest at the top: the one arrangement a wrapped line cannot push out of the window.
addon.log:Clear()
addon.log:Push("first")
addon.log:Push("second")
check("newest line first", LogText(), "second\nfirst")

-- Held to the line count, oldest off the end.
Slash("log clear")
PanelRow("Lines kept").setFunction(3)
for index = 1, 5 do addon.log:Push("line " .. index) end
check("no more lines than asked for", LogLines(), 3)
check("and it is the oldest that goes", LogText():find("line 1", 1, true), nil)
check("the label is bounded too", addon.log.label.maxLineCount, 3)
PanelRow("Lines kept").setFunction(12)

-- Chat, when chat is what you want.
Slash("log chat")
addon.log:Clear()
ClearOutput()
SetKeep(VLASTARUS, { attacked = false })
Advance(10)
check("chat gets it again", ChatSaid("still ours"), true)
check("and the window does not", LogLines(), 0)
check("which is hidden", LogHidden(), true)

-- Both, for the belt-and-braces case.
Slash("log both")
addon.log:Clear()
ClearOutput()
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
check("chat has it", ChatSaid("Vlastarus"), true)
check("and so does the window", LogText():find("Vlastarus", 1, true) ~= nil, true)
Slash("log window")

ClearOutput()
Slash("log sideways")
check("a destination that is not one is refused", Said("say window, chat or both"), true)

print("\n== 34. the output window is placed and sized ==")
ResetWorld()
addon.log:Clear()
addon.log:Push("something")
check("its own default corner", LogWindow().anchors[1].point, "BOTTOMLEFT")
check("its default size", LogWindow().width, 620)
check("and its own font size", addon.log.label.font, "$(BOLD_FONT)|20|soft-shadow-thick")
PanelRow("Window width").setFunction(800)
PanelRow("Window height").setFunction(300)
PanelRow("Text size").setFunction(26)
check("width follows the panel", LogWindow().width, 800)
check("height too", LogWindow().height, 300)
check("and the text size", addon.log.label.font, "$(BOLD_FONT)|26|soft-shadow-thick")
PanelRow("Window position").setFunction(nil, nil, { data = "TOPRIGHT" })
PanelRow("Move the window sideways").setFunction(-30)
PanelRow("Move the window up or down").setFunction(90)
check("position follows it", LogWindow().anchors[1].point, "TOPRIGHT")
check("with both offsets", LogWindow().anchors[1].x, -30)
check("applied", LogWindow().anchors[1].y, 90)
PanelRow("Background").setFunction(80)
check("the panel behind the text darkens", LogBackdrop().colour[4], 0.8)
PanelRow("Background").setFunction(0)
check("and nothing at all is a panel you can see through", LogBackdrop().hidden, true)

-- The draw order, the same three the summary has.
check("in front of everything to begin with", LogWindow().drawLayer, "overlay")
check("on the top tier", LogWindow().drawTier, "high")
Slash("log back")
check("moved behind everything", LogWindow().drawLayer, "background")
check("and to the bottom tier", LogWindow().drawTier, "low")
Slash("log normal")
check("or to an ordinary control's place", LogWindow().drawLayer, "controls")
check("the panel dropdown agrees", PanelRow("Window draw order").getFunction(), "Normal")
PanelRow("Window draw order").setFunction(nil, nil, { data = "FRONT" })
check("and can set it back", LogWindow().drawLayer, "overlay")
-- The summary has its own, and moving one must not move the other. It has to be drawing for
-- the change to reach the window at all, which is the same rule as its position and size.
Slash("board on")
Advance(10)
Slash("board back")
check("the summary's is its own", addon.board.window.drawLayer, "background")
check("and the output window is where it was", LogWindow().drawLayer, "overlay")
Slash("board front")
Slash("board off")

DrawOrderRefused = true
ClearOutput()
Slash("log back")
check("a refusal is reported", Said("refused the draw order"), true)
check("and the window still draws", LogHidden(), false)
DrawOrderRefused = false
Slash("log front")

-- A client with no window manager puts everything back in chat rather than losing it.
ResetWorld()
addon.log.window = nil
addon.log.failed = false
WindowManagerBroken = true
ClearOutput()
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
check("no window, so chat gets it", ChatSaid("Vlastarus"), true)
ClearOutput()
Slash("")
check("and the status says why", Said("could not be created"), true)
WindowManagerBroken = false
addon.log.failed = false

print("\n== 35. the window belongs to Cyrodiil ==")
ResetWorld()
addon.log:Clear()
Slash("log window")
addon.log:Push("something from Cyrodiil")
check("up while we are in an AvA zone", LogHidden(), false)

-- Riding out. The window is not merely empty out there, it is not there.
SetInAvA(false)
Fire(EVENT_PLAYER_ACTIVATED)
check("gone on the way out", LogHidden(), true)
check("and empty, so nothing old comes back with us", LogLines(), 0)

-- Output does not stop, it goes where it would have gone anyway.
ClearOutput()
Slash("")
check("the status still answers", Said("watching every"), true)
check("in chat", ChatSaid("watching every"), true)
check("and not into the window", LogLines(), 0)
check("which says why", Said("outside Cyrodiil"), true)

-- The Imperial City counts as home too: IsInAvAZone covers both.
SetInAvA(true)
SetCampaign({ imperialCity = true })
Fire(EVENT_PLAYER_ACTIVATED)
ClearOutput()
addon.log:Push("something from the Imperial City")
check("the Imperial City is home as well", LogHidden(), false)
SetCampaign({ imperialCity = false })

-- Alerts, not just command replies.
SetInAvA(false)
Fire(EVENT_PLAYER_ACTIVATED)
Slash("ava off")
addon.log:Clear()
ClearOutput()
SetKeep(VLASTARUS, { attacked = true })
Advance(10)
check("an alert raised outside still reaches chat", ChatSaid("Vlastarus"), true)
check("and not the window", LogLines(), 0)
Slash("ava on")
SetInAvA(true)
Fire(EVENT_PLAYER_ACTIVATED)

print("\n== 36. every row on the panel can be read ==")
-- LibHarvensAddonSettings calls getFunction on every row when it builds and when it updates.
-- One row that answers with nil -- or throws -- takes the whole settings panel down with it,
-- which is exactly what a slider did on a live console: its reader's name was derived from the
-- setting's name, and one setting's reader is not called what its field is called.
local unreadable = {}
for _, row in ipairs(PanelRows) do
	if row.getFunction then
		local ok, value = pcall(row.getFunction)
		if not ok then
			unreadable[#unreadable + 1] = tostring(row.label) .. " (threw)"
		elseif value == nil then
			unreadable[#unreadable + 1] = tostring(row.label) .. " (nil)"
		end
	end
end
check("every row answers when the panel reads it", table.concat(unreadable, ", "), "")

-- Setting a row and reading it back is the other half: the panel has to show what it just did.
local roundTrips = {}
for _, row in ipairs(PanelRows) do
	if row.type == LibHarvensAddonSettings.ST_SLIDER and row.getFunction and row.setFunction then
		local before = row.getFunction()
		local wanted = row.min + row.step
		row.setFunction(wanted)
		if row.getFunction() ~= wanted then
			roundTrips[#roundTrips + 1] = tostring(row.label)
		end
		row.setFunction(before)
	end
end
check("and every slider reads back what it was set to", table.concat(roundTrips, ", "), "")

print("\n== 37. the panel ==")
-- A heading with nothing under it draws as an empty collapsible row. Every heading has to be
-- followed by something that is not another heading, and the panel must not end on one.
local emptySections = {}
for index, row in ipairs(PanelRows) do
	if row.type == LibHarvensAddonSettings.ST_SECTION then
		local next_ = PanelRows[index + 1]
		if not next_ or next_.type == LibHarvensAddonSettings.ST_SECTION then
			emptySections[#emptySections + 1] = row.label
		end
	end
end
-- The name the settings library is given. It carries the typographic apostrophe: with an
-- ASCII one the library ate the whole "PB's " and the panel was called "CyrodiilAlert".
check("the panel is named after the add-on", PanelTitle, "PB\u{2019}s CyrodiilAlert 2.3.1")
-- Byte positions, not characters: the apostrophe is three bytes, which is exactly the sort of
-- thing that makes a string comparison look right and be wrong.
check("with the prefix intact", PanelTitle:find("PB\u{2019}s ", 1, true), 1)

check("no empty sections", #emptySections, 0)
check("a group checkbox reads the live setting", PanelRow("Resources").getFunction(), addon:GroupEnabled("resources"))
local before = PanelUpdates
Slash("towns off")
check("a chat command redraws the panel", PanelUpdates > before, true)
check("and the panel agrees", PanelRow("Towns").getFunction(), false)
PanelRow("Towns").setFunction(true)
check("and the panel can set it back", addon:GroupEnabled("towns"), true)

print("\n== 38. the two languages line up ==")
local english = CollectStringKeys(ADDON_DIR .. "/lang/strings.lua")
local japanese = CollectStringKeys(ADDON_DIR .. "/lang/jp.lua")
local missing, extra = {}, {}
for key in pairs(english) do if not japanese[key] then missing[#missing + 1] = key end end
for key in pairs(japanese) do if not english[key] then extra[#extra + 1] = key end end
table.sort(missing)
table.sort(extra)
check("jp.lua translates every string", table.concat(missing, ","), "")
check("jp.lua invents none", table.concat(extra, ","), "")

print("")
if failures == 0 then
	print("all checks passed")
else
	print(failures .. " CHECK(S) FAILED")
	os.exit(1)
end
