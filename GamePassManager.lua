-- 脚本名称: GamePassManager
-- 脚本作用: 管理GamePass购买验证、新手礼包奖励发放和防重复逻辑
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local GamePassManager = {}
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 🧪 检测是否在Studio环境
local isStudio = RunService:IsStudio()

-- 配置
local CONFIG = {
	NEW_PLAYER_GIFT_GAMEPASS_ID = 1503422953,  -- V1.9: 新手礼包通行证ID
	COIN_REWARD = 500,  -- 金币奖励
	MAX_RETRY_ATTEMPTS = 5,  -- 🔧 增加到5次重试（应对Roblox延迟）
	RETRY_DELAY = 3,  -- 🔧 增加到3秒重试延迟
	STUDIO_TEST_MODE = false  -- ⚠️ 生产环境必须设置为false！
}

-- 🔒 防重复处理：记录正在处理的玩家
local processingPlayers = {}

-- 🔒 购买冷却：防止短时间内重复触发
local purchaseCooldown = {}
local COOLDOWN_TIME = 5  -- 5秒冷却时间

-- 等待依赖系统加载
local PropManager = nil
local CoinManager = nil

-- 延迟加载PropManager
spawn(function()
	local attempts = 0
	while not _G.PropManager and attempts < 20 do
		wait(0.5)
		attempts = attempts + 1
	end

	if _G.PropManager then
		PropManager = _G.PropManager
	else
		warn("GamePassManager: PropManager加载失败")
	end
end)

-- 延迟加载CoinManager
spawn(function()
	local attempts = 0
	while not _G.CoinManager and attempts < 20 do
		wait(0.5)
		attempts = attempts + 1
	end

	if _G.CoinManager then
		CoinManager = _G.CoinManager
	else
		warn("GamePassManager: CoinManager加载失败")
	end
end)

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

-- 创建新手礼包RemoteEvent（如果不存在）
local newPlayerGiftEvent = remoteEventsFolder:FindFirstChild("NewPlayerGift")
if not newPlayerGiftEvent then
	newPlayerGiftEvent = Instance.new("RemoteEvent")
	newPlayerGiftEvent.Name = "NewPlayerGift"
	newPlayerGiftEvent.Parent = remoteEventsFolder
end

-- 🔒 检查购买冷却
local function isInCooldown(player)
	if not player then return true end

	local lastPurchaseTime = purchaseCooldown[player.UserId]
	if lastPurchaseTime then
		local timeSinceLastPurchase = tick() - lastPurchaseTime
		if timeSinceLastPurchase < COOLDOWN_TIME then
			return true
		end
	end

	return false
end

-- 🔒 设置购买冷却
local function setCooldown(player)
	if not player then return end
	purchaseCooldown[player.UserId] = tick()
end

-- 🔒 检查玩家是否正在处理
local function isProcessing(player)
	if not player then return true end
	return processingPlayers[player.UserId] == true
end

-- 🔒 标记玩家处理状态
local function setProcessing(player, processing)
	if not player then return end
	processingPlayers[player.UserId] = processing
end

-- 验证玩家是否拥有GamePass（带重试机制）
function GamePassManager.verifyGamePassOwnership(player, gamePassId, maxRetries)
	if not player or not gamePassId then
		warn("GamePassManager.verifyGamePassOwnership: 参数无效")
		return false
	end

	-- 🧪 Studio测试模式：跳过验证
	if isStudio and CONFIG.STUDIO_TEST_MODE then
		return true
	end

	maxRetries = maxRetries or CONFIG.MAX_RETRY_ATTEMPTS
	local lastError = nil

	for attempt = 1, maxRetries do
		local success, ownsGamePass = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
		end)

		if success then
			if ownsGamePass then
				return true
			else
				-- ✅ 修复：玩家确实不拥有GamePass，不需要重试，直接返回
				-- 只有API调用失败时才需要重试
				return false
			end
		else
			-- API调用失败，记录错误并重试
			lastError = ownsGamePass

			-- ✅ 修复：优化日志等级 - 只在最后一次重试失败时显示warn，之前的重试使用print
			if attempt < maxRetries then
				print("GamePassManager: GamePass验证API调用失败，正在重试 (尝试 " .. attempt .. "/" .. maxRetries .. ")")
				wait(CONFIG.RETRY_DELAY)
			else
				-- 最后一次重试失败才显示warn
				warn("🔴 GamePassManager: 验证GamePass失败，已达最大重试次数(" .. maxRetries .. ")，玩家: " .. player.Name .. ", 错误: " .. tostring(lastError))
			end
		end
	end

	return false
end

