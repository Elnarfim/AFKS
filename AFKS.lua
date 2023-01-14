----------------------------------------------
--	The codes are based on ElvUI	    --
----------------------------------------------

local AFKS = CreateFrame("Frame")
local AFKMode = true

local wowVersion = nil

if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
	wowVersion = "classic"
elseif WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC then
	wowVersion = "wrath"
elseif WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	wowVersion = "retail"
end

--Cache global variables
--Lua functions
local _G = _G
local GetTime = _G.GetTime
local tostring, pcall = _G.tostring, _G.pcall
local floor = _G.floor
local format, strsub, gsub = _G.string.format, _G.string.sub, _G.string.gsub
--WoW API / Variables
local textfont = _G.STANDARD_TEXT_FONT
local ChatFrame_GetMobileEmbeddedTexture = _G.ChatFrame_GetMobileEmbeddedTexture
local ChatHistory_GetAccessID = _G.ChatHistory_GetAccessID
local Chat_GetChatCategory = _G.Chat_GetChatCategory
local CinematicFrame = _G.CinematicFrame
local CloseAllWindows = _G.CloseAllWindows
local CreateFrame = _G.CreateFrame
local GetBattlefieldStatus = _G.GetBattlefieldStatus
local GetColoredName = _G.GetColoredName
local GetGuildInfo = _G.GetGuildInfo
local GetScreenHeight = _G.GetScreenHeight
local GetScreenWidth = _G.GetScreenWidth
local GetPhysicalScreenSize = _G.GetPhysicalScreenSize
local InCombatLockdown = _G.InCombatLockdown
local IsInGuild = _G.IsInGuild
local IsShiftKeyDown = _G.IsShiftKeyDown
local MoveViewLeftStart = _G.MoveViewLeftStart
local MoveViewLeftStop = _G.MoveViewLeftStop
local MovieFrame = _G.MovieFrame
local PVEFrame_ToggleFrame = _G.PVEFrame_ToggleFrame
local RemoveExtraSpaces = _G.RemoveExtraSpaces
local Screenshot = _G.Screenshot
local SetCVar = _G.SetCVar
local UnitFactionGroup = _G.UnitFactionGroup
local UnitIsAFK = _G.UnitIsAFK

local C_PetBattles_IsInBattle
local C_Club_GetStreamInfo
local C_Club_GetClubInfo
local C_TradeSkillUI_IsRecipeRepeating
local Release_Type_Classic
if wowVersion == "retail" then
	C_PetBattles_IsInBattle = _G.C_PetBattles.IsInBattle
	C_Club_GetStreamInfo = _G.C_Club.GetStreamInfo
	C_Club_GetClubInfo = _G.C_Club.GetClubInfo
	C_TradeSkillUI_IsRecipeRepeating = _G.C_TradeSkillUI.IsRecipeRepeating
	C_Texture_GetAtlasInfo = _G.C_Texture.GetAtlasInfo
	C_UnitAuras_GetPlayerAuraBySpellID = _G.C_UnitAuras.GetPlayerAuraBySpellID
	C_Garrison_GetLandingPageGarrisonType = _G.C_Garrison.GetLandingPageGarrisonType
	--C_Covenants_GetCovenantData = _G.C_Covenants.GetCovenantData
	--C_Covenants_GetActiveCovenantID = _G.C_Covenants.GetActiveCovenantID
else
	Release_Type_Classic = _G.LE_RELEASE_TYPE_CLASSIC
end

local GetExpansionDisplayInfo = _G.GetExpansionDisplayInfo
local GetExpansionLevel = _G.GetExpansionLevel
local classcolors = _G.RAID_CLASS_COLORS
local weekday_names = _G.CALENDAR_WEEKDAY_NAMES
local C_DateAndTime = _G.C_DateAndTime
local C_TimerNewTimer, C_TimerNewTicker, C_TimerAfter = _G.C_Timer.NewTimer, _G.C_Timer.NewTicker, _G.C_Timer.After
local GetLocalTime = _G.GameTime_GetLocalTime

local CAMERA_SPEED = 0.035
local ignoreKeys = {
	LALT = true,
	LSHIFT = true,
	RSHIFT = true,
}
local printKeys = {
	["PRINTSCREEN"] = true,
}

