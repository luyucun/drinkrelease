-- 脚本名称: FreeGiftManager
-- 脚本作用: V2.1 免费在线奖励系统 - 核心管理模块
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService
-- 功能：
--   1. 追踪玩家累计在线时长（永久，跨会话）
--   2. 验证领奖条件（15分钟 + 关注游戏）
--   3. 发放奖励（3个毒药验证道具）
--   4. 防止重复领取

local FreeGiftManager = {}
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local BadgeService = game:GetService("BadgeService")
local RunService = game:GetService("RunService")

-- 检测环境
local isStudio = RunService:IsStudio()

-- DataStore配置
local freeGiftDataStore = nil
if not isStudio then
	local success, result = pcall(function()
		return DataStoreService:GetDataStore("FreeGiftData")
	end)
	if success then
		freeGiftDataStore = result
	else
		warn("FreeGiftManager: DataStore initialization failed - " .. tostring(result))
	end
end

-- 配置参数
local CONFIG = {
	REQUIRED_SECONDS = 10 * 60,        -- 领奖所需秒数（10分钟 = 600秒）
	SAVE_INTERVAL = 30,                -- 保存间隔（秒）
	PROGRESS_SYNC_INTERVAL = 30,       -- 进度同步间隔（秒）
	REWARD_PROP_ID = 1,                -- 奖励道具ID（毒药验证，PropId=1）
	REWARD_PROP_COUNT = 3,             -- 奖励数量
	LIKE_CHECK_METHOD = "Badge",       -- 关注验证方式：Badge/GamePass/API
	-- ⚠️ 重要：徽章 ID 必须是已在游戏后台创建的有效徽章，否则 AwardBadge 会报错
	-- 部署前请确保该徽章存在，否则设置为 0 禁用验证
	LIKE_BADGE_ID = 0,                 -- Badge ID（需要创建后填入，0表示禁用验证）
	MAX_RETRY_ATTEMPTS = 3,            -- DataStore保存最大重试次数
	OFFLINE_SAVE_QUEUE_EXPIRE = 86400, -- 离线保存队列过期时间（24小时）
	MAX_OFFLINE_SAVE_ATTEMPTS = 10     -- 离线保存最大重试次数
}

-- 默认玩家数据结构
local DEFAULT_PLAYER_DATA = {
	accumulatedSeconds = 0,  -- 累计在线秒数
	claimed = false,         -- 是否已领取
	lastSaveTime = 0         -- 最后保存时间
}

-- 内存缓存
FreeGiftManager.playerDataCache = {}     -- {[player] = playerData}
FreeGiftManager.dirtyPlayers = {}        -- {[player] = true} 标记需要保存的玩家
FreeGiftManager.onlineTimers = {}        -- {[player] = true} 在线计时器运行标志
FreeGiftManager.offlineSaveQueue = {}    -- {[userId] = {data, lastAttempt, attempts}}

-- ========== 数据加载与保存 ==========

-- 加载玩家数据
function FreeGiftManager.loadPlayerData(player)
	if not player then
		warn("FreeGiftManager.loadPlayerData: player is nil")
		return nil
	end

	local userId = tostring(player.UserId)
	local playerData = nil

	-- 从DataStore加载
	if freeGiftDataStore then
		local success, data = pcall(function()
			return freeGiftDataStore:GetAsync("Player_" .. userId)
		end)

		if success and data then
			playerData = data
			-- 确保数据结构完整
			for key, defaultValue in pairs(DEFAULT_PLAYER_DATA) do
				if playerData[key] == nil then
					playerData[key] = defaultValue
				end
			end
		else
			if not success then
				warn("FreeGiftManager: Failed to load player " .. player.Name .. " data: " .. tostring(data))
			end
		end
	end

	-- 如果加载失败或新玩家，使用默认数据
	if not playerData then
		playerData = {}
		for key, value in pairs(DEFAULT_PLAYER_DATA) do
			playerData[key] = value
		end
		playerData.lastSaveTime = tick()
	end

	-- 缓存数据
	FreeGiftManager.playerDataCache[player] = playerData

	return playerData
