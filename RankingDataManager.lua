-- 脚本名称: RankingDataManager
-- 脚本作用: 管理排行榜数据存储、更新和排序，处理玩家胜负记录
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local RankingDataManager = {}
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- 检测是否在Studio环境中
local isStudio = RunService:IsStudio()

-- 创建DataStore用于存储排行榜数据（仅在非Studio环境中）
local rankingDataStore = nil
local globalRankingStore = nil
-- ✅ P1修复：新增OrderedDataStore用于高效排行榜查询
local orderedTotalWinsStore = nil
local orderedConsecutiveWinsStore = nil

-- DataStore连接状态
local dataStoreConnected = false
local dataStoreRetryAttempts = 0
local maxDataStoreRetries = 10

-- 初始化DataStore连接
local function initializeDataStores()
	if isStudio then
		-- Studio环境中DataStore默认禁用，这是正常行为
		return false
	end

	local success1, result1 = pcall(function()
		return DataStoreService:GetDataStore("PlayerRankingData")
	end)

	local success2, result2 = pcall(function()
		return DataStoreService:GetDataStore("GlobalRankingCache")
	end)

	-- ✅ P2-8修复：OrderedDataStore初始化失败不应影响核心功能
	local success3, result3 = pcall(function()
		return DataStoreService:GetOrderedDataStore("TotalWinsRanking")
	end)

	local success4, result4 = pcall(function()
		return DataStoreService:GetOrderedDataStore("ConsecutiveWinsRanking")
	end)

	-- 核心DataStore必须成功
	if success1 and success2 then
		rankingDataStore = result1
		globalRankingStore = result2

		-- OrderedDataStore是可选功能，失败时只警告
		if success3 and success4 then
			orderedTotalWinsStore = result3
			orderedConsecutiveWinsStore = result4
		else
			warn("RankingDataManager: OrderedDataStore初始化失败（可选功能，不影响核心排行榜）: " .. tostring(result3 or result4))
			-- 继续运行，只是没有离线Top玩家查询功能
		end

		dataStoreConnected = true
		dataStoreRetryAttempts = 0
		return true
	else
		warn("RankingDataManager: 核心DataStore连接失败 - " .. tostring(result1 or result2))
		dataStoreConnected = false
		return false
	end
end

-- DataStore重连机制
-- ✅ P3-3修复：重连后同步OrderedDataStore队列
local function setupDataStoreRetry()
	spawn(function()
		while not dataStoreConnected and dataStoreRetryAttempts < maxDataStoreRetries do
			wait(math.min(30 + dataStoreRetryAttempts * 10, 120)) -- 指数退避，最大2分钟

			dataStoreRetryAttempts = dataStoreRetryAttempts + 1

			if initializeDataStores() then

				-- 重连成功后，立即保存所有内存数据
				for player, data in pairs(RankingDataManager.playerRankingCache) do
					if player and player.Parent then
						RankingDataManager.savePlayerDataAsync(player, data)
					end
				end

				-- ✅ P3-3修复：重连后同步OrderedDataStore队列中的数据
				if orderedTotalWinsStore and orderedConsecutiveWinsStore then
					local queueCount = 0
					for playerId, queueData in pairs(RankingDataManager.orderedStoreUpdateQueue) do
						-- 异步更新OrderedDataStore
						spawn(function()
							pcall(function()
								orderedTotalWinsStore:SetAsync(playerId, queueData.totalWins)
							end)

							pcall(function()
								orderedConsecutiveWinsStore:SetAsync(playerId, queueData.consecutiveWins)
							end)
						end)

						queueCount = queueCount + 1

						-- 限制单次重连同步的数量，避免超限
						if queueCount >= 50 then
							break
						end
					end
				end

				break
			else
				warn("RankingDataManager: DataStore重连失败 (尝试 " .. dataStoreRetryAttempts .. ")")
			end
		end

		if not dataStoreConnected then
			warn("RankingDataManager: DataStore重连失败，已达最大重试次数，将永久运行在内存模式")
		end
	end)
end

-- 初始化DataStore
if not initializeDataStores() then
	if isStudio then
		-- Studio环境下运行在内存模式，这是正常行为
	else
		warn("RankingDataManager: 初始DataStore连接失败，启动重试机制")
		setupDataStoreRetry()
	end
end

-- 排行榜数据缓存
RankingDataManager.playerRankingCache = {}  -- 缓存所有玩家的排行榜数据
RankingDataManager.dirtyPlayers = {}  -- 🔧 标记数据已变化需要保存的玩家
RankingDataManager.globalRankingCache = {
	consecutiveWinsRanking = {},
	totalWinsRanking = {},
	lastUpdateTime = 0
}

-- ✅ P1修复：新增离线玩家数据缓存
RankingDataManager.offlinePlayersCache = {
	topPlayers = {},           -- 缓存的Top玩家数据
	lastFetchTime = 0,         -- 上次获取时间
	isFetching = false,        -- 是否正在获取中（防止并发）
	isPreloading = false       -- ✅ P2-6修复：是否正在预加载（启动时）
}

-- ✅ P0修复：OrderedDataStore更新队列（批量更新，减少请求）
RankingDataManager.orderedStoreUpdateQueue = {}  -- 待更新的玩家队列

-- 配置参数
local CONFIG = {
	UPDATE_INTERVAL = 60,        -- 排行榜更新间隔（秒）
	RANKING_LIMIT = 50,          -- 排行榜显示数量限制
	DATA_SAVE_INTERVAL = 120,    -- 🔧 数据保存间隔（秒）- 从30秒改为120秒，减少DataStore请求
	CACHE_EXPIRE_TIME = 300,     -- 缓存过期时间（秒）
	MAX_SAVES_PER_CYCLE = 50,    -- ✅ P0修复：从10提高到50，减少数据丢失风险
	PRIORITY_SAVE_LIMIT = 20,    -- ✅ P0修复：优先保存最近活跃的玩家数量
	OFFLINE_DATA_FETCH_LIMIT = 20,   -- ✅ P2-5修复：从50降低到20，减少阻塞时间
	OFFLINE_CACHE_EXPIRE = 300,  -- ✅ P1修复：离线数据缓存过期时间（秒）
	ORDERED_STORE_UPDATE_INTERVAL = 30,  -- ✅ P0修复：OrderedDataStore批量更新间隔（秒）
	MAX_ORDERED_UPDATES_PER_CYCLE = 20   -- ✅ P0修复：每周期最多更新OrderedDataStore的玩家数
}

