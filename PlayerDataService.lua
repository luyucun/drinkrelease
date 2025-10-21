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
			newPlayerCompleted = false
		}
		return playerDataCache[userId]
	end

	-- 如果DataStore中没有数据，创建新的
	if not data then
		playerDataCache[userId] = {
			newPlayerCompleted = false
		}
	else
		playerDataCache[userId] = data
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

return PlayerDataService
