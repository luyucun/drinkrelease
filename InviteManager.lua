-- 脚本名称: InviteManager
-- 脚本作用: 管理玩家的邀请系统，包括邀请数据、奖励发放和UTC0重置
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local InviteManager = {}
InviteManager.__index = InviteManager

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 检查环境
local isStudio = RunService:IsStudio()

-- DataStore
local inviteDataStore = nil
if not isStudio then
	inviteDataStore = DataStoreService:GetDataStore("InviteData_V1")
end

-- 玩家邀请数据缓存
local playerInviteData = {}

-- 操作锁
local playerOperationLocks = {}

-- 保存队列
local saveQueue = {}
local saveQueueProcessing = false

-- 邀请链接映射表
local inviteLinkMap = {}

-- 默认邀请数据
local DEFAULT_INVITE_DATA = {
	invitedCount = 0,              -- 累计邀请人数
	dailyInvitedCount = 0,         -- 当日邀请人数
	lastResetTime = 0,             -- 上次UTC0重置时间
	claimedRewards = {
		reward_1 = false,
		reward_3 = false,
		reward_5 = false
	},
	invitedPlayerIds = {},         -- 邀请过的玩家ID列表
	inviteLinks = {}               -- 邀请链接追踪
}

-- 奖励配置
local REWARD_CONFIG = {
	reward_1 = {
		requiredCount = 1,
		rewards = {
			coins = 200
		}
	},
	reward_3 = {
		requiredCount = 3,
		rewards = {
			coins = 200,
			wheelSpins = 1
		}
	},
	reward_5 = {
		requiredCount = 5,
		rewards = {
			coins = 200,
			wheelSpins = 2,
			poisonClear = 1
		}
	}
}

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
			InviteManager.processSaveQueue()
		end)
	end
end

function InviteManager.processSaveQueue()
	while #saveQueue > 0 do
		local operation = table.remove(saveQueue, 1)

		if operation.player and operation.player.Parent then
			InviteManager.savePlayerInviteData(operation.player, operation.data)
		end

		task.wait(0.1)
	end
	saveQueueProcessing = false
end

-- ============================================
-- 内部函数：生成随机邀请码
-- ============================================