-- 等待依赖系统加载完成
local function waitForDependencies(player, timeout)
	timeout = timeout or 10
	local startTime = tick()

	while (not PropManager or not CoinManager) and (tick() - startTime < timeout) do
		wait(0.5)
	end

	if not PropManager then
		warn("GamePassManager: PropManager超时未加载")
		return false
	end

	if not CoinManager then
		warn("GamePassManager: CoinManager超时未加载")
		return false
	end

	-- 等待玩家数据加载
	if PropManager.isPlayerDataLoaded then
		local dataLoadStartTime = tick()
		while not PropManager.isPlayerDataLoaded(player) and (tick() - dataLoadStartTime < timeout) do
			wait(0.5)
		end

		if not PropManager.isPlayerDataLoaded(player) then
			warn("GamePassManager: 玩家 " .. player.Name .. " 数据加载超时")
			return false
		end
	end

	return true
end

-- 发放新手礼包奖励（内部函数，不检查处理标志）
local function grantRewardsInternal(player)
	if not player then
		warn("GamePassManager.grantRewardsInternal: 玩家参数为空")
		return false
	end

	-- 等待依赖系统加载
	if not waitForDependencies(player, 10) then
		warn("GamePassManager: 玩家 " .. player.Name .. " 依赖系统加载超时")
		return false
	end

	-- 🔒 双重检查：验证玩家是否已领取过
	local hasReceived = PropManager.hasReceivedNewPlayerGift(player)

	-- 🔧 V1.9.1: 如果数据未加载（nil），等待一下再检查
	if hasReceived == nil then
		wait(1)
		hasReceived = PropManager.hasReceivedNewPlayerGift(player)
	end

	if hasReceived == true then
		warn("GamePassManager: 玩家 " .. player.Name .. " 已领取过新手礼包，阻止重复发放")
		return false
	end

	-- ✅ P0修复：先发放奖励，全部成功后再标记已领取，避免永久锁定Bug
	-- 发放道具（验证毒药×3 + 跳过阶段×3）
	local propSuccess = PropManager.grantNewPlayerGiftProps(player)

	if not propSuccess then
		warn("GamePassManager: 发放道具失败，玩家 " .. player.Name)
		return false
	end

	-- 发放金币+500
	local coinSuccess = CoinManager.addCoins(player, CONFIG.COIN_REWARD, "V1.9:新手礼包奖励")

	if not coinSuccess then
		warn("GamePassManager: 发放金币失败，玩家 " .. player.Name)
		-- ⚠️ 金币发放失败，但道具已发放
		-- 考虑是否需要回滚道具？当前选择不回滚，避免复杂度
		-- 玩家至少得到了道具，金币可以通过客服补偿
		return false
	end

	-- 🔒 所有奖励发放成功后，才标记为已领取
	local markSuccess = PropManager.markNewPlayerGiftReceived(player)
	if not markSuccess then
		warn("⚠️ Critical: 玩家 " .. player.Name .. " 奖励已发放但标记失败，可能重复领取")
		-- 奖励已发放，标记失败不影响玩家，只是可能重复领取
		-- 这种情况比"标记成功但奖励未发"好得多
		return false
	end

	return true
end

-- 发放新手礼包奖励（外部接口，带完整检查）
function GamePassManager.grantNewPlayerGiftRewards(player)
	if not player then
		warn("GamePassManager.grantNewPlayerGiftRewards: 玩家参数为空")
		return false
	end

	-- 🔒 检查是否正在处理
	if isProcessing(player) then
		warn("GamePassManager: 玩家 " .. player.Name .. " 正在处理中，跳过")
		return false
	end

	-- 🔒 检查冷却
	if isInCooldown(player) then
		warn("GamePassManager: 玩家 " .. player.Name .. " 在冷却中，跳过")
		return false
	end

	-- 🔒 立即标记为处理中
	setProcessing(player, true)

	-- 调用内部发放函数
	local success = grantRewardsInternal(player)

	-- 🔒 设置冷却
	if success then
		setCooldown(player)
	end

	-- 🔒 清除处理标记
	setProcessing(player, false)

	return success
end

