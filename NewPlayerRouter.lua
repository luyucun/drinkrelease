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

-- 引入服务
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

-- ============================================
-- 玩家加入时的分流逻辑
-- ============================================

local function onPlayerAdded(player)
	print("[NewPlayerRouter] 玩家加入: " .. player.Name)

	-- 🔧 V1.6修复: 添加状态检查，防止重复处理
	-- 检查内存中的状态，避免重复路由
	if _G.TutorialCompleted and _G.TutorialCompleted[player.UserId] then
		print("[NewPlayerRouter] 玩家 " .. player.Name .. " 已在内存中标记为完成教程，直接进入主场景")
		return
	end

	-- 检查传送失败标记，避免无限循环
	if _G.TutorialTransportFailed and _G.TutorialTransportFailed[player.UserId] then
		print("[NewPlayerRouter] 玩家 " .. player.Name .. " 之前传送失败，跳过本次路由")
		-- 清理失败标记，允许下次尝试
		_G.TutorialTransportFailed[player.UserId] = nil
		return
	end

	-- 加载玩家数据
	local playerData = PlayerDataService:loadPlayerData(player)

	-- 检查是否是新玩家
	local isNewPlayer = playerData.newPlayerCompleted == false

	print("[NewPlayerRouter] 玩家 " .. player.Name .. " isNewPlayer = " .. tostring(isNewPlayer))

	-- 如果是新玩家，传送到Newplayer场景
	if isNewPlayer then
		print("[NewPlayerRouter] 传送新玩家 " .. player.Name .. " 到Newplayer场景")

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
		print("[NewPlayerRouter] 老玩家 " .. player.Name .. " 进入主场景")
		-- 老玩家自动进入主场景（由游戏逻辑负责）
	end
end

local function onPlayerRemoving(player)
	print("[NewPlayerRouter] 玩家离开: " .. player.Name)

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

print("[NewPlayerRouter] ✓ 新玩家路由系统已启动")
