-- 脚本名称: TaskDataManager
-- 脚本作用: 管理玩家每日任务数据，包括进度追踪、奖励发放和UTC0重置
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService
-- 版本: V1.8

local TaskDataManager = {}
TaskDataManager.__index = TaskDataManager

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 检查环境
local isStudio = RunService:IsStudio()

-- DataStore
local taskDataStore = nil
if not isStudio then
	taskDataStore = DataStoreService:GetDataStore("TaskData_V1")
end

-- 延迟加载配置
local TaskConfig = nil

-- 玩家任务数据缓存
local playerTaskData = {}

-- 操作锁
local playerOperationLocks = {}

-- 保存队列
local saveQueue = {}
local saveQueueProcessing = false

-- 默认任务数据
local DEFAULT_TASK_DATA = {
	dailyMatchesCompleted = 0,     -- 当日完成对局数
	lastResetTime = 0,             -- 上次UTC0重置时间
	claimedRewards = {
		task_1 = false,
		task_2 = false,
		task_3 = false
	}
}

-- ============================================
-- 配置加载
-- ============================================

local function loadConfig()
	if not TaskConfig then
		local success, result = pcall(function()
			return require(ReplicatedStorage:WaitForChild("TaskConfig", 10))
		end)

		if success then
			TaskConfig = result
			print("[TaskDataManager] ✓ TaskConfig加载成功")
		else
			warn("[TaskDataManager] ❌ TaskConfig加载失败: " .. tostring(result))
		end
	end
	return TaskConfig ~= nil
end

-- ============================================
-- 内部函数：获取/释放锁
-- ============================================

local function acquirePlayerLock(player)
	local userId = tostring(player.UserId)
	if playerOperationLocks[userId] then
		return false
	end
	playerOperationLocks[userId] = true
	return true
end

local function releasePlayerLock(player)
	local userId = tostring(player.UserId)
	playerOperationLocks[userId] = nil
end

-- ============================================
-- 内部函数：队列化保存
-- ============================================

local function queueSaveOperation(player, data)
	table.insert(saveQueue, {
		player = player,
		data = data,
		timestamp = tick()
	})

	if not saveQueueProcessing then
		saveQueueProcessing = true
		spawn(function()
			TaskDataManager.processSaveQueue()
		end)
	end
end

function TaskDataManager.processSaveQueue()
	while #saveQueue > 0 do
		local operation = table.remove(saveQueue, 1)

		if operation.player and operation.player.Parent then
			TaskDataManager.savePlayerTaskData(operation.player, operation.data)
		end

		task.wait(0.1)
	end
	saveQueueProcessing = false
end

-- ============================================
-- 内部函数：计算当前UTC0时间戳
-- ============================================

local function getCurrentUTC0Timestamp()
	local now = os.time()
	local date = os.date("!*t", now)

	return os.time({
		year = date.year,
		month = date.month,
		day = date.day,
		hour = 0,
		min = 0,
		sec = 0
	})
end

local function getNextUTC0Timestamp()
	local currentUTC0 = getCurrentUTC0Timestamp()
	return currentUTC0 + 86400
end

-- ============================================
-- 加载玩家任务数据
-- ============================================