-- 处理新手礼包购买完成
function GamePassManager.handleNewPlayerGiftPurchase(player)
	if not player then
		warn("GamePassManager.handleNewPlayerGiftPurchase: 玩家参数为空")
		return
	end

	-- 🔒 检查是否正在处理
	if isProcessing(player) then
		warn("GamePassManager: 玩家 " .. player.Name .. " 正在处理购买，跳过")
		return
	end

	-- 🔒 立即标记为处理中
	setProcessing(player, true)

	-- 等待依赖系统加载
	if not waitForDependencies(player, 10) then
		newPlayerGiftEvent:FireClient(player, "failed", {
			reason = "系统加载中，请稍后再试"
		})
		setProcessing(player, false)
		return
	end

	-- 🔒 第一重检查：验证玩家是否已领取过
	local hasReceived = PropManager.hasReceivedNewPlayerGift(player)
	if hasReceived == true then
		warn("GamePassManager: 玩家 " .. player.Name .. " 已领取过新手礼包")
		newPlayerGiftEvent:FireClient(player, "alreadyReceived", {})
		setProcessing(player, false)
		return
	end

	-- 验证GamePass所有权（带重试）
	local ownsGamePass = GamePassManager.verifyGamePassOwnership(
		player,
		CONFIG.NEW_PLAYER_GIFT_GAMEPASS_ID,
		CONFIG.MAX_RETRY_ATTEMPTS
	)

	if not ownsGamePass then
		warn("GamePassManager: 玩家 " .. player.Name .. " 未拥有新手礼包GamePass")

		-- 🔧 给玩家友好提示：可能是延迟，建议稍后重试
		newPlayerGiftEvent:FireClient(player, "notOwned", {
			message = "Purchase verification failed. Please wait 10 seconds and click the button again."
		})
		setProcessing(player, false)
		return
	end

	-- 🔒 第二重检查：再次验证是否已领取（防止验证期间其他进程发放）
	local hasReceivedAgain = PropManager.hasReceivedNewPlayerGift(player)
	if hasReceivedAgain == true then
		warn("GamePassManager: 玩家 " .. player.Name .. " 在验证期间已领取")
		newPlayerGiftEvent:FireClient(player, "alreadyReceived", {})
		setProcessing(player, false)
		return
	end

	-- 发放奖励（直接调用内部函数，避免重复检查）
	local success = grantRewardsInternal(player)

	if success then
		-- 设置冷却
		setCooldown(player)
		-- 通知客户端发放成功
		newPlayerGiftEvent:FireClient(player, "success", {})
	else
		-- 通知客户端发放失败
		newPlayerGiftEvent:FireClient(player, "failed", {
			reason = "奖励发放失败，请联系管理员"
		})
	end

	-- 🔒 清除处理标记
	setProcessing(player, false)
end

-- 玩家加入时检查GamePass状态
function GamePassManager.onPlayerAdded(player)
	if not player then return end

	-- 延迟检查，确保所有系统已加载
	spawn(function()
		wait(3)

		-- 等待依赖系统加载
		if not waitForDependencies(player, 15) then
			warn("GamePassManager: 玩家 " .. player.Name .. " 依赖系统加载失败，跳过自动检查")
			return
		end

		-- 检查玩家是否已领取过
		local hasReceived = PropManager.hasReceivedNewPlayerGift(player)

		-- 🔧 V1.9.1: 处理nil（数据未加载）的情况
		if hasReceived == nil then
			return
		end

		if hasReceived then
			-- 已领取，通知客户端隐藏按钮
			newPlayerGiftEvent:FireClient(player, "hideButton", {})
			return
		end

		-- 🧪 Studio测试模式：跳过自动发放，让玩家手动测试完整流程
		if isStudio and CONFIG.STUDIO_TEST_MODE then
			return
		end

		-- 验证玩家是否拥有GamePass（仅在正式环境）
		local ownsGamePass = GamePassManager.verifyGamePassOwnership(
			player,
			CONFIG.NEW_PLAYER_GIFT_GAMEPASS_ID,
			CONFIG.MAX_RETRY_ATTEMPTS
		)

		if ownsGamePass then
			-- 拥有GamePass但未领取，自动发放
			local success = GamePassManager.grantNewPlayerGiftRewards(player)

			if success then
				-- 通知客户端发放成功并隐藏按钮
				newPlayerGiftEvent:FireClient(player, "success", {})
			else
				-- 发放失败，保持按钮显示，允许玩家手动点击
				warn("GamePassManager: 自动发放失败，玩家 " .. player.Name .. " 可手动点击领取")
			end
		end
	end)
end

-- 玩家离开时清理
function GamePassManager.onPlayerRemoving(player)
	if not player then return end

	-- 清理处理标记
	processingPlayers[player.UserId] = nil
	purchaseCooldown[player.UserId] = nil
end

-- 设置RemoteEvent处理
function GamePassManager.setupRemoteEvents()
	newPlayerGiftEvent.OnServerEvent:Connect(function(player, action, data)
		if action == "claimReward" then
			-- 玩家点击领取按钮
			GamePassManager.handleNewPlayerGiftPurchase(player)
		elseif action == "checkStatus" then
			-- 客户端请求检查状态
			spawn(function()
				if not waitForDependencies(player, 10) then
					return
				end

				local hasReceived = PropManager.hasReceivedNewPlayerGift(player)

				-- 🔧 V1.9.1: 只在明确已领取时隐藏按钮
				-- nil（数据未加载）或false（未领取）都不隐藏
				if hasReceived == true then
					newPlayerGiftEvent:FireClient(player, "hideButton", {})
				end
			end)
		end
	end)