-- 默认玩家排行榜数据
local DEFAULT_RANKING_DATA = {
	consecutiveWins = 0,
	totalWins = 0,
	lastGameTime = 0,
	displayName = "",
	pendingStreak = 0  -- V1.6: 死亡前的连胜数，用于付费恢复
}

-- 初始化玩家排行榜数据
function RankingDataManager.initializePlayerData(player)
	local playerId = tostring(player.UserId)

	-- 从DataStore加载数据（仅在可用时）
	local playerData
	if rankingDataStore then
		local success, data = pcall(function()
			return rankingDataStore:GetAsync("Player_" .. player.UserId)
		end)

		if success and data then
			playerData = data
			-- 确保数据结构完整
			for key, defaultValue in pairs(DEFAULT_RANKING_DATA) do
				if playerData[key] == nil then
					playerData[key] = defaultValue
				end
			end
		else
			if not success then
				warn("加载玩家 " .. player.Name .. " 排行榜数据失败: " .. tostring(data))
			end
			playerData = nil
		end
	else
		playerData = nil
	end

	if not playerData then
		-- 创建默认数据
		playerData = {}
		for key, value in pairs(DEFAULT_RANKING_DATA) do
			playerData[key] = value
		end
		playerData.displayName = player.Name

		-- ✅ P4-1修复：改为异步保存，避免阻塞玩家加入
		if rankingDataStore then
			RankingDataManager.savePlayerDataAsync(player, playerData)
		end
	end

	-- 更新显示名称
	playerData.displayName = player.Name

	-- 修复：检查缓存中是否已有更新的数据，避免覆盖
	local existingData = RankingDataManager.playerRankingCache[player]
	if existingData then
		-- 比较lastGameTime，如果缓存数据更新，则保留缓存数据
		if existingData.lastGameTime > playerData.lastGameTime then
			-- 只更新显示名称，其他数据保持缓存中的最新值
			existingData.displayName = player.Name
			return existingData
		else
			-- DataStore数据更新，合并数据
			-- 保留更大的胜利数和连胜数
			if existingData.totalWins > playerData.totalWins then
				playerData.totalWins = existingData.totalWins
			end
			if existingData.consecutiveWins > playerData.consecutiveWins then
				playerData.consecutiveWins = existingData.consecutiveWins
			end
			if existingData.pendingStreak > playerData.pendingStreak then
				playerData.pendingStreak = existingData.pendingStreak
			end
		end
	end

	-- 缓存数据
	RankingDataManager.playerRankingCache[player] = playerData

	return playerData
end

-- 同步保存玩家排行榜数据（带重试机制）
-- ✅ P3-2修复：保存失败时也更新队列，确保数据最终一致性
function RankingDataManager.savePlayerData(player, data, maxRetries)
	if not player or not data then return false end

	maxRetries = maxRetries or 3
	local playerId = tostring(player.UserId)

	-- ✅ P3-2修复：提前更新OrderedDataStore队列，确保数据不丢失
	-- 无论主DataStore是否保存成功，队列都会更新，后续批量任务会重试
	if orderedTotalWinsStore and orderedConsecutiveWinsStore then
		RankingDataManager.orderedStoreUpdateQueue[playerId] = {
			totalWins = data.totalWins or 0,
			consecutiveWins = data.consecutiveWins or 0,
			timestamp = tick()
		}
	end

	-- 只在DataStore可用时保存
	if not rankingDataStore then
		return true -- 返回true避免错误，数据仍在内存中且已加入队列
	end

	-- 同步重试机制
	for attempt = 1, maxRetries do
		local success, errorMessage = pcall(function()
			rankingDataStore:SetAsync("Player_" .. player.UserId, data)
		end)

		if success then
			return true
		else
			warn("保存玩家 " .. player.Name .. " 排行榜数据失败 (尝试 " .. attempt .. "): " .. tostring(errorMessage))

			if attempt < maxRetries then
				-- 指数退避重试
				local waitTime = math.min(2 ^ attempt, 10)
				wait(waitTime)
			end
		end
	end

	warn("保存玩家 " .. player.Name .. " 数据失败，已达最大重试次数（数据已加入OrderedDataStore队列）")
	return false
end

-- 异步保存函数（用于定期保存）
-- 🔧 关键修复：返回实际的保存状态，并提供失败回调
function RankingDataManager.savePlayerDataAsync(player, data, onFailure)
	if not player or not data then
		if onFailure then onFailure("invalid_parameters") end
		return false
	end

	spawn(function()
		local success = RankingDataManager.savePlayerData(player, data)

		-- 🔧 关键修复：保存失败时执行回调并重新标记为脏数据
		if not success then
			warn("⚠️ 异步保存失败: " .. player.Name .. "，重新标记为需要保存")

			-- 重新标记为脏数据，确保定期任务会重试
			RankingDataManager.dirtyPlayers[player] = true

			-- 执行失败回调
			if onFailure then
				onFailure("save_failed")
			end
		else
			print("✅ 异步保存成功: " .. player.Name)
		end
	end)

	return true  -- 返回true表示异步任务已启动，不代表保存成功
end

-- 获取玩家排行榜数据
-- ✅ P4-4修复：确保总是返回有效数据（从缓存或初始化）
function RankingDataManager.getPlayerRankingData(player)
	if not player then return nil end

	local cachedData = RankingDataManager.playerRankingCache[player]
	if cachedData then
		return cachedData
	end

	-- ✅ P4-4修复：玩家不在缓存中时，返回DEFAULT的副本而非引用
	-- 避免调用者修改DEFAULT常量
	local defaultCopy = {}
	for key, value in pairs(DEFAULT_RANKING_DATA) do
		defaultCopy[key] = value
	end
	return defaultCopy
end

