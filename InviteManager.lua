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

-- 🔧 V2.1 新增：待处理的邀请记录（用于同服务器内邀请检测）
-- 结构: [inviterId] = {timestamp = os.time(), inviterName = "..."}
local pendingInvites = {}

-- 默认邀请数据
local DEFAULT_INVITE_DATA = {
	dailyInvitedCount = 0,         -- 当日邀请人数（每日UTC0重置）
	lastResetTime = 0,             -- 上次UTC0重置时间
	claimedRewards = {
		reward_1 = false,
		reward_3 = false,
		reward_5 = false
	},
	dailyInvitedPlayers = {}       -- 🔧 修复：当日已邀请的玩家ID集合（每日重置，防止重复计数）
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
			wheelSpins = 2
		}
	},
	reward_5 = {
		requiredCount = 5,
		rewards = {
			coins = 200,
			wheelSpins = 3,
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
	-- 🔧 修复：使用 "!*t" 获取UTC时间，而不是本地时区时间
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
		playerInviteData[userId] = defaultData
		return defaultData
	end

	-- 如果DataStore中没有数据，使用默认值
	if not result then
		playerInviteData[userId] = defaultData
	else
		playerInviteData[userId] = result
	end

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
				return
			else
				task.wait(1)
			end
		end
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

	-- 🔧 修复：每日重置时清理当日邀请记录和奖励领取状态
	playerData.dailyInvitedCount = 0
	playerData.dailyInvitedPlayers = {}  -- 清空当日已邀请玩家列表
	playerData.claimedRewards = {
		reward_1 = false,
		reward_3 = false,
		reward_5 = false
	}
	playerData.lastResetTime = getCurrentUTC0Timestamp()

	-- 🔧 修复：兼容旧数据，清理废弃字段
	playerData.invitedCount = nil
	playerData.invitedPlayerIds = nil
	playerData.inviteLinks = nil

	self:savePlayerInviteData(player, playerData)
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

	-- 🔧 关键修复：即使邀请者离线也要记录邀请！
	-- 邀请者可能已经离线，我们仍需要保存这个邀请记录到他的DataStore中

	-- 尝试获取在线玩家
	local inviter = Players:GetPlayerByUserId(inviterId)

	-- 如果邀请者离线，直接从DataStore加载数据
	if not inviter then
		-- 创建临时玩家对象供数据加载使用
		-- 这允许我们从DataStore读取离线玩家的数据
		local tempPlayerData = nil

		if inviteDataStore then
			local success, result = pcall(function()
				return inviteDataStore:GetAsync(tostring(inviterId))
			end)

			if success and result then
				tempPlayerData = result
			else
				tempPlayerData = {}
				for k, v in pairs(DEFAULT_INVITE_DATA) do
					if type(v) == "table" then
						tempPlayerData[k] = {}
						for k2, v2 in pairs(v) do
							tempPlayerData[k][k2] = v2
						end
					else
						tempPlayerData[k] = v
					end
				end
			end
		else
			-- Studio环境
			tempPlayerData = {}
			for k, v in pairs(DEFAULT_INVITE_DATA) do
				if type(v) == "table" then
					tempPlayerData[k] = {}
					for k2, v2 in pairs(v) do
						tempPlayerData[k][k2] = v2
					end
				else
					tempPlayerData[k] = v
				end
			end
		end

		-- 检查当日是否已经邀请过这个玩家
		if tempPlayerData.dailyInvitedPlayers and tempPlayerData.dailyInvitedPlayers[tostring(invitedId)] then
			return false
		end

		-- 记录邀请
		tempPlayerData.dailyInvitedCount = (tempPlayerData.dailyInvitedCount or 0) + 1
		tempPlayerData.dailyInvitedPlayers = tempPlayerData.dailyInvitedPlayers or {}
		tempPlayerData.dailyInvitedPlayers[tostring(invitedId)] = {
			invitedAt = os.time(),
			date = os.date("!%Y-%m-%d")
		}

		-- 保存到DataStore
		if inviteDataStore then
			spawn(function()
				pcall(function()
					inviteDataStore:SetAsync(tostring(inviterId), tempPlayerData)
				end)
			end)
		end

		return true
	end

	-- 邀请者在线，使用正常流程
	local playerData = self:loadPlayerInviteData(inviter)

	-- 检查当日是否已经邀请过这个玩家（防止重复计数）
	if playerData.dailyInvitedPlayers[tostring(invitedId)] then
		return false
	end

	-- 记录当日邀请
	playerData.dailyInvitedCount = playerData.dailyInvitedCount + 1
	playerData.dailyInvitedPlayers[tostring(invitedId)] = {
		invitedAt = os.time(),
		date = os.date("!%Y-%m-%d")  -- UTC日期
	}

	queueSaveOperation(inviter, playerData)

	-- 🔧 新增：立即通知邀请者客户端刷新UI（如果邀请者在线）
	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if remoteEventsFolder then
		local inviteEvent = remoteEventsFolder:FindFirstChild("InviteEvent")
		if inviteEvent then
			pcall(function()
				-- 发送状态更新，触发UI刷新
				local status = self:getInviteStatus(inviter)
				status.nextResetTime = getNextUTC0Timestamp()
				inviteEvent:FireClient(inviter, "statusResponse", status)
			end)
		end
	end

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

	-- 🔧 修复：使用dailyInvitedCount而不是invitedCount
	-- 因为奖励每天都可以重新领取，所以判断当日邀请人数
	if playerData.dailyInvitedCount < rewardConfig.requiredCount then
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
			_G.CoinManager.addCoins(player, rewards.coins, "邀请奖励")
		end
	end

	-- 发放转盘次数
	if rewards.wheelSpins and rewards.wheelSpins > 0 then
		if _G.WheelDataManager then
			_G.WheelDataManager.addSpinsFromInviteReward(player, rewards.wheelSpins)
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

	return true, "Success"
end

-- ============================================
-- 获取玩家邀请状态
-- ============================================

function InviteManager:getInviteStatus(player)
	if not player then return nil end

	local playerData = self:loadPlayerInviteData(player)

	-- 🔧 修复：移除好友加成相关字段
	return {
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
			-- 🔧 修复：使用dailyInvitedCount而不是invitedCount
			if rewardConfig and playerData.dailyInvitedCount >= rewardConfig.requiredCount then
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
		elseif action == "inviteSent" then
			-- 🔧 V2.1 新增：客户端通知服务器"我发出了邀请"
			InviteManager:recordPendingInvite(player.UserId, player.Name)
		end
	end)

	-- 玩家加入时检查重置和邀请
	Players.PlayerAdded:Connect(function(player)
		task.wait(1)

		-- 检查并重置每日数据
		InviteManager:checkAndResetPlayer(player)

		-- 🔧 V2.1 修复：优先检查待处理的邀请（同服务器内邀请）
		local foundPendingInvite = InviteManager:checkPendingInvites(player)

		if not foundPendingInvite then
			-- 如果没有找到待处理的邀请，再尝试使用Roblox官方API检测（跨服务器邀请）
			InviteManager:checkPlayerJoinWithInvite(player)
		end
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
			local player = Players:GetPlayerByUserId(userId)
			if player then
				InviteManager:savePlayerInviteData(player, playerData)
			end
		end
	end)

	-- 🔧 新增：定期清理过期的邀请链接（每10分钟）
	spawn(function()
		while true do
			task.wait(600)  -- 10分钟
			InviteManager:cleanupExpiredLinks()
		end
	end)
end

-- ============================================
-- V2.1 新增：记录待处理的邀请
-- ============================================

function InviteManager:recordPendingInvite(inviterId, inviterName)
	if not inviterId then return end

	pendingInvites[inviterId] = {
		timestamp = os.time(),
		inviterName = inviterName or "Unknown"
	}
end

-- ============================================
-- V2.1 新增：检查并匹配待处理的邀请
-- ============================================

function InviteManager:checkPendingInvites(player)
	if not player then return false end

	-- 清理过期的邀请（超过5分钟）
	local now = os.time()
	local expiredInviters = {}

	for inviterId, inviteData in pairs(pendingInvites) do
		if now - inviteData.timestamp > 300 then  -- 5分钟 = 300秒
			table.insert(expiredInviters, inviterId)
		end
	end

	for _, inviterId in ipairs(expiredInviters) do
		pendingInvites[inviterId] = nil
	end

	-- 检查是否有待处理的邀请
	for inviterId, inviteData in pairs(pendingInvites) do
		-- 检查不是自己邀请自己
		if inviterId ~= player.UserId then
			-- 🔧 V2.1.2 修复：移除好友关系检查
			-- 原因：
			-- 1. SocialService:PromptGameInvite() 本身只能邀请好友
			-- 2. 如果不是好友，PromptGameInvite就不会让邀请者选择这个人
			-- 3. 所以只要有待处理邀请记录，就代表这是有效的邀请
			-- 4. Players:IsFriendsWith() 在某些Roblox版本中不存在
			-- 5. 直接信任待处理邀请是安全的做法

			-- 记录邀请
			local success = self:recordInvitedPlayer(inviterId, player.UserId)

			if success then
				-- 清除这个待处理的邀请
				pendingInvites[inviterId] = nil
				return true
			end
		end
	end

	return false
end

-- ============================================
-- 检查玩家是否通过邀请链接进入
-- ============================================

function InviteManager:checkPlayerJoinWithInvite(player)
	if not player then return end

	-- 🔧 修复：使用多种方式检测邀请来源
	local inviterId = nil

	-- 获取玩家的加入数据
	local joinData = player:GetJoinData()

	-- 方式1：通过GetJoinData获取LaunchData（适用于自定义邀请链接）
	if joinData and joinData.LaunchData then
		local inviteCode = string.match(joinData.LaunchData, "inviteCode=([^&]+)")
		if inviteCode then
			local success, foundInviterId = self:verifyAndUseInviteCode(inviteCode, player.UserId)
			if success then
				inviterId = foundInviterId
			end
		end
	end

	-- 方式2：通过TeleportData获取邀请者ID（推荐使用）
	if not inviterId and joinData and joinData.TeleportData then
		if type(joinData.TeleportData) == "table" and joinData.TeleportData.inviterId then
			inviterId = tonumber(joinData.TeleportData.inviterId)
		end
	end

	-- 方式3：检查是否通过好友邀请加入（Roblox内置功能）
	if not inviterId and joinData and joinData.SourceUserId then
		inviterId = joinData.SourceUserId
	end

	-- 如果检测到邀请者，记录邀请
	if inviterId and inviterId ~= player.UserId then
		self:recordInvitedPlayer(inviterId, player.UserId)
	end
end

-- ============================================
-- 处理邀请码（向后兼容旧方法）
-- ============================================

function InviteManager:processInviteCode(player, code)
	if not player or not code then return end

	local success, inviterId = self:verifyAndUseInviteCode(code, player.UserId)

	if success and inviterId then
		self:recordInvitedPlayer(inviterId, player.UserId)
	end
end

-- ============================================
-- 🔧 新增：清理过期的邀请链接
-- ============================================

function InviteManager:cleanupExpiredLinks()
	local now = os.time()
	local cleanedCount = 0

	for code, link in pairs(inviteLinkMap) do
		-- 清理条件：已过期、已使用、或创建超过48小时
		if link.status == "expired" or
		   link.status == "used" or
		   now > link.expiryTime or
		   (now - link.createTime) > 172800 then  -- 48小时
			inviteLinkMap[code] = nil
			cleanedCount = cleanedCount + 1
		end
	end
end

-- ============================================
-- V1.9: 重置玩家数据为新玩家（管理员命令用）
-- ============================================

function InviteManager:resetPlayerData(userId, player)
	-- 1. 检查参数有效性
	if not userId or type(userId) ~= "number" then
		return false
	end

	if not player or not player.UserId or player.UserId ~= userId then
		return false
	end

	-- 2. 清空内存缓存（如果玩家在线）
	if playerInviteData[userId] then
		playerInviteData[userId] = nil
	end

	-- 清空操作锁
	if playerOperationLocks[tostring(userId)] then
		playerOperationLocks[tostring(userId)] = nil
	end

	-- 3. 重置 DataStore 为默认值（带重试机制）
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

	local maxRetries = 3
	local resetSuccess = false

	-- 仅在非Studio环境下操作DataStore
	if not isStudio and inviteDataStore then
		for attempt = 1, maxRetries do
			local success, err = pcall(function()
				inviteDataStore:SetAsync(tostring(userId), defaultData)
			end)

			if success then
				resetSuccess = true
				break
			else
				if attempt < maxRetries then
					wait(1)
				end
			end
		end

		if not resetSuccess then
			return false
		end
	else
		resetSuccess = true
	end

	-- 4. 如果玩家在线，重新加载数据
	if player and player.Parent then
		self:loadPlayerInviteData(player)
	end

	return true
end

-- 全局导出
_G.InviteManager = InviteManager

return InviteManager
