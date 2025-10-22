-- 脚本名称: WheelDataManager
-- 脚本作用: 转盘数据持久化管理，仿照CoinManager模式
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local WheelDataManager = {}
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 检查是否在Studio环境
local isStudio = RunService:IsStudio()

-- DataStore
local wheelDataStore = nil
if not isStudio then
	wheelDataStore = DataStoreService:GetDataStore("PlayerWheelData_V1")
end

-- 引入配置 (延迟加载，避免循环依赖)
local WheelConfig = nil

-- 玩家转盘数据缓存
local playerWheelData = {}

-- 免费次数倒计时状态
local freeSpinTimers = {}

-- RemoteEvents (延迟初始化)
local wheelDataSyncEvent = nil
local remoteEventsFolder = nil

-- 默认数据结构
local DEFAULT_WHEEL_DATA = {
	spinCount = 0,              -- 可用转盘次数
	totalSpinsUsed = 0,         -- 总使用次数
	lastFreeSpinTime = 0,       -- 上次免费次数获得时间
	isOnline = false,           -- 在线状态
	sessionStartTime = 0,       -- 本次会话开始时间
	hasReceivedFirstFreeSpin = false,  -- 🎁 是否已获得过首次免费转盘（新玩家优惠标记）
	version = 1
}

-- ============================================
-- 配置和RemoteEvents初始化
-- ============================================

-- 延迟加载配置
local function loadConfig()
	if not WheelConfig then
		local success, result = pcall(function()
			return require(ReplicatedStorage:WaitForChild("WheelConfig", 10))
		end)

		if success then
			WheelConfig = result
		else
			warn("❌ WheelDataManager: WheelConfig加载失败: " .. tostring(result))
		end
	end
	return WheelConfig ~= nil
end

-- 初始化RemoteEvents
local function initializeRemoteEvents()
	if not remoteEventsFolder then
		remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
		if not remoteEventsFolder then
			warn("❌ WheelDataManager: RemoteEvents文件夹不存在")
			return false
		end
	end

	if not wheelDataSyncEvent then
		wheelDataSyncEvent = remoteEventsFolder:WaitForChild("WheelDataSync", 5)
		if not wheelDataSyncEvent then
			warn("❌ WheelDataManager: WheelDataSync事件不存在")
			return false
		end
	end

	return true
end

-- ============================================
-- 数据管理核心函数
-- ============================================

-- 初始化玩家转盘数据
function WheelDataManager.initializePlayerData(player)
	if playerWheelData[player] then
		warn("WheelDataManager: 玩家数据已存在，跳过初始化: " .. player.Name)
		return
	end

	local success, data = false, nil
	local isNewPlayer = true  -- 🔧 关键：标记是否是真正的新玩家

	if wheelDataStore then
		success, data = pcall(function()
			return wheelDataStore:GetAsync("Player_" .. player.UserId)
		end)
	end

	if success and data then
		-- 从DataStore加载成功 → 这是老玩家
		isNewPlayer = false

		-- 验证数据完整性
		for key, defaultValue in pairs(DEFAULT_WHEEL_DATA) do
			if data[key] == nil then
				data[key] = defaultValue
			end
		end

		-- 🔧 关键修复：老玩家强制设置为已获得首次免费转盘
		-- 防止老玩家享受新玩家优惠
		if data.hasReceivedFirstFreeSpin == nil or data.hasReceivedFirstFreeSpin == false then
			data.hasReceivedFirstFreeSpin = true
		end

		playerWheelData[player] = data
	else
		-- 使用默认数据 → 这是新玩家
		isNewPlayer = true
		playerWheelData[player] = {}
		for key, value in pairs(DEFAULT_WHEEL_DATA) do
			playerWheelData[player][key] = value
		end
	end

	-- 设置在线状态
	playerWheelData[player].isOnline = true
	playerWheelData[player].sessionStartTime = tick()

	-- 初始化倒计时
	WheelDataManager.initializeFreeSpinTimer(player)

	-- 同步数据到客户端
	WheelDataManager.syncDataToClient(player)
end

-- 保存玩家数据
function WheelDataManager.savePlayerData(player)
	if not playerWheelData[player] or not wheelDataStore then
		return false
	end

	-- 🔧 Bug #17修复：添加重试机制,仿照CoinManager
	local maxRetries = 3
	local saved = false

	for attempt = 1, maxRetries do
		local success, error = pcall(function()
			wheelDataStore:SetAsync("Player_" .. player.UserId, playerWheelData[player])
		end)

		if success then
			saved = true
			break
		else
			warn("❌ 保存玩家 " .. player.Name .. " 转盘数据失败 (尝试 " .. attempt .. "/" .. maxRetries .. "): " .. tostring(error))
			if attempt < maxRetries then
				task.wait(1) -- 重试前等待1秒
			end
		end
	end

	if not saved then
		warn("🚨 玩家 " .. player.Name .. " 转盘数据最终保存失败，数据可能丢失！")
	end

	return saved
end