if IsMacClient() then
	printKeys[_G["KEY_PRINTSCREEN_MAC"]] = true
end

local isCamp = false

SlashCmdList["AFKSCampToggle"] = function()
	if isCamp then
		isCamp = false
		print(AFKS_CAMPOFF)
	else
		isCamp = true
		print(AFKS_CAMPON)
	end
end
SLASH_AFKSCampToggle1 = "/AFKCAMP"

function AFKS:OnEvent(event, ...)
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

	if event == "VIGNETTE_MINIMAP_UPDATED" and self.isAFK then
		C_TimerAfter(0.5, function() self:SetAFK(false) end)
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
	if event == "PLAYER_CONTROL_GAINED" and UnitOnTaxi("player") then
		if ((wowVersion == "classic" or wowVersion == "wrath") and GetPVPDesired()) or (wowVersion == "retail" and UnitIsPVP("player")) then
			self:SetAFK(false)
		end
	end

	if (not AFKMode or UnitInParty("player") or UnitInRaid("player") or (wowVersion == "retail" and C_PetBattles_IsInBattle())) then return end
	if (wowVersion == "classic" or wowVersion == "wrath") and GetPVPDesired() then
		return
	elseif UnitIsPVP("player") and not IsResting() then
		return
	end
	if (InCombatLockdown() or CinematicFrame:IsShown() or MovieFrame:IsShown()) then return end
	if wowVersion == "retail" then
		if C_TradeSkillUI_IsRecipeRepeating() then
			 --Don't activate afk if player is crafting stuff, check back in 30 seconds
			C_TimerAfter(30, function() self:OnEvent() end)
			return
		end
	else
		if CastingInfo("player") ~= nil then
			 --Don't activate afk if player is crafting stuff, check back in 30 seconds
			C_TimerAfter(30, function() self:OnEvent() end)
			return
		end
	end
	
	if UnitIsAFK("player") and not self.isAFK then
		if wowVersion == "retail" and PVEFrame and PVEFrame:IsShown() or isCamp then return end
		self:SetAFK(true)
	else
		self:SetAFK(false)
	end
end

function AFKS:Toggle()
	if(AFKMode) then
		self:RegisterEvent("PLAYER_FLAGS_CHANGED", "OnEvent")
		self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEvent")
		self:RegisterEvent("PLAYER_CONTROL_GAINED", "OnEvent")
		self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", "OnEvent")
		if wowVersion == "retail" then
			self:RegisterEvent("LFG_PROPOSAL_SHOW", "OnEvent")
			self:RegisterEvent("PARTY_INVITE_REQUEST", "OnEvent")
			self:RegisterEvent("VIGNETTE_MINIMAP_UPDATED", "OnEvent")
			self:RegisterEvent("TALKINGHEAD_REQUESTED", "OnEvent")
		end
		self:SetScript("OnEvent", function(event, ...)
			self:OnEvent(...)
		end)
		SetCVar("autoClearAFK", "1")
	else
		self:UnregisterEvent("PLAYER_FLAGS_CHANGED")
		self:UnregisterEvent("PLAYER_REGEN_DISABLED")
		self:UnregisterEvent("PLAYER_CONTROL_GAINED")
		self:UnregisterEvent("UPDATE_BATTLEFIELD_STATUS")
		if wowVersion == "retail" then
			self:UnregisterEvent("LFG_PROPOSAL_SHOW")
			self:UnregisterEvent("PARTY_INVITE_REQUEST")
			self:UnregisterEvent("VIGNETTE_MINIMAP_UPDATED")
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

local function Chat_OnMouseWheel(self, delta)
	if(delta == 1 and IsShiftKeyDown()) then
		self:ScrollToTop()
	elseif(delta == -1 and IsShiftKeyDown()) then
		self:ScrollToBottom()
	elseif(delta == -1) then
		self:ScrollDown()
	else
		self:ScrollUp()
	end
end

local function TruncateToMaxLength(text, maxLength)
	local length = strlenutf8(text)
	if ( length > maxLength ) then
		return text:sub(1, maxLength - 2).."..."
	end
	return text
end