end

-- 同步保存玩家数据（带重试）
function FreeGiftManager.savePlayerData(player, data, maxRetries)
	if not player or not data then
		warn("FreeGiftManager.savePlayerData: parameters are nil")
		return false
	end

	if not freeGiftDataStore then
		-- Studio环境或DataStore不可用，返回true避免错误
		return true
	end

	maxRetries = maxRetries or CONFIG.MAX_RETRY_ATTEMPTS
	local userId = tostring(player.UserId)

	-- 更新保存时间
	data.lastSaveTime = tick()

	-- 重试机制
	for attempt = 1, maxRetries do
		local success, errorMessage = pcall(function()
			freeGiftDataStore:SetAsync("Player_" .. userId, data)
		end)

		if success then
			return true
		else
			warn("FreeGiftManager: Failed to save player " .. player.Name .. " data (attempt " .. attempt .. "): " .. tostring(errorMessage))

			if attempt < maxRetries then
				-- 指数退避
				local waitTime = math.min(2 ^ attempt, 10)
				wait(waitTime)
			end
		end
	end

	warn("FreeGiftManager: Failed to save player " .. player.Name .. " data, max retries reached")
	return false
end

-- 异步保存玩家数据
function FreeGiftManager.savePlayerDataAsync(player, data)
	if not player or not data then return false end

	spawn(function()
		FreeGiftManager.savePlayerData(player, data)
	end)

	return true
end

-- ========== 在线时长追踪 ==========

-- 启动在线计时器
function FreeGiftManager.startOnlineTimer(player)
	if not player then return end

	-- 设置运行标志
	FreeGiftManager.onlineTimers[player] = true

	-- 启动计时器
	spawn(function()
		local saveCounter = 0

		while FreeGiftManager.onlineTimers[player] and player.Parent do
			wait(1) -- 每秒执行一次

			-- 检查玩家是否还在线
			if not player.Parent then
				break
			end

			-- 检查数据是否存在
			local playerData = FreeGiftManager.playerDataCache[player]
			if not playerData then
				break
			end

			-- ✅ P2修复：如果已领取，停止计时器节省资源
			if playerData.claimed then
				break
			end

			-- 累加时间
			playerData.accumulatedSeconds = playerData.accumulatedSeconds + 1

			-- 标记需要保存
			FreeGiftManager.dirtyPlayers[player] = true

			-- 定期保存
			saveCounter = saveCounter + 1
			if saveCounter >= CONFIG.SAVE_INTERVAL then
				saveCounter = 0

				if FreeGiftManager.dirtyPlayers[player] then
					FreeGiftManager.savePlayerDataAsync(player, playerData)
					FreeGiftManager.dirtyPlayers[player] = nil
				end
			end
		end

		-- 计时器结束，清理标志
		FreeGiftManager.onlineTimers[player] = nil
	end)
end

-- 停止在线计时器
function FreeGiftManager.stopOnlineTimer(player)
	if not player then return end

	FreeGiftManager.onlineTimers[player] = nil
end

-- ========== 条件验证 ==========

-- 检查时长条件
function FreeGiftManager.checkTimeCondition(player)
	if not player then return false end

	local playerData = FreeGiftManager.playerDataCache[player]
	if not playerData then return false end

	return playerData.accumulatedSeconds >= CONFIG.REQUIRED_SECONDS
end