-- ============================================
-- 转盘次数管理
-- ============================================

-- 获取玩家转盘次数
function WheelDataManager.getSpinCount(player)
	if not playerWheelData[player] then
		return 0
	end
	return playerWheelData[player].spinCount
end

-- 增加转盘次数
function WheelDataManager.addSpinCount(player, count, source)
	if not playerWheelData[player] or count <= 0 then
		return false
	end

	source = source or "unknown"
	local oldCount = playerWheelData[player].spinCount
	playerWheelData[player].spinCount = oldCount + count

	-- 保存数据
	WheelDataManager.savePlayerData(player)

	-- 通知客户端更新
	WheelDataManager.syncDataToClient(player)

	-- 通知客户端播放动画
	WheelDataManager.notifySpinCountAdded(player, count)

	return true
end

-- V1.7: 从邀请奖励增加转盘次数
function WheelDataManager.addSpinsFromInviteReward(player, count)
	if not player or count <= 0 then
		return false
	end

	return WheelDataManager.addSpinCount(player, count, "invite_reward")
end

-- 使用转盘次数
function WheelDataManager.useSpinCount(player)
	if not playerWheelData[player] then
		return false
	end

	if playerWheelData[player].spinCount <= 0 then
		return false
	end

	playerWheelData[player].spinCount = playerWheelData[player].spinCount - 1
	playerWheelData[player].totalSpinsUsed = playerWheelData[player].totalSpinsUsed + 1

	-- 保存数据
	WheelDataManager.savePlayerData(player)

	-- 通知客户端更新
	WheelDataManager.syncDataToClient(player)

	return true
end

-- ============================================
-- 免费次数倒计时系统
-- ============================================

-- 初始化免费次数倒计时
function WheelDataManager.initializeFreeSpinTimer(player)
	if not loadConfig() then
		warn("WheelDataManager: 配置未加载，跳过倒计时初始化")
		return
	end

	local currentTime = tick()

	-- 🔧 关键修复V2：玩家每次上线都重置倒计时起点
	-- 需求：玩家离线后再进来，需要重新开始倒计时
	-- 无论之前的 lastFreeSpinTime 是什么值，都重置为当前时间
	playerWheelData[player].lastFreeSpinTime = currentTime

	-- 启动倒计时
	WheelDataManager.startFreeSpinTimer(player)
end

-- 启动免费次数倒计时
function WheelDataManager.startFreeSpinTimer(player)
	-- 🔧 Bug #16修复：玩家快速重连时，先停止旧的倒计时
	if freeSpinTimers[player] then
		WheelDataManager.stopFreeSpinTimer(player)
		task.wait(0.1) -- 等待旧循环结束
	end

	if not WheelConfig then
		warn("⚠️ WheelDataManager: 配置未加载，跳过倒计时启动")
		return
	end

	-- 🔧 重大修复：使用while循环代替递归，避免栈溢出
	local function updateTimer()
		-- 🎁 判断使用哪个免费间隔（只检查一次，避免重复打印）
		local isFirstFreeSpin = not playerWheelData[player].hasReceivedFirstFreeSpin

		while player.Parent and playerWheelData[player] and playerWheelData[player].isOnline do
			local currentTime = tick()
			local lastFreeTime = playerWheelData[player].lastFreeSpinTime
			local elapsed = currentTime - lastFreeTime

			-- 🎁 新功能：判断使用哪个免费间隔
			-- 如果玩家从未获得过首次免费转盘，使用首次间隔（3分钟）
			-- 否则使用正常间隔（5分钟）
			local freeSpinInterval
			if isFirstFreeSpin then
				freeSpinInterval = WheelConfig.SETTINGS.FIRST_FREE_SPIN_INTERVAL
			else
				freeSpinInterval = WheelConfig.SETTINGS.FREE_SPIN_INTERVAL
			end

			if elapsed >= freeSpinInterval then
				-- 发放免费次数
				WheelDataManager.addSpinCount(player, 1, "free_timer")
				playerWheelData[player].lastFreeSpinTime = currentTime

				-- 🎁 标记已获得首次免费转盘（仅第一次）
				if not playerWheelData[player].hasReceivedFirstFreeSpin then
					playerWheelData[player].hasReceivedFirstFreeSpin = true
					isFirstFreeSpin = false  -- 🔧 关键修复：立即更新本地标志位，确保下次使用5分钟间隔
				end

				WheelDataManager.savePlayerData(player)
			end

			-- 通知客户端剩余时间
			local remainingTime = math.max(0, freeSpinInterval - elapsed)
			WheelDataManager.updateFreeTimerUI(player, remainingTime)

			-- 等待1秒后继续下一次检查
			task.wait(1)
		end

		-- 清理倒计时状态
		freeSpinTimers[player] = nil
	end

	freeSpinTimers[player] = true
	task.spawn(updateTimer)
end

-- 停止免费次数倒计时
function WheelDataManager.stopFreeSpinTimer(player)
	if playerWheelData[player] then
		playerWheelData[player].isOnline = false
	end
	freeSpinTimers[player] = nil
