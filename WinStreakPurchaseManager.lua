-- 脚本名称: WinStreakPurchaseManager
-- 脚本作用: V1.6 连胜购买管理器，处理玩家死亡后的连胜购买流程
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local WinStreakPurchaseManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

-- 等待RemoteEvents文件夹
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

-- 创建WinStreakPurchase RemoteEvent
local winStreakPurchaseEvent = remoteEventsFolder:FindFirstChild("WinStreakPurchase")
if not winStreakPurchaseEvent then
	winStreakPurchaseEvent = Instance.new("RemoteEvent")
	winStreakPurchaseEvent.Name = "WinStreakPurchase"
	winStreakPurchaseEvent.Parent = remoteEventsFolder
end

-- 配置参数
local PURCHASE_CONFIG = {
	PRODUCT_ID = 3414342081,           -- 开发者商品ID
	UI_SHOW_DELAY = 1.0,               -- 复活后延迟显示UI的时间（秒）
	UI_AUTO_HIDE_TIME = 30.0,          -- UI自动隐藏时间（秒）
	MIN_STREAK_FOR_PURCHASE = 1        -- 最小可购买的连胜数
}

-- 玩家购买状态管理
local playerPurchaseStates = {}  -- 存储每个玩家的购买状态

-- 购买状态枚举
local PURCHASE_STATES = {
	NONE = "none",                     -- 无购买流程
	PENDING_SHOW_UI = "pending_show_ui", -- 等待显示UI
	UI_SHOWN = "ui_shown",             -- UI已显示
	PURCHASING = "purchasing",         -- 正在购买
	COMPLETED = "completed"            -- 购买完成
}

-- 初始化玩家购买状态
function WinStreakPurchaseManager.initializePlayerState(player)
	playerPurchaseStates[player] = {
		state = PURCHASE_STATES.NONE,
		pendingStreak = 0,
		uiShowTime = 0,
		purchaseAttempts = 0
	}
end

-- 清理玩家购买状态
function WinStreakPurchaseManager.cleanupPlayerState(player)
	if playerPurchaseStates[player] then
		-- 如果玩家离开时UI还在显示，先隐藏UI
		if playerPurchaseStates[player].state == PURCHASE_STATES.UI_SHOWN then
			WinStreakPurchaseManager.hideWinStreakPurchaseUI(player)
		end
		playerPurchaseStates[player] = nil
	end
end

-- 获取玩家购买状态
function WinStreakPurchaseManager.getPlayerPurchaseState(player)
	return playerPurchaseStates[player] and playerPurchaseStates[player].state or PURCHASE_STATES.NONE
end

-- 处理玩家死亡（由DeathEffectManager调用）
function WinStreakPurchaseManager.onPlayerDeath(player)
	if not player then
		warn("WinStreakPurchaseManager.onPlayerDeath: 玩家参数为空")
		return false
	end

	-- 确保RankingDataManager可用
	if not _G.RankingDataManager then
		warn("WinStreakPurchaseManager.onPlayerDeath: RankingDataManager不可用")
		return false
	end

	-- 🔧 关键修复：使用pcall保护RankingDataManager调用
	local callSuccess, pendingStreak = pcall(function()
		return _G.RankingDataManager.getPendingStreak(player)
	end)

	if not callSuccess then
		warn("WinStreakPurchaseManager.onPlayerDeath: 获取待恢复连胜数调用异常: " .. tostring(pendingStreak))
		return false
	end


	-- 只有有待恢复连胜数时才设置购买状态
	if pendingStreak >= PURCHASE_CONFIG.MIN_STREAK_FOR_PURCHASE then
		-- 初始化购买状态
		local purchaseState = playerPurchaseStates[player]
		if not purchaseState then
			WinStreakPurchaseManager.initializePlayerState(player)
			purchaseState = playerPurchaseStates[player]
		end

		purchaseState.pendingStreak = pendingStreak
		purchaseState.state = PURCHASE_STATES.PENDING_SHOW_UI
		purchaseState.purchaseAttempts = 0

		return true
	else
		return false
	end
end