-- 记录游戏结果
function RankingDataManager.recordGameResult(player, isWinner)
	if not player then
		warn("❌ RankingDataManager.recordGameResult: 玩家参数为空")
		return false
	end

	print("🎯 记录游戏结果: " .. player.Name .. " - " .. (isWinner and "获胜" or "失败"))

	-- 获取玩家当前数据
	local playerData = RankingDataManager.getPlayerRankingData(player)
	if not playerData then
		warn("❌ 无法获取玩家 " .. player.Name .. " 的排行榜数据")
		return false
	end

	-- 创建数据副本以避免直接修改缓存
	local newData = {}
	for key, value in pairs(playerData) do
		newData[key] = value
	end

	-- 保存原始数据用于对比
	local originalTotalWins = newData.totalWins
	local originalConsecutiveWins = newData.consecutiveWins

	if isWinner then
		-- 胜利：总胜利数+1，连胜数+1
		newData.totalWins = newData.totalWins + 1
		newData.consecutiveWins = newData.consecutiveWins + 1
		print("📈 " .. player.Name .. " 获胜: 总胜利 " .. originalTotalWins .. "→" .. newData.totalWins .. ", 连胜 " .. originalConsecutiveWins .. "→" .. newData.consecutiveWins)
	else
		-- 失败：连胜数重置为0，总胜利数不变
		newData.consecutiveWins = 0
		print("📉 " .. player.Name .. " 失败: 总胜利保持 " .. newData.totalWins .. ", 连胜 " .. originalConsecutiveWins .. "→0")
	end

	-- 更新最后游戏时间
	newData.lastGameTime = tick()
	newData.displayName = player.Name

	-- 🔧 关键修复：先尝试立即同步保存（关键游戏数据）
	local immediateSaveSuccess = false
	if rankingDataStore then
		print("💾 尝试立即保存关键游戏数据...")
		immediateSaveSuccess = RankingDataManager.savePlayerData(player, newData, 3) -- 最多重试3次

		if immediateSaveSuccess then
			print("✅ 立即保存成功: " .. player.Name)
		else
			warn("⚠️ 立即保存失败: " .. player.Name .. "，数据已缓存，将通过备用机制保存")
		end
	else
		warn("⚠️ DataStore不可用，数据仅保存在内存中")
	end

	-- 更新缓存（无论DataStore是否保存成功）
	RankingDataManager.playerRankingCache[player] = newData

	-- 🔧 标记为需要保存（脏数据标记）
	-- 即使立即保存成功，也保留脏标记作为双保险，定期任务会检查并跳过已保存的数据
	RankingDataManager.dirtyPlayers[player] = true

	-- 🔧 关键修复：如果立即保存失败，启动额外的异步重试机制
	if not immediateSaveSuccess then
		spawn(function()
			local retryAttempts = 0
			local maxRetries = 5
			local baseDelay = 2

			while retryAttempts < maxRetries do
				wait(baseDelay * (retryAttempts + 1)) -- 指数退避
				retryAttempts = retryAttempts + 1

				-- 检查玩家是否仍然在线且数据有效
				if not player or not player.Parent then
					warn("⚠️ 玩家 " .. (player and player.Name or "未知") .. " 已离线，停止重试保存")
					break
				end

				-- 检查缓存中的数据是否仍然是我们要保存的数据
				local currentCachedData = RankingDataManager.playerRankingCache[player]
				if not currentCachedData or currentCachedData.lastGameTime ~= newData.lastGameTime then
					print("ℹ️ 玩家 " .. player.Name .. " 数据已被新游戏更新，停止旧数据重试")
					break
				end

				print("🔄 第 " .. retryAttempts .. " 次重试保存: " .. player.Name)
				local retrySuccess = RankingDataManager.savePlayerData(player, newData, 2)

				if retrySuccess then
					print("✅ 重试保存成功: " .. player.Name .. " (第 " .. retryAttempts .. " 次)")
					break
				else
					warn("⚠️ 第 " .. retryAttempts .. " 次重试失败: " .. player.Name)
				end
			end

			if retryAttempts >= maxRetries then
				warn("❌ 所有重试已用尽，玩家 " .. player.Name .. " 数据依赖定期保存任务")
			end
		end)
	end

	-- 标记需要更新全服排行榜
	RankingDataManager.markGlobalRankingNeedUpdate()

	print("🎉 游戏结果记录流程完成: " .. player.Name)
	return true
end

-- 🔧 标记玩家数据为需要保存（供其他系统调用）
function RankingDataManager.markPlayerDirty(player)
	if not player then return end
	RankingDataManager.dirtyPlayers[player] = true
end

-- 标记全服排行榜需要更新
function RankingDataManager.markGlobalRankingNeedUpdate()
	RankingDataManager.globalRankingCache.lastUpdateTime = 0 -- 强制下次更新
end

-- 从DataStore加载全局排行榜
function RankingDataManager.loadGlobalRankingFromDataStore()
	if not globalRankingStore then
		return false
	end

	local success, result = pcall(function()
		return globalRankingStore:GetAsync("GlobalRankingData")
	end)

	if success and result then
		RankingDataManager.globalRankingCache.consecutiveWinsRanking = result.consecutiveWinsRanking or {}
		RankingDataManager.globalRankingCache.totalWinsRanking = result.totalWinsRanking or {}
		RankingDataManager.globalRankingCache.lastUpdateTime = result.lastUpdateTime or 0
		return true
	else
		warn("从DataStore加载全局排行榜失败: " .. tostring(result))
		return false
	end
end

-- 保存全局排行榜到DataStore
function RankingDataManager.saveGlobalRankingToDataStore()
	if not globalRankingStore then
		return false
	end

	local dataToSave = {
		consecutiveWinsRanking = RankingDataManager.globalRankingCache.consecutiveWinsRanking,
		totalWinsRanking = RankingDataManager.globalRankingCache.totalWinsRanking,
		lastUpdateTime = tick()
	}

	local success, errorMessage = pcall(function()
		globalRankingStore:SetAsync("GlobalRankingData", dataToSave)
	end)

	if success then
		RankingDataManager.globalRankingCache.lastUpdateTime = dataToSave.lastUpdateTime
		return true
	else
		warn("保存全局排行榜到DataStore失败: " .. tostring(errorMessage))
		return false
	end
end