-- 检查关注条件
function FreeGiftManager.checkLikeCondition(player)
	if not player then return false, "Player does not exist" end

	-- 如果Badge ID为0，跳过验证（开发测试用）
	if CONFIG.LIKE_BADGE_ID == 0 then
		warn("FreeGiftManager: Badge verification disabled (CONFIG.LIKE_BADGE_ID = 0), skipping check")
		return true
	end

	-- Badge验证方式
	if CONFIG.LIKE_CHECK_METHOD == "Badge" then
		local success, hasBadge = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, CONFIG.LIKE_BADGE_ID)
		end)

		if not success then
			warn("FreeGiftManager: Badge verification failed: " .. tostring(hasBadge))
			return false, "Badge verification failed, please try again"
		end

		if not hasBadge then
			return false, "Please like the game first to unlock this reward!"
		end

		return true
	end

	-- GamePass验证方式（预留）
	if CONFIG.LIKE_CHECK_METHOD == "GamePass" then
		warn("FreeGiftManager: GamePass verification not yet implemented")
		return false, "GamePass verification not implemented"
	end

	-- 默认：跳过验证
	warn("FreeGiftManager: Unknown verification method: " .. CONFIG.LIKE_CHECK_METHOD)
	return true
end

-- 检查是否符合领奖条件
function FreeGiftManager.isEligible(player, skipLikeCheck)
	if not player then
		return false, "Player does not exist"
	end

	local playerData = FreeGiftManager.playerDataCache[player]
	if not playerData then
		return false, "Failed to load data"
	end

	-- 检查是否已领取
	if playerData.claimed then
		return false, "Already claimed"
	end

	-- 检查时长条件
	if not FreeGiftManager.checkTimeCondition(player) then
		local current = playerData.accumulatedSeconds
		local required = CONFIG.REQUIRED_SECONDS
		local remaining = required - current
		return false, string.format("Need %d more seconds (%d:%02d)", remaining, math.floor(remaining / 60), remaining % 60)
	end

	-- 检查关注条件（可选跳过，用于首次领取时的徽章颁发流程）
	if not skipLikeCheck then
		local hasLiked, likeError = FreeGiftManager.checkLikeCondition(player)
		if not hasLiked then
			return false, likeError or "Please like the game"
		end
	end

	return true, "Conditions met"
end

-- ========== 奖励发放 ==========

-- 领取奖励
function FreeGiftManager.claimReward(player)
	if not player then
		return {success = false, message = "Player does not exist"}
	end

	-- 获取玩家数据（用于埋点）
	local playerData = FreeGiftManager.playerDataCache[player]

	-- 检查完整条件（时长 + claimed状态 + 点赞验证）
	-- 修复P1：移除自动徽章发放逻辑，确保徽章发放数与实际点赞数一致
	-- 徽章应该是玩家点赞游戏的证明，而不是领取奖励的附带效果
	local fullEligible, fullReason = FreeGiftManager.isEligible(player, false) -- skipLikeCheck = false
	if not fullEligible then
		-- 📊 埋点：领取失败
		if _G.FreeGiftAnalytics then
			_G.FreeGiftAnalytics.logClaimFailure(player, fullReason, {
				accumulatedSeconds = playerData and playerData.accumulatedSeconds or 0
			})
		end
		return {success = false, message = fullReason}
	end

	-- ✅ P0修复：先标记已领取并保存，再发放道具，防止重复领取漏洞
	playerData.claimed = true

	-- 立即同步保存claimed状态（最高优先级，重试5次）
	local saveSuccess = FreeGiftManager.savePlayerData(player, playerData, 5)

	if not saveSuccess then
		-- 保存失败，回滚内存状态
		playerData.claimed = false
		warn("FreeGiftManager: Failed to save claim status, rolled back - " .. player.Name)

		-- 📊 埋点：保存失败
		if _G.FreeGiftAnalytics then
			_G.FreeGiftAnalytics.logClaimFailure(player, "save_failed", {
				accumulatedSeconds = playerData.accumulatedSeconds
			})
		end

		return {success = false, message = "Save failed, please try again later"}
	end

	-- 保存成功后再发放道具
	if _G.PropManager and _G.PropManager.addProp then
		local addSuccess = _G.PropManager.addProp(player, CONFIG.REWARD_PROP_ID, CONFIG.REWARD_PROP_COUNT)

		if not addSuccess then
			warn("⚠️ Critical: Player " .. player.Name .. " claimed saved but prop delivery failed, manual compensation needed")

			-- 📊 埋点：道具发放失败
			if _G.FreeGiftAnalytics then
				_G.FreeGiftAnalytics.logClaimFailure(player, "prop_delivery_failed", {
					accumulatedSeconds = playerData.accumulatedSeconds,
					hasBadge = true -- 此时应该已经有徽章了
				})
			end

			-- 道具发放失败，但claimed已持久化，无法再次领取
			-- 这种情况需要GM工具手动补发道具
			return {success = false, message = "Reward delivery failed, please contact support"}
		end
	else
		warn("⚠️ Critical: Player " .. player.Name .. " claimed saved but PropManager not loaded")

		-- 📊 埋点：PropManager未加载
		if _G.FreeGiftAnalytics then
			_G.FreeGiftAnalytics.logClaimFailure(player, "prop_manager_not_loaded", {
				accumulatedSeconds = playerData.accumulatedSeconds,
				hasBadge = true -- 此时应该已经有徽章了
			})
		end

		return {success = false, message = "Reward system unavailable, please contact support"}
	end

	-- 📊 埋点：领取成功（关键埋点）
	if _G.FreeGiftAnalytics then
		_G.FreeGiftAnalytics.logClaimSuccess(player, {
			accumulatedSeconds = playerData.accumulatedSeconds,
			hasBadge = true -- 此时应该已经有徽章了（来自玩家的真实点赞行为）
		})
	end

	return {success = true, message = "Reward claimed successfully!"}