-- 处理玩家复活完成（由DeathEffectManager调用）
function WinStreakPurchaseManager.onPlayerRespawned(player)
	if not player then
		warn("WinStreakPurchaseManager.onPlayerRespawned: 玩家参数为空")
		return
	end

	local purchaseState = playerPurchaseStates[player]
	if not purchaseState or purchaseState.state ~= PURCHASE_STATES.PENDING_SHOW_UI then
		return
	end


	-- 延迟显示UI，确保玩家完全恢复
	spawn(function()
		wait(PURCHASE_CONFIG.UI_SHOW_DELAY)

		-- 再次检查状态，确保玩家还在线且状态正确
		if player.Parent and purchaseState.state == PURCHASE_STATES.PENDING_SHOW_UI then
			WinStreakPurchaseManager.showWinStreakPurchaseUI(player)
		else
			-- 状态变化，取消显示
		end
	end)
end

-- 显示连胜购买UI（通过RemoteEvent通知客户端）
function WinStreakPurchaseManager.showWinStreakPurchaseUI(player)
	local purchaseState = playerPurchaseStates[player]
	if not purchaseState then
		warn("无法获取玩家 " .. player.Name .. " 的购买状态")
		return false
	end


	-- 🔧 关键修复：使用pcall保护RemoteEvent调用
	pcall(function()
		winStreakPurchaseEvent:FireClient(player, "showUI", {
			streakCount = purchaseState.pendingStreak
		})
	end)


	-- 更新状态
	purchaseState.state = PURCHASE_STATES.UI_SHOWN
	purchaseState.uiShowTime = tick()

	-- 设置自动隐藏定时器
	spawn(function()
		wait(PURCHASE_CONFIG.UI_AUTO_HIDE_TIME)

		-- 如果UI还在显示状态，自动隐藏并清除pendingStreak
		if purchaseState.state == PURCHASE_STATES.UI_SHOWN then
			WinStreakPurchaseManager.hideWinStreakPurchaseUI(player)
			WinStreakPurchaseManager.declinePurchase(player)
		end
	end)

	return true
end

-- 隐藏连胜购买UI（通过RemoteEvent通知客户端）
function WinStreakPurchaseManager.hideWinStreakPurchaseUI(player)

	-- 🔧 关键修复：使用pcall保护RemoteEvent调用
	pcall(function()
		winStreakPurchaseEvent:FireClient(player, "hideUI")
	end)

	-- 注意：暂时不更新状态，等待客户端确认或在购买流程中适当时机更新
end

-- 处理玩家选择购买
function WinStreakPurchaseManager.onPlayerChoosePurchase(player)
	local purchaseState = playerPurchaseStates[player]
	if not purchaseState or purchaseState.state ~= PURCHASE_STATES.UI_SHOWN then
		warn("玩家 " .. player.Name .. " 购买请求无效，当前状态: " ..
			(purchaseState and purchaseState.state or "无状态"))
		return false
	end


	-- 先隐藏UI（通知客户端）
	WinStreakPurchaseManager.hideWinStreakPurchaseUI(player)

	-- 更新状态为购买中（确认收到购买请求）
	purchaseState.state = PURCHASE_STATES.PURCHASING
	purchaseState.purchaseAttempts = purchaseState.purchaseAttempts + 1

	-- 发起购买流程
	WinStreakPurchaseManager.promptPurchase(player)

	return true
end

-- 处理玩家选择拒绝购买
function WinStreakPurchaseManager.onPlayerDeclinePurchase(player)
	local purchaseState = playerPurchaseStates[player]
	if not purchaseState or purchaseState.state ~= PURCHASE_STATES.UI_SHOWN then
		warn("玩家 " .. player.Name .. " 拒绝购买请求无效，当前状态: " ..
			(purchaseState and purchaseState.state or "无状态"))
		return false
	end


	-- 先隐藏UI（通知客户端）
	WinStreakPurchaseManager.hideWinStreakPurchaseUI(player)

	-- 更新状态为无（确认收到拒绝请求）
	purchaseState.state = PURCHASE_STATES.NONE
	purchaseState.uiShowTime = 0

	-- 执行拒绝购买逻辑
	WinStreakPurchaseManager.declinePurchase(player)

	return true