-- ✅ P1修复：从OrderedDataStore获取Top N玩家数据（高效查询）
-- ✅ P2-5修复：优化性能，减少阻塞时间
function RankingDataManager.fetchTopPlayersFromOrderedStore(limit)
	limit = limit or CONFIG.OFFLINE_DATA_FETCH_LIMIT
	-- ✅ P2-5修复：限制最大查询数量为20，减少阻塞时间（从50降到20）
	limit = math.min(limit, 20)

	local topPlayers = {}

	-- 只在OrderedDataStore可用时获取
	if not orderedTotalWinsStore or not rankingDataStore then
		return topPlayers -- 返回空表，使用fallback逻辑
	end

	-- 获取Top玩家的UserId列表（按总胜利数降序）
	local success, pages = pcall(function()
		return orderedTotalWinsStore:GetSortedAsync(false, limit) -- false = 降序
	end)

	if not success or not pages then
		warn("从OrderedDataStore获取Top玩家失败: " .. tostring(pages))
		return topPlayers
	end

	-- ✅ P2-5修复：批量收集UserId，然后并行读取数据
	local userIdsToFetch = {}

	-- 先收集所有UserId（不阻塞）
	local playerCount = 0
	while playerCount < limit do
		if pages.IsFinished then
			break
		end

		local currentPage = pages:GetCurrentPage()

		for _, entry in ipairs(currentPage) do
			if playerCount >= limit then break end

			local userId = tonumber(entry.key)
			local totalWins = entry.value

			if userId and totalWins and totalWins > 0 then
				table.insert(userIdsToFetch, {
					userId = userId,
					totalWins = totalWins
				})
				playerCount = playerCount + 1
			end
		end

		if playerCount >= limit then
			break
		end

		if pages.IsFinished then
			break
		end

		-- 获取下一页（如果有）
		local nextSuccess = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)

		if not nextSuccess then
			break
		end
	end

	-- ✅ P2-5修复：批量读取玩家数据，每5个添加一次延迟（优化吞吐量）
	for i, entry in ipairs(userIdsToFetch) do
		local playerDataSuccess, playerData = pcall(function()
			return rankingDataStore:GetAsync("Player_" .. entry.userId)
		end)

		if playerDataSuccess and playerData then
			table.insert(topPlayers, {
				userId = entry.userId,
				displayName = playerData.displayName or "Player",
				consecutiveWins = playerData.consecutiveWins or 0,
				totalWins = playerData.totalWins or 0,
				lastGameTime = playerData.lastGameTime or 0
			})
		end

		-- ✅ P2-5修复：每5个玩家添加延迟（从10改为5，提高响应速度）
		if i % 5 == 0 and i < #userIdsToFetch then
			wait(0.05)  -- 缩短延迟时间（从0.1改为0.05秒）
		end
	end

	return topPlayers
end

-- ✅ P1修复：获取离线玩家数据（带缓存机制）
-- ✅ P2-6修复：预加载机制，减少首次调用阻塞
-- ✅ P3-1修复：修复topPlayers变量作用域错误
function RankingDataManager.getOfflinePlayersData(forceSync)
	local currentTime = tick()

	-- 检查缓存是否有效
	if currentTime - RankingDataManager.offlinePlayersCache.lastFetchTime < CONFIG.OFFLINE_CACHE_EXPIRE then
		-- 缓存未过期，直接返回
		return RankingDataManager.offlinePlayersCache.topPlayers
	end

	-- 检查是否正在获取中（防止并发）
	if RankingDataManager.offlinePlayersCache.isFetching then
		-- 返回旧缓存（虽然过期，但总比没有好）
		return RankingDataManager.offlinePlayersCache.topPlayers
	end

	-- ✅ P2-6修复：首次调用时使用超时机制，最多等待2秒
	local isFirstTime = RankingDataManager.offlinePlayersCache.lastFetchTime == 0

	if (isFirstTime or forceSync) and not RankingDataManager.offlinePlayersCache.isPreloading then
		-- 首次调用：带超时的同步获取
		RankingDataManager.offlinePlayersCache.isFetching = true

		local fetchStartTime = tick()
		local fetchCompleted = false
		-- ✅ P3-1修复：使用共享表存储结果，避免闭包作用域问题
		local fetchResult = {data = nil}

		-- 在子线程中执行获取
		spawn(function()
			local success, topPlayers = pcall(function()
				return RankingDataManager.fetchTopPlayersFromOrderedStore(CONFIG.OFFLINE_DATA_FETCH_LIMIT)
			end)

			if success then
				fetchResult.data = topPlayers
			else
				warn("getOfflinePlayersData获取数据异常: " .. tostring(topPlayers))
				fetchResult.data = {}
			end
			fetchCompleted = true
		end)

		-- ✅ P2-6修复：最多等待2秒，超时则返回空数组并继续异步加载
		local maxWaitTime = 2
		while not fetchCompleted and (tick() - fetchStartTime) < maxWaitTime do
			wait(0.1)
		end

		if fetchCompleted and fetchResult.data then
			-- 成功获取数据
			RankingDataManager.offlinePlayersCache.topPlayers = fetchResult.data
			RankingDataManager.offlinePlayersCache.lastFetchTime = tick()
			RankingDataManager.offlinePlayersCache.isFetching = false
			return fetchResult.data
		else
			-- 超时，继续异步加载但先返回空数组
			warn("getOfflinePlayersData首次调用超时，继续异步加载")

			-- 异步继续等待加载完成
			spawn(function()
				while not fetchCompleted do
					wait(0.5)
				end

				if fetchResult.data then
					RankingDataManager.offlinePlayersCache.topPlayers = fetchResult.data
					RankingDataManager.offlinePlayersCache.lastFetchTime = tick()
				end
				RankingDataManager.offlinePlayersCache.isFetching = false
			end)

			return {}  -- 返回空数组，使用fallback逻辑
		end
	end

	-- 非首次调用：异步刷新缓存，立即返回旧数据
	RankingDataManager.offlinePlayersCache.isFetching = true

	spawn(function()
		local success, topPlayers = pcall(function()
			return RankingDataManager.fetchTopPlayersFromOrderedStore(CONFIG.OFFLINE_DATA_FETCH_LIMIT)
		end)

		if success and topPlayers then
			-- 更新缓存
			RankingDataManager.offlinePlayersCache.topPlayers = topPlayers
			RankingDataManager.offlinePlayersCache.lastFetchTime = tick()
		else
			warn("异步刷新离线玩家数据失败: " .. tostring(topPlayers))
		end

		RankingDataManager.offlinePlayersCache.isFetching = false
	end)

	-- 返回旧缓存
	return RankingDataManager.offlinePlayersCache.topPlayers
