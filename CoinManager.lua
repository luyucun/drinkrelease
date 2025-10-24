-- 脚本名称: CoinManager
-- 脚本作用: 管理玩家金币系统，包括数据存储、UI更新和奖励发放
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local CoinManager = {}
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 检查是否在Studio环境中
local isStudio = RunService:IsStudio()

-- 创建DataStore用于永久存储玩家金币（仅在非Studio环境中）
local coinDataStore = nil
if not isStudio then
	coinDataStore = DataStoreService:GetDataStore("PlayerCoins")
else
end

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

-- 创建金币相关的RemoteEvent
local coinUpdateEvent
if not remoteEventsFolder:FindFirstChild("CoinUpdate") then
	coinUpdateEvent = Instance.new("RemoteEvent")
	coinUpdateEvent.Name = "CoinUpdate"
	coinUpdateEvent.Parent = remoteEventsFolder
else
	coinUpdateEvent = remoteEventsFolder:WaitForChild("CoinUpdate")
end

-- 玩家金币数据缓存
local playerCoins = {}

-- 🔧 新增：操作锁定机制，防止并发修改同一玩家数据
local playerOperationLocks = {}

-- 🔧 新增：保存队列，确保保存操作按顺序执行
local saveQueue = {}
local saveQueueProcessing = false

-- 默认配置
local CONFIG = {
	DEFAULT_COINS = 0,        -- 新玩家默认金币
	SAFE_DRINK_REWARD = 5,     -- 安全饮用奖励
	DATA_SAVE_INTERVAL = 30     -- 数据保存间隔（秒）
}

-- 🔧 新增：获取玩家操作锁
local function acquirePlayerLock(player)
	local playerId = tostring(player.UserId)
	if playerOperationLocks[playerId] then
		return false -- 已被锁定
	end
	playerOperationLocks[playerId] = true
	return true
end

-- 🔧 新增：释放玩家操作锁
local function releasePlayerLock(player)
	local playerId = tostring(player.UserId)
	playerOperationLocks[playerId] = nil
end

-- 🔧 新增：队列化保存操作，防止并发保存同一玩家数据
local function queueSaveOperation(player, coinAmount)
	table.insert(saveQueue, {
		player = player,
		coinAmount = coinAmount,
		timestamp = tick()
	})

	-- 启动队列处理（如果未在处理中）
	if not saveQueueProcessing then
		saveQueueProcessing = true
		spawn(function()
			CoinManager.processSaveQueue()
		end)
	end
end

-- 🔧 新增：处理保存队列
function CoinManager.processSaveQueue()
	while #saveQueue > 0 do
		local saveOperation = table.remove(saveQueue, 1)

		-- 检查玩家是否仍在线
		if saveOperation.player and saveOperation.player.Parent then
			CoinManager.savePlayerDataSync(saveOperation.player, saveOperation.coinAmount)
		end

		-- 短暂等待，避免过度频繁的DataStore调用
		task.wait(0.1)
	end
	saveQueueProcessing = false
end

-- 🔧 新增：同步保存玩家数据（带锁定机制）
function CoinManager.savePlayerDataSync(player, coinAmount)
	if not player or not coinAmount then return false end

	if not coinDataStore then
		return false
	end

	local playerId = tostring(player.UserId)
	local maxRetries = 3
	local saved = false

	for attempt = 1, maxRetries do
		local success, errorMessage = pcall(function()
			coinDataStore:SetAsync(playerId, coinAmount)
		end)

		if success then
			saved = true
			break
		else
			warn("❌ 同步保存玩家 " .. player.Name .. " 金币数据失败 (尝试 " .. attempt .. "/" .. maxRetries .. "): " .. tostring(errorMessage))
			if attempt < maxRetries then
				task.wait(1) -- 重试前等待1秒
			end
		end
	end

	if not saved then
		warn("🚨 玩家 " .. player.Name .. " 金币数据最终保存失败: " .. coinAmount .. " 金币可能丢失！")
	end

	return saved
end