local function ResolvePrefixChannelName(communityChannel)
	local communityName = ""
	local prefix, channelCode = communityChannel:match("(%d+. )(.*)")
	local clubId, streamId = channelCode:match("(%d+)%:(%d+)")
	clubId = tonumber(clubId)
	streamId = tonumber(streamId)

	local streamInfo = C_Club_GetStreamInfo(clubId, streamId)
	if streamInfo and streamInfo.streamType == 0 then
		local clubInfo = C_Club_GetClubInfo(clubId)
		communityName = clubInfo and TruncateToMaxLength(clubInfo.shortName or clubInfo.name, 12) or ""
	end
	
	return prefix..communityName
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
	local info = ChatTypeInfo[type]
--[[
	if(event == "CHAT_MSG_BN_WHISPER") then
		coloredName = GetBNFriendColor(arg2, arg13)
	end
]]
	arg1 = RemoveExtraSpaces(arg1)

	local chatGroup = Chat_GetChatCategory(type)
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
	if ( type ~= "BN_WHISPER" and type ~= "BN_CONVERSATION" ) then
		playerLink = "|Hplayer:"..arg2..":"..arg11..":"..chatGroup..(chatTarget and ":"..chatTarget or "").."|h"
	else
		playerLink = "|HBNplayer:"..arg2..":"..arg13..":"..arg11..":"..chatGroup..(chatTarget and ":"..chatTarget or "").."|h"
	end

	local message = arg1
	if ( arg14 ) then	--isMobile
		message = ChatFrame_GetMobileEmbeddedTexture(info.r, info.g, info.b)..message
	end
	
	--Escape any % characters, as it may otherwise cause an "invalid option in format" error in the next step
	message = gsub(message, "%%", "%%%%")

	local success
	success, body = pcall(format, _G["CHAT_"..type.."_GET"]..message, playerLink.."["..coloredName.."]".."|h")
	if not success then
		print("Error:", type, message, _G["CHAT_"..type.."_GET"])
	end
	if event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
		body = "[" .. ResolvePrefixChannelName(arg4) .. "] " .. body
	end

	if event == "CHAT_MSG_CHANNEL" then
		if arg7 == 1 or arg7 == 2 or arg7 == 22 or arg7 == 42 then
			return
		end
		if arg7 == 26 then -- private channel filter
			return
		end
		body = "[" .. arg4 .. "] " .. body
	end

	local accessID = ChatHistory_GetAccessID(chatGroup, chatTarget)
	local typeID = ChatHistory_GetAccessID(type, chatTarget, arg12 == "" and arg13 or arg12)

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
	fs.font = textfont
	fs.fontSize = fontSize

	fontSize = fontSize or 12

	if not outline then
		outline = ""
	end
	fs:SetFont(textfont, fontSize, outline)
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
		-- DK
		[250] = "talents-background-deathknight-blood",
		[251] = "talents-background-deathknight-frost",
		[252] = "talents-background-deathknight-unholy",

		-- DH
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
		[65] = -0.015, -- Holy Paladin
		[66] = 0.010, -- Protect Paladin
		[70] = 0.075, -- Ret Paladin
		[71] = 0.042, -- Arms Warrior
		[72] = 0.005, -- Fury Warrior
		[73] = 0.037, -- Protect Warrior
		[102] = 0.006, -- Balance Druid
		[103] = 0.037, -- Feral Druid
		[104] = 0.034, -- Guardian Druid
		[105] = 0.010, -- Resto Druid
		[250] = -0.049, -- Blood DK
		[252] = 0.037, -- Unholy DK
		[253] = -0.010, -- Beast Hunter
		[254] = 0.005, -- Marksmanship Hunter
		[255] = 0.057, -- Survival Hunter
		[256] = 0.012, -- Discipline Priest
		[259] = 0.020, -- Assassination Rogue
		[261] = 0.064, -- Subtlety Rogue
		[262] = 0.037, -- Elemental Shaman
		[264] = 0.037, -- Resto Shaman
		[265] = 0.020, -- Affl Warlock
		[266] = -0.035, -- Demon Warlock
		[267] = 0.030, -- Dest Warlock
		[268] = 0.025, -- Brew Monk
		[269] = 0.015, -- Wind Monk
		[1467] = 0.014, -- Devast Evoker
		[1468] = 0.023, -- Preserv Evoker
	}

	local model_yoffset = {
		[1] = 30, -- Human
		[3] = 40, -- Dwarf
		[6] = 65, -- Tauren
		[8] = 10, -- Troll
		[11] = 20, -- Draenei
		[22] = 50, -- Worgen
		[24] = 65, -- Pandaren (Neutral)
		[25] = 65, -- Pandaren (Horde)
		[26] = 65, -- Pandaren (Alliance)
		[28] = 65, -- Highmountain
		[30] = 20, -- Lightforged
		[31] = 10, -- Zandalari
	}

	local yoffset = 0
	local raceid = select(3, UnitRace("player"))
	if model_yoffset[raceid] then
		yoffset = model_yoffset[raceid]
	end
	if select(2, UnitClass("player")) == "EVOKER" then
		if C_UnitAuras_GetPlayerAuraBySpellID(372014) then
			yoffset = -7
		else
			yoffset = 70
		end
	end
	AFKS.AFKMode.bottom.modelHolder:ClearAllPoints()
	AFKS.AFKMode.bottom.modelHolder:SetPoint("BOTTOMRIGHT", AFKS.AFKMode.bottom, "BOTTOMRIGHT", -220, 265 + yoffset)

	local specid = select(1,GetSpecializationInfo(GetSpecialization())) 
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
--[[
local function GetWoWLogo()
	if wowVersion == "classic" then
		return "Interface\\Glues\\Common\\WOW_Classic-LogoHR"
	elseif wowVersion == "bcc" then
		return "Interface\\Glues\\Common\\Glues-WoW-ClassicBurningCrusadeLogo"
	elseif wowVersion == "wrath" then
		return 4544489
	else
		local expansion = GetExpansionDisplayInfo(GetExpansionLevel())
		return expansion.logo
	end
end
]]
local function GetWoWLogo()
	local expansion
	if wowVersion == "retail" then
		expansion = GetExpansionDisplayInfo(GetExpansionLevel())
	else
		expansion = GetExpansionDisplayInfo(GetExpansionLevel(), Release_Type_Classic)
	end
	return expansion and expansion.logo
