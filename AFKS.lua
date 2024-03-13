----------------------------------------------
--	The codes are based on ElvUI	    --
----------------------------------------------

local AFKS = CreateFrame("Frame")

local wowVersion
local isHardcore
local UIscale = 1
local panelheight = GetScreenHeight() * 0.1

if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
	wowVersion = "classic"
	if C_GameRules.IsHardcoreActive() then
		isHardcore = true
	end
elseif WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC then
	wowVersion = "wrath"
elseif WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	wowVersion = "retail"
end

local eastasian = false

if GetLocale() == "koKR" or GetLocale() == "zhCN" or GetLocale() == "zhTW" then
	eastasian = true
end

--Cache global variables
--Lua functions
local _G = _G
local floor = math.floor
local type, select = type, select
local tonumber, tostring = tonumber, tostring
local pairs = pairs
local GetTime = GetTime
--WoW API / Variables
local CreateFrame = CreateFrame
local GetBattlefieldStatus = GetBattlefieldStatus
local GetGuildInfo = GetGuildInfo
local GetZonePVPInfo = GetZonePVPInfo
local InCombatLockdown = InCombatLockdown
local IsInGuild = IsInGuild
local IsResting = IsResting
local UnitFactionGroup = UnitFactionGroup
local UnitIsPVP = UnitIsPVP
local UnitIsAFK = UnitIsAFK
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid
local UnitOnTaxi = UnitOnTaxi
local GetExpansionDisplayInfo = GetExpansionDisplayInfo
local GetExpansionLevel = GetExpansionLevel
local MoveViewLeftStart = MoveViewLeftStart
local MoveViewLeftStop = MoveViewLeftStop
local C_TimerNewTicker, C_TimerNewTimer, C_TimerAfter = C_Timer.NewTicker, C_Timer.NewTimer, C_Timer.After

local RAID_CLASS_COLORS = RAID_CLASS_COLORS

--Retail only API
local C_Texture_GetAtlasInfo
local GetSpecializationInfo
local GetSpecialization
local C_Calendar_GetNumDayEvents
local C_Calendar_GetDayEvent
local C_PetBattles_IsInBattle
local C_UnitAuras_GetPlayerAuraBySpellID
local C_TradeSkillUI_IsRecipeRepeating
local C_Club_GetStreamInfo
local C_Club_GetClubInfo

--Classic only API
local CastingInfo

if wowVersion == "retail" then
	C_Texture_GetAtlasInfo = _G.C_Texture.GetAtlasInfo
	GetSpecializationInfo = _G.GetSpecializationInfo
	GetSpecialization = _G.GetSpecialization
	C_Calendar_GetNumDayEvents = _G.C_Calendar.GetNumDayEvents
	C_Calendar_GetDayEvent = _G.C_Calendar.GetDayEvent
	C_TradeSkillUI_IsRecipeRepeating = _G.C_TradeSkillUI.IsRecipeRepeating
	C_PetBattles_IsInBattle = _G.C_PetBattles.IsInBattle
	C_UnitAuras_GetPlayerAuraBySpellID = _G.C_UnitAuras.GetPlayerAuraBySpellID
	C_Club_GetStreamInfo = _G.C_Club.GetStreamInfo
	C_Club_GetClubInfo = _G.C_Club.GetClubInfo
else
	CastingInfo = _G.CastingInfo
end

--WoW Functions / Frames
--[[
local ChatHistory_GetAccessID = _G.ChatHistory_GetAccessID
local Chat_GetChatCategory = _G.Chat_GetChatCategory
local ChatFrame_GetMobileEmbeddedTexture = _G.ChatFrame_GetMobileEmbeddedTexture
local PVEFrame_ToggleFrame = PVEFrame_ToggleFrame
]]
local UIParent = _G.UIParent

local ignoreKeys = {
	LALT = true,
	LSHIFT = true,
	RSHIFT = true,
}
local printKeys = {
	PRINTSCREEN = true,
}

if IsMacClient() then
	printKeys[_G.KEY_PRINTSCREEN_MAC] = true
end

local isCamp = false

SLASH_AFKSCampToggle1 = "/AFKCAMP"
function SlashCmdList.AFKSCampToggle()
	if isCamp then
		isCamp = false
		print(AFKS_CAMPOFF)
	else
		isCamp = true
		print(AFKS_CAMPON)
	end
end

local public_channels = {
	["retail"] = {26, 42},
	["wrath"] = {23, 25, 26},
	["classic"] = {23, 24, 25},
}

local default_options = {
	enabled = true,
	hidechat = false,
}

function AFKS:OnEvent(event, ...)
	if event == "VARIABLES_LOADED" then
		AFKS_DB = AFKS_DB or CopyTable(default_options)
		self.options = AFKS_DB

		self:Toggle()
		self:RenderOptions()
	end

	if event == "PLAYER_REGEN_DISABLED" or event == "LFG_PROPOSAL_SHOW" or event == "UPDATE_BATTLEFIELD_STATUS" or event == "PARTY_INVITE_REQUEST" then
		if event == "UPDATE_BATTLEFIELD_STATUS" then
			local status = GetBattlefieldStatus(...)
			if status == "confirm" then
				self:SetAFK(false)
			end
		else
			self:SetAFK(false)
		end

		if event == "PLAYER_REGEN_DISABLED" then
			self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnEvent")
			if self.isAFK then
				self.isInterrupted = true
			end
		end
		return
	end

	if event == "TALKINGHEAD_REQUESTED" and self.isAFK then
		self:SetAFK(false)
	end

	if event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if self.isInterrupted then
			C_TimerAfter(0.5, function() self:SetAFK(false) end)
			self.isInterrupted = false
		end
	end
	if event == "PLAYER_CONTROL_GAINED" and UnitOnTaxi("player") and UnitIsPVP("player") then
		self:SetAFK(false)
	end

	if not self.options.enabled then
		return
	end

	if wowVersion == "classic" and isHardcore and not IsResting() then
		return
	end
	if UnitInParty("player") or UnitInRaid("player") or (wowVersion == "retail" and C_PetBattles_IsInBattle()) then
		return
	end
	if UnitIsPVP("player") and GetZonePVPInfo() ~= "sanctuary" and not IsResting() then
		return
	end
	if UnitIsDeadOrGhost("player") or InCombatLockdown() then
		return
	end
	if wowVersion == "retail" then
		if C_TradeSkillUI_IsRecipeRepeating() then
			 --Don't activate afk if player is crafting stuff, check back in 30 seconds
			C_TimerAfter(30, function() self:OnEvent() end)
			return
		end
	else
		if CastingInfo() then
			 --Don't activate afk if player is crafting stuff, check back in 30 seconds
			C_TimerAfter(30, function() self:OnEvent() end)
			return
		end
	end
	
	if UnitIsAFK("player") and not self.isAFK then
		if wowVersion == "retail" and PVEFrame and PVEFrame:IsShown() or isCamp then return end
		self:SetAFK(true)
	elseif not UnitIsAFK("player") then
		self:SetAFK(false)
	end
end