function TaskDataManager:loadPlayerTaskData(player)
	if not player then return nil end

	local userId = player.UserId

	-- 如果已缓存，直接返回
	if playerTaskData[userId] then
		return playerTaskData[userId]
	end

	-- 创建默认数据的副本
	local defaultData = {}
	for k, v in pairs(DEFAULT_TASK_DATA) do
		if type(v) == "table" then
			defaultData[k] = {}
			for k2, v2 in pairs(v) do
				defaultData[k][k2] = v2
			end
		else
			defaultData[k] = v
		end
	end

	-- Studio环境直接返回默认值
	if isStudio then
		playerTaskData[userId] = defaultData
		print("[TaskDataManager] Studio环境 - 使用默认数据: " .. player.Name)
		return defaultData
	end

	-- 从DataStore加载
	local success, result = pcall(function()
		return taskDataStore:GetAsync(tostring(userId))
	end)

	if not success then
		warn("[TaskDataManager] 加载数据失败: " .. player.Name .. ", 使用默认值")
		playerTaskData[userId] = defaultData
		return defaultData
	end

	-- 如果DataStore中没有数据，使用默认值
	if not result then
		playerTaskData[userId] = defaultData
		print("[TaskDataManager] 新玩家数据初始化: " .. player.Name)
	else
		-- 合并数据，确保新字段存在
		for key, defaultValue in pairs(DEFAULT_TASK_DATA) do
			if result[key] == nil then
				result[key] = defaultValue
			end
		end
		playerTaskData[userId] = result
		print("[TaskDataManager] ✓ 已加载玩家数据: " .. player.Name)
	end

	return playerTaskData[userId]
end

-- ============================================
-- 保存玩家任务数据
-- ============================================

function TaskDataManager:savePlayerTaskData(player, data)
	if not player or not taskDataStore then return false end

	local userId = tostring(player.UserId)
	playerTaskData[player.UserId] = data

	-- 异步保存到DataStore
	spawn(function()
		local maxRetries = 3
		for attempt = 1, maxRetries do
			local success = pcall(function()
				taskDataStore:SetAsync(userId, data)
			end)

			if success then
				print("[TaskDataManager] ✓ 保存成功: " .. player.Name)
				return
			else
				warn("[TaskDataManager] 保存失败 (尝试 " .. attempt .. "/" .. maxRetries .. "): " .. player.Name)
				task.wait(1)
			end
		end
	end)

	return true
end

-- ============================================
-- 检查和重置每日任务数据
-- ============================================

function TaskDataManager:checkAndResetPlayer(player)
	if not player then return end

	local playerData = self:loadPlayerTaskData(player)
	local currentUTC0 = getCurrentUTC0Timestamp()

	-- 判断是否需要重置
	if playerData.lastResetTime < currentUTC0 then
		print("[TaskDataManager] 检测到UTC0已过，重置玩家任务: " .. player.Name)
		self:resetDailyTaskData(player)
	end
end

function TaskDataManager:resetDailyTaskData(player)
	if not player then return end

	local playerData = self:loadPlayerTaskData(player)

	-- 重置每日数据
	playerData.dailyMatchesCompleted = 0
	playerData.claimedRewards = {
		task_1 = false,
		task_2 = false,
		task_3 = false
	}
	playerData.lastResetTime = getCurrentUTC0Timestamp()

	self:savePlayerTaskData(player, playerData)

	print("[TaskDataManager] ✓ 已重置玩家任务: " .. player.Name)

	-- 通知客户端刷新UI
	self:notifyClientRefresh(player)
end

-- ============================================
-- 增加对局完成计数
-- ============================================

function TaskDataManager:incrementMatchCount(player)
	if not player then
		warn("[TaskDataManager] incrementMatchCount: 玩家参数为空")
		return false
	end

	-- 等待获取锁
	while not acquirePlayerLock(player) do
		task.wait(0.01)
	end

	local playerData = self:loadPlayerTaskData(player)

	-- 增加对局计数
	playerData.dailyMatchesCompleted = playerData.dailyMatchesCompleted + 1

	print("[TaskDataManager] ✓ 玩家 " .. player.Name .. " 对局计数: " .. playerData.dailyMatchesCompleted)

	queueSaveOperation(player, playerData)

	releasePlayerLock(player)

	-- 通知客户端更新进度
	self:notifyClientProgressUpdate(player)

	return true
end

-- ============================================
-- 检查是否可以领取奖励
-- ============================================