end

function AFKS:Init()
	local logo = GetWoWLogo()
	local class = select(2, UnitClass("player"))
	
	self.AFKMode = CreateFrame("Frame", "AFKSFrame")
	self.AFKMode:SetFrameLevel(1)
	self.AFKMode:SetScale(UIParent:GetScale())
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
	self.AFKMode.chat:EnableMouseWheel(true)
	self.AFKMode.chat:SetFading(false)
	self.AFKMode.chat:SetMovable(true)
	self.AFKMode.chat:EnableMouse(true)
	self.AFKMode.chat:RegisterForDrag("LeftButton")
	self.AFKMode.chat:SetScript("OnDragStart", self.AFKMode.chat.StartMoving)
	self.AFKMode.chat:SetScript("OnDragStop", self.AFKMode.chat.StopMovingOrSizing)
	self.AFKMode.chat:SetScript("OnMouseWheel", Chat_OnMouseWheel)
	self.AFKMode.chat:SetScript("OnEvent", Chat_OnEvent)

	self.AFKMode.bottom = CreateFrame("Frame", nil, self.AFKMode, BackdropTemplateMixin and "BackdropTemplate")
	self.AFKMode.bottom:SetFrameLevel(0)
	SetTemplate(self.AFKMode.bottom)
	self.AFKMode.bottom:SetPoint("BOTTOM", self.AFKMode, "BOTTOM", 0, -2)
	self.AFKMode.bottom:SetWidth(GetScreenWidth() + 4)
	self.AFKMode.bottom:SetHeight(GetScreenHeight() * (1 / 10))

	self.AFKMode.bottom.logo = self.AFKMode:CreateTexture(nil, 'OVERLAY')
	self.AFKMode.bottom.logo:SetSize(256, 128)
	self.AFKMode.bottom.logo:SetPoint("CENTER", self.AFKMode.bottom, "CENTER", 0, 25)
	self.AFKMode.bottom.logo:SetTexture(logo)
	--[[
	if wowVersion == "classic" or wowVersion == "bcc" then
		self.AFKMode.bottom.logo:SetTexCoord(0.125, 0.875, 0.3125, 0.6875)
	end
	]]
	local factionGroup = UnitFactionGroup("player")
	local size, offsetX, offsetY = 140, -20, -16
	local nameOffsetX, nameOffsetY = -10, -28
	local ratio = tonumber(string.sub(GetMonitorAspectRatio(), 0, 3))
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
	self.AFKMode.bottom.faction = self.AFKMode.bottom:CreateTexture(nil, 'OVERLAY')
	self.AFKMode.bottom.faction:SetPoint("BOTTOMLEFT", self.AFKMode.bottom, "BOTTOMLEFT", offsetX, offsetY)
	self.AFKMode.bottom.faction:SetTexture("Interface\\Timer\\"..factionGroup.."-Logo")
	self.AFKMode.bottom.faction:SetSize(size, size)

	self.AFKMode.bottom.name = self.AFKMode.bottom:CreateFontString(nil, 'OVERLAY')
	FontTemplate(self.AFKMode.bottom.name, 20, "OUTLINE")
	self.AFKMode.bottom.name:SetText(format("%s-%s", UnitName("player"), GetRealmName()))
	self.AFKMode.bottom.name:SetPoint("TOPLEFT", self.AFKMode.bottom.faction, "TOPRIGHT", nameOffsetX, nameOffsetY)
	self.AFKMode.bottom.name:SetTextColor(classcolors[class].r, classcolors[class].g, classcolors[class].b)

	if wowVersion == "retail" then
		local yoffset = 0
		if select(2, GetPhysicalScreenSize()) == 2160 then
			yoffset = 20
		end

		--[[
		self.AFKMode.bottom.covenant = self.AFKMode.bottom:CreateTexture(nil, 'OVERLAY')
		self.AFKMode.bottom.covenant:SetPoint("CENTER", self.AFKMode.bottom.name, "RIGHT", 15, 0)
		]]

		self.AFKMode.bottom.specpanel = self.AFKMode.bottom:CreateTexture(nil, 'BACKGROUND')
		self.AFKMode.bottom.specpanel:SetSize(1612, 774)
		self.AFKMode.bottom.specpanel:SetPoint("RIGHT", self.AFKMode.bottom, "BOTTOMRIGHT", 0, -285 + yoffset)
		self.AFKMode.bottom.specpanelend = self.AFKMode.bottom:CreateTexture(nil, 'BACKGROUND')
		self.AFKMode.bottom.specpanelend:SetSize(GetScreenWidth() - 1602, GetScreenHeight() * (1 / 10))
		self.AFKMode.bottom.specpanelend:SetPoint("LEFT", self.AFKMode.bottom, "LEFT", 0, 0)
		self.AFKMode.bottom.specpanelend:SetTexture("Interface/BUTTONS/WHITE8X8")
		self.AFKMode.bottom.specpanelend:SetColorTexture(0, 0, 0)
	end

	self.AFKMode.bottom.guild = self.AFKMode.bottom:CreateFontString(nil, 'OVERLAY')
	FontTemplate(self.AFKMode.bottom.guild, 20, "OUTLINE")
	self.AFKMode.bottom.guild:SetText(AFKS_NOGUILD)
	self.AFKMode.bottom.guild:SetPoint("TOPLEFT", self.AFKMode.bottom.name, "BOTTOMLEFT", 0, -6)
	self.AFKMode.bottom.guild:SetTextColor(0.7, 0.7, 0.7)

	self.AFKMode.bottom.time = self.AFKMode.bottom:CreateFontString(nil, 'OVERLAY')
	FontTemplate(self.AFKMode.bottom.time, 20, "OUTLINE")
	self.AFKMode.bottom.time:SetText("00:00")
	self.AFKMode.bottom.time:SetPoint("TOPLEFT", self.AFKMode.bottom.guild, "BOTTOMLEFT", 0, -6)
	self.AFKMode.bottom.time:SetTextColor(0.7, 0.7, 0.7)

	self.AFKMode.bottom.date = self.AFKMode.bottom:CreateFontString(nil, 'OVERLAY')
	FontTemplate(self.AFKMode.bottom.date, 20, "OUTLINE")
	self.AFKMode.bottom.date:SetPoint("RIGHT", self.AFKMode.bottom, "RIGHT", -10, 6)
	self.AFKMode.bottom.date:SetTextColor(0.7, 0.7, 0.7)

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
	self:Toggle()