function AFKS:Toggle()
	if(self.options.enabled) then
		self:RegisterEvent("PLAYER_FLAGS_CHANGED", "OnEvent")
		self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEvent")
		self:RegisterEvent("PLAYER_CONTROL_GAINED", "OnEvent")
		self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", "OnEvent")
		if wowVersion == "retail" then
			self:RegisterEvent("LFG_PROPOSAL_SHOW", "OnEvent")
			self:RegisterEvent("PARTY_INVITE_REQUEST", "OnEvent")
			self:RegisterEvent("TALKINGHEAD_REQUESTED", "OnEvent")
		end
		SetCVar("autoClearAFK", "1")
	else
		self:UnregisterEvent("PLAYER_FLAGS_CHANGED")
		self:UnregisterEvent("PLAYER_REGEN_DISABLED")
		self:UnregisterEvent("PLAYER_CONTROL_GAINED")
		self:UnregisterEvent("UPDATE_BATTLEFIELD_STATUS")
		if wowVersion == "retail" then
			self:UnregisterEvent("LFG_PROPOSAL_SHOW")
			self:UnregisterEvent("PARTY_INVITE_REQUEST")
			self:UnregisterEvent("TALKINGHEAD_REQUESTED")
		end
	end
end

local function OnKeyDown(self, key)
	if(ignoreKeys[key]) then return end
	if printKeys[key] then
		Screenshot()
	else
		if InCombatLockdown() then return end
		AFKS:SetAFK(false)
		C_TimerAfter(60, function() AFKS:OnEvent() end)
	end
end

local function Chat_MouseDown(self, button)
	if button == "RightButton" then
		AFKS.AFKMode.chatminbar.minimized = true
		AFKS.AFKMode.chatminbar.unreadwhisper = 0
		AFKS.AFKMode.chatminbar.unreadbnet = 0
		AFKS.AFKMode.chatminbar.unreadchannel = 0
		AFKS.AFKMode.chatminbar.unreadguild = 0
		AFKS.AFKMode.chatminbar.unreadgroup = 0

		local text = format(AFKS_CHATBAR_TEXT, 0, 0, 0)
		if IsInGuild() then
			text = text.." "..format(AFKS_CHATBAR_GUILD, 0)
		end
		AFKS.AFKMode.chatminbar.title:SetText(text)
		AFKS.AFKMode.chatminbar.title:Show()
		AFKS.AFKMode.chatminbar:SetBackdropColor(.2, .2, .2, .8)
		self:Hide()
	elseif button == "LeftButton" and IsShiftKeyDown() then
		self:ClearAllPoints()
		self:SetPoint("BOTTOMLEFT", AFKSFrame, "BOTTOMLEFT", 4, 120)
	end
end

local function Chat_OnMouseWheel(self, delta)
	if delta == 1 then
		if IsShiftKeyDown() then
			self:ScrollToTop()
		else
			self:ScrollUp()
		end
	elseif delta == -1 then
		if IsShiftKeyDown() then
			self:ScrollToBottom()
		else
			self:ScrollDown()
		end
	end
end

local function ChatMinBar_MouseDown(self, button)
	if button == "LeftButton" or button == "RightButton" then
		AFKS.AFKMode.chatminbar.minimized = false
		AFKS.AFKMode.chatminbar.title:Hide()
		AFKS.AFKMode.chatminbar:SetBackdropColor(.2, .2, .2, 0)
		AFKS.AFKMode.chat:Show()
	end
end

local function TruncateToMaxLength(text, maxLength)
	local length = strlenutf8(text)
	if ( length > maxLength ) then
		return text:sub(1, maxLength - 2).."..."
	end
	return text
end

local function GetCommunityName(clubId, streamId)
	local communityName = ""
	local streamInfo = C_Club_GetStreamInfo(clubId, streamId)
	if streamInfo and streamInfo.streamType == 0 then
		local clubInfo = C_Club.GetClubInfo(clubId)
		communityName = clubInfo and TruncateToMaxLength(clubInfo.shortName or clubInfo.name, 12) or ""
	end
	
	return communityName
end

--[[
local function GetBNFriendColor(name, id, useBTag)
	local _, _, battleTag, _, _, bnetIDGameAccount = BNGetFriendInfoByID(id)
	local TAG = useBTag and battleTag and strmatch(battleTag,'([^#]+)')
	local Class

	if not bnetIDGameAccount then --dont know how this is possible
		local firstToonClass = getFirstToonClassColor(id)
		if firstToonClass then
			Class = firstToonClass
		else
			return TAG or name
		end
	end

	if not Class then
		_, _, _, _, _, _, _, Class = BNGetGameAccountInfo(bnetIDGameAccount)
	end

	if Class and Class ~= '' then --other non-english locales require this
		for k,v in pairs(LOCALIZED_CLASS_NAMES_MALE) do if Class == v then Class = k;break end end
		for k,v in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do if Class == v then Class = k;break end end
	end

	local CLASS = Class and Class ~= '' and gsub(strupper(Class),'%s','')
	local COLOR = CLASS and classcolors[CLASS]

	return (COLOR and format('|c%s%s|r', COLOR.colorStr, TAG or name)) or TAG or name
end
]]