end

-- ========== 进度查询 ==========

-- 获取玩家进度
function FreeGiftManager.getProgress(player)
	if not player then
		return {
			seconds = 0,
			percent = 0,
			claimed = false,
			canClaim = false
		}
	end

	local playerData = FreeGiftManager.playerDataCache[player]
	if not playerData then
		return {
			seconds = 0,
			percent = 0,
			claimed = false,
			canClaim = false
		}
	end

	-- 修复P1：进度查询应该进行完整条件检查（时长 + 点赞验证）
	-- 只有同时满足这两个条件，玩家才能看到Claim按钮
	local eligibleForClaim, eligibilityReason = FreeGiftManager.isEligible(player, false) -- 完整检查，包括点赞

	local canClaim = eligibleForClaim
	local message = eligibilityReason

	return {
		seconds = playerData.accumulatedSeconds,
		percent = math.min(playerData.accumulatedSeconds / CONFIG.REQUIRED_SECONDS, 1),
		claimed = playerData.claimed,
		canClaim = canClaim,
		message = message
	}
end

-- ========== 玩家生命周期 ==========

-- 玩家加入
function FreeGiftManager.onPlayerAdded(player)
	if not player then return end

	-- 延迟2秒等待其他系统加载
	spawn(function()
		wait(2)

		-- 加载数据
		local playerData = FreeGiftManager.loadPlayerData(player)

		if playerData then
			-- 启动在线计时器
			FreeGiftManager.startOnlineTimer(player)
		else
			warn("FreeGiftManager: Player " .. player.Name .. " data failed to load")
		end
	end)
end

-- 玩家离开
function FreeGiftManager.onPlayerRemoving(player)
	if not player then return end

	local playerData = FreeGiftManager.playerDataCache[player]
	if not playerData then return end

	local userId = tostring(player.UserId)

	-- 停止在线计时器
	FreeGiftManager.stopOnlineTimer(player)

	-- 同步保存数据（增加重试次数）
	local saveSuccess = FreeGiftManager.savePlayerData(player, playerData, 5)

	if not saveSuccess then
		warn("⚠️ FreeGiftManager: Player " .. player.Name .. " save failed on disconnect, added to offline queue")

		-- 创建数据副本
		local dataCopy = {}
		for key, value in pairs(playerData) do
			dataCopy[key] = value
		end

		-- 加入离线保存队列
		FreeGiftManager.offlineSaveQueue[userId] = {
			data = dataCopy,
			lastAttempt = tick(),
			attempts = 5  -- 已经尝试了5次
		}
	end

	-- 清理缓存（无论保存成功与否，player对象即将销毁）
	FreeGiftManager.playerDataCache[player] = nil
	FreeGiftManager.dirtyPlayers[player] = nil