end

-- 获取所有玩家的排行榜数据（包含历史数据）
-- ✅ P1修复：不再从globalRankingCache读取历史数据（循环依赖），改为从OrderedDataStore读取
function RankingDataManager.getAllPlayersRankingData()
	local allPlayersData = {}
	local playerDataMap = {} -- 用于去重

	-- 首先收集当前在线玩家的数据（优先级最高，数据最新）
	for player, data in pairs(RankingDataManager.playerRankingCache) do
		if player and player.Parent then -- 确保玩家还在线
			local playerInfo = {
				userId = player.UserId,
				displayName = player.Name,
				consecutiveWins = data.consecutiveWins,
				totalWins = data.totalWins,
				lastGameTime = data.lastGameTime or 0
			}
			playerDataMap[player.UserId] = playerInfo
			table.insert(allPlayersData, playerInfo)
		end
	end

	-- ✅ P1修复：从OrderedDataStore获取离线Top玩家数据（真实的历史数据）
	local offlinePlayersData = RankingDataManager.getOfflinePlayersData()

	for _, playerInfo in ipairs(offlinePlayersData) do
		if not playerDataMap[playerInfo.userId] then -- 避免与在线玩家重复
			table.insert(allPlayersData, playerInfo)
			playerDataMap[playerInfo.userId] = playerInfo
		end
	end

	-- ✅ P1修复：如果OrderedDataStore不可用，降级使用globalRankingCache作为fallback
	-- 这种情况仅在Studio环境或DataStore初始化失败时发生
	if #offlinePlayersData == 0 and not isStudio then
		-- fallback到旧逻辑（仅作为降级方案）
		local fallbackData = {}

		-- 从连胜排行榜获取历史数据
		for _, playerInfo in ipairs(RankingDataManager.globalRankingCache.consecutiveWinsRanking or {}) do
			if not playerDataMap[playerInfo.userId] then
				table.insert(fallbackData, playerInfo)
				playerDataMap[playerInfo.userId] = playerInfo
			end
		end

		-- 从总胜利排行榜获取历史数据
		for _, playerInfo in ipairs(RankingDataManager.globalRankingCache.totalWinsRanking or {}) do
			if not playerDataMap[playerInfo.userId] then
				table.insert(fallbackData, playerInfo)
				playerDataMap[playerInfo.userId] = playerInfo
			end
		end

		-- 合并fallback数据
		for _, playerInfo in ipairs(fallbackData) do
			table.insert(allPlayersData, playerInfo)
		end
	end

	return allPlayersData
end