end

do
	AFKS:Init()

	if wowVersion == "retail" then
		hooksecurefunc ("LFGListInviteDialog_Show", function()
			if not InCombatLockdown() then
				AFKS:SetAFK(false)
			end
		end)
	end
end

function AFKS:UpdateTimer()
	local curtime = GetTime() - self.startTime
	if wowVersion == "classic" then
		self.AFKMode.bottom.date:SetText(format("%s", GetLocalTime(true)))
	else
		local today = C_DateAndTime.GetCurrentCalendarTime()
		local _, _, month, day, year = today.hour, today.minute, today.month, today.monthDay, today.year
		local weekday = weekday_names[today.weekday]

		if today.weekday == 7 then
			weekday = "|cFF2b59FF"..weekday.."|r"
		elseif today.weekday == 1 then
			weekday = "|cFFFF2b2b"..weekday.."|r"
		end

		if GetLocale() == "koKR" or GetLocale() == "zhCN" or GetLocale() == "zhTW" then -- East Asia date format check
			self.AFKMode.bottom.date:SetText(format(AFKS_DATEFORMAT, year, month, day, weekday, GetLocalTime(true)))
		else
			self.AFKMode.bottom.date:SetText(format(AFKS_DATEFORMAT, month, day, year, weekday, GetLocalTime(true)))
		end
	end
	self.AFKMode.bottom.time:SetText(format("%02d:%02d", floor(curtime/60), curtime % 60))