local function Chat_OnEvent(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
	local coloredName = GetColoredName(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14);
	local type = strsub(event, 10)
	local info = _G.ChatTypeInfo[type]

--[[
	if(event == "CHAT_MSG_BN_WHISPER") then
		coloredName = GetBNFriendColor(arg2, arg13)
	end
]]
	arg1 = RemoveExtraSpaces(arg1)

	local chatGroup = _G.Chat_GetChatCategory(type)
	local chatTarget, body
	if ( chatGroup == "BN_CONVERSATION" ) then
		chatTarget = tostring(arg8)
	elseif ( chatGroup == "WHISPER" or chatGroup == "BN_WHISPER" ) then
		if(not(strsub(arg2, 1, 2) == "|K")) then
			chatTarget = arg2:upper()
		else
			chatTarget = arg2
		end
	end

	local playerLink
	local texture = ""
	if type == "BN_WHISPER" then
		local accountInfo = C_BattleNet.GetAccountInfoByID(arg13)
		if accountInfo and accountInfo.gameAccountInfo.clientProgram ~= "" then
			texture = BNet_GetClientEmbeddedAtlas(accountInfo.gameAccountInfo.clientProgram, 14, 14)
		end
		playerLink = "|HBNplayer:"..arg2..":"..arg13..":"..arg11..":"..chatGroup..(chatTarget and ":"..chatTarget or "").."|h"
		if AFKS.AFKMode.chatminbar.minimized then
			AFKS.AFKMode.chatminbar.unreadbnet = AFKS.AFKMode.chatminbar.unreadbnet + 1
			--print("bnet:"..AFKS.AFKMode.chatminbar.unreadbnet)
		end
	else
		playerLink = "|Hplayer:"..arg2..":"..arg11..":"..chatGroup..(chatTarget and ":"..chatTarget or "").."|h"
	end

	local message = arg1
	if ( arg14 ) then	--isMobile
		message = _G.ChatFrame_GetMobileEmbeddedTexture(info.r, info.g, info.b)..message
	else
		message = texture..message
	end
	
	--Escape any % characters, as it may otherwise cause an "invalid option in format" error in the next step
	message = gsub(message, "%%", "%%%%")

	local success
	success, body = pcall(format, _G["CHAT_"..type.."_GET"]..message, playerLink.."["..coloredName.."]".."|h")
	if not success then
		print("Error:", type, message, _G["CHAT_"..type.."_GET"])
	end
	if type == "COMMUNITIES_CHANNEL" then
		local prefix, channelCode = arg4:match("(%d+. )(.*)")
		local clubId, streamId = channelCode:match("(%d+)%:(%d+)")
		clubId = tonumber(clubId)
		streamId = tonumber(streamId)

		type = _G.Chat_GetCommunitiesChannel(clubId, streamId)
		info = _G.ChatTypeInfo[type]
		body = "[" .. prefix .. GetCommunityName(clubId, streamId) .. "] " .. body
		if AFKS.AFKMode.chatminbar.minimized then
			AFKS.AFKMode.chatminbar.unreadchannel = AFKS.AFKMode.chatminbar.unreadchannel + 1
		end
	elseif type == "CHANNEL" then
		if arg7 == 1 or arg7 == 2 or arg7 == 22 then
			return
		end
		for k, v in pairs(public_channels[wowVersion]) do
			if arg7 == v then
				return
			end
		end
		info = _G.ChatTypeInfo[type..arg8]
		body = "[" .. arg4 .. "]" .. body
		if AFKS.AFKMode.chatminbar.minimized then
			AFKS.AFKMode.chatminbar.unreadchannel = AFKS.AFKMode.chatminbar.unreadchannel + 1
		end
	end

	local accessID = _G.ChatHistory_GetAccessID(chatGroup, chatTarget)
	local typeID = _G.ChatHistory_GetAccessID(type, chatTarget, arg12 == "" and arg13 or arg12)

	if AFKS.AFKMode.chatminbar.minimized then
		if type == "WHISPER" then
			AFKS.AFKMode.chatminbar.unreadwhisper = AFKS.AFKMode.chatminbar.unreadwhisper + 1
			--print("whisper:"..AFKS.AFKMode.chatminbar.unreadwhisper)
		--elseif type == "BN_WHISPER" then
		--	AFKS.AFKMode.chatminbar.unreadbnet = AFKS.AFKMode.chatminbar.unreadbnet + 1
		elseif type == "GUILD" then
			AFKS.AFKMode.chatminbar.unreadguild = AFKS.AFKMode.chatminbar.unreadguild + 1
		end
		local text = format(AFKS_CHATBAR_TEXT, AFKS.AFKMode.chatminbar.unreadwhisper, AFKS.AFKMode.chatminbar.unreadbnet, AFKS.AFKMode.chatminbar.unreadchannel)
		if IsInGuild() then
			text = text.." "..format(AFKS_CHATBAR_GUILD, AFKS.AFKMode.chatminbar.unreadguild)
		end

		AFKS.AFKMode.chatminbar.title:SetText(text)
	end

	self:AddMessage(body, info.r, info.g, info.b, info.id, false, accessID, typeID)
end

local function LoopAnimations()
	if(AFKSPlayerModel.curAnimation == "wave") then
		AFKSPlayerModel:SetAnimation(69)
		AFKSPlayerModel.curAnimation = "dance"
		AFKSPlayerModel.startTime = GetTime()
		AFKSPlayerModel.duration = 300
		AFKSPlayerModel.isIdle = false
		AFKSPlayerModel.idleDuration = 120
	end
end

local function FontTemplate(fs, fontSize, outline)
	fontSize = fontSize or 12

	if not outline then
		outline = ""
	end
	fs:SetFont(_G.STANDARD_TEXT_FONT, fontSize, outline)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
end

local function SetTemplate(Frame)
	local blank = "Interface/BUTTONS/WHITE8X8"

	Frame:SetBackdrop({
		bgFile = blank,
		edgeFile = blank,
		tile = false, tileSize = 0, edgeSize = 1,
		insets = { left = -1, right = -1, top = -1, bottom = -1},
	})

	if not Frame.isInsetDone then
		Frame.InsetTop = Frame:CreateTexture(nil, "BORDER")
		Frame.InsetTop:SetPoint("TOPLEFT", Frame, "TOPLEFT", -1, 1)
		Frame.InsetTop:SetPoint("TOPRIGHT", Frame, "TOPRIGHT", 1, -1)
		Frame.InsetTop:SetHeight(1)
		Frame.InsetTop:SetColorTexture(0,0,0)
		Frame.InsetTop:SetDrawLayer("BORDER", -7)

		Frame.InsetBottom = Frame:CreateTexture(nil, "BORDER")
		Frame.InsetBottom:SetPoint("BOTTOMLEFT", Frame, "BOTTOMLEFT", -1, -1)
		Frame.InsetBottom:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT", 1, -1)
		Frame.InsetBottom:SetHeight(1)
		Frame.InsetBottom:SetColorTexture(0,0,0)
		Frame.InsetBottom:SetDrawLayer("BORDER", -7)

		Frame.InsetLeft = Frame:CreateTexture(nil, "BORDER")
		Frame.InsetLeft:SetPoint("TOPLEFT", Frame, "TOPLEFT", -1, 1)
		Frame.InsetLeft:SetPoint("BOTTOMLEFT", Frame, "BOTTOMLEFT", 1, -1)
		Frame.InsetLeft:SetWidth(1)
		Frame.InsetLeft:SetColorTexture(0,0,0)
		Frame.InsetLeft:SetDrawLayer("BORDER", -7)

		Frame.InsetRight = Frame:CreateTexture(nil, "BORDER")
		Frame.InsetRight:SetPoint("TOPRIGHT", Frame, "TOPRIGHT", 1, 1)
		Frame.InsetRight:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT", -1, -1)
		Frame.InsetRight:SetWidth(1)
		Frame.InsetRight:SetColorTexture(0,0,0)
		Frame.InsetRight:SetDrawLayer("BORDER", -7)

		Frame.InsetInsideTop = Frame:CreateTexture(nil, "BORDER")
		Frame.InsetInsideTop:SetPoint("TOPLEFT", Frame, "TOPLEFT", 1, -1)
		Frame.InsetInsideTop:SetPoint("TOPRIGHT", Frame, "TOPRIGHT", -1, 1)
		Frame.InsetInsideTop:SetHeight(1)
		Frame.InsetInsideTop:SetColorTexture(0,0,0)
		Frame.InsetInsideTop:SetDrawLayer("BORDER", -7)

		Frame.InsetInsideBottom = Frame:CreateTexture(nil, "BORDER")
		Frame.InsetInsideBottom:SetPoint("BOTTOMLEFT", Frame, "BOTTOMLEFT", 1, 1)
		Frame.InsetInsideBottom:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT", -1, 1)
		Frame.InsetInsideBottom:SetHeight(1)
		Frame.InsetInsideBottom:SetColorTexture(0,0,0)
		Frame.InsetInsideBottom:SetDrawLayer("BORDER", -7)

		Frame.InsetInsideLeft = Frame:CreateTexture(nil, "BORDER")
		Frame.InsetInsideLeft:SetPoint("TOPLEFT", Frame, "TOPLEFT", 1, -1)
		Frame.InsetInsideLeft:SetPoint("BOTTOMLEFT", Frame, "BOTTOMLEFT", -1, 1)
		Frame.InsetInsideLeft:SetWidth(1)
		Frame.InsetInsideLeft:SetColorTexture(0,0,0)
		Frame.InsetInsideLeft:SetDrawLayer("BORDER", -7)

		Frame.InsetInsideRight = Frame:CreateTexture(nil, "BORDER")
		Frame.InsetInsideRight:SetPoint("TOPRIGHT", Frame, "TOPRIGHT", -1, -1)
		Frame.InsetInsideRight:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT", 1, 1)
		Frame.InsetInsideRight:SetWidth(1)
		Frame.InsetInsideRight:SetColorTexture(0,0,0)
		Frame.InsetInsideRight:SetDrawLayer("BORDER", -7)

		Frame.isInsetDone = true
	end

	Frame:SetBackdropBorderColor(.31, .31, .31)
	if wowVersion == "retail" then
		Frame:SetBackdropColor(.06, .06, .06, 0)
	else
		Frame:SetBackdropColor(.06, .06, .06, .8)
	end
end

local function SetSpecPanel()
	local SpecIDToBackgroundAtlas = {
		-- Death Knight
		[250] = "talents-background-deathknight-blood",
		[251] = "talents-background-deathknight-frost",
		[252] = "talents-background-deathknight-unholy",

		-- Demon Hunter
		[577] = "talents-background-demonhunter-havoc",
		[581] = "talents-background-demonhunter-vengeance",

		-- Druid
		[102] = "talents-background-druid-balance",
		[103] = "talents-background-druid-feral",
		[104] = "talents-background-druid-guardian",
		[105] = "talents-background-druid-restoration",

		-- Evoker
		[1467] = "talents-background-evoker-devastation",
		[1468] = "talents-background-evoker-preservation",
		[1473] = "talents-background-evoker-augmentation",

		-- Hunter
		[253] = "talents-background-hunter-beastmastery",
		[254] = "talents-background-hunter-marksmanship",
		[255] = "talents-background-hunter-survival",

		-- Mage
		[62] = "talents-background-mage-arcane",
		[63] = "talents-background-mage-fire",
		[64] = "talents-background-mage-frost",

		-- Monk
		[268] = "talents-background-monk-brewmaster",
		[269] = "talents-background-monk-windwalker",
		[270] = "talents-background-monk-mistweaver",

		-- Paladin
		[65] = "talents-background-paladin-holy",
		[66] = "talents-background-paladin-protection",
		[70] = "talents-background-paladin-retribution",

		-- Priest
		[256] = "talents-background-priest-discipline",
		[257] = "talents-background-priest-holy",
		[258] = "talents-background-priest-shadow",

		-- Rogue
		[259] = "talents-background-rogue-assassination",
		[260] = "talents-background-rogue-outlaw",
		[261] =  "talents-background-rogue-subtlety",

		-- Shaman
		[262] = "talents-background-shaman-elemental",
		[263] = "talents-background-shaman-enhancement",
		[264] = "talents-background-shaman-restoration",

		-- Warlock
		[265] = "talents-background-warlock-affliction",
		[266] = "talents-background-warlock-demonology",
		[267] = "talents-background-warlock-destruction",

		-- Warrior
		[71] = "talents-background-warrior-arms",
		[72] = "talents-background-warrior-fury",
		[73] = "talents-background-warrior-protection",
	}

	local panel_offset = { -- 0.049 + offset to toptexcoord
		[63] = 0.010, -- Fire Mage
		[64] = 0.05, -- Frost Mage
		[65] = -0.015, -- Holy Paladin
		[66] = 0.010, -- Protect Paladin
		[70] = 0.075, -- Ret Paladin
		[71] = 0.042, -- Arms Warrior
		[72] = 0.005, -- Fury Warrior
		[73] = 0.037, -- Protect Warrior
		[102] = 0.006, -- Balance Druid
		[103] = 0.037, -- Feral Druid
		[104] = 0.025, -- Guardian Druid
		[105] = 0.010, -- Resto Druid
		[250] = -0.02, -- Blood DK
		[251] = -0.01, -- Frost DK
		[252] = 0.117, -- Unholy DK
		[253] = -0.010, -- Beast Hunter
		[254] = 0.005, -- Marksmanship Hunter
		[255] = 0.057, -- Survival Hunter
		[256] = 0.012, -- Discipline Priest
		[259] = 0.020, -- Assassination Rogue
		[261] = 0.064, -- Subtlety Rogue
		[262] = 0.037, -- Elemental Shaman
		[263] = -0.01, -- Enhancement Shaman
		[264] = 0.037, -- Resto Shaman
		[265] = 0.020, -- Affl Warlock
		[266] = -0.035, -- Demon Warlock
		[267] = 0.030, -- Dest Warlock
		[268] = 0.025, -- Brew Monk
		[269] = 0.015, -- Wind Monk
		[581] = 0.022, -- Vengeance DH
		[1467] = 0.014, -- Devast Evoker
		[1468] = 0.023, -- Preserv Evoker
		[1473] = 0.023, -- Augment Evoker
	}

	local model_yoffset = {
			[1] = 30, -- Human
			[2] = -15, -- Orc
			[3] = 40, -- Dwarf
			[5] = 10, -- Undead
			[6] = 35, -- Tauren
			[8] = 10, -- Troll
			[11] = 8, -- Draenei
			[22] = 50, -- Worgen
			[24] = 73, -- Pandaren (Neutral)
			[25] = 73, -- Pandaren (Horde)
			[26] = 73, -- Pandaren (Alliance)
			[28] = 65, -- Highmountain
			[30] = 20, -- Lightforged
			[31] = 5, -- Zandalari
			[34] = 40, -- Dark Iron Dwarf
	}

	local yoffset = GetScreenHeight() * 0.1 - 102.4
	if yoffset < 0 then
		yoffset = yoffset * 2.3
	else
		yoffset = yoffset * 3.5
	end
	
	local raceid = select(3, UnitRace("player"))
	if model_yoffset[raceid] then
		yoffset = yoffset + model_yoffset[raceid]
	end
	if select(2, UnitClass("player")) == "DRUID" then
		if C_UnitAuras_GetPlayerAuraBySpellID(5487) then -- Bear form
			yoffset = yoffset + 25
		elseif C_UnitAuras_GetPlayerAuraBySpellID(768) then -- Cat form
			yoffset = yoffset - 135
		elseif C_UnitAuras_GetPlayerAuraBySpellID(783) then -- Flying form
			yoffset = yoffset + 40
		elseif C_UnitAuras_GetPlayerAuraBySpellID(197625) then -- Moonkin form
			yoffset = yoffset - 50
		end
	elseif select(2, UnitClass("player")) == "EVOKER" then
		if C_UnitAuras_GetPlayerAuraBySpellID(372014) then
			yoffset = yoffset + -7
		else
			yoffset = yoffset + 80
		end
	end
	AFKS.AFKMode.bottom.modelHolder:ClearAllPoints()
	AFKS.AFKMode.bottom.modelHolder:SetPoint("BOTTOMRIGHT", AFKS.AFKMode.bottom, "BOTTOMRIGHT", -220, 265 + yoffset)

	local specid = select(1, GetSpecializationInfo(GetSpecialization())) 
	local atlasinfo = specid and SpecIDToBackgroundAtlas[specid]
	local offset = panel_offset[specid] or 0
	local info = atlasinfo and C_Texture_GetAtlasInfo(atlasinfo)

	if info then
		if not AFKS.AFKMode.bottom.specpanel:IsVisible() then
			AFKS.AFKMode.bottom:SetBackdropColor(.06, .06, .06, 0)
			AFKS.AFKMode.bottom.specpanel:Show()
			AFKS.AFKMode.bottom.specpanelend:Show()
		end
		AFKS.AFKMode.bottom.specpanel:SetTexture(info.file)
		AFKS.AFKMode.bottom.specpanel:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.topTexCoord+0.049+offset, info.bottomTexCoord)
	else
		AFKS.AFKMode.bottom:SetBackdropColor(.06, .06, .06, .8)
		AFKS.AFKMode.bottom.specpanel:Hide()
		AFKS.AFKMode.bottom.specpanelend:Hide()
	end