-- 加载玩家金币数据
function CoinManager.loadPlayerData(player)
	-- 🔧 关键修复：检查玩家金币数据是否已被写入（例如早期购买已发放奖励）
	-- 如果已存在数据，说明可能是购买等操作已经初始化了玩家数据，不应覆盖
	if playerCoins[player] ~= nil then
		-- 玩家数据已存在（可能是购买奖励已发放），仅更新UI，不覆盖数据
		CoinManager.updatePlayerCoinUI(player)
		return playerCoins[player]
	end

	if not coinDataStore then
		-- Studio环境，使用默认金币
		local playerCoinData = CONFIG.DEFAULT_COINS
		playerCoins[player] = playerCoinData
		CoinManager.updatePlayerCoinUI(player)
		return playerCoinData
	end

	local playerId = tostring(player.UserId)
	local success, result = pcall(function()
		return coinDataStore:GetAsync(playerId)
	end)

	local playerCoinData
	if success and result then
		playerCoinData = result
	else
		-- 新玩家或加载失败，使用默认值
		playerCoinData = CONFIG.DEFAULT_COINS

		-- 立即保存默认数据
		CoinManager.savePlayerData(player, playerCoinData)
	end

	playerCoins[player] = playerCoinData

	-- 通知客户端更新UI
	CoinManager.updatePlayerCoinUI(player)

	return playerCoinData
end

-- 保存玩家金币数据
function CoinManager.savePlayerData(player, coinAmount)
	if not player or not coinAmount then return end

	if not coinDataStore then
		return
	end

	-- 🔧 关键修复：使用队列化保存，防止并发保存同一玩家数据
	queueSaveOperation(player, coinAmount)
end

-- 获取玩家当前金币
function CoinManager.getPlayerCoins(player)
	return playerCoins[player] or 0
end

-- V1.8: 获取玩家金币（别名，供ShopManager使用）
function CoinManager.getCoins(player)
	return CoinManager.getPlayerCoins(player)
end

-- V1.8: 检查玩家是否有足够金币
function CoinManager.canAfford(player, amount)
	if not player or not amount then return false end

	local currentCoins = CoinManager.getPlayerCoins(player)
	return currentCoins >= amount
end

-- V1.8: 移除玩家金币（供ShopManager使用）
function CoinManager.removeCoins(player, amount, reason)
	if not player or not amount or amount <= 0 then return false end

	-- 🔧 关键修复：获取操作锁，防止并发修改
	if not acquirePlayerLock(player) then
		warn("玩家 " .. player.Name .. " 正在进行其他金币操作，请稍后重试")
		return false
	end

	local success = false
	-- 使用pcall保护，确保即使出错也能释放锁
	pcall(function()
		local currentCoins = CoinManager.getPlayerCoins(player)
		if currentCoins < amount then
			warn("玩家 " .. player.Name .. " 金币不足，当前: " .. currentCoins .. ", 需要: " .. amount)
			return
		end

		local newCoins = currentCoins - amount
		playerCoins[player] = newCoins

		-- 更新UI
		CoinManager.updatePlayerCoinUI(player)

		-- 队列化保存数据
		CoinManager.savePlayerData(player, newCoins)

		-- 🔧 关键修复：使用pcall保护RemoteEvent调用
		pcall(function()
			-- 通知客户端金币变化
			coinUpdateEvent:FireClient(player, "coinsSpent", {
				amount = amount,
				reason = reason,
				newTotal = newCoins
			})
		end)

		success = true
	end)

	-- 🔧 关键修复：确保释放操作锁
	releasePlayerLock(player)
	return success
end

-- 增加玩家金币
function CoinManager.addCoins(player, amount, reason)
	if not player or type(amount) ~= "number" or amount <= 0 then
		warn("[CoinManager] 无效参数: player=" .. tostring(player) .. ", amount=" .. tostring(amount))
		return false
	end

	-- 🔧 关键修复：获取操作锁，防止并发修改
	if not acquirePlayerLock(player) then
		warn("玩家 " .. player.Name .. " 正在进行其他金币操作，请稍后重试")
		return false
	end

	local success = false
	-- 使用pcall保护，确保即使出错也能释放锁
	pcall(function()
		local currentCoins = CoinManager.getPlayerCoins(player)
		local newCoins = currentCoins + amount

		playerCoins[player] = newCoins

		-- 更新UI
		CoinManager.updatePlayerCoinUI(player)

		-- 队列化保存数据
		CoinManager.savePlayerData(player, newCoins)

		-- 🔧 关键修复：使用pcall保护RemoteEvent调用
		pcall(function()
			-- 通知客户端显示奖励动画
			coinUpdateEvent:FireClient(player, "showReward", {
				amount = amount,
				reason = reason,
				newTotal = newCoins
			})
		end)

		success = true
	end)

	-- 🔧 关键修复：确保释放操作锁
	releasePlayerLock(player)
	return success
