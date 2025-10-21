-- 脚本名称: TutorialAnalyticsService
-- 脚本作用: 新手教程埋点系统，记录关键事件用于数据分析
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local TutorialAnalyticsService = {}
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- 是否在Studio环境
local isStudio = RunService:IsStudio()

-- 埋点数据存储
local analyticsDataStore = nil
if not isStudio then
	analyticsDataStore = DataStoreService:GetDataStore("TutorialAnalytics")
end

-- 本地缓存（用于防止重复埋点）
local trackedEvents = {} -- {[playerId] = {enterNewplayer, sitDown, portalInteraction}}

-- ============================================
-- 埋点工具函数
-- ============================================

local function getPlayerCacheKey(player)
	return tostring(player.UserId)
end

-- 🔧 V1.6: 检查玩家是否为真实玩家（排除NPC伪对象）
local function isRealPlayer(player)
	if not player then return false end

	-- 排除NPC伪对象（UserId为99999999）
	if player.UserId == 99999999 then
		return false
	end

	-- 检查是否为真实Player对象
	return player:IsA("Player") or (player.Parent and player.Parent:IsA("Players"))
end

local function initializePlayerTrack(playerId)
	if not trackedEvents[playerId] then
		trackedEvents[playerId] = {
			enterNewplayer = false,
			sitDown = false,
			portalInteraction = false,
			startTime = tick(),
			gameResult = nil
		}
	end
end

-- ============================================
-- 记录埋点到本地缓存（防止重复）
-- ============================================

local function recordEventLocally(playerId, eventName)
	initializePlayerTrack(playerId)
	trackedEvents[playerId][eventName] = true
end

-- ============================================
-- 清理埋点缓存（当玩家离开时）
-- ============================================

local function clearPlayerTrack(playerId)
	trackedEvents[playerId] = nil
end

-- ============================================
-- 保存埋点到DataStore
-- ============================================

local function saveAnalyticsToDataStore(playerId, eventData)
	if isStudio then
		print("[TutorialAnalytics] Studio模式，跳过DataStore保存")
		return
	end

	spawn(function()
		local success, err = pcall(function()
			if analyticsDataStore then
				-- 创建唯一的事件KEY（防止覆盖）
				local eventKey = string.format("TutorialEvent_%d_%d", playerId, tick() * 1000)
				analyticsDataStore:SetAsync(eventKey, eventData)
			end
		end)

		if not success then
			warn("[TutorialAnalyticsService] DataStore保存失败: " .. tostring(err))
		end
	end)
end

-- ============================================
-- 埋点1：玩家进入Newplayer场景
-- ============================================

function TutorialAnalyticsService:trackPlayerEnterNewplayer(player)
	if not player or not isRealPlayer(player) then
		-- 🔧 V1.6: 排除NPC伪对象
		if player and player.UserId == 99999999 then
			return  -- NPC不需要埋点
		end
		warn("TutorialAnalyticsService: 无效的玩家对象")
		return
	end

	local playerId = getPlayerCacheKey(player)

	-- 防重复检查
	if trackedEvents[playerId] and trackedEvents[playerId].enterNewplayer then
		print("[TutorialAnalytics] 玩家 " .. player.Name .. " 已记录过进入埋点，跳过重复记录")
		return
	end

	-- 本地记录
	recordEventLocally(playerId, "enterNewplayer")

	-- 准备埋点数据
	local eventData = {
		event = "enterNewplayer",
		playerId = player.UserId,
		playerName = player.Name,
		timestamp = os.time(),
		sessionTime = tick()
	}

	-- 保存到DataStore
	saveAnalyticsToDataStore(playerId, eventData)

	print("[TutorialAnalytics] ✓ 埋点1记录: 玩家进入Newplayer - " .. player.Name)
end

-- ============================================
-- 埋点2：玩家坐到椅子上
-- ============================================