end

local function SetLeftEndColor()
	if not AFKS.AFKMode.bottom.leftendtex:IsVisible() then
		return
	end

	local ColorBySpecID = {
		-- Death Knight
		[250] = {r=0.082, g=0.078, b=0.078},
		[251] = {r=0.019, g=0.11, b=0.176},
		[252] = {r=0.07, g=0.082, b=0.027},

		-- Demon Hunter
		[577] = {r=0.043, g=0.1, b=0.078},
		[581] = {r=0.07, g=0.055, b=0.18},

		-- Druid
		[102] = {r=0.086, g=0.1, b=0.243},
		[103] = {r=0.082, g=0.129, b=0.188},
		[104] = {r=0.172, g=0.086, b=0.002},
		[105] = {r=0.058, g=0.086, b=0.002},

		-- Evoker
		[1467] = {r=0.1, g=0.063, b=0.1},
		[1468] = {r=0.062, g=0.121, b=0.105},
		[1473] = {r=0.1, g=0.1, b=0.067},

		-- Hunter
		[253] = {r=0.082, g=0.098, b=0.235},
		[254] = {r=0.066, g=0.09, b=0.043},
		[255] = {r=0.176, g=0.152, b=0.137},

		-- Mage
		[62] = {r=0.066, g=0.023, b=0.141},
		[63] = {r=0.1, g=0.059, b=0.035},
		[64] = {r=0.062, g=0.078, b=0.145},

		-- Monk
		[268] = {r=0.082, g=0.09, b=0},
		[269] = {r=0.125, g=0.1, b=0.16},
		[270] = {r=0.118, g=0.149, b=0.255},

		-- Paladin
		[65] = {r=0.1, g=0.067, b=0.047},
		[66] = {r=0.176, g=0.067, b=0.129},
		[70] = {r=0.184, g=0.145, b=0.047},

		-- Priest
		[256] = {r=0.066, g=0.086, b=0.1},
		[257] = {r=0.18, g=0.145, b=0.122},
		[258] = {r=0.113, g=0.07, b=0.086},

		-- Rogue
		[259] = {r=0.113, g=0.066, b=0.003},
		[260] = {r=0.043, g=0.086, b=0.082},
		[261] = {r=0.075, g=0.043, b=0.075},

		-- Shaman
		[262] = {r=0.003, g=0.078, b=0.149},
		[263] = {r=0.074, g=0.07, b=0.156},
		[264] = {r=0.082, g=0.086, b=0.121},

		-- Warlock
		[265] = {r=0.07, g=0.063, b=0.22},
		[266] = {r=0.078, g=0.078, b=0.074},
		[267] = {r=0.1, g=0.055, b=0.031},

		-- Warrior
		[71] = {r=0.05, g=0.078, b=0.082},
		[72] = {r=0.066, g=0.07, b=0.074},
		[73] = {r=0.1, g=0.078, b=0.071},
	}

	local specid = select(1, GetSpecializationInfo(GetSpecialization()))
	local r, g, b = ColorBySpecID[specid].r, ColorBySpecID[specid].g, ColorBySpecID[specid].b
	AFKS.AFKMode.bottom.leftendtex:SetColorTexture(r, g, b)
