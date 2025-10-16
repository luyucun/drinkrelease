-- 脚本名称: RankingUIManager
-- 脚本作用: 管理排行榜UI显示和更新，处理Workspace中排行榜界面的渲染
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local RankingUIManager = {}
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- 配置参数
local CONFIG = {
	MAX_RANKING_DISPLAY = 50,    -- 最大排行榜显示数量
	TOP3_SPECIAL_DISPLAY = 3,    -- 前3名特殊显示
	UPDATE_DELAY = 2             -- UI更新延迟（秒）
}

-- 排行榜UI路径配置
local RANKING_PATHS = {
	consecutiveWins = {
		leaderboard = nil,  -- 将在initialize中设置
		scrollingFrame = nil,  -- 将在initialize中设置
		title = "连胜排行榜"
	},
	totalWins = {
		leaderboard = nil,  -- 将在initialize中设置
		scrollingFrame = nil,  -- 将在initialize中设置
		title = "总胜利排行榜"
	}
}

-- UI状态
local uiState = {
	lastUpdateTime = 0,
	isUpdating = false,
	thumbnailCache = {}  -- 头像缓存
}

-- 获取玩家头像
function RankingUIManager.getPlayerThumbnail(userId)
	-- 检查缓存
	if uiState.thumbnailCache[userId] then
		return uiState.thumbnailCache[userId]
	end

	-- 异步获取头像
	local success, thumbnail = pcall(function()
		return Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
	end)

	if success and thumbnail then
		-- 缓存头像
		uiState.thumbnailCache[userId] = thumbnail
		return thumbnail
	else
		warn("获取玩家 " .. userId .. " 头像失败: " .. tostring(thumbnail))
		-- 返回默认头像URL
		return "rbxasset://textures/face.png"
	end
end

-- 清理动态生成的排行榜UI元素
function RankingUIManager.clearDynamicRankingItems(scrollingFrame)
	if not scrollingFrame then return end

	-- 查找并删除所有动态生成的排行榜项目（除了前3名和模板）
	for _, child in pairs(scrollingFrame:GetChildren()) do
		if child.Name:match("^Rank_%d+$") then -- 匹配动态生成的项目
			child:Destroy()
		end
	end

end

-- 更新单个排行榜项目
function RankingUIManager.updateRankingItem(rankFrame, rank, playerData)
	if not rankFrame or not playerData then return false end

	-- 更新排名
	local rankingLabel = rankFrame:FindFirstChild("Ranking")
	if rankingLabel then
		rankingLabel.Text = "#" .. rank
	end

	-- 更新玩家名称
	local userNameLabel = rankFrame:FindFirstChild("UserName")
	if userNameLabel then
		userNameLabel.Text = playerData.displayName or "Unknown"
	end

	-- 更新分数（连胜数或总胜利数）
	local scoreLabel = rankFrame:FindFirstChild("Score")
	if scoreLabel then
		-- 根据排行榜类型显示不同的分数
		if rankFrame.Parent.Parent.Parent.Name == "Ranking01" then
			-- 连胜排行榜显示连胜数
			scoreLabel.Text = tostring(playerData.consecutiveWins or 0)
		else
			-- 总胜利排行榜显示总胜利数
			scoreLabel.Text = tostring(playerData.totalWins or 0)
		end
	end

	-- 异步更新玩家头像
	spawn(function()
		local userPhotoLabel = rankFrame:FindFirstChild("UserPhoto")
		if userPhotoLabel and playerData.userId then
			local thumbnail = RankingUIManager.getPlayerThumbnail(playerData.userId)
			userPhotoLabel.Image = thumbnail
		end
	end)

	return true
end

-- 创建动态排行榜项目（为第4-50名使用）
function RankingUIManager.createDynamicRankingItem(scrollingFrame, templateFrame, rank, playerData)
	if not scrollingFrame or not templateFrame then return nil end

	-- 克隆模板
	local newRankFrame = templateFrame:Clone()
	newRankFrame.Name = "Rank_" .. rank
	newRankFrame.Visible = true
	newRankFrame.Parent = scrollingFrame

	-- 只更新内容，不设置位置和大小（由您在编辑器中设置的布局控制）
	RankingUIManager.updateRankingItem(newRankFrame, rank, playerData)

	return newRankFrame
end

