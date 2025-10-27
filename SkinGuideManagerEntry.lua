-- 脚本名称: SkinGuideManagerEntry
-- 脚本作用: V1.9新手皮肤引导系统入口脚本
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local SkinGuideManager = require(script.Parent.SkinGuideManager)
local Players = game:GetService("Players")

-- 初始化管理器
SkinGuideManager:initialize()

-- 等待PlayerDataService加载（最多等10秒）
local function waitForPlayerDataService()
	local maxAttempts = 20
	local attempts = 0

	while attempts < maxAttempts do
		if _G.PlayerDataService then
			return true
		end
		attempts = attempts + 1
		task.wait(0.5)
	end

	warn("[SkinGuideManagerEntry] ⚠️ PlayerDataService加载超时")
	return false
end

-- 异步等待PlayerDataService
task.spawn(function()
	waitForPlayerDataService()
end)

-- 监听玩家加入（检查是否刚从新手场景传送过来）
Players.PlayerAdded:Connect(function(player)
	-- 等待玩家角色加载
	player.CharacterAdded:Connect(function(character)
		-- 延迟检测，确保PlayerDataService已加载玩家数据
		task.delay(2, function()
			if not player or not player.Parent then return end

			-- 检查PlayerDataService是否加载
			local PlayerDataService = _G.PlayerDataService
			if not PlayerDataService then
				warn("[SkinGuideManagerEntry] PlayerDataService未加载，跳过玩家引导")
				return
			end

			local playerData = PlayerDataService:loadPlayerData(player)
			if not playerData then return end

			-- 只对刚完成新手教程且未触发过皮肤引导的玩家生效
			if playerData.newPlayerCompleted and not playerData.skinGuideShown then
					SkinGuideManager:initializePlayerGuide(player)
			end
		end)
	end)

	-- 如果玩家已在游戏中（热重载情况）
	if player.Character then
		task.delay(2, function()
			if not player or not player.Parent then return end

			local PlayerDataService = _G.PlayerDataService
			if not PlayerDataService then return end

			local playerData = PlayerDataService:loadPlayerData(player)
			if not playerData then return end

			if playerData.newPlayerCompleted and not playerData.skinGuideShown then
				print("[SkinGuideManagerEntry] 检测到新玩家完成教程（热重载）: " .. player.Name)
				SkinGuideManager:initializePlayerGuide(player)
			end
		end)
	end
end)
print("[SkinGuideManagerEntry] ✓ 皮肤引导系统已启动")