end

local function SetSpecIcon()
	if UnitLevel("player") >= 10 then
		if wowVersion == "retail" then
			local _, _, _, specicon = select(1, GetSpecializationInfo(GetSpecialization())) 
			if specicon then
				AFKS.AFKMode.bottom.specicon:SetTexture(specicon)
				AFKS.AFKMode.bottom.specicon:Show()
			else
				AFKS.AFKMode.bottom.specicon:Hide()
			end
		else
			local primaryTalent
			local talent_tree = {}
			for i=1, GetNumTalentTabs() do
				talent_tree[i] = select(3, GetTalentTabInfo(i))
			end
			for k, v in pairs(talent_tree) do
				if k > 1 and v > talent_tree[k-1] then
					primaryTalent = k
				else
					primaryTalent = 1
				end
			end
			if primaryTalent == 1 and talent_tree[1] == 0 then
				AFKS.AFKMode.bottom.specicon:Hide()
				return
			end

			local specicon = select(2, GetTalentTabInfo(primaryTalent))
			if specicon then
				AFKS.AFKMode.bottom.specicon:SetTexture(specicon)
				AFKS.AFKMode.bottom.specicon:Show()
			else
				AFKS.AFKMode.bottom.specicon:Hide()
			end
		end
	else
		AFKS.AFKMode.bottom.specicon:Hide()
	end
end

local function SetDate(weekday_str, weekday_num)
	local weekday
	if eastasian then
		local localized_weekday = {
			_G.WEEKDAY_SUNDAY,
			_G.WEEKDAY_MONDAY,
			_G.WEEKDAY_TUESDAY,
			_G.WEEKDAY_WEDNESDAY,
			_G.WEEKDAY_THURSDAY,
			_G.WEEKDAY_FRIDAY,
			_G.WEEKDAY_SATURDAY,
		}

		weekday = localized_weekday[weekday_num+1]
	else
		weekday = weekday_str
	end

	if weekday_num == 6 then -- Sat
		weekday = "|cFF2b59FF"..weekday.."|r"
	elseif weekday_num == 0 then -- Sun
		weekday = "|cFFFF2b2b"..weekday.."|r"
	end

	if eastasian then -- East Asian date format check
		AFKS.AFKMode.bottom.date:SetText(format(AFKS_DATEFORMAT, date("%Y"), date("%m"), date("%d"), weekday))
	else
		AFKS.AFKMode.bottom.date:SetText(format(AFKS_DATEFORMAT, date("%b"), date("%d"), date("%Y"), weekday))
	end
end