function TutorialAnalyticsService:trackPlayerSitDown(player)
	if not player or not isRealPlayer(player) then
		-- 🔧 V1.6: 排除NPC伪对象
		if player and player.UserId == 99999999 then
			return  -- NPC不需要埋点
		end
		warn("TutorialAnalyticsService: 无效的玩家对象")
		return
	end

	local playerId = getPlayerCacheKey(player)

	-- 防重复检查
	if trackedEvents[playerId] and trackedEvents[playerId].sitDown then
		print("[TutorialAnalytics] 玩家 " .. player.Name .. " 已记录过坐下埋点，跳过重复记录")
		return
	end

	-- 本地记录
	recordEventLocally(playerId, "sitDown")

	-- 准备埋点数据
	local eventData = {
		event = "sitDown",
		playerId = player.UserId,
		playerName = player.Name,
		timestamp = os.time(),
		timeSinceEnter = tick() - (trackedEvents[playerId] and trackedEvents[playerId].startTime or tick())
	}

	-- 保存到DataStore
	saveAnalyticsToDataStore(playerId, eventData)

	print("[TutorialAnalytics] ✓ 埋点2记录: 玩家坐下 - " .. player.Name)
end

-- ============================================
-- 埋点3：玩家完成Portal交互
-- ============================================

function TutorialAnalyticsService:trackPortalInteraction(player, gameResult)
	if not player or not isRealPlayer(player) then
		-- 🔧 V1.6: 排除NPC伪对象
		if player and player.UserId == 99999999 then
			return  -- NPC不需要埋点
		end
		warn("TutorialAnalyticsService: 无效的玩家对象")
		return
	end

	local playerId = getPlayerCacheKey(player)

	-- 防重复检查
	if trackedEvents[playerId] and trackedEvents[playerId].portalInteraction then
		print("[TutorialAnalytics] 玩家 " .. player.Name .. " 已记录过Portal交互埋点，跳过重复记录")
		return
	end

	-- 本地记录
	recordEventLocally(playerId, "portalInteraction")

	-- 记录游戏结果
	if trackedEvents[playerId] then
		trackedEvents[playerId].gameResult = gameResult or "unknown"
	end

	-- 准备埋点数据
	local eventData = {
		event = "portalInteraction",
		playerId = player.UserId,
		playerName = player.Name,
		timestamp = os.time(),
		totalDuration = tick() - (trackedEvents[playerId] and trackedEvents[playerId].startTime or tick()),
		gameResult = gameResult or "unknown"
	}

	-- 保存到DataStore
	saveAnalyticsToDataStore(playerId, eventData)

	print("[TutorialAnalytics] ✓ 埋点3记录: Portal交互 - " .. player.Name .. " | 游戏结果: " .. (gameResult or "unknown"))
end

-- ============================================
-- 清理玩家埋点缓存（当玩家离开时）
-- ============================================

function TutorialAnalyticsService:cleanupPlayerTrack(player)
	if not player then return end

	local playerId = getPlayerCacheKey(player)
	clearPlayerTrack(playerId)

	print("[TutorialAnalytics] ✓ 已清理玩家埋点缓存 - " .. player.Name)
end

-- ============================================
-- 获取玩家埋点状态（调试用）
-- ============================================

function TutorialAnalyticsService:getPlayerTrackStatus(player)
	if not player then return nil end

	local playerId = getPlayerCacheKey(player)
	if not trackedEvents[playerId] then
		return nil
	end

	return {
		playerId = player.UserId,
		playerName = player.Name,
		enterNewplayer = trackedEvents[playerId].enterNewplayer,
		sitDown = trackedEvents[playerId].sitDown,
		portalInteraction = trackedEvents[playerId].portalInteraction,
		gameResult = trackedEvents[playerId].gameResult,
		startTime = trackedEvents[playerId].startTime,
		elapsedTime = tick() - trackedEvents[playerId].startTime
	}
end

-- ============================================
-- 获取所有埋点统计（调试用）
-- ============================================

function TutorialAnalyticsService:getAllTrackStats()
	local stats = {
		totalPlayers = 0,
		completedFunnel = 0,
		dropOffAmbulance = {}
	}

	for playerId, track in pairs(trackedEvents) do
		stats.totalPlayers = stats.totalPlayers + 1

		if track.enterNewplayer and track.sitDown and track.portalInteraction then
			stats.completedFunnel = stats.completedFunnel + 1
		else
			-- 记录流失点
			local dropOff = {}
			if not track.enterNewplayer then table.insert(dropOff, "未进入") end
			if not track.sitDown then table.insert(dropOff, "未坐下") end
			if not track.portalInteraction then table.insert(dropOff, "未完成Portal") end
			table.insert(stats.dropOffAmbulance, {
				playerId = playerId,
				dropPoints = dropOff
			})
		end
	end

	stats.completionRate = stats.totalPlayers > 0 and (stats.completedFunnel / stats.totalPlayers) or 0

	return stats
end

return TutorialAnalyticsService