end

function AFKS:SetAFK(status)
	if(status) then
		MoveViewLeftStart(CAMERA_SPEED)
		self.AFKMode:Show()
		CloseAllWindows()
		UIParent:Hide()

		if(IsInGuild()) then
			local guildName, guildRankName = GetGuildInfo("player")
			self.AFKMode.bottom.guild:SetText(format("%s-%s", guildName, guildRankName))
		else
			self.AFKMode.bottom.guild:SetText(AFKS_NOGUILD)
		end

		if wowVersion == "retail" then
			--[[
			if GetExpansionLevel() == 8 then
				local garrisonType = C_Garrison_GetLandingPageGarrisonType()
				if (garrisonType == Enum.GarrisonType.Type_9_0) then
					local covenantData = C_Covenants_GetCovenantData(C_Covenants_GetActiveCovenantID())
					if covenantData and covenantData.textureKit then
						local info = C_Texture_GetAtlasInfo("shadowlands-landingbutton-"..covenantData.textureKit.."-up")
						self.AFKMode.bottom.covenant:SetAtlas("shadowlands-landingbutton-"..covenantData.textureKit.."-up", true)
						self.AFKMode.bottom.covenant:SetSize(info and math.floor(info.width * 0.6) or 0, info and math.floor(info.height * 0.6) or 0)
					end
				end
			else
				self.AFKMode.bottom.covenant:Hide()
			end
			]]
			SetSpecPanel()
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

		self.AFKMode.chat:RegisterEvent("CHAT_MSG_WHISPER")
		self.AFKMode.chat:RegisterEvent("CHAT_MSG_BN_WHISPER")
		self.AFKMode.chat:RegisterEvent("CHAT_MSG_GUILD")
		self.AFKMode.chat:RegisterEvent("CHAT_MSG_PARTY")
		self.AFKMode.chat:RegisterEvent("CHAT_MSG_PARTY_LEADER")
		self.AFKMode.chat:RegisterEvent("CHAT_MSG_RAID")
		self.AFKMode.chat:RegisterEvent("CHAT_MSG_RAID_LEADER")
		self.AFKMode.chat:RegisterEvent("CHAT_MSG_CHANNEL")
		if wowVersion == "retail" then
			self.AFKMode.chat:RegisterEvent("CHAT_MSG_COMMUNITIES_CHANNEL")
		end

		self.isAFK = true
	elseif(self.isAFK) then
		UIParent:Show()
		self.AFKMode:Hide()
		MoveViewLeftStop();

		self.timer:Cancel()
		if self.animTimer then
			self.animTimer:Cancel()
		end
		self.AFKMode.bottom.time:SetText("00:00")

		self.AFKMode.chat:UnregisterAllEvents()
		self.AFKMode.chat:Clear()
		if wowVersion == "retail" and PVEFrame:IsShown() then --odd bug, frame is blank
			PVEFrame_ToggleFrame()
			PVEFrame_ToggleFrame()
		end

		self.isAFK = false
	end
end