end

-- ========== 定期保存与离线队列处理 ==========

-- 定期保存
function FreeGiftManager.setupPeriodicSave()
	spawn(function()
		while true do
			wait(CONFIG.SAVE_INTERVAL)

			-- 保存所有标记为dirty的玩家
			for player, _ in pairs(FreeGiftManager.dirtyPlayers) do
				if player and player.Parent then
					local playerData = FreeGiftManager.playerDataCache[player]
					if playerData then
						FreeGiftManager.savePlayerDataAsync(player, playerData)
						FreeGiftManager.dirtyPlayers[player] = nil
					end
				end
			end

			-- 处理离线保存队列
			if freeGiftDataStore then
				local currentTime = tick()
				local offlineRetryCount = 0
				local MAX_OFFLINE_RETRIES_PER_CYCLE = 10

				for userId, queueEntry in pairs(FreeGiftManager.offlineSaveQueue) do
					if offlineRetryCount >= MAX_OFFLINE_RETRIES_PER_CYCLE then
						break
					end

					-- 检查是否超过最大重试次数
					if queueEntry.attempts >= CONFIG.MAX_OFFLINE_SAVE_ATTEMPTS then
						warn("⚠️ FreeGiftManager offline queue: Player " .. userId .. " max retries reached, abandoning save")
						FreeGiftManager.offlineSaveQueue[userId] = nil
						offlineRetryCount = offlineRetryCount + 1

						-- 检查是否过期
					elseif currentTime - queueEntry.lastAttempt > CONFIG.OFFLINE_SAVE_QUEUE_EXPIRE then
						warn("⚠️ FreeGiftManager offline queue: Player " .. userId .. " data expired, abandoning save")
						FreeGiftManager.offlineSaveQueue[userId] = nil
						offlineRetryCount = offlineRetryCount + 1

						-- 尝试重新保存
					else
						local success, errorMessage = pcall(function()
							freeGiftDataStore:SetAsync("Player_" .. userId, queueEntry.data)
						end)

						if success then
							FreeGiftManager.offlineSaveQueue[userId] = nil
						else
							queueEntry.attempts = queueEntry.attempts + 1
							queueEntry.lastAttempt = currentTime
							warn("⚠️ FreeGiftManager offline queue: Player " .. userId .. " save failed (attempt " .. queueEntry.attempts .. ")")
						end

						offlineRetryCount = offlineRetryCount + 1
						wait(0.1)
					end
				end
			end
		end
	end)
end

-- 服务器关闭时保存所有数据
function FreeGiftManager.saveAllDataOnShutdown()
	game:BindToClose(function()
		-- 保存所有在线玩家数据
		for player, playerData in pairs(FreeGiftManager.playerDataCache) do
			if player and playerData then
				FreeGiftManager.savePlayerData(player, playerData, 5)
			end
		end

		-- 保存离线队列（最多20个）
		if freeGiftDataStore then
			local saveCount = 0
			for userId, queueEntry in pairs(FreeGiftManager.offlineSaveQueue) do
				if saveCount >= 20 then break end

				local success = pcall(function()
					freeGiftDataStore:SetAsync("Player_" .. userId, queueEntry.data)
				end)

				if success then
					saveCount = saveCount + 1
				end
			end
		end

		-- 等待DataStore完成
		wait(3)
	end)
end

-- ========== 初始化 ==========