local function generateRandomCode()
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	local code = ""
	math.randomseed(os.time() + math.random(10000))

	for i = 1, 32 do
		local randomIndex = math.random(1, #chars)
		code = code .. string.sub(chars, randomIndex, randomIndex)
	end

	return code
end

-- ============================================
-- 内部函数：计算当前UTC0时间戳
-- ============================================

local function getCurrentUTC0Timestamp()
	local now = os.time()
	local date = os.date("*t", now)

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
-- 加载玩家邀请数据
-- ============================================

function InviteManager:loadPlayerInviteData(player)
	if not player then return nil end

	local userId = player.UserId

	-- 如果已缓存，直接返回
	if playerInviteData[userId] then
		return playerInviteData[userId]
	end

	-- 创建默认数据的副本
	local defaultData = {}
	for k, v in pairs(DEFAULT_INVITE_DATA) do
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
		playerInviteData[userId] = defaultData
		return defaultData
	end

	-- 从DataStore加载
	local success, result = pcall(function()
		return inviteDataStore:GetAsync(tostring(userId))
	end)

	if not success then
		warn("[InviteManager] 加载玩家邀请数据失败: " .. player.Name)
		playerInviteData[userId] = defaultData
		return defaultData
	end

	-- 如果DataStore中没有数据，使用默认值
	if not result then
		playerInviteData[userId] = defaultData
	else
		playerInviteData[userId] = result
	end

	print("[InviteManager] ✓ 已加载玩家邀请数据: " .. player.Name)
	return playerInviteData[userId]
end

-- ============================================
-- 保存玩家邀请数据
-- ============================================

function InviteManager:savePlayerInviteData(player, data)
	if not player or not inviteDataStore then return false end

	local userId = tostring(player.UserId)
	playerInviteData[player.UserId] = data

	-- 异步保存到DataStore
	spawn(function()
		local maxRetries = 3
		for attempt = 1, maxRetries do
			local success = pcall(function()
				inviteDataStore:SetAsync(userId, data)
			end)

			if success then
				print("[InviteManager] ✓ 已保存玩家邀请数据: " .. player.Name)
				return
			else
				task.wait(1)
			end
		end

		warn("[InviteManager] 保存玩家邀请数据失败: " .. player.Name)
	end)

	return true
end

-- ============================================
-- 检查和重置每日邀请数据
-- ============================================

function InviteManager:checkAndResetPlayer(player)
	if not player then return end

	local playerData = self:loadPlayerInviteData(player)
	local now = os.time()
	local currentUTC0 = getCurrentUTC0Timestamp()

	-- 判断是否需要重置
	if playerData.lastResetTime < currentUTC0 then
		self:resetDailyInviteData(player)
	end
end

function InviteManager:resetDailyInviteData(player)
	if not player then return end

	local playerData = self:loadPlayerInviteData(player)

	-- 保持不变：邀请总数、邀请过的玩家列表
	-- 重置项：
	playerData.dailyInvitedCount = 0
	playerData.claimedRewards = {
		reward_1 = false,
		reward_3 = false,
		reward_5 = false
	}
	playerData.lastResetTime = getCurrentUTC0Timestamp()

	self:savePlayerInviteData(player, playerData)

	print("[InviteManager] ✓ 已为玩家重置每日邀请数据: " .. player.Name)
end

-- ============================================
-- 生成邀请链接
-- ============================================

function InviteManager:generateInviteLink(player)
	if not player then return nil end

	local code = generateRandomCode()
	local now = os.time()

	inviteLinkMap[code] = {
		inviterId = player.UserId,
		inviterName = player.Name,
		createTime = now,
		expiryTime = now + 86400,  -- 24小时后过期
		maxUses = 1,
		status = "active"
	}

	-- 返回完整链接（这里使用简化格式，实际应该是完整URL）
	return "inviteCode=" .. code
end

-- ============================================
-- 验证和使用邀请码
-- ============================================

function InviteManager:verifyAndUseInviteCode(code, playerId)
	if not code or not playerId then
		return false, "Invalid parameters"
	end

	local link = inviteLinkMap[code]

	-- 检查链接是否存在
	if not link then
		return false, "Invalid code"
	end

	-- 检查链接是否过期
	if os.time() > link.expiryTime then
		link.status = "expired"
		return false, "Link expired"
	end

	-- 检查链接是否已使用
	if link.maxUses <= 0 then
		link.status = "used"
		return false, "Link already used"
	end

	-- 检查是否是自己邀请自己
	if link.inviterId == playerId then
		return false, "Cannot invite yourself"
	end

	-- 验证通过，标记为已使用
	link.maxUses = link.maxUses - 1
	if link.maxUses <= 0 then
		link.status = "used"
	end

	return true, link.inviterId
end

-- ============================================
-- 记录邀请成功
-- ============================================

function InviteManager:recordInvitedPlayer(inviterId, invitedId)
	if not inviterId or not invitedId then return false end

	-- 获取邀请者数据
	local inviter = Players:FindFirstChild(inviterId) or Players:GetPlayerByUserId(inviterId)
	if not inviter then return false end

	local playerData = self:loadPlayerInviteData(inviter)

	-- 检查今天是否已经邀请过这个玩家
	for recordedId, _ in pairs(playerData.inviteLinks) do
		if recordedId == invitedId then
			-- 已经邀请过，检查是否是同一天
			local today = os.date("%Y-%m-%d")
			if playerData.inviteLinks[invitedId].dateUsed == today then
				return false  -- 同一天已邀请过
			end
		end
	end

	-- 记录邀请
	playerData.invitedCount = playerData.invitedCount + 1
	playerData.dailyInvitedCount = playerData.dailyInvitedCount + 1

	-- 避免重复
	if not table.find(playerData.invitedPlayerIds, invitedId) then
		table.insert(playerData.invitedPlayerIds, invitedId)
	end

	-- 记录邀请链接
	playerData.inviteLinks[invitedId] = {
		inviterId = inviterId,
		dateUsed = os.date("%Y-%m-%d"),
		usedTime = os.time()
	}

	queueSaveOperation(inviter, playerData)

	print("[InviteManager] ✓ 邀请成功: " .. inviter.Name .. " 邀请了 " .. invitedId)

	return true
end

-- ============================================
-- 检查是否可以领取奖励
-- ============================================

function InviteManager:canClaimReward(player, rewardId)
	if not player or not rewardId then return false end

	local playerData = self:loadPlayerInviteData(player)
	local rewardConfig = REWARD_CONFIG[rewardId]

	if not rewardConfig then return false end

	-- 检查邀请人数是否满足
	if playerData.invitedCount < rewardConfig.requiredCount then
		return false
	end

	-- 检查是否已经领取过
	if playerData.claimedRewards[rewardId] then
		return false
	end

	return true
end

-- ============================================
-- 领取奖励
-- ============================================

function InviteManager:claimReward(player, rewardId)
	if not player or not rewardId then
		return false, "Invalid parameters"
	end

	-- 等待获取锁
	while not acquirePlayerLock(player) do
		task.wait(0.01)
	end

	local playerData = self:loadPlayerInviteData(player)
	local rewardConfig = REWARD_CONFIG[rewardId]

	-- 检查奖励配置
	if not rewardConfig then
		releasePlayerLock(player)
		return false, "Invalid reward"
	end

	-- 检查是否满足条件
	if not self:canClaimReward(player, rewardId) then
		releasePlayerLock(player)
		return false, "Requirements Not Met"
	end

	-- 发放奖励
	local rewards = rewardConfig.rewards

	-- 发放金币
	if rewards.coins and rewards.coins > 0 then
		if _G.CoinManager then
			_G.CoinManager:addCoins(player, rewards.coins, "邀请奖励")
		end
	end

	-- 发放转盘次数
	if rewards.wheelSpins and rewards.wheelSpins > 0 then
		if _G.WheelDataManager then
			_G.WheelDataManager:addSpinsFromInviteReward(player, rewards.wheelSpins)
		end
	end

	-- 发放清除毒药道具
	if rewards.poisonClear and rewards.poisonClear > 0 then
		if _G.PropManager then
			-- propId 3 对应 poison_clean（清除对方所有毒药）
			_G.PropManager.addProp(player, 3, rewards.poisonClear)
		end
	end

	-- 标记为已领取
	playerData.claimedRewards[rewardId] = true
	queueSaveOperation(player, playerData)

	releasePlayerLock(player)

	-- 发送UI更新事件
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local inviteEvent = remoteEventsFolder:FindFirstChild("InviteEvent")
	if inviteEvent then
		inviteEvent:FireClient(player, "rewardSuccess", {
			rewardId = rewardId,
			rewards = rewards
		})
	end

	print("[InviteManager] ✓ 玩家 " .. player.Name .. " 领取了奖励: " .. rewardId)

	return true, "Success"
end

-- ============================================
-- 获取玩家邀请状态
-- ============================================

function InviteManager:getInviteStatus(player)
	if not player then return nil end

	local playerData = self:loadPlayerInviteData(player)

	return {
		invitedCount = playerData.invitedCount,
		dailyInvitedCount = playerData.dailyInvitedCount,
		claimedRewards = playerData.claimedRewards,
		hasUnclaimedRewards = self:hasUnclaimedRewards(player)
	}
end

function InviteManager:hasUnclaimedRewards(player)
	if not player then return false end

	local playerData = self:loadPlayerInviteData(player)

	for rewardId, claimed in pairs(playerData.claimedRewards) do
		if not claimed then
			local rewardConfig = REWARD_CONFIG[rewardId]
			if rewardConfig and playerData.invitedCount >= rewardConfig.requiredCount then
				return true
			end
		end
	end

	return false
end

-- ============================================
-- 初始化
-- ============================================

function InviteManager.initialize()
	-- 创建RemoteEvent
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local inviteEvent = remoteEventsFolder:FindFirstChild("InviteEvent")
	if not inviteEvent then
		inviteEvent = Instance.new("RemoteEvent")
		inviteEvent.Name = "InviteEvent"
		inviteEvent.Parent = remoteEventsFolder
	end

	-- 设置事件监听
	inviteEvent.OnServerEvent:Connect(function(player, action, data)
		if action == "claimReward" then
			InviteManager:claimReward(player, data.rewardId)
		elseif action == "requestStatus" then
			local status = InviteManager:getInviteStatus(player)
			status.nextResetTime = getNextUTC0Timestamp()
			inviteEvent:FireClient(player, "statusResponse", status)
		elseif action == "generateLink" then
			local link = InviteManager:generateInviteLink(player)
			inviteEvent:FireClient(player, "inviteLinkGenerated", {
				link = link
			})
		end
	end)

	-- 玩家加入时检查重置和邀请
	Players.PlayerAdded:Connect(function(player)
		task.wait(1)

		-- 检查并重置每日数据
		InviteManager:checkAndResetPlayer(player)

		-- 检查是否通过邀请链接进入游戏
		InviteManager:checkPlayerJoinWithInvite(player)
	end)

	-- 玩家离开时保存数据
	Players.PlayerRemoving:Connect(function(player)
		local playerData = playerInviteData[player.UserId]
		if playerData then
			InviteManager:savePlayerInviteData(player, playerData)
		end
		playerInviteData[player.UserId] = nil
	end)

	-- 服务器关闭时保存所有数据
	game:BindToClose(function()
		for userId, playerData in pairs(playerInviteData) do
			local player = Players:FindFirstChild(userId) or Players:GetPlayerByUserId(userId)
			if player then
				InviteManager:savePlayerInviteData(player, playerData)
			end
		end
	end)

	print("[InviteManager] ✓ 初始化完成")
end

-- ============================================
-- 检查玩家是否通过邀请链接进入
-- ============================================

function InviteManager:checkPlayerJoinWithInvite(player)
	if not player then return end

	-- 尝试从多个渠道获取邀请信息
	local inviteCode = nil

	-- 方式1：通过GetJoinData获取LaunchData
	local joinData = player:GetJoinData()
	if joinData and joinData.LaunchData then
		-- 从LaunchData中提取邀请码
		-- 格式应该是 "inviteCode=xxxxx"
		inviteCode = string.match(joinData.LaunchData, "inviteCode=([^&]+)")
	end

	if inviteCode then
		print("[InviteManager] 玩家 " .. player.Name .. " 通过邀请链接进入，邀请码: " .. inviteCode)
		InviteManager:processInviteCode(player, inviteCode)
	end
end

-- ============================================
-- 处理邀请码
-- ============================================

function InviteManager:processInviteCode(player, code)
	if not player or not code then return end

	local success, inviterId = self:verifyAndUseInviteCode(code, player.UserId)

	if success then
		-- 邀请码有效，记录邀请
		local invitedPlayerData = self:loadPlayerInviteData(player)

		-- 获取邀请者信息（可能不在线）
		local inviter = Players:GetPlayerByUserId(inviterId)
		if inviter then
			self:recordInvitedPlayer(inviterId, player.UserId)
		else
			-- 邀请者不在线，仍然记录邀请（异步）
			self:recordInvitedPlayer(inviterId, player.UserId)
		end

		print("[InviteManager] ✓ 邀请链接有效，已记录邀请: " .. (inviter and inviter.Name or "玩家#" .. inviterId))
	else
		warn("[InviteManager] 邀请链接无效或已过期: " .. code)
	end
end

-- 全局导出
_G.InviteManager = InviteManager

return InviteManager