local function GetCalendarSchedule(day, hour)
	for i = 1, C_Calendar_GetNumDayEvents(0, day) do
		local event = C_Calendar_GetDayEvent(0, day, i)
		if event and event.calendarType == "PLAYER" and event.startTime.hour > hour then
			if event.inviteStatus == 2 or event.inviteStatus == 4 then
				return
			end

			if event.inviteStatus == 1 then
				AFKS.AFKMode.bottom.schedule:SetTextColor(0, 1, 0)
			end
			AFKS.AFKMode.bottom.calendaricon:SetTexture(event.iconTexture)
			local minute = event.startTime.minute
			if event.startTime.minute < 10 then
				minute = "0"..minute
			end

			local ampm
			if event.startTime.hour < 12 then
				ampm = _G.TIMEMANAGER_AM
			else
				ampm = _G.TIMEMANAGER_PM
				if event.startTime.hour > 12 then
					event.startTime.hour = event.startTime.hour - 12
				end
			end

			if eastasian then
				AFKS.AFKMode.bottom.schedule:SetText("("..ampm.." "..event.startTime.hour..":"..minute..") "..event.title)
			else
				AFKS.AFKMode.bottom.schedule:SetText(event.title.." in "..event.startTime.hour..":"..minute.." "..ampm)
			end
			break
		end
	end                   
end

local function GetWoWLogo()
	local expansion
	if wowVersion == "retail" then
		expansion = GetExpansionDisplayInfo(GetExpansionLevel())
	else
		expansion = GetExpansionDisplayInfo(GetExpansionLevel(), _G.LE_RELEASE_TYPE_CLASSIC)
	end
	return expansion and expansion.logo
end