end

-- ============================================
-- 客户端通信
-- ============================================

-- 同步数据到客户端
function WheelDataManager.syncDataToClient(player)
	if not initializeRemoteEvents() or not player.Parent then
		return
	end

	local spinCount = WheelDataManager.getSpinCount(player)
	wheelDataSyncEvent:FireClient(player, "dataUpdate", {
		spinCount = spinCount
	})
end

-- 更新免费倒计时UI
function WheelDataManager.updateFreeTimerUI(player, remainingTime)
	if not initializeRemoteEvents() or not player.Parent then
		return
	end

	wheelDataSyncEvent:FireClient(player, "timerUpdate", {
		remainingTime = math.floor(remainingTime)
	})
end

-- 通知客户端次数增加（播放动画）
function WheelDataManager.notifySpinCountAdded(player, addedCount)
	if not initializeRemoteEvents() or not player.Parent then
		return
	end

	wheelDataSyncEvent:FireClient(player, "spinCountAdded", {
		newSpinCount = WheelDataManager.getSpinCount(player),
		addedCount = addedCount
	})
end

-- ============================================
-- 玩家事件处理
-- ============================================

-- 玩家加入处理
function WheelDataManager.onPlayerAdded(player)
	task.spawn(function()
		task.wait(3) -- 等待其他系统加载，包括RemoteEvents
		WheelDataManager.initializePlayerData(player)
	end)
end

-- 玩家离开处理
function WheelDataManager.onPlayerRemoving(player)
	WheelDataManager.stopFreeSpinTimer(player)
	if playerWheelData[player] then
		WheelDataManager.savePlayerData(player)
		playerWheelData[player] = nil
	end
end

-- 🔧 Bug #17修复：定期保存所有在线玩家数据
function WheelDataManager.setupPeriodicSave()
	task.spawn(function()
		while true do
			task.wait(30) -- 每30秒保存一次

			local saveCount = 0
			for player, wheelData in pairs(playerWheelData) do
				if player and player.Parent then -- 确保玩家还在线
					WheelDataManager.savePlayerData(player)
					saveCount = saveCount + 1
				end
			end
		end
	end)
end

-- 🔧 Bug #17修复：服务器关闭时保存所有数据
function WheelDataManager.saveAllDataOnShutdown()
	game:BindToClose(function()
		if not wheelDataStore then
			return
		end

		local playersToSave = {}
		for player, wheelData in pairs(playerWheelData) do
			table.insert(playersToSave, {player = player, data = wheelData})
		end

		local savedCount = 0
		local failedCount = 0

		for _, playerData in ipairs(playersToSave) do
			local player = playerData.player
			local maxRetries = 3
			local saved = false

			for attempt = 1, maxRetries do
				local success, error = pcall(function()
					wheelDataStore:SetAsync("Player_" .. player.UserId, playerData.data)
				end)

				if success then
					saved = true
					savedCount = savedCount + 1
					break
				else
					warn("❌ 保存玩家 " .. player.Name .. " 数据失败 (尝试 " .. attempt .. "/" .. maxRetries .. "): " .. tostring(error))
					if attempt < maxRetries then
						task.wait(0.5) -- 重试前等待
					end
				end
			end

			if not saved then
				failedCount = failedCount + 1
				warn("🚨 玩家 " .. player.Name .. " 转盘数据最终保存失败，数据可能丢失！")
			end
		end
	end)
end

-- ============================================
-- RemoteEvent处理
-- ============================================

-- 设置RemoteEvent监听
function WheelDataManager.setupRemoteEvents()
	if not initializeRemoteEvents() then
		return
	end

	wheelDataSyncEvent.OnServerEvent:Connect(function(player, action)
		if action == "requestData" then
			WheelDataManager.syncDataToClient(player)
		end
	end)
end

-- ============================================
-- 初始化和启动
-- ============================================

-- 初始化管理器
function WheelDataManager.initialize()
	-- 延迟加载配置
	task.spawn(function()
		task.wait(2) -- 等待ReplicatedStorage完全加载
		loadConfig()
	end)

	-- 设置RemoteEvent监听
	task.spawn(function()
		task.wait(3) -- 等待RemoteEvents创建
		WheelDataManager.setupRemoteEvents()
	end)

	-- 设置玩家事件
	Players.PlayerAdded:Connect(WheelDataManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(WheelDataManager.onPlayerRemoving)

	-- 处理已在线玩家
	for _, player in pairs(Players:GetPlayers()) do
		WheelDataManager.onPlayerAdded(player)
	end

	-- 🔧 Bug #17修复：启动定期保存
	WheelDataManager.setupPeriodicSave()

	-- 🔧 Bug #17修复：设置服务器关闭保存
	WheelDataManager.saveAllDataOnShutdown()
end

-- 启动管理器
WheelDataManager.initialize()

-- 导出到全局
_G.WheelDataManager = WheelDataManager

return WheelDataManager