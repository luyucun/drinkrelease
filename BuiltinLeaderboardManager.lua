-- 脚本名称: BuiltinLeaderboardManager
-- 脚本作用: 管理Roblox内置游戏排行榜，显示单局内玩家累计获胜数
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local BuiltinLeaderboardManager = {}
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- 内置排行榜配置
local CONFIG = {
	LEADERBOARD_NAME = "Leaderboard",        -- 排行榜名称
	STAT_NAME = "Total Wins",                -- 统计名称
	UPDATE_INTERVAL = 5,                     -- 更新间隔（秒）
	DISPLAY_NAME = "🏆 Wins"                 -- 显示名称
}

-- 排行榜状态
local leaderboardState = {
	lastUpdateTime = 0,
	playerStats = {},  -- 缓存玩家统计数据
	isInitialized = false
}

-- 初始化玩家排行榜显示
function BuiltinLeaderboardManager.initializePlayerLeaderboard(player)

	-- 创建leaderstats文件夹（Roblox内置排行榜要求）
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	-- 创建累计获胜数统计
	local totalWinsValue = leaderstats:FindFirstChild(CONFIG.STAT_NAME)
	if not totalWinsValue then
		totalWinsValue = Instance.new("IntValue")
		totalWinsValue.Name = CONFIG.STAT_NAME
		totalWinsValue.Value = 0
		totalWinsValue.Parent = leaderstats
	end

	-- 从RankingDataManager获取玩家数据
	spawn(function()
		-- 等待RankingDataManager加载
		local attempts = 0
		while not _G.RankingDataManager and attempts < 20 do
			wait(0.5)
			attempts = attempts + 1
		end

		if _G.RankingDataManager then
			wait(1) -- 等待玩家数据加载完成
			local playerData = _G.RankingDataManager.getPlayerRankingData(player)
			if playerData then
				totalWinsValue.Value = playerData.totalWins or 0
			end
		else
			warn("RankingDataManager 未加载，无法获取玩家 " .. player.Name .. " 的初始数据")
		end
	end)

	-- 缓存引用
	leaderboardState.playerStats[player] = totalWinsValue

	return totalWinsValue
end

-- 更新玩家内置排行榜数据
function BuiltinLeaderboardManager.updatePlayerStats(player, totalWins)
	if not player then return false end

	local totalWinsValue = leaderboardState.playerStats[player]
	if not totalWinsValue then
		-- 如果统计对象不存在，尝试重新初始化
		totalWinsValue = BuiltinLeaderboardManager.initializePlayerLeaderboard(player)
	end

	if totalWinsValue then
		totalWinsValue.Value = totalWins or 0
		return true
	else
		warn("无法更新玩家 " .. player.Name .. " 的内置排行榜数据")
		return false
	end
end

-- 更新所有在线玩家的内置排行榜
function BuiltinLeaderboardManager.updateAllPlayersStats()
	if not _G.RankingDataManager then
		warn("RankingDataManager 未加载，无法更新内置排行榜")
		return
	end

	local updatedCount = 0
	for _, player in pairs(Players:GetPlayers()) do
		local playerData = _G.RankingDataManager.getPlayerRankingData(player)
		if playerData then
			local success = BuiltinLeaderboardManager.updatePlayerStats(player, playerData.totalWins)
			if success then
				updatedCount = updatedCount + 1
			end
		end
	end
end

-- 响应排行榜数据变化
function BuiltinLeaderboardManager.onPlayerRankingChanged(player, newRankingData)
	if not player or not newRankingData then return end

	BuiltinLeaderboardManager.updatePlayerStats(player, newRankingData.totalWins)
end

-- 玩家加入游戏处理
function BuiltinLeaderboardManager.onPlayerAdded(player)

	-- 延迟初始化，确保其他系统已加载
	spawn(function()
		wait(3)
		BuiltinLeaderboardManager.initializePlayerLeaderboard(player)
	end)
end

-- 玩家离开游戏处理
function BuiltinLeaderboardManager.onPlayerRemoving(player)

	-- 清理缓存
	if leaderboardState.playerStats[player] then
		leaderboardState.playerStats[player] = nil
	end
