-- 脚本名称: PlayerDataService
-- 脚本作用: 管理玩家的持久化数据，包括新手完成状态
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local PlayerDataService = {}
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

-- DataStore
local playerDataStore = DataStoreService:GetDataStore("PlayerData_V1")

-- 本地缓存（避免频繁访问DataStore）
local playerDataCache = {} -- {[userId] = {newPlayerCompleted = true/false}}

-- 操作锁，防止并发问题
local operationLocks = {}

local function acquireLock(userId)
	while operationLocks[userId] do
		wait(0.01)
	end
	operationLocks[userId] = true
end

local function releaseLock(userId)
	operationLocks[userId] = nil
end

-- ============================================
-- 获取玩家数据
-- ============================================

function PlayerDataService:loadPlayerData(player)
	if not player then return nil end

	local userId = player.UserId

	-- 如果已缓存，直接返回
	if playerDataCache[userId] then
		return playerDataCache[userId]
	end

	acquireLock(userId)

	local success, data = pcall(function()
		return playerDataStore:GetAsync(tostring(userId))
	end)

	releaseLock(userId)

	if not success then
		warn("[PlayerDataService] 加载玩家数据失败: " .. player.Name .. ", 使用默认值")
		playerDataCache[userId] = {
			newPlayerCompleted = false,
			skinGuideShown = false  -- V1.9: 皮肤引导是否已触发
		}
		return playerDataCache[userId]
	end

	-- 如果DataStore中没有数据，创建新的
	if not data then
		playerDataCache[userId] = {
			newPlayerCompleted = false,
			skinGuideShown = false  -- V1.9: 皮肤引导是否已触发
		}
	else
		playerDataCache[userId] = data
		-- 确保新字段存在（兼容旧数据）
		if playerDataCache[userId].skinGuideShown == nil then
			playerDataCache[userId].skinGuideShown = false
		end
	end

	print("[PlayerDataService] ✓ 已加载玩家数据: " .. player.Name)
	return playerDataCache[userId]
end

-- ============================================
-- 检查是否是新玩家
-- ============================================

function PlayerDataService:isNewPlayer(player)
	if not player then return false end

	local playerData = self:loadPlayerData(player)
	return not playerData.newPlayerCompleted
end

-- ============================================
-- 标记玩家为已完成新手
-- ============================================

function PlayerDataService:setTutorialCompleted(player, completed)
	if not player then return false end

	local userId = player.UserId

	-- 更新缓存
	if not playerDataCache[userId] then
		playerDataCache[userId] = {}
	end
	playerDataCache[userId].newPlayerCompleted = completed

	-- 异步保存到DataStore
	spawn(function()
		acquireLock(userId)

		local success, err = pcall(function()
			playerDataStore:SetAsync(tostring(userId), playerDataCache[userId])
		end)

		releaseLock(userId)

		if success then
			print("[PlayerDataService] ✓ 已保存玩家教程完成状态: " .. player.Name .. " = " .. tostring(completed))
		else
			warn("[PlayerDataService] 保存玩家数据失败: " .. player.Name .. ", 错误: " .. tostring(err))
		end
	end)

	return true
end

-- ============================================
-- 清理玩家缓存
-- ============================================

function PlayerDataService:cleanupPlayerCache(player)
	if not player then return end

	local userId = player.UserId
	playerDataCache[userId] = nil

	print("[PlayerDataService] ✓ 已清理玩家缓存: " .. player.Name)
end

-- ============================================
-- V1.9: 重置玩家数据为新玩家（管理员命令用）
-- ============================================

function PlayerDataService:resetPlayerData(userId, player)
	-- 1. 检查参数有效性
	if not userId or type(userId) ~= "number" then
		warn("[PlayerDataService] resetPlayerData: 无效的 userId: " .. tostring(userId))
		return false
	end

	if not player or not player.UserId or player.UserId ~= userId then
		warn("[PlayerDataService] resetPlayerData: player 参数与 userId 不匹配")
		return false
	end

	print("[PlayerDataService] 开始重置玩家数据: " .. player.Name .. " (UserId: " .. userId .. ")")

	-- 2. 清空内存缓存（如果玩家在线）
	if playerDataCache[userId] then
		playerDataCache[userId] = nil
		print("[PlayerDataService] ✓ 已清空内存缓存")
	end

	-- 清空操作锁
	if operationLocks[userId] then
		operationLocks[userId] = nil
		print("[PlayerDataService] ✓ 已清空操作锁")
	end

	-- 3. 重置 DataStore 为默认值（带重试机制）
	local defaultData = {
		newPlayerCompleted = false
	}

	local maxRetries = 3
	local resetSuccess = false

	for attempt = 1, maxRetries do
		local success, err = pcall(function()
			playerDataStore:SetAsync(tostring(userId), defaultData)
		end)

		if success then
			resetSuccess = true
			print("[PlayerDataService] ✓ DataStore 重置成功 (尝试 " .. attempt .. "/" .. maxRetries .. ")")
			break
		else
			warn("[PlayerDataService] DataStore 重置失败 (尝试 " .. attempt .. "/" .. maxRetries .. "): " .. tostring(err))
			if attempt < maxRetries then
				wait(1) -- 重试前等待1秒
			end
		end
	end

	if not resetSuccess then
		warn("[PlayerDataService] ❌ DataStore 重置最终失败，达到最大重试次数")
		return false
	end

	-- 4. 如果玩家在线，重新加载数据
	if player and player.Parent then
		local newData = self:loadPlayerData(player)
		if newData then
			print("[PlayerDataService] ✓ 已重新加载玩家数据")
		else
			warn("[PlayerDataService] ⚠️ 重新加载玩家数据失败")
		end
	end

	print("[PlayerDataService] ✅ 玩家数据重置完成: " .. player.Name)
	return true
end

-- ============================================
-- V1.9: 检查是否已触发皮肤引导
-- ============================================

function PlayerDataService:hasSkinGuideShown(player)
	if not player then return false end

	local playerData = self:loadPlayerData(player)
	if not playerData then return false end

	return playerData.skinGuideShown == true
end

-- ============================================
-- V1.9: 设置皮肤引导已触发状态
-- ============================================

function PlayerDataService:setSkinGuideShown(player, shown)
	if not player then return false end

	local userId = player.UserId

	-- 更新缓存
	if not playerDataCache[userId] then
		playerDataCache[userId] = {}
	end
	playerDataCache[userId].skinGuideShown = shown

	-- 异步保存到DataStore
	spawn(function()
		acquireLock(userId)

		local success, err = pcall(function()
			playerDataStore:SetAsync(tostring(userId), playerDataCache[userId])
		end)

		releaseLock(userId)

		if success then
		else
			warn("[PlayerDataService] 保存皮肤引导状态失败: " .. player.Name .. ", 错误: " .. tostring(err))
		end
	end)

	return true
end

return PlayerDataService