function AFKS:RenderOptions()
	local panel = CreateFrame("Frame", "AFKS_OptionPanel")
	panel.name = "AFKS"

	local title = panel:CreateFontString("ARTWORK", nil, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText("AFKS")

	local enable = CreateFrame("CheckButton", nil, panel, "ChatConfigCheckButtonTemplate")
	enable:SetPoint("TOPLEFT", 10, -35)
	enable.Text:SetText(AFKS_ENABLED_TEXT)
	enable.tooltip = AFKS_ENABLED_TOOLTIP
	enable:HookScript("OnClick", function(_, btn, down)
		self.options.enabled = enable:GetChecked()
		self:Toggle()
	end)
	enable:SetChecked(self.options.enabled)

	local hidechat = CreateFrame("CheckButton", nil, panel, "ChatConfigCheckButtonTemplate")
	hidechat:SetPoint("TOPLEFT", 10, -65)
	hidechat.Text:SetText(AFKS_HIDECHAT_TEXT)
	hidechat.tooltip = AFKS_HIDECHAT_TOOLTIP
	hidechat:HookScript("OnClick", function(_, btn, down)
		self.options.hidechat = hidechat:GetChecked()
	end)
	hidechat:SetChecked(self.options.hidechat)

	InterfaceOptions_AddCategory(panel)
end

function AFKS:Init()
	local logo = GetWoWLogo()
	local class = select(2, UnitClass("player"))

	UIscale = UIParent:GetScale()
	if panelheight < 102 then -- Adjust to 102.4 in small resolution
		panelheight = 102.4
	end

	self.AFKMode = CreateFrame("Frame", "AFKSFrame")
	self.AFKMode:SetFrameLevel(1)
	self.AFKMode:SetScale(UIscale)
	self.AFKMode:SetAllPoints(UIParent)
	self.AFKMode:Hide()
	self.AFKMode:EnableKeyboard(true)
	self.AFKMode:SetScript("OnKeyDown", OnKeyDown)

	self.AFKMode.chat = CreateFrame("ScrollingMessageFrame", nil, self.AFKMode)
	self.AFKMode.chat:SetSize(500, 300)
	self.AFKMode.chat:SetPoint("BOTTOMLEFT", self.AFKMode, "BOTTOMLEFT", 4, 120)
	FontTemplate(self.AFKMode.chat, 18)
	self.AFKMode.chat:SetJustifyH("LEFT")
	self.AFKMode.chat:SetMaxLines(500)
	self.AFKMode.chat:SetClampedToScreen(true)
	self.AFKMode.chat:EnableMouseWheel(true)
	self.AFKMode.chat:SetFading(false)
	self.AFKMode.chat:SetMovable(true)
	self.AFKMode.chat:EnableMouse(true)
	self.AFKMode.chat:RegisterForDrag("LeftButton")
	self.AFKMode.chat:SetScript("OnDragStart", self.AFKMode.chat.StartMoving)
	self.AFKMode.chat:SetScript("OnDragStop", self.AFKMode.chat.StopMovingOrSizing)
	self.AFKMode.chat:SetScript("OnMouseDown", Chat_MouseDown)
	self.AFKMode.chat:SetScript("OnMouseWheel", Chat_OnMouseWheel)
	self.AFKMode.chat:SetScript("OnEvent", Chat_OnEvent)

	self.AFKMode.bottom = CreateFrame("Frame", nil, self.AFKMode, BackdropTemplateMixin and "BackdropTemplate")
	self.AFKMode.bottom:SetFrameLevel(0)
	SetTemplate(self.AFKMode.bottom)
	self.AFKMode.bottom:SetPoint("BOTTOM", self.AFKMode, "BOTTOM", 0, -2)
	self.AFKMode.bottom:SetWidth(GetScreenWidth() + 4)
	self.AFKMode.bottom:SetHeight(panelheight)

	self.AFKMode.bottom.logo = self.AFKMode:CreateTexture(nil, 'OVERLAY')
	self.AFKMode.bottom.logo:SetSize(256, 128)
	self.AFKMode.bottom.logo:SetPoint("CENTER", self.AFKMode.bottom, "CENTER", 0, 25)
	self.AFKMode.bottom.logo:SetTexture(logo)

	self.AFKMode.chatminbar = CreateFrame("Frame", nil, self.AFKMode, BackdropTemplateMixin and "BackdropTemplate")
	self.AFKMode.chatminbar:SetPoint("BOTTOMLEFT", self.AFKMode.bottom, "TOPLEFT", 0, 2)
	self.AFKMode.chatminbar:SetSize(350, 20)
	self.AFKMode.chatminbar:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = nil,
		tile = false, tileSize = 0, edgeSize = 0,
	})
	self.AFKMode.chatminbar:SetBackdropColor(.2, .2, .2, .0)
	self.AFKMode.chatminbar:SetScript("OnMouseDown", ChatMinBar_MouseDown)

	self.AFKMode.chatminbar.title = self.AFKMode.chatminbar:CreateFontString(nil, 'OVERLAY')
	self.AFKMode.chatminbar.title:SetPoint("CENTER", self.AFKMode.chatminbar, "CENTER", 0, 0)
	FontTemplate(self.AFKMode.chatminbar.title, 20, "OUTLINE")

	local text = format(AFKS_CHATBAR_TEXT, 0, 0, 0)
	if IsInGuild() then
		text = text.." "..format(AFKS_CHATBAR_GUILD, 0)
	end
	self.AFKMode.chatminbar.title:SetText(text)
	self.AFKMode.chatminbar.title:SetTextColor(.6, .6, .6)
	self.AFKMode.chatminbar.title:Hide()

	if wowVersion == "retail" then
		local yoffset = panelheight - 102.4
		if yoffset < 0 then
			yoffset = 0
		end

		self.AFKMode.bottom.specpanel = self.AFKMode.bottom:CreateTexture(nil, 'BACKGROUND')
		self.AFKMode.bottom.specpanel:SetSize(1612, 774)
		self.AFKMode.bottom.specpanel:SetPoint("RIGHT", self.AFKMode.bottom, "BOTTOMRIGHT", 0, -285 + yoffset)
		self.AFKMode.bottom.leftend = CreateFrame("Frame", nil, self.AFKMode.bottom)
		self.AFKMode.bottom.leftendtex = self.AFKMode.bottom.leftend:CreateTexture(nil, 'BACKGROUND')
		if GetScreenWidth() - 1567 > 0 then
			self.AFKMode.bottom.leftendtex:SetSize(GetScreenWidth() - 1567, panelheight - 3)
			self.AFKMode.bottom.leftendtex:SetPoint("LEFT", self.AFKMode.bottom, "LEFT", 0, 0)
			self.AFKMode.bottom.leftendtex:SetTexture("Interface/BUTTONS/WHITE8X8")
		else
			self.AFKMode.bottom.leftendtex:Hide()
		end

		self.AFKMode.bottom.schedule = self.AFKMode.bottom:CreateFontString(nil, 'OVERLAY')
		FontTemplate(self.AFKMode.bottom.schedule, 20, "OUTLINE")
		self.AFKMode.bottom.schedule:SetPoint("BOTTOMLEFT", self.AFKMode.bottom.logo, "BOTTOMRIGHT", 200, 0)
		self.AFKMode.bottom.schedule:SetTextColor(1, 1, 1)
		self.AFKMode.bottom.calendaricon = self.AFKMode.bottom:CreateTexture(nil, 'OVERLAY')
		self.AFKMode.bottom.calendaricon:SetPoint("RIGHT", self.AFKMode.bottom.schedule, "LEFT", 0, 0)
		self.AFKMode.bottom.calendaricon:SetSize(40, 40)
	end

	local factionGroup = UnitFactionGroup("player")
	local size, offsetX, offsetY = 140, -20, -16
	local nameOffsetX, nameOffsetY = -10, -28
	local ratio = tonumber(strsub(GetMonitorAspectRatio(), 0, 3))
	if ratio == 1.6 then
		nameOffsetY = -45 -- 16:10 monitor ratio fix
	end
	if factionGroup == "Neutral" then
		factionGroup = "Panda"
		size, offsetX, offsetY = 90, 15, 10
		nameOffsetX, nameOffsetY = 20, -5
		if ratio == 1.6 then
			nameOffsetY = -22 -- a chinese font size is bigger than others
		end
	end

	if wowVersion == "retail" then
		self.AFKMode.bottom.faction = self.AFKMode.bottom.leftend:CreateTexture(nil, 'OVERLAY')
	else
		self.AFKMode.bottom.faction = self.AFKMode.bottom:CreateTexture(nil, 'OVERLAY')
	end
	self.AFKMode.bottom.faction:SetPoint("BOTTOMLEFT", self.AFKMode.bottom, "BOTTOMLEFT", offsetX, offsetY)
	self.AFKMode.bottom.faction:SetTexture("Interface\\Timer\\"..factionGroup.."-Logo")
	self.AFKMode.bottom.faction:SetSize(size, size)

	if wowVersion == "retail" then
		self.AFKMode.bottom.name = self.AFKMode.bottom.leftend:CreateFontString(nil, 'OVERLAY')
	else
		self.AFKMode.bottom.name = self.AFKMode.bottom:CreateFontString(nil, 'OVERLAY')
	end
	FontTemplate(self.AFKMode.bottom.name, 20, "OUTLINE")
	self.AFKMode.bottom.name:SetText(format("%s-%s", UnitName("player"), GetRealmName()))
	self.AFKMode.bottom.name:SetPoint("TOPLEFT", self.AFKMode.bottom.faction, "TOPRIGHT", nameOffsetX, nameOffsetY)
	self.AFKMode.bottom.name:SetTextColor(RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b)

	if wowVersion ~= "classic" then
		if wowVersion == "retail" then
			self.AFKMode.bottom.specicon = self.AFKMode.bottom.leftend:CreateTexture(nil, 'OVERLAY')
		else
			self.AFKMode.bottom.specicon = self.AFKMode.bottom:CreateTexture(nil, 'OVERLAY')
		end
		self.AFKMode.bottom.specicon:SetPoint("CENTER", self.AFKMode.bottom.name, "RIGHT", 15, -2)
		self.AFKMode.bottom.specicon:SetSize(25, 25)
	end

	if wowVersion == "retail" then
		self.AFKMode.bottom.guild = self.AFKMode.bottom.leftend:CreateFontString(nil, 'OVERLAY')
	else
		self.AFKMode.bottom.guild = self.AFKMode.bottom:CreateFontString(nil, 'OVERLAY')
	end
	FontTemplate(self.AFKMode.bottom.guild, 20, "OUTLINE")
	self.AFKMode.bottom.guild:SetText(AFKS_NOGUILD)
	self.AFKMode.bottom.guild:SetPoint("TOPLEFT", self.AFKMode.bottom.name, "BOTTOMLEFT", 0, -6)
	self.AFKMode.bottom.guild:SetTextColor(0.7, 0.7, 0.7)

	if wowVersion == "retail" then
		self.AFKMode.bottom.timer = self.AFKMode.bottom.leftend:CreateFontString(nil, 'OVERLAY')
	else
		self.AFKMode.bottom.timer = self.AFKMode.bottom:CreateFontString(nil, 'OVERLAY')
	end
	FontTemplate(self.AFKMode.bottom.timer, 20, "OUTLINE")
	self.AFKMode.bottom.timer:SetText("00:00")
	self.AFKMode.bottom.timer:SetPoint("TOPLEFT", self.AFKMode.bottom.guild, "BOTTOMLEFT", 0, -6)
	self.AFKMode.bottom.timer:SetTextColor(0.7, 0.7, 0.7)

	self.AFKMode.bottom.date = self.AFKMode.bottom:CreateFontString(nil, 'OVERLAY')
	FontTemplate(self.AFKMode.bottom.date, 20, "OUTLINE")
	self.AFKMode.bottom.date:SetPoint("RIGHT", self.AFKMode.bottom, "RIGHT", -10, 25)
	self.AFKMode.bottom.date:SetTextColor(0.7, 0.7, 0.7)

	self.AFKMode.bottom.time = self.AFKMode.bottom:CreateFontString(nil, 'OVERLAY')
	FontTemplate(self.AFKMode.bottom.time, 20, "OUTLINE")
	self.AFKMode.bottom.time:SetPoint("CENTER", self.AFKMode.bottom.date, "CENTER", 0, -50)
	self.AFKMode.bottom.time:SetTextColor(0.7, 0.7, 0.7)

	--Use this frame to control position of the model
	self.AFKMode.bottom.modelHolder = CreateFrame("Frame", nil, self.AFKMode.bottom)
	self.AFKMode.bottom.modelHolder:SetSize(150, 150)
	if wowVersion == "retail" then
		self.AFKMode.bottom.modelHolder:SetPoint("BOTTOMRIGHT", self.AFKMode.bottom, "BOTTOMRIGHT", -220, 265)
	else
		self.AFKMode.bottom.modelHolder:SetPoint("BOTTOMRIGHT", self.AFKMode.bottom, "BOTTOMRIGHT", -220, 220)
	end

	self.AFKMode.bottom.model = CreateFrame("PlayerModel", "AFKSPlayerModel", self.AFKMode.bottom.modelHolder)
	self.AFKMode.bottom.model:SetPoint("CENTER", self.AFKMode.bottom.modelHolder, "CENTER")
	self.AFKMode.bottom.model:SetSize(GetScreenWidth() * 2, GetScreenHeight() * 2)
	self.AFKMode.bottom.model:SetCamDistanceScale(4.5) --Since the model frame is huge, we need to zoom out quite a bit.
	self.AFKMode.bottom.model:SetFacing(6)
	self.AFKMode.bottom.model:SetScript("OnUpdate", function(self)
		local timePassed = GetTime() - self.startTime
		if(timePassed > self.duration) and self.isIdle ~= true then
			self:SetAnimation(0)
			self.isIdle = true
			AFKS.animTimer = C_TimerNewTimer(self.idleDuration, LoopAnimations)
		end
	end)

	self.isInterrupted = false

	self:SetScript("OnEvent", function(event, ...)
		self:OnEvent(...)
	end)
