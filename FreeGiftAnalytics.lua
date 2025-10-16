-- 脚本名称: FreeGiftAnalytics
-- 脚本作用: V2.1 免费在线奖励 - 埋点统计系统（仅Roblox官方统计）
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService
-- 功能：使用 AnalyticsService 记录事件到 Roblox Creator Dashboard

local FreeGiftAnalytics = {}
local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

-- 检测环境
local isStudio = RunService:IsStudio()

-- ============================================
-- 核心埋点函数
-- ============================================

-- 记录成功领取事件
function FreeGiftAnalytics.logClaimSuccess(player, extraData)
	if not player then
		warn("FreeGiftAnalytics.logClaimSuccess: player is nil")
		return
	end

	-- Studio 环境下不发送埋点（避免污染正式数据）
	if isStudio then
		return
	end

	local userId = player.UserId
	local accumulatedSeconds = (extraData and extraData.accumulatedSeconds) or 0
	local hasBadge = (extraData and extraData.hasBadge) or false

	-- 📊 Roblox AnalyticsService - 经济事件（道具获得）
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Source,  -- 玩家获得奖励
			"FreeGift",                             -- 货币类型（自定义名称）
			3,                                      -- 数量（3个道具）
			0,                                      -- 花费（免费）
			"FreeGiftReward"                        -- 上下文
		)
	end)

	-- 📊 Roblox AnalyticsService - 自定义事件（详细数据）
	pcall(function()
		AnalyticsService:FireEvent("FreeGift_Claimed", {
			userId = userId,
			accumulatedSeconds = accumulatedSeconds,
			hasBadge = hasBadge
		})
	end)
end

-- 记录领取失败事件（用于分析转化率）
function FreeGiftAnalytics.logClaimFailure(player, reason, extraData)
	if not player then return end

	-- Studio 环境下不发送埋点
	if isStudio then
		return
	end

	local userId = player.UserId
	local accumulatedSeconds = (extraData and extraData.accumulatedSeconds) or 0

	-- 📊 Roblox AnalyticsService - 自定义事件
	pcall(function()
		AnalyticsService:FireEvent("FreeGift_ClaimFailed", {
			userId = userId,
			reason = reason,
			accumulatedSeconds = accumulatedSeconds
		})
	end)
end

-- 记录UI打开事件（用于分析漏斗转化）
function FreeGiftAnalytics.logUIOpened(player)
	if not player then return end

	-- Studio 环境下不发送埋点
	if isStudio then
		return
	end

	-- 📊 Roblox AnalyticsService - 自定义事件
	pcall(function()
		AnalyticsService:FireEvent("FreeGift_UIOpened", {
			userId = player.UserId
		})
	end)
end

-- ============================================
-- 初始化
-- ============================================

function FreeGiftAnalytics.initialize()
	-- 静默初始化，无日志输出
end

-- 导出到全局
_G.FreeGiftAnalytics = FreeGiftAnalytics

return FreeGiftAnalytics