function TaskDataManager:canClaimTask(player, taskId)
	if not player or not taskId then return false end
	if not loadConfig() then return false end

	local playerData = self:loadPlayerTaskData(player)
	local taskConfig = TaskConfig.getTaskById(taskId)

	if not taskConfig then
		warn("[TaskDataManager] 任务ID不存在: " .. taskId)
		return false
	end

	-- 检查对局数是否达标
	if playerData.dailyMatchesCompleted < taskConfig.requiredMatches then
		return false
	end

	-- 检查是否已经领取过
	if playerData.claimedRewards["task_" .. taskId] then
		return false
	end

	return true
end

-- ============================================
-- 领取奖励
-- ============================================

function TaskDataManager:claimReward(player, taskId)
	if not player or not taskId then
		return false, "Invalid parameters"
	end

	if not loadConfig() then
		return false, "Config not loaded"
	end

	-- 等待获取锁
	while not acquirePlayerLock(player) do
		task.wait(0.01)
	end

	local playerData = self:loadPlayerTaskData(player)
	local taskConfig = TaskConfig.getTaskById(taskId)

	-- 检查任务配置
	if not taskConfig then
		releasePlayerLock(player)
		return false, "Invalid task"
	end

	-- 检查是否满足条件
	if not self:canClaimTask(player, taskId) then
		releasePlayerLock(player)
		return false, "Requirements Not Met"
	end

	-- 发放奖励 (原子性操作)
	local rewardSuccess = false

	if taskConfig.rewardType == TaskConfig.REWARD_TYPES.COINS then
		-- 发放金币
		if _G.CoinManager then
			rewardSuccess = _G.CoinManager.addCoins(player, taskConfig.rewardAmount, "每日任务奖励")
		else
			warn("[TaskDataManager] CoinManager未加载")
		end
	elseif taskConfig.rewardType == TaskConfig.REWARD_TYPES.WHEEL_SPINS then
		-- 发放转盘次数
		if _G.WheelDataManager and _G.WheelDataManager.addSpinsFromTaskReward then
			rewardSuccess = _G.WheelDataManager.addSpinsFromTaskReward(player, taskConfig.rewardAmount)
		else
			warn("[TaskDataManager] WheelDataManager未加载或方法不存在")
		end
	end

	-- 只有奖励发放成功才标记为已领取
	if rewardSuccess then
		playerData.claimedRewards["task_" .. taskId] = true
		queueSaveOperation(player, playerData)

		print("[TaskDataManager] ✓ 玩家 " .. player.Name .. " 领取任务 " .. taskId .. " 奖励成功")

		releasePlayerLock(player)

		-- 通知客户端更新UI
		self:notifyClientRefresh(player)

		return true, "Success"
	else
		warn("[TaskDataManager] 奖励发放失败: " .. player.Name .. ", 任务ID: " .. taskId)
		releasePlayerLock(player)
		return false, "Reward failed"
	end
end

-- ============================================
-- 获取玩家任务状态
-- ============================================

function TaskDataManager:getTaskStatus(player)
	if not player then return nil end

	local playerData = self:loadPlayerTaskData(player)

	return {
		dailyMatchesCompleted = playerData.dailyMatchesCompleted,
		claimedRewards = playerData.claimedRewards,
		nextResetTime = getNextUTC0Timestamp(),
		hasUnclaimedRewards = self:hasUnclaimedRewards(player)
	}
end

function TaskDataManager:hasUnclaimedRewards(player)
	if not player then return false end
	if not loadConfig() then return false end

	local playerData = self:loadPlayerTaskData(player)

	for _, task in ipairs(TaskConfig.TASKS) do
		local taskKey = "task_" .. task.id
		if not playerData.claimedRewards[taskKey] then
			if playerData.dailyMatchesCompleted >= task.requiredMatches then
				return true
			end
		end
	end

	return false
end

-- ============================================
-- RemoteEvent通信
-- ============================================

function TaskDataManager:notifyClientRefresh(player)
	if not player or not player.Parent then return end

	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEventsFolder then return end

	local taskEvent = remoteEventsFolder:FindFirstChild("TaskEvent")
	if not taskEvent then return end

	pcall(function()
		local status = self:getTaskStatus(player)
		taskEvent:FireClient(player, "statusRefresh", status)
	end)