end

-- 扣除玩家金币
function CoinManager.deductCoins(player, amount, reason)
	if not player or not amount or amount <= 0 then return false end

	-- 🔧 关键修复：获取操作锁，防止并发修改
	if not acquirePlayerLock(player) then
		warn("玩家 " .. player.Name .. " 正在进行其他金币操作，请稍后重试")
		return false
	end

	local success = false
	-- 使用pcall保护，确保即使出错也能释放锁
	pcall(function()
		local currentCoins = CoinManager.getPlayerCoins(player)
		if currentCoins < amount then
			warn("玩家 " .. player.Name .. " 金币不足，当前: " .. currentCoins .. ", 需要: " .. amount)
			return
		end

		local newCoins = currentCoins - amount
		playerCoins[player] = newCoins

		-- 更新UI
		CoinManager.updatePlayerCoinUI(player)

		-- 队列化保存数据
		CoinManager.savePlayerData(player, newCoins)

		success = true
	end)

	-- 🔧 关键修复：确保释放操作锁
	releasePlayerLock(player)
	return success
end

-- 更新玩家金币UI
function CoinManager.updatePlayerCoinUI(player)
	if not player then return end

	local coinAmount = CoinManager.getPlayerCoins(player)

	-- 🔧 关键修复：使用pcall保护RemoteEvent调用
	pcall(function()
		coinUpdateEvent:FireClient(player, "updateUI", {
			coins = coinAmount,
			formattedText = "$" .. coinAmount
		})
	end)
end

-- V1.7: 发放金币奖励（带好友加成）
function CoinManager.giveCoinsReward(player, baseCoins, tableId, reason)
	if not player or not baseCoins or baseCoins <= 0 then return false end

	local finalCoins = baseCoins

	-- 应用好友加成
	if _G.FriendsService and tableId then
		local bonus = _G.FriendsService:getRoomFriendsBonus(player, tableId)
		finalCoins = math.floor(baseCoins * (1 + bonus))
		if bonus > 0 then
			print("[CoinManager] 玩家 " .. player.Name .. " 获得好友加成: " .. (bonus * 100) .. "%, " .. baseCoins .. " -> " .. finalCoins)
		end
	end

	return CoinManager.addCoins(player, finalCoins, reason or "游戏奖励")
end

-- 奖励安全饮用
function CoinManager.rewardSafeDrinking(player)
	if not player then return false end

	-- 🔧 V1.6: 教程模式中不发放金币
	if _G.TutorialMode then
		print("[CoinManager] 教程模式，跳过安全饮用奖励")
		return true  -- 返回true表示处理成功，但不发放金币
	end

	return CoinManager.addCoins(player, CONFIG.SAFE_DRINK_REWARD, "安全饮用奶茶")
end

-- 玩家加入游戏处理
function CoinManager.onPlayerAdded(player)

	-- 等待玩家GUI加载完成
	player.CharacterAdded:Connect(function()
		wait(2) -- 等待UI完全加载
		CoinManager.loadPlayerData(player)
	end)

	-- 如果玩家已经有角色，立即加载
	if player.Character then
		wait(2)
		CoinManager.loadPlayerData(player)
	end
end

-- 玩家离开游戏处理
function CoinManager.onPlayerRemoving(player)
	local coinAmount = playerCoins[player]
	if coinAmount then
		-- 🔧 关键修复：立即同步保存数据，确保不丢失
		CoinManager.savePlayerDataSync(player, coinAmount)
		playerCoins[player] = nil
	end

	-- 🔧 关键修复：清理玩家的操作锁
	local playerId = tostring(player.UserId)
	playerOperationLocks[playerId] = nil
end

-- 定期保存所有在线玩家数据
function CoinManager.setupPeriodicSave()
	spawn(function()
		while true do
			wait(CONFIG.DATA_SAVE_INTERVAL)

			for player, coinAmount in pairs(playerCoins) do
				if player and player.Parent then -- 确保玩家还在线
					CoinManager.savePlayerData(player, coinAmount)
				end
			end

		end
	end)