function FreeGiftManager.initialize()
	-- 监听玩家事件
	Players.PlayerAdded:Connect(FreeGiftManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(FreeGiftManager.onPlayerRemoving)

	-- 处理已在线玩家
	for _, player in pairs(Players:GetPlayers()) do
		FreeGiftManager.onPlayerAdded(player)
	end

	-- 启动定期保存
	FreeGiftManager.setupPeriodicSave()

	-- 设置服务器关闭保存
	FreeGiftManager.saveAllDataOnShutdown()

	-- 设置全局变量
	_G.FreeGiftManager = FreeGiftManager
end

-- ============================================
-- V1.9: 重置玩家数据为新玩家（管理员命令用）
-- ============================================

function FreeGiftManager.resetPlayerData(userId, player)
	-- 1. 检查参数有效性
	if not userId or type(userId) ~= "number" then
		warn("[FreeGiftManager] resetPlayerData: 无效的 userId: " .. tostring(userId))
		return false
	end

	if not player or not player.UserId or player.UserId ~= userId then
		warn("[FreeGiftManager] resetPlayerData: player 参数与 userId 不匹配")
		return false
	end

	print("[FreeGiftManager] 开始重置玩家数据: " .. player.Name .. " (UserId: " .. userId .. ")")

	-- 2. 清空内存缓存（如果玩家在线）
	if FreeGiftManager.playerDataCache[player] then
		-- 停止在线计时器
		FreeGiftManager.stopOnlineTimer(player)
		FreeGiftManager.playerDataCache[player] = nil
		print("[FreeGiftManager] ✓ 已清空内存缓存和计时器")
	end

	-- 清空相关标志
	if FreeGiftManager.dirtyPlayers[player] then
		FreeGiftManager.dirtyPlayers[player] = nil
		print("[FreeGiftManager] ✓ 已清空dirty标志")
	end

	if FreeGiftManager.onlineTimers[player] then
		FreeGiftManager.onlineTimers[player] = nil
		print("[FreeGiftManager] ✓ 已清空在线计时器标志")
	end

	-- 清空离线保存队列中的数据
	local userIdStr = tostring(userId)
	if FreeGiftManager.offlineSaveQueue[userIdStr] then
		FreeGiftManager.offlineSaveQueue[userIdStr] = nil
		print("[FreeGiftManager] ✓ 已清空离线保存队列")
	end

	-- 3. 重置 DataStore 为默认值（带重试机制）
	local defaultData = {}
	for key, value in pairs(DEFAULT_PLAYER_DATA) do
		defaultData[key] = value
	end
	defaultData.lastSaveTime = tick()

	local maxRetries = 3
	local resetSuccess = false

	-- 仅在非Studio环境下操作DataStore
	if not isStudio and freeGiftDataStore then
		for attempt = 1, maxRetries do
			local success, err = pcall(function()
				freeGiftDataStore:SetAsync("Player_" .. userIdStr, defaultData)
			end)

			if success then
				resetSuccess = true
				print("[FreeGiftManager] ✓ DataStore 重置成功 (尝试 " .. attempt .. "/" .. maxRetries .. ")")
				break
			else
				warn("[FreeGiftManager] DataStore 重置失败 (尝试 " .. attempt .. "/" .. maxRetries .. "): " .. tostring(err))
				if attempt < maxRetries then
					wait(1) -- 重试前等待1秒
				end
			end
		end

		if not resetSuccess then
			warn("[FreeGiftManager] ❌ DataStore 重置最终失败，达到最大重试次数")
			return false
		end
	else
		resetSuccess = true
		print("[FreeGiftManager] ✓ Studio环境或DataStore不可用，跳过DataStore重置")
	end

	-- 4. 如果玩家在线，重新加载数据并启动计时器
	if player and player.Parent then
		local newData = FreeGiftManager.loadPlayerData(player)
		if newData then
			FreeGiftManager.startOnlineTimer(player)
			print("[FreeGiftManager] ✓ 已重新加载玩家数据并启动计时器")
		else
			warn("[FreeGiftManager] ⚠️ 重新加载玩家数据失败")
		end
	end

	print("[FreeGiftManager] ✅ 玩家数据重置完成: " .. player.Name)
	return true
end

return FreeGiftManager
