if GetLocale() ~= "koKR" then return end
-- Slash Command
AFKS_CAMPON = "\124cFFFFEA00캠핑 ON\124r"
AFKS_CAMPOFF = "\124cFFFFEA00캠핑 OFF\124r"
SLASH_AFKSCampToggle2 = "/캠핑"

-- Variables
AFKS_CHATBAR_TEXT = "|cffff7fff귓속말|r(%s) |cff00fffe배틀넷|r(%s) |cffffc0c0채널|r(%s)"
AFKS_CHATBAR_GUILD = "|cff40ff40길드|r(%s)"
AFKS_NOGUILD = "길드 없음"
AFKS_DATEFORMAT = "%d년 %d월 %d일\n%s"

-- Options
AFKS_ENABLED_TEXT = "활성화"
AFKS_ENABLED_TOOLTIP = "AFKS를 활성화 합니다."
AFKS_HIDECHAT_TEXT = "대화창 숨김"
AFKS_HIDECHAT_TOOLTIP = "자리비움 스크린에 대화창이 나오지 않습니다."
AFKS_GROUP_TEXT = "그룹일 때도 활성화"
AFKS_GROUP_TOOLTIP = "그룹에 있을 때도 자리비움 스크린이 활성화 됩니다."