end

-- 发起购买流程
function WinStreakPurchaseManager.promptPurchase(player)

	-- 使用MarketplaceService发起购买
	local success, result = pcall(function()
		MarketplaceService:PromptProductPurchase(player, PURCHASE_CONFIG.PRODUCT_ID)
	end)

	if not success then
		warn("为玩家 " .. player.Name .. " 发起购买失败: " .. tostring(result))
		WinStreakPurchaseManager.onPurchaseFailed(player, "发起购买失败")
	else
		-- 成功发起购买流程
	end
end

-- 处理购买成功
function WinStreakPurchaseManager.onPurchaseSuccess(player)
	local purchaseState = playerPurchaseStates[player]
	if not purchaseState then
		warn("玩家 " .. player.Name .. " 购买成功但状态不存在")
		return false
	end


	-- 确保RankingDataManager可用
	if not _G.RankingDataManager then
		warn("RankingDataManager不可用，无法恢复连胜数")
		return false
	end

	-- 🔧 关键修复：使用pcall保护RankingDataManager调用
	local callSuccess, success, restoredStreak = pcall(function()
		return _G.RankingDataManager.restorePendingStreak(player)
	end)

	if not callSuccess then
		warn("恢复玩家 " .. player.Name .. " 连胜数调用异常: " .. tostring(success))
		WinStreakPurchaseManager.onPurchaseFailed(player, "连胜数恢复调用失败")
		return false
	end

	if success then

		-- 🔧 关键修复：使用pcall保护PlayerOverheadDisplayManager调用
		if _G.PlayerOverheadDisplayManager and _G.PlayerOverheadDisplayManager.onWinStreakChanged then
			pcall(function()
				_G.PlayerOverheadDisplayManager.onWinStreakChanged(player)
			end)
		end

		-- 🔧 关键修复：使用pcall保护RemoteEvent调用
		pcall(function()
			-- 发送购买成功通知到客户端
			winStreakPurchaseEvent:FireClient(player, "purchaseSuccess", {
				restoredStreak = restoredStreak
			})
		end)

		-- 更新状态
		purchaseState.state = PURCHASE_STATES.COMPLETED
		purchaseState.pendingStreak = 0

		return true
	else
		warn("恢复玩家 " .. player.Name .. " 连胜数失败")
		WinStreakPurchaseManager.onPurchaseFailed(player, "连胜数恢复失败")
		return false
	end
end

-- 处理购买失败
function WinStreakPurchaseManager.onPurchaseFailed(player, reason)
	local purchaseState = playerPurchaseStates[player]
	if not purchaseState then
		warn("玩家 " .. player.Name .. " 购买失败但状态不存在")
		return
	end

	warn("玩家 " .. player.Name .. " 购买失败: " .. (reason or "未知原因"))

	-- 🔧 关键修复：使用pcall保护RemoteEvent调用
	pcall(function()
		winStreakPurchaseEvent:FireClient(player, "purchaseFailed", {
			reason = reason or "购买失败"
		})
	end)

	-- 根据购买尝试次数决定处理方式
	if purchaseState.purchaseAttempts >= 3 then
		WinStreakPurchaseManager.declinePurchase(player)
	else
		-- 重置状态，允许重新尝试（但不再自动显示UI）
		purchaseState.state = PURCHASE_STATES.NONE
	end
end

-- 拒绝购买处理
function WinStreakPurchaseManager.declinePurchase(player)

	-- 🔧 关键修复：使用pcall保护RankingDataManager调用
	if _G.RankingDataManager and _G.RankingDataManager.clearPendingStreak then
		pcall(function()
			_G.RankingDataManager.clearPendingStreak(player)
		end)
	end

	-- 重置购买状态
	local purchaseState = playerPurchaseStates[player]
	if purchaseState then
		purchaseState.state = PURCHASE_STATES.NONE
		purchaseState.pendingStreak = 0
		purchaseState.uiShowTime = 0
	end
end