end

-- 设置玩家事件监听
function GamePassManager.setupPlayerEvents()
	Players.PlayerAdded:Connect(GamePassManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(GamePassManager.onPlayerRemoving)

	-- 处理已在线的玩家
	for _, player in pairs(Players:GetPlayers()) do
		GamePassManager.onPlayerAdded(player)
	end
end

-- 设置MarketplaceService事件监听（检测游戏内购买）
function GamePassManager.setupMarketplaceEvents()
	-- 监听GamePass购买完成事件（服务端）
	-- ⚠️ 注意：此事件仅对通过游戏内PromptGamePassPurchase触发的购买有效
	-- 网页购买不会触发此事件，需要通过定期检查或手动按钮来处理
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		-- 只处理新手礼包的购买
		if gamePassId ~= CONFIG.NEW_PLAYER_GIFT_GAMEPASS_ID then
			return
		end

		-- 只处理购买成功的情况
		if not wasPurchased then
			return
		end

		-- 🔒 检查是否正在处理（防止与客户端的claimReward请求冲突）
		if isProcessing(player) then
			return
		end

		-- 🔒 检查冷却（防止重复触发）
		if isInCooldown(player) then
			return
		end

		-- 等待一小段时间确保GamePass所有权已更新
		wait(2)

		-- 🔒 再次检查是否正在处理（wait期间可能有其他请求）
		if isProcessing(player) then
			return
		end

		-- 🔒 立即标记为处理中
		setProcessing(player, true)

		-- 等待依赖系统加载
		if not waitForDependencies(player, 10) then
			warn("GamePassManager: 玩家 " .. player.Name .. " 购买后依赖系统加载失败")
			setProcessing(player, false)
			return
		end

		-- 检查玩家是否已领取过
		local hasReceivedCheck = PropManager.hasReceivedNewPlayerGift(player)
		if hasReceivedCheck == true then
			return
		end

		-- 验证GamePass所有权（带重试）
		local ownsGamePass = GamePassManager.verifyGamePassOwnership(
			player,
			CONFIG.NEW_PLAYER_GIFT_GAMEPASS_ID,
			3  -- 减少重试次数，因为是购买完成后
		)

		if ownsGamePass then
			-- 调用内部发放函数（避免重复检查isProcessing）
			local success = grantRewardsInternal(player)

			if success then
				-- 设置冷却
				setCooldown(player)
				-- 通知客户端发放成功并隐藏按钮
				newPlayerGiftEvent:FireClient(player, "success", {})
			else
				warn("GamePassManager: 购买后自动发放失败，玩家 " .. player.Name)
			end
		end

		-- 🔒 清除处理标记
		setProcessing(player, false)
	end)
end

-- 设置定期检查（用于检测网页购买）
function GamePassManager.setupPeriodicCheck()
	-- 每30秒检查一次所有在线玩家是否购买了新手礼包
	spawn(function()
		while true do
			wait(30)  -- 每30秒检查一次

			for _, player in pairs(Players:GetPlayers()) do
				-- 只检查未领取的玩家
				if player and player.Parent then
					spawn(function()
						-- 等待依赖加载
						if not waitForDependencies(player, 5) then
							return
						end

						-- 已领取的跳过
						local hasReceivedPeriodic = PropManager.hasReceivedNewPlayerGift(player)
						if hasReceivedPeriodic == true then
							return
						end

						-- 检查是否正在处理
						if isProcessing(player) then
							return
						end

						-- 检查是否拥有GamePass
						local ownsGamePass = GamePassManager.verifyGamePassOwnership(
							player,
							CONFIG.NEW_PLAYER_GIFT_GAMEPASS_ID,
							2  -- 定期检查只用2次重试
						)

						if ownsGamePass then
							-- 发现玩家拥有GamePass但未领取，自动发放
							local success = GamePassManager.grantNewPlayerGiftRewards(player)

							if success then
								-- 通知客户端
								newPlayerGiftEvent:FireClient(player, "success", {})
							end
						end
					end)
				end
			end
		end
	end)
end

-- 初始化GamePassManager
function GamePassManager.initialize()
	GamePassManager.setupRemoteEvents()
	GamePassManager.setupPlayerEvents()
	GamePassManager.setupMarketplaceEvents()  -- 监听游戏内购买
	GamePassManager.setupPeriodicCheck()  -- 定期检查网页购买
end

-- 启动管理器
GamePassManager.initialize()

-- 导出到全局供其他脚本使用
_G.GamePassManager = GamePassManager

return GamePassManager