-- 更新指定类型的排行榜UI
function RankingUIManager.updateRankingDisplay(rankingType, rankingData)
	local pathConfig = RANKING_PATHS[rankingType]
	if not pathConfig or not pathConfig.scrollingFrame then
		warn("无效的排行榜类型或路径配置: " .. tostring(rankingType))
		return false
	end

	local scrollingFrame = pathConfig.scrollingFrame


	-- 清理动态生成的项目
	RankingUIManager.clearDynamicRankingItems(scrollingFrame)

	-- 更新前3名（使用固定的UI元素）
	for i = 1, math.min(#rankingData, CONFIG.TOP3_SPECIAL_DISPLAY) do
		local rankFrame = scrollingFrame:FindFirstChild("Rank" .. string.format("%02d", i))
		if rankFrame then
			RankingUIManager.updateRankingItem(rankFrame, i, rankingData[i])
			rankFrame.Visible = true
		else
			warn("未找到排行榜UI元素: Rank" .. string.format("%02d", i))
		end
	end

	-- 隐藏空的前3名位置
	for i = #rankingData + 1, CONFIG.TOP3_SPECIAL_DISPLAY do
		local rankFrame = scrollingFrame:FindFirstChild("Rank" .. string.format("%02d", i))
		if rankFrame then
			rankFrame.Visible = false
		end
	end

	-- 为第4-50名创建动态项目
	if #rankingData > CONFIG.TOP3_SPECIAL_DISPLAY then
		local templateFrame = scrollingFrame:FindFirstChild("RankTemplate")
		if templateFrame then
			for i = 4, math.min(#rankingData, CONFIG.MAX_RANKING_DISPLAY) do
				RankingUIManager.createDynamicRankingItem(
					scrollingFrame,
					templateFrame,
					i,
					rankingData[i]
				)
			end
		else
			warn("未找到排行榜模板: RankTemplate")
		end
	end

	-- 注意: CanvasSize由您在编辑器中的UI布局自动控制，不在代码中设置

	return true
end

-- 更新连胜排行榜UI
function RankingUIManager.updateConsecutiveWinsRanking()
	if not _G.RankingDataManager then
		warn("RankingDataManager 未加载，无法更新连胜排行榜UI")
		return false
	end


	local rankingData = _G.RankingDataManager.getConsecutiveWinsRanking(CONFIG.MAX_RANKING_DISPLAY)
	return RankingUIManager.updateRankingDisplay("consecutiveWins", rankingData)
end

-- 更新总胜利排行榜UI
function RankingUIManager.updateTotalWinsRanking()
	if not _G.RankingDataManager then
		warn("RankingDataManager 未加载，无法更新总胜利排行榜UI")
		return false
	end


	local rankingData = _G.RankingDataManager.getTotalWinsRanking(CONFIG.MAX_RANKING_DISPLAY)
	return RankingUIManager.updateRankingDisplay("totalWins", rankingData)
end

-- 更新所有排行榜UI
function RankingUIManager.updateAllRankings()
	if uiState.isUpdating then
		return
	end

	uiState.isUpdating = true

	-- 添加延迟避免频繁更新
	local currentTime = tick()
	if currentTime - uiState.lastUpdateTime < CONFIG.UPDATE_DELAY then
		uiState.isUpdating = false
		return
	end

	spawn(function()
		-- 更新连胜排行榜
		local success1 = RankingUIManager.updateConsecutiveWinsRanking()

		-- 等待一小段时间避免同时更新造成卡顿
		wait(0.5)

		-- 更新总胜利排行榜
		local success2 = RankingUIManager.updateTotalWinsRanking()

		if success1 and success2 then
		else
			warn("部分排行榜UI更新失败")
		end

		uiState.lastUpdateTime = currentTime
		uiState.isUpdating = false
	end)
end

-- 响应全服排行榜数据更新
function RankingUIManager.onGlobalRankingUpdated()

	-- 延迟更新UI，确保数据已完全更新
	spawn(function()
		wait(1)
		RankingUIManager.updateAllRankings()
	end)
end

-- 定期更新排行榜UI
function RankingUIManager.setupPeriodicUpdate()
	spawn(function()
		while true do
			wait(60) -- 每60秒更新一次UI

			if not uiState.isUpdating then
				RankingUIManager.updateAllRankings()
			end
		end
	end)
end

-- 验证排行榜UI结构
function RankingUIManager.validateUIStructure()
	local isValid = true

	-- 首先检查主要Leaderboard文件夹
	local workspace = game.Workspace
	local leaderboard = workspace:FindFirstChild("Leaderboard")
	if not leaderboard then
		warn("未找到Workspace.Leaderboard")
		return false
	end

	-- 定义排行榜类型和对应的Workspace路径
	local rankingConfigs = {
		consecutiveWins = {name = "Ranking01", title = "连胜排行榜"},
		totalWins = {name = "Ranking02", title = "总胜利排行榜"}
	}

	for rankingType, config in pairs(rankingConfigs) do

		local rankingFolder = leaderboard:FindFirstChild(config.name)
		if not rankingFolder then
			warn("未找到排行榜文件夹: " .. config.name)
			isValid = false
			continue
		end

		-- 保存leaderboard引用
		RANKING_PATHS[rankingType].leaderboard = rankingFolder

		-- 尝试找到ScrollingFrame的路径，支持多种可能的结构
		local scrollingFrame = nil
		local foundPath = ""

		-- 方法1: 标准结构 - Ranking/List/SurfaceGui/ScrollingFrame
		local listFolder = rankingFolder:FindFirstChild("List")
		if listFolder then
			local surfaceGui = listFolder:FindFirstChild("SurfaceGui")
			if surfaceGui then
				scrollingFrame = surfaceGui:FindFirstChild("ScrollingFrame")
				if scrollingFrame then
					foundPath = config.name .. "/List/SurfaceGui/ScrollingFrame"
				end
			end
		end

		-- 方法2: 直接结构 - Ranking/SurfaceGui/ScrollingFrame
		if not scrollingFrame then
			local surfaceGui = rankingFolder:FindFirstChild("SurfaceGui")
			if surfaceGui then
				scrollingFrame = surfaceGui:FindFirstChild("ScrollingFrame")
				if scrollingFrame then
					foundPath = config.name .. "/SurfaceGui/ScrollingFrame"
				end
			end
		end

		-- 方法3: 深度搜索ScrollingFrame
		if not scrollingFrame then
			local function findScrollingFrame(parent)
				for _, child in pairs(parent:GetChildren()) do
					if child.Name == "ScrollingFrame" and child:IsA("ScrollingFrame") then
						return child
					end
					local found = findScrollingFrame(child)
					if found then return found end
				end
				return nil
			end

			scrollingFrame = findScrollingFrame(rankingFolder)
			if scrollingFrame then
				foundPath = config.name .. "/[深度搜索找到]ScrollingFrame"
			end
		end

		if scrollingFrame then
			RANKING_PATHS[rankingType].scrollingFrame = scrollingFrame

			-- 验证前3名UI元素
			for i = 1, CONFIG.TOP3_SPECIAL_DISPLAY do
				local rankFrame = scrollingFrame:FindFirstChild("Rank" .. string.format("%02d", i))
				if not rankFrame then
					warn("未找到前" .. i .. "名UI元素: " .. config.name)
					isValid = false
				else
					-- 验证子元素
					local requiredChildren = {"UserPhoto", "Ranking", "Score", "UserName"}
					for _, childName in ipairs(requiredChildren) do
						if not rankFrame:FindFirstChild(childName) then
							warn("排行榜项目缺少子元素 " .. childName .. ": " .. rankFrame.Name)
							isValid = false
						end
					end
				end
			end

			-- 验证模板
			local templateFrame = scrollingFrame:FindFirstChild("RankTemplate")
			if not templateFrame then
				warn("未找到RankTemplate: " .. config.name)
				isValid = false
			end
		else
			warn("❌ 未找到ScrollingFrame: " .. config.name)
			isValid = false
		end

	end

	return isValid
end

-- 调试：打印排行榜UI状态
function RankingUIManager.debugPrintUIStatus()
	-- Debug function for UI status - prints removed for production
end

-- 初始化排行榜UI管理器
function RankingUIManager.initialize()

	-- 验证UI结构
	local isValid = RankingUIManager.validateUIStructure()
	if not isValid then
		warn("排行榜UI结构验证失败，部分功能可能无法正常工作")
	end

	-- 初始更新排行榜
	spawn(function()
		wait(3) -- 等待其他系统加载完成
		RankingUIManager.updateAllRankings()
	end)

	-- 启动定期更新
	RankingUIManager.setupPeriodicUpdate()

end

-- 启动管理器
RankingUIManager.initialize()

-- 将RankingUIManager暴露到全局环境，供其他脚本使用
_G.RankingUIManager = RankingUIManager

return RankingUIManager