-- 强制重置玩家购买状态（用于异常情况）
function WinStreakPurchaseManager.forceResetPlayerState(player)

	-- 隐藏UI
	WinStreakPurchaseManager.hideWinStreakPurchaseUI(player)

	-- 🔧 关键修复：使用pcall保护RankingDataManager调用
	if _G.RankingDataManager and _G.RankingDataManager.clearPendingStreak then
		pcall(function()
			_G.RankingDataManager.clearPendingStreak(player)
		end)
	end

	-- 重置状态
	local purchaseState = playerPurchaseStates[player]
	if purchaseState then
		purchaseState.state = PURCHASE_STATES.NONE
		purchaseState.pendingStreak = 0
		purchaseState.uiShowTime = 0
		purchaseState.purchaseAttempts = 0
	end
end

-- 检查购买流程超时
function WinStreakPurchaseManager.checkPurchaseTimeouts()
	local currentTime = tick()

	for player, purchaseState in pairs(playerPurchaseStates) do
		-- 检查UI显示超时（已在showWinStreakPurchaseUI中处理）
		-- 检查购买流程超时
		if purchaseState.state == PURCHASE_STATES.PURCHASING then
			local elapsedTime = currentTime - (purchaseState.uiShowTime + PURCHASE_CONFIG.UI_SHOW_DELAY)
			if elapsedTime > 60 then -- 购买流程超时60秒
				WinStreakPurchaseManager.onPurchaseFailed(player, "购买超时")
			end
		end
	end
end

-- 处理玩家加入
function WinStreakPurchaseManager.onPlayerAdded(player)
	WinStreakPurchaseManager.initializePlayerState(player)
end

-- 处理玩家离开
function WinStreakPurchaseManager.onPlayerRemoving(player)
	WinStreakPurchaseManager.cleanupPlayerState(player)
end

-- 设置RemoteEvent处理
function WinStreakPurchaseManager.setupRemoteEvents()
	winStreakPurchaseEvent.OnServerEvent:Connect(function(player, action, data)

		if action == "purchase" then
			WinStreakPurchaseManager.onPlayerChoosePurchase(player)
		elseif action == "decline" then
			WinStreakPurchaseManager.onPlayerDeclinePurchase(player)
		else
			warn("未知的连胜购买事件: " .. action)
		end
	end)

end

-- 设置MarketplaceService事件监听
function WinStreakPurchaseManager.setupMarketplaceEvents()
	-- 🔧 修复：移除不可靠的PromptProductPurchaseFinished监听
	-- 现在购买处理由UnifiedPurchaseManager的ProcessReceipt处理，更加可靠
	print("📝 WinStreakPurchaseManager: 购买处理已移至UnifiedPurchaseManager")
end

-- 定期检查超时
function WinStreakPurchaseManager.setupTimeoutChecker()
	spawn(function()
		while true do
			wait(10)  -- 每10秒检查一次
			WinStreakPurchaseManager.checkPurchaseTimeouts()
		end
	end)
end

-- 调试：打印所有玩家购买状态
-- Debug function - prints removed for production
function WinStreakPurchaseManager.debugPrintAllStates()
end

-- 初始化连胜购买管理器
function WinStreakPurchaseManager.initialize()

	-- 设置玩家事件监听
	Players.PlayerAdded:Connect(WinStreakPurchaseManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(WinStreakPurchaseManager.onPlayerRemoving)

	-- 处理已在线的玩家
	for _, player in pairs(Players:GetPlayers()) do
		WinStreakPurchaseManager.onPlayerAdded(player)
	end

	-- 设置RemoteEvent处理
	WinStreakPurchaseManager.setupRemoteEvents()

	-- 设置MarketplaceService事件监听
	WinStreakPurchaseManager.setupMarketplaceEvents()

	-- 启动超时检查器
	WinStreakPurchaseManager.setupTimeoutChecker()

end

-- 启动管理器
WinStreakPurchaseManager.initialize()

-- 导出到全局供其他脚本使用
_G.WinStreakPurchaseManager = WinStreakPurchaseManager

return WinStreakPurchaseManager