end

function TaskDataManager:notifyClientProgressUpdate(player)
	if not player or not player.Parent then return end

	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEventsFolder then return end

	local taskEvent = remoteEventsFolder:FindFirstChild("TaskEvent")
	if not taskEvent then return end

	pcall(function()
		local status = self:getTaskStatus(player)
		taskEvent:FireClient(player, "progressUpdate", status)
	end)
end

-- ============================================
-- 定期检查UTC0重置
-- ============================================

function TaskDataManager.setupPeriodicResetCheck()
	spawn(function()
		while true do
			task.wait(60)  -- 每分钟检查一次

			local currentUTC0 = getCurrentUTC0Timestamp()

			for userId, playerData in pairs(playerTaskData) do
				if playerData.lastResetTime < currentUTC0 then
					local player = Players:GetPlayerByUserId(userId)
					if player and player.Parent then
						TaskDataManager:resetDailyTaskData(player)
					end
				end
			end
		end
	end)
end

-- ============================================
-- 初始化
-- ============================================

function TaskDataManager.initialize()
	print("[TaskDataManager] 🚀 开始初始化...")

	-- 加载配置
	if not loadConfig() then
		warn("[TaskDataManager] ❌ 配置加载失败，初始化中止")
		return
	end

	-- 创建RemoteEvent
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEventsFolder then
		warn("[TaskDataManager] ❌ RemoteEvents文件夹不存在")
		return
	end

	local taskEvent = remoteEventsFolder:FindFirstChild("TaskEvent")
	if not taskEvent then
		taskEvent = Instance.new("RemoteEvent")
		taskEvent.Name = "TaskEvent"
		taskEvent.Parent = remoteEventsFolder
		print("[TaskDataManager] ✓ 创建TaskEvent")
	end

	-- 设置事件监听
	taskEvent.OnServerEvent:Connect(function(player, action, data)
		if action == "claimReward" then
			local success, message = TaskDataManager:claimReward(player, data.taskId)
			if success then
				-- 通知客户端领取成功
				taskEvent:FireClient(player, "rewardSuccess", {
					taskId = data.taskId
				})
			else
				-- 通知客户端失败原因
				taskEvent:FireClient(player, "rewardFailed", {
					taskId = data.taskId,
					reason = message
				})
			end
		elseif action == "requestStatus" then
			local status = TaskDataManager:getTaskStatus(player)
			taskEvent:FireClient(player, "statusResponse", status)
		end
	end)

	-- 玩家加入时检查重置
	Players.PlayerAdded:Connect(function(player)
		task.wait(2)  -- 等待其他系统加载
		TaskDataManager:checkAndResetPlayer(player)
	end)

	-- 玩家离开时保存数据
	Players.PlayerRemoving:Connect(function(player)
		local playerData = playerTaskData[player.UserId]
		if playerData then
			TaskDataManager:savePlayerTaskData(player, playerData)
		end
		playerTaskData[player.UserId] = nil
		playerOperationLocks[tostring(player.UserId)] = nil
	end)

	-- 服务器关闭时保存所有数据
	game:BindToClose(function()
		print("[TaskDataManager] 🔒 服务器关闭，保存所有数据...")
		for userId, playerData in pairs(playerTaskData) do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				TaskDataManager:savePlayerTaskData(player, playerData)
			end
		end
		task.wait(3)  -- 等待保存完成
	end)

	-- 启动定期重置检查
	TaskDataManager.setupPeriodicResetCheck()

	-- 处理已在线玩家
	for _, player in pairs(Players:GetPlayers()) do
		TaskDataManager:checkAndResetPlayer(player)
	end

	-- 全局导出
	_G.TaskDataManager = TaskDataManager

	print("[TaskDataManager] ✅ 初始化完成")
end

return TaskDataManager