end

-- 服务器关闭时保存所有数据
function CoinManager.saveAllDataOnShutdown()
	game:BindToClose(function()
		-- 🔧 关键修复：服务器关闭时同步保存所有玩家数据
		print("🔒 服务器关闭，开始保存所有玩家金币数据...")

		if not coinDataStore then
			print("⚠️ Studio环境或DataStore不可用，跳过保存")
			return
		end

		local playersToSave = {}
		for player, coinAmount in pairs(playerCoins) do
			table.insert(playersToSave, {player = player, coins = coinAmount})
		end

		print("📊 需要保存 " .. #playersToSave .. " 个玩家的数据")

		-- 🔧 关键修复：使用同步等待确保所有数据保存完成
		local savedCount = 0
		local failedCount = 0

		for _, data in ipairs(playersToSave) do
			local player = data.player
			local coinAmount = data.coins
			local playerId = tostring(player.UserId)

			-- 🔧 关键修复：同步保存，带重试机制
			local maxRetries = 3
			local saved = false

			for attempt = 1, maxRetries do
				local success, errorMessage = pcall(function()
					coinDataStore:SetAsync(playerId, coinAmount)
				end)

				if success then
					saved = true
					savedCount = savedCount + 1
					break
				else
					warn("❌ 保存玩家 " .. player.Name .. " 数据失败 (尝试 " .. attempt .. "/" .. maxRetries .. "): " .. tostring(errorMessage))
					if attempt < maxRetries then
						task.wait(0.5) -- 重试前等待
					end
				end
			end

			if not saved then
				failedCount = failedCount + 1
				warn("🚨 玩家 " .. player.Name .. " 数据最终保存失败，数据可能丢失！")
			end
		end

		print("✅ 服务器关闭保存完成: 成功=" .. savedCount .. ", 失败=" .. failedCount)
	end)
end

-- 调试：重置玩家金币（仅用于测试）
function CoinManager.resetPlayerCoins(player, newAmount)
	if not player then return false end

	newAmount = newAmount or CONFIG.DEFAULT_COINS
	playerCoins[player] = newAmount

	CoinManager.updatePlayerCoinUI(player)
	CoinManager.savePlayerData(player, newAmount)

	return true
end

-- 调试：获取所有玩家金币信息
function CoinManager.debugPrintAllCoins()
	for player, coinAmount in pairs(playerCoins) do
		if player and player.Parent then
		end
	end
end

-- V1.9: 重置玩家数据为新玩家（管理员命令用）
function CoinManager.resetPlayerData(userId, player)
	if not userId then return false end

	-- 清空内存缓存
	if player then
		playerCoins[player] = nil
	end

	-- 清空操作锁
	local userIdStr = tostring(userId)
	playerOperationLocks[userIdStr] = nil

	-- 重置DataStore为默认值
	if not coinDataStore then
		return true  -- Studio环境，直接返回
	end

	local success = false
	local maxRetries = 3

	for attempt = 1, maxRetries do
		local saveSuccess = pcall(function()
			coinDataStore:SetAsync(userIdStr, CONFIG.DEFAULT_COINS)
		end)

		if saveSuccess then
			success = true
			break
		else
			task.wait(1)
		end
	end

	if not success then
		warn("[CoinManager] 重置玩家 " .. userIdStr .. " 的金币数据失败")
		return false
	end

	-- 如果玩家在线，刷新UI
	if player and player.Parent then
		playerCoins[player] = CONFIG.DEFAULT_COINS
		CoinManager.updatePlayerCoinUI(player)
	end

	return true
end

-- 初始化金币管理器
function CoinManager.initialize()

	-- 设置玩家事件监听
	Players.PlayerAdded:Connect(CoinManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(CoinManager.onPlayerRemoving)

	-- 处理已在线的玩家
	for _, player in pairs(Players:GetPlayers()) do
		CoinManager.onPlayerAdded(player)
	end

	-- 启动定期保存
	CoinManager.setupPeriodicSave()

	-- 设置服务器关闭保存
	CoinManager.saveAllDataOnShutdown()

end

-- 启动管理器
CoinManager.initialize()

-- 将CoinManager暴露到全局环境，供其他脚本使用
_G.CoinManager = CoinManager

return CoinManager