end

-- 定期更新内置排行榜
function BuiltinLeaderboardManager.setupPeriodicUpdate()
	spawn(function()
		while true do
			wait(CONFIG.UPDATE_INTERVAL)

			local currentTime = tick()
			if currentTime - leaderboardState.lastUpdateTime >= CONFIG.UPDATE_INTERVAL then
				BuiltinLeaderboardManager.updateAllPlayersStats()
				leaderboardState.lastUpdateTime = currentTime
			end
		end
	end)
end

-- 手动刷新特定玩家的排行榜数据
function BuiltinLeaderboardManager.refreshPlayerStats(player)
	if not player or not _G.RankingDataManager then return false end


	local playerData = _G.RankingDataManager.getPlayerRankingData(player)
	if playerData then
		return BuiltinLeaderboardManager.updatePlayerStats(player, playerData.totalWins)
	else
		warn("无法获取玩家 " .. player.Name .. " 的排行榜数据")
		return false
	end
end

-- 获取所有玩家当前排行榜数据（调试用）
function BuiltinLeaderboardManager.getAllPlayerStats()
	local allStats = {}

	for player, totalWinsValue in pairs(leaderboardState.playerStats) do
		if player and player.Parent and totalWinsValue then
			allStats[player.Name] = {
				totalWins = totalWinsValue.Value,
				displayName = player.DisplayName or player.Name
			}
		end
	end

	return allStats
end

-- 调试：打印所有玩家内置排行榜状态
function BuiltinLeaderboardManager.debugPrintAllStats()
end

-- 集成到RankingDataManager的回调（修复：避免重复记录排行榜数据）
function BuiltinLeaderboardManager.setupRankingDataIntegration()
	-- 检查RankingDataManager是否可用
	spawn(function()
		local attempts = 0
		while not _G.RankingDataManager and attempts < 30 do
			wait(1)
			attempts = attempts + 1
		end

		if _G.RankingDataManager then
			-- 不再扩展 recordGameResult 函数，避免重复调用
			-- 而是监听数据变化事件来更新内置排行榜
			-- 这样避免了重复记录的问题

			-- 设置定期同步机制，而不是在每次记录时同步
			spawn(function()
				while true do
					wait(2) -- 每2秒检查一次是否需要更新

					-- 检查所有在线玩家，同步他们的内置排行榜数据
					for _, player in pairs(Players:GetPlayers()) do
						if player and player.Parent then
							pcall(function()
								BuiltinLeaderboardManager.refreshPlayerStats(player)
							end)
						end
					end
				end
			end)
		else
			warn("RankingDataManager 加载超时，内置排行榜功能可能受影响")
		end
	end)
end

-- 初始化内置排行榜管理器
function BuiltinLeaderboardManager.initialize()

	-- 设置玩家事件监听
	Players.PlayerAdded:Connect(BuiltinLeaderboardManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(BuiltinLeaderboardManager.onPlayerRemoving)

	-- 处理已在线的玩家
	for _, player in pairs(Players:GetPlayers()) do
		BuiltinLeaderboardManager.onPlayerAdded(player)
	end

	-- 启动定期更新
	BuiltinLeaderboardManager.setupPeriodicUpdate()

	-- 设置与RankingDataManager的集成
	BuiltinLeaderboardManager.setupRankingDataIntegration()

	leaderboardState.isInitialized = true
end

-- 获取玩家当前总胜利数（供外部调用）
function BuiltinLeaderboardManager.getPlayerTotalWins(player)
	local totalWinsValue = leaderboardState.playerStats[player]
	return totalWinsValue and totalWinsValue.Value or 0
end

-- 强制更新所有玩家数据（供外部调用）
function BuiltinLeaderboardManager.forceUpdateAll()
	BuiltinLeaderboardManager.updateAllPlayersStats()
end

-- 启动管理器
BuiltinLeaderboardManager.initialize()

-- 将BuiltinLeaderboardManager暴露到全局环境，供其他脚本使用
_G.BuiltinLeaderboardManager = BuiltinLeaderboardManager

return BuiltinLeaderboardManager