-- 更新连胜数排行榜
function RankingDataManager.updateConsecutiveWinsRanking()

	local allData = RankingDataManager.getAllPlayersRankingData()

	-- 按连胜数排序（降序），连胜数相同时按总胜利数排序
	table.sort(allData, function(a, b)
		if a.consecutiveWins == b.consecutiveWins then
			if a.totalWins == b.totalWins then
				return a.lastGameTime > b.lastGameTime -- 最近游戏时间优先
			end
			return a.totalWins > b.totalWins
		end
		return a.consecutiveWins > b.consecutiveWins
	end)

	-- 限制数量
	local ranking = {}
	for i = 1, math.min(#allData, CONFIG.RANKING_LIMIT) do
		ranking[i] = allData[i]
	end

	RankingDataManager.globalRankingCache.consecutiveWinsRanking = ranking

	-- 保存到DataStore以实现跨服务器持久化
	spawn(function()
		RankingDataManager.saveGlobalRankingToDataStore()
	end)

	return ranking
end

-- 更新总胜利数排行榜
function RankingDataManager.updateTotalWinsRanking()

	local allData = RankingDataManager.getAllPlayersRankingData()

	-- 按总胜利数排序（降序），总胜利数相同时按连胜数排序
	table.sort(allData, function(a, b)
		if a.totalWins == b.totalWins then
			if a.consecutiveWins == b.consecutiveWins then
				return a.lastGameTime > b.lastGameTime -- 最近游戏时间优先
			end
			return a.consecutiveWins > b.consecutiveWins
		end
		return a.totalWins > b.totalWins
	end)

	-- 限制数量
	local ranking = {}
	for i = 1, math.min(#allData, CONFIG.RANKING_LIMIT) do
		ranking[i] = allData[i]
	end

	RankingDataManager.globalRankingCache.totalWinsRanking = ranking

	-- 保存到DataStore以实现跨服务器持久化
	spawn(function()
		RankingDataManager.saveGlobalRankingToDataStore()
	end)

	return ranking
end

-- 更新全服排行榜
function RankingDataManager.updateGlobalRankings()
	local currentTime = tick()

	-- 检查是否需要更新
	if currentTime - RankingDataManager.globalRankingCache.lastUpdateTime < CONFIG.UPDATE_INTERVAL then
		return false
	end

	-- 更新两个排行榜
	RankingDataManager.updateConsecutiveWinsRanking()
	RankingDataManager.updateTotalWinsRanking()

	-- 更新时间戳
	RankingDataManager.globalRankingCache.lastUpdateTime = currentTime

	-- 通知UI系统更新
	if _G.RankingUIManager and _G.RankingUIManager.onGlobalRankingUpdated then
		_G.RankingUIManager.onGlobalRankingUpdated()
	end

	return true
end

-- 获取连胜数排行榜
function RankingDataManager.getConsecutiveWinsRanking(limit)
	limit = limit or CONFIG.RANKING_LIMIT

	-- 确保排行榜是最新的
	RankingDataManager.updateGlobalRankings()

	local ranking = RankingDataManager.globalRankingCache.consecutiveWinsRanking or {}
	local result = {}

	for i = 1, math.min(#ranking, limit) do
		result[i] = ranking[i]
	end

	return result
end

-- 获取总胜利数排行榜
function RankingDataManager.getTotalWinsRanking(limit)
	limit = limit or CONFIG.RANKING_LIMIT

	-- 确保排行榜是最新的
	RankingDataManager.updateGlobalRankings()

	local ranking = RankingDataManager.globalRankingCache.totalWinsRanking or {}
	local result = {}

	for i = 1, math.min(#ranking, limit) do
		result[i] = ranking[i]
	end

	return result
end

-- 玩家加入游戏处理
function RankingDataManager.onPlayerAdded(player)

	-- 延迟初始化，等待其他系统加载完成
	spawn(function()
		wait(2)
		RankingDataManager.initializePlayerData(player)
	end)
end

-- 玩家离开游戏处理
-- ✅ P5-2修复：OrderedDataStore保存失败时不删除队列项
function RankingDataManager.onPlayerRemoving(player)

	local playerData = RankingDataManager.playerRankingCache[player]
	if playerData then
		-- 🔧 优先保存：玩家离开时立即保存，无论是否标记为dirty
		RankingDataManager.savePlayerData(player, playerData)

		-- ✅ P1修复：玩家离开时立即同步OrderedDataStore队列中的数据
		-- ✅ P5-2修复：只有成功时才删除队列项，失败时保留供后续重试
		local playerId = tostring(player.UserId)
		if orderedTotalWinsStore and orderedConsecutiveWinsStore and RankingDataManager.orderedStoreUpdateQueue[playerId] then
			local queueData = RankingDataManager.orderedStoreUpdateQueue[playerId]

			-- 同步更新（不能异步，因为玩家即将离开）
			local success1 = pcall(function()
				orderedTotalWinsStore:SetAsync(playerId, queueData.totalWins)
			end)

			local success2 = pcall(function()
				orderedConsecutiveWinsStore:SetAsync(playerId, queueData.consecutiveWins)
			end)

			-- ✅ P5-2修复：只有两个都成功才删除队列项
			if success1 and success2 then
				RankingDataManager.orderedStoreUpdateQueue[playerId] = nil
			else
				-- 保存失败，保留队列项供后续批量任务重试
				if not success1 then
					warn("玩家 " .. player.Name .. " 离开时OrderedDataStore(totalWins)保存失败，数据已保留在队列中")
				end
				if not success2 then
					warn("玩家 " .. player.Name .. " 离开时OrderedDataStore(consecutiveWins)保存失败，数据已保留在队列中")
				end
			end
		end

		RankingDataManager.playerRankingCache[player] = nil
		RankingDataManager.dirtyPlayers[player] = nil -- 清除dirty标记
	end
end

-- 定期保存所有在线玩家数据
function RankingDataManager.setupPeriodicSave()
	spawn(function()
		while true do
			wait(CONFIG.DATA_SAVE_INTERVAL)

			-- 🔧 优化：只保存标记为dirty的玩家，减少不必要的DataStore请求
			local playersToSave = {}
			for player, _ in pairs(RankingDataManager.dirtyPlayers) do
				if player and player.Parent then -- 确保玩家还在线
					local data = RankingDataManager.playerRankingCache[player]
					if data then
						table.insert(playersToSave, {player = player, data = data})
					end
				end
			end

			-- ✅ P0修复：智能优先级保存 - 按最近活跃时间排序
			-- 优先保存最近玩过游戏的玩家，他们的数据最重要
			table.sort(playersToSave, function(a, b)
				return (a.data.lastGameTime or 0) > (b.data.lastGameTime or 0)
			end)

			-- 🔧 限流：每次最多保存MAX_SAVES_PER_CYCLE个玩家，避免请求堆积
			-- ✅ P0修复：上限从10提高到50，覆盖更多并发场景
			local saveCount = 0
			local successCount = 0
			local failedPlayers = {}

			for _, playerInfo in ipairs(playersToSave) do
				if saveCount >= CONFIG.MAX_SAVES_PER_CYCLE then
					break -- 达到本周期上限，剩余的下次保存
				end

				-- 🔧 关键修复：使用同步保存并检查结果，只有成功时才清除脏标记
				local success = RankingDataManager.savePlayerData(playerInfo.player, playerInfo.data, 2) -- 最多重试2次

				if success then
					RankingDataManager.dirtyPlayers[playerInfo.player] = nil -- 只有成功时才清除dirty标记
					successCount = successCount + 1
					print("✅ 定期保存成功: " .. playerInfo.player.Name)
				else
					-- 保存失败，保留脏标记，下次重试
					table.insert(failedPlayers, playerInfo.player.Name)
					warn("⚠️ 定期保存失败: " .. playerInfo.player.Name .. "，保留脏标记供下次重试")
				end

				saveCount = saveCount + 1

				-- 🔧 添加小延迟，进一步平滑请求
				wait(0.1)
			end

			if saveCount > 0 then
				print("🔄 定期保存周期完成: " .. successCount .. "/" .. saveCount .. " 成功")
				if #failedPlayers > 0 then
					warn("⚠️ 失败的玩家将在下次周期重试: " .. table.concat(failedPlayers, ", "))
				end
			end
		end
	end)
end

-- 定期更新全服排行榜
function RankingDataManager.setupPeriodicRankingUpdate()
	spawn(function()
		while true do
			wait(CONFIG.UPDATE_INTERVAL)
			RankingDataManager.updateGlobalRankings()
		end
	end)
end

-- ✅ P0修复：定期批量更新OrderedDataStore
function RankingDataManager.setupOrderedStoreSync()
	spawn(function()
		while true do
			wait(CONFIG.ORDERED_STORE_UPDATE_INTERVAL)

			-- ✅ 修复continue错误：Lua没有continue，改用条件判断
			if orderedTotalWinsStore and orderedConsecutiveWinsStore then
				-- 收集待更新的玩家
				local playersToUpdate = {}
				for playerId, data in pairs(RankingDataManager.orderedStoreUpdateQueue) do
					table.insert(playersToUpdate, {
						playerId = playerId,
						totalWins = data.totalWins,
						consecutiveWins = data.consecutiveWins,
						timestamp = data.timestamp
					})
				end

				-- 按时间戳排序，优先更新最新的数据
				table.sort(playersToUpdate, function(a, b)
					return a.timestamp > b.timestamp
				end)

				-- ✅ P1修复：清理过期队列项（超过24小时）
				local currentTime = tick()
				local cleanedCount = 0
				for i = #playersToUpdate, 1, -1 do
					local ageHours = (currentTime - playersToUpdate[i].timestamp) / 3600
					if ageHours > 24 then
						-- 移除超过24小时的队列项
						RankingDataManager.orderedStoreUpdateQueue[playersToUpdate[i].playerId] = nil
						table.remove(playersToUpdate, i)
						cleanedCount = cleanedCount + 1
					end
				end

				-- 批量更新（限制数量，避免超限）
				local updateCount = 0
				for _, playerData in ipairs(playersToUpdate) do
					if updateCount >= CONFIG.MAX_ORDERED_UPDATES_PER_CYCLE then
						break
					end

					-- ✅ P4-3修复：分别跟踪每个store的成功状态，避免重复更新
					local success1 = pcall(function()
						orderedTotalWinsStore:SetAsync(playerData.playerId, playerData.totalWins)
					end)

					local success2 = pcall(function()
						orderedConsecutiveWinsStore:SetAsync(playerData.playerId, playerData.consecutiveWins)
					end)

					-- ✅ P4-3修复：只有两个都成功才从队列移除
					-- 如果部分成功，保留队列项但更新timestamp避免重复清理
					if success1 and success2 then
						RankingDataManager.orderedStoreUpdateQueue[playerData.playerId] = nil
						updateCount = updateCount + 1
					else
						-- 失败则保留在队列中，下次重试
						-- 更新timestamp避免被24小时清理逻辑误删
						RankingDataManager.orderedStoreUpdateQueue[playerData.playerId].timestamp = tick()

						if not success1 then
							warn("更新OrderedDataStore失败: totalWins for player " .. playerData.playerId)
						end
						if not success2 then
							warn("更新OrderedDataStore失败: consecutiveWins for player " .. playerData.playerId)
						end
					end

					-- 添加小延迟，平滑请求
					wait(0.1)
				end
			end
		end
	end)
end

-- 服务器关闭时保存所有数据（同步版本）
function RankingDataManager.saveAllDataOnShutdown()
	game:BindToClose(function()

		-- 🔧 优先保存dirty玩家，再保存所有玩家
		local playersToSave = {}

		-- 先收集所有dirty玩家
		for player, _ in pairs(RankingDataManager.dirtyPlayers) do
			if player and RankingDataManager.playerRankingCache[player] then
				table.insert(playersToSave, {
					player = player,
					data = RankingDataManager.playerRankingCache[player],
					priority = true
				})
			end
		end

		-- 再收集其他玩家
		for player, data in pairs(RankingDataManager.playerRankingCache) do
			if player and data and not RankingDataManager.dirtyPlayers[player] then
				table.insert(playersToSave, {
					player = player,
					data = data,
					priority = false
				})
			end
		end

		-- 同步保存每个玩家的数据
		local successCount = 0
		local failCount = 0

		for i, playerInfo in ipairs(playersToSave) do
			local success = RankingDataManager.savePlayerData(playerInfo.player, playerInfo.data, 5) -- 最多重试5次

			if success then
				successCount = successCount + 1
			else
				failCount = failCount + 1
			end
		end

		-- ✅ P0修复：同步保存OrderedDataStore队列中的所有数据
		if orderedTotalWinsStore and orderedConsecutiveWinsStore then
			local queueCount = 0
			for playerId, data in pairs(RankingDataManager.orderedStoreUpdateQueue) do
				-- 同步更新OrderedDataStore
				local success1 = pcall(function()
					orderedTotalWinsStore:SetAsync(playerId, data.totalWins)
				end)

				local success2 = pcall(function()
					orderedConsecutiveWinsStore:SetAsync(playerId, data.consecutiveWins)
				end)

				if success1 and success2 then
					queueCount = queueCount + 1
				end

				-- BindToClose只有5秒，限制最多保存30个
				if queueCount >= 30 then
					break
				end
			end
		end

		-- 同步保存最终的全局排行榜
		RankingDataManager.saveGlobalRankingToDataStore()

		-- 额外等待时间确保DataStore完成
		wait(3)
	end)
end

-- 调试：打印玩家排行榜数据
-- Debug function - prints removed for production
function RankingDataManager.debugPrintPlayerData(player)
end

-- 调试：打印全服排行榜
-- Debug function - prints removed for production
function RankingDataManager.debugPrintGlobalRankings()
end

-- 初始化排行榜数据管理器
function RankingDataManager.initialize()
	print("🚀 RankingDataManager 开始初始化...")

	-- 验证DataStore状态
	if isStudio then
		print("🏠 Studio环境：运行在内存模式")
	elseif rankingDataStore and globalRankingStore then
		print("💾 DataStore模式已启用")
	else
		warn("⚠️ RankingDataManager: DataStore不可用，运行在内存模式")
	end

	-- 设置玩家事件监听
	Players.PlayerAdded:Connect(RankingDataManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(RankingDataManager.onPlayerRemoving)

	-- 处理已在线的玩家
	for _, player in pairs(Players:GetPlayers()) do
		RankingDataManager.onPlayerAdded(player)
	end

	-- 加载全局排行榜数据
	spawn(function()
		wait(2) -- 等待DataStore连接稳定
		RankingDataManager.loadGlobalRankingFromDataStore()
	end)

	-- ✅ P2-6修复：预加载离线玩家数据，减少首次调用阻塞
	-- ✅ P3-5修复：添加异常保护，防止标志永久锁定
	spawn(function()
		wait(5) -- 等待DataStore稳定后再预加载
		if orderedTotalWinsStore and rankingDataStore then
			RankingDataManager.offlinePlayersCache.isPreloading = true
			RankingDataManager.offlinePlayersCache.isFetching = true

			-- ✅ P3-5修复：使用pcall保护，确保异常时标志能正确重置
			local success, topPlayers = pcall(function()
				return RankingDataManager.fetchTopPlayersFromOrderedStore(CONFIG.OFFLINE_DATA_FETCH_LIMIT)
			end)

			if success and topPlayers then
				RankingDataManager.offlinePlayersCache.topPlayers = topPlayers
				RankingDataManager.offlinePlayersCache.lastFetchTime = tick()
				print("✅ 离线玩家数据预加载完成")
			else
				warn("⚠️ 预加载离线玩家数据失败: " .. tostring(topPlayers))
				-- 失败时设置空表，避免nil错误
				RankingDataManager.offlinePlayersCache.topPlayers = {}
			end

			RankingDataManager.offlinePlayersCache.isFetching = false
			RankingDataManager.offlinePlayersCache.isPreloading = false
		end
	end)

	-- 🔧 新增：检查是否有待处理的游戏结果需要处理
	spawn(function()
		wait(3) -- 等待系统稳定

		if _G.PendingGameResults and #_G.PendingGameResults > 0 then
			print("🔄 发现 " .. #_G.PendingGameResults .. " 个待处理的游戏结果，开始处理...")

			local processedCount = 0
			local expiredCount = 0

			for i = #_G.PendingGameResults, 1, -1 do
				local result = _G.PendingGameResults[i]

				-- 检查结果是否过期（超过10分钟）
				if tick() - result.timestamp > 600 then
					table.remove(_G.PendingGameResults, i)
					expiredCount = expiredCount + 1
					warn("⚠️ 丢弃过期的游戏结果: " .. (result.winner and result.winner.Name or "未知") .. " vs " .. (result.loser and result.loser.Name or "未知"))
				else
					-- 验证玩家仍然有效
					if result.winner and result.winner.Parent and result.loser and result.loser.Parent then
						-- 使用DrinkSelectionManager的内部函数处理
						local success = false
						if _G.DrinkSelectionManager and _G.DrinkSelectionManager.recordGameResultToRankingInternal then
							success = _G.DrinkSelectionManager.recordGameResultToRankingInternal(result.winner, result.loser)
						else
							-- 直接调用RankingDataManager
							local winnerSuccess = RankingDataManager.recordGameResult(result.winner, true)
							local loserSuccess = RankingDataManager.recordGameResult(result.loser, false)
							success = winnerSuccess and loserSuccess
						end

						if success then
							table.remove(_G.PendingGameResults, i)
							processedCount = processedCount + 1
							print("✅ 成功处理初始化时的待处理结果: " .. result.winner.Name .. " vs " .. result.loser.Name)
						else
							warn("⚠️ 处理待处理结果失败: " .. result.winner.Name .. " vs " .. result.loser.Name)
						end
					else
						-- 玩家已离线，移除该结果
						table.remove(_G.PendingGameResults, i)
						warn("⚠️ 玩家已离线，移除游戏结果: " .. (result.winner and result.winner.Name or "未知") .. " vs " .. (result.loser and result.loser.Name or "未知"))
					end
				end
			end

			if processedCount > 0 then
				print("🎉 初始化时成功处理 " .. processedCount .. " 个待处理的游戏结果")
			end
			if expiredCount > 0 then
				print("🗑️ 清理了 " .. expiredCount .. " 个过期的游戏结果")
			end
		end
	end)

	-- 启动定期保存
	RankingDataManager.setupPeriodicSave()

	-- 启动定期更新排行榜
	RankingDataManager.setupPeriodicRankingUpdate()

	-- ✅ P0修复：启动OrderedDataStore同步任务
	if orderedTotalWinsStore and orderedConsecutiveWinsStore then
		RankingDataManager.setupOrderedStoreSync()
	end

	-- 设置服务器关闭保存
	RankingDataManager.saveAllDataOnShutdown()

	-- 重要：立即设置全局变量
	_G.RankingDataManager = RankingDataManager

	print("✅ RankingDataManager 初始化完成")
end

-- 启动管理器
RankingDataManager.initialize()

-- V1.6: PendingStreak 管理方法

-- 设置玩家的待恢复连胜数（死亡时调用）
-- ✅ P4-5修复：创建副本后修改，避免修改DEFAULT常量
function RankingDataManager.setPendingStreak(player, streakCount)
	if not player or not streakCount then return false end

	local playerData = RankingDataManager.getPlayerRankingData(player)
	if playerData then
		-- ✅ P4-5修复：创建数据副本避免直接修改
		local newData = {}
		for key, value in pairs(playerData) do
			newData[key] = value
		end

		newData.pendingStreak = streakCount
		RankingDataManager.playerRankingCache[player] = newData

		-- ✅ P0修复：标记为脏数据，确保与recordGameResult一致
		RankingDataManager.dirtyPlayers[player] = true

		-- 异步保存数据（立即保存，因为这是关键时刻）
		RankingDataManager.savePlayerDataAsync(player, newData)

		return true
	end

	return false
end

-- 获取玩家的待恢复连胜数
function RankingDataManager.getPendingStreak(player)
	if not player then return 0 end

	local playerData = RankingDataManager.getPlayerRankingData(player)
	return playerData and playerData.pendingStreak or 0
end

-- 恢复玩家的连胜数（购买成功时调用）
-- ✅ P4-5修复：创建副本后修改
function RankingDataManager.restorePendingStreak(player)
	if not player then return false end

	local playerData = RankingDataManager.getPlayerRankingData(player)
	if playerData and playerData.pendingStreak > 0 then
		local pendingStreak = playerData.pendingStreak

		-- ✅ P4-5修复：创建数据副本避免直接修改
		local newData = {}
		for key, value in pairs(playerData) do
			newData[key] = value
		end

		-- 恢复连胜数
		newData.consecutiveWins = pendingStreak
		newData.pendingStreak = 0  -- 清零待恢复数
		newData.lastGameTime = tick()

		RankingDataManager.playerRankingCache[player] = newData

		-- ✅ P0修复：标记为脏数据
		RankingDataManager.dirtyPlayers[player] = true

		-- 异步保存数据（立即保存）
		RankingDataManager.savePlayerDataAsync(player, newData)

		return true, pendingStreak
	end

	return false, 0
end

-- 清除玩家的待恢复连胜数（放弃购买时调用）
-- ✅ P4-5修复：创建副本后修改
function RankingDataManager.clearPendingStreak(player)
	if not player then return false end

	local playerData = RankingDataManager.getPlayerRankingData(player)
	if playerData and playerData.pendingStreak > 0 then
		local clearedStreak = playerData.pendingStreak

		-- ✅ P4-5修复：创建数据副本避免直接修改
		local newData = {}
		for key, value in pairs(playerData) do
			newData[key] = value
		end

		newData.pendingStreak = 0

		RankingDataManager.playerRankingCache[player] = newData

		-- ✅ P0修复：标记为脏数据
		RankingDataManager.dirtyPlayers[player] = true

		-- 异步保存数据（立即保存）
		RankingDataManager.savePlayerDataAsync(player, newData)

		return true
	end

	return false
end

-- 检查玩家是否有待恢复的连胜数
function RankingDataManager.hasPendingStreak(player)
	if not player then return false end

	local pendingStreak = RankingDataManager.getPendingStreak(player)
	return pendingStreak > 0
end

return RankingDataManager