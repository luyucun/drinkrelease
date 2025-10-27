-- 脚本名称: NewPlayerRouter
-- 脚本作用: 在玩家加入游戏时，检查是否是新玩家，如果是则传送到Newplayer场景
-- 脚本类型: Script
-- 放置位置: ServerScriptService (仅主场景)

-- 🔧 CRITICAL FIX: 此脚本仅在主场景运行，教程场景不需要
local NEWPLAYER_PLACE_ID = 139891708045596  -- 新手引导场景
local MAIN_PLACE_ID = 138909711165251       -- 常规场景

-- 检查当前场景
if game.PlaceId ~= MAIN_PLACE_ID then
	print("[NewPlayerRouter] 当前不在主场景，脚本已禁用")
	return
end

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

-- 检查是否在Studio环境
local isStudio = RunService:IsStudio()

-- 引入服务
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

-- V1.9: 将PlayerDataService注册到全局，供其他模块使用
_G.PlayerDataService = PlayerDataService

-- ============================================
-- 玩家加入时的分流逻辑
-- ============================================

local function onPlayerAdded(player)
	-- 🔧 V1.6修复: 添加状态检查，防止重复处理
	-- 检查内存中的状态，避免重复路由
	if _G.TutorialCompleted and _G.TutorialCompleted[player.UserId] then
		return
	end

	-- 检查传送失败标记，避免无限循环
	if _G.TutorialTransportFailed and _G.TutorialTransportFailed[player.UserId] then
		-- 清理失败标记，允许下次尝试
		_G.TutorialTransportFailed[player.UserId] = nil
		return
	end

	-- 加载玩家数据
	local playerData = PlayerDataService:loadPlayerData(player)

	-- 检查是否是新玩家
	local isNewPlayer = playerData.newPlayerCompleted == false

	-- 如果是新玩家，传送到Newplayer场景
	if isNewPlayer then
		-- 在 Studio 中不进行传送，避免警告
		if isStudio then
			return
		end

		local success, err = pcall(function()
			TeleportService:Teleport(NEWPLAYER_PLACE_ID, player)
		end)

		if not success then
			warn("[NewPlayerRouter] 传送失败: " .. tostring(err))
			-- 🔧 CRITICAL FIX: 传送失败时不应该标记为完成，而是让玩家留在主场景
			-- 但给予一个"跳过教程"的标记，以便后续识别
			warn("[NewPlayerRouter] 传送失败，玩家将在主场景体验游戏，但仍标记为新玩家")

			-- 设置一个特殊标记，表示这个玩家传送失败了
			if not _G.TutorialTransportFailed then
				_G.TutorialTransportFailed = {}
			end
			_G.TutorialTransportFailed[player.UserId] = true

			-- 不设置为已完成，让玩家下次登录仍可能被传送到教程场景
			-- PlayerDataService:setTutorialCompleted(player, true)  -- 移除这行
		end
	else
		-- V1.9: 检查是否刚完成教程且需要皮肤引导
		if playerData.newPlayerCompleted and not playerData.skinGuideShown then
			-- 等待玩家角色加载后再触发引导
			player.CharacterAdded:Wait()
			task.delay(2, function()
				if player and player.Parent and _G.SkinGuideManager then
					_G.SkinGuideManager:initializePlayerGuide(player)
				end
			end)
		end
	end
end

local function onPlayerRemoving(player)
	-- 清理缓存
	PlayerDataService:cleanupPlayerCache(player)
end

-- 监听玩家加入和离开
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- 处理已在线的玩家（虽然通常不会发生）
for _, player in pairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