end

do
	AFKS:RegisterEvent("VARIABLES_LOADED")

	AFKS:Init()

	hooksecurefunc ("LFGListInviteDialog_Show", function()
		if not InCombatLockdown() then
			AFKS:SetAFK(false)
		end
	end)

	if wowVersion == "retail" then
		AddonCompartmentFrame:RegisterAddon({
			text = "AFKS",
			icon = "Interface\\AddOns\\AFKS\\AFKS-icon.tga",
			notCheckable = true,
			func = function()
				_G.Settings.OpenToCategory("AFKS")
			end,
		})
	end
end

function AFKS:UpdateTimer()
	self.AFKMode.bottom.time:SetText(format("%s", GameTime_GetLocalTime(true)))

	local curtime = GetTime() - self.startTime
	self.AFKMode.bottom.timer:SetText(format("%02d:%02d", floor(curtime/60), curtime % 60))

	if date("%H") == "23" and date("%M") == "59" and tonumber(date("%S")) >= 55 then
		SetDate(date("%a"), tonumber(date("%w")))
		if wowVersion == "retail" then
			GetCalendarSchedule(tonumber(date("%d")), tonumber(date("%H")))
		end
	end
end

function AFKS:SetAFK(status)
	if status then
		local currUIscale = UIParent:GetScale()

		if UIscale ~= currUIscale then
			UIscale = currUIscale
			panelheight = GetScreenHeight() * 0.1
			if panelheight < 102 then -- Adjust to 102.4 in small resolution
				panelheight = 102.4
			end

			local yoffset = panelheight - 102.4

			self.AFKMode:SetScale(UIscale)
			self.AFKMode.bottom:SetWidth(GetScreenWidth() + 4)
			self.AFKMode.bottom:SetHeight(panelheight)
			self.AFKMode.bottom.model:SetSize(GetScreenWidth() * 2, GetScreenHeight() * 2)

			if wowVersion == "retail" then
				if yoffset < 0 then
					yoffset = 0
				end
				self.AFKMode.bottom.specpanel:SetPoint("RIGHT", self.AFKMode.bottom, "BOTTOMRIGHT", 0, -285 + yoffset)
				if GetScreenWidth() - 1567 > 0 then
					self.AFKMode.bottom.leftendtex:SetSize(GetScreenWidth() - 1567, panelheight - 3)
					self.AFKMode.bottom.leftendtex:SetPoint("LEFT", self.AFKMode.bottom, "LEFT", 0, 0)
					self.AFKMode.bottom.leftendtex:SetTexture("Interface/BUTTONS/WHITE8X8")
					self.AFKMode.bottom.leftendtex:Show()
				else
					self.AFKMode.bottom.leftendtex:Hide()
				end
			else
				if yoffset > 0 then
					yoffset = yoffset + 30
				else
					yoffset = yoffset - 30
				end
				self.AFKMode.bottom.modelHolder:ClearAllPoints()
				self.AFKMode.bottom.modelHolder:SetPoint("BOTTOMRIGHT", self.AFKMode.bottom, "BOTTOMRIGHT", -220, 220 + yoffset)
			end
		end

		MoveViewLeftStart(0.035)
		self.AFKMode:Show()
		CloseAllWindows()
		UIParent:Hide()

		SetDate(date("%a"), tonumber(date("%w")))
		self.AFKMode.bottom.time:SetText(format("%s", GameTime_GetLocalTime(true)))

		if IsInGuild() then
			local guildName, guildRankName = GetGuildInfo("player")
			self.AFKMode.bottom.guild:SetText(format("%s-%s", guildName, guildRankName))
		else
			self.AFKMode.bottom.guild:SetText(AFKS_NOGUILD)
		end

		if wowVersion ~= "classic" then
			SetSpecIcon()
		end

		if wowVersion == "retail" then
			SetSpecPanel()
			SetLeftEndColor()
			GetCalendarSchedule(tonumber(date("%d")), tonumber(date("%H")))
		end

		self.AFKMode.bottom.model.curAnimation = "wave"
		self.AFKMode.bottom.model.startTime = GetTime()
		self.AFKMode.bottom.model.duration = 2.3
		self.AFKMode.bottom.model:SetUnit("player")
		self.AFKMode.bottom.model.isIdle = nil
		self.AFKMode.bottom.model:SetAnimation(67)
		self.AFKMode.bottom.model.idleDuration = 40
		self.startTime = GetTime()
		self.timer = C_TimerNewTicker(1, function() self:UpdateTimer() end)

		if self.AFKMode.chatminbar.minimized then
			self.AFKMode.chatminbar.unreadwhisper = 0
			self.AFKMode.chatminbar.unreadbnet = 0
			self.AFKMode.chatminbar.unreadchannel = 0
			self.AFKMode.chatminbar.unreadguild = 0
			self.AFKMode.chatminbar.unreadgroup = 0
			self.AFKMode.chatminbar.title:SetText(format(AFKS_CHATBARTITLE, 0, 0, 0, 0))
		end

		if self.options.hidechat then
			self.AFKMode.chat:UnregisterAllEvents()
			self.AFKMode.chat:Clear()
		else
			self.AFKMode.chat:RegisterEvent("CHAT_MSG_WHISPER")
			self.AFKMode.chat:RegisterEvent("CHAT_MSG_BN_WHISPER")
			self.AFKMode.chat:RegisterEvent("CHAT_MSG_GUILD")
			self.AFKMode.chat:RegisterEvent("CHAT_MSG_CHANNEL")

			if wowVersion == "retail" then
				self.AFKMode.chat:RegisterEvent("CHAT_MSG_COMMUNITIES_CHANNEL")
			end
		end

		self.isAFK = true
	elseif not status and self.isAFK then
		UIParent:Show()
		self.AFKMode:Hide()
		MoveViewLeftStop()

		self.timer:Cancel()
		if self.animTimer then
			self.animTimer:Cancel()
		end
		self.AFKMode.bottom.timer:SetText("00:00")

		self.AFKMode.chat:UnregisterAllEvents()
		self.AFKMode.chat:Clear()

		if wowVersion == "retail" and PVEFrame:IsShown() then --odd bug, frame is blank
			--PVEFrame_ToggleFrame()
			--PVEFrame_ToggleFrame()
		end

		self.isAFK = false
	end
end