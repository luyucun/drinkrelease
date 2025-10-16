-- 脚本名称: DeathEffectManager
-- 脚本作用: 服务端死亡效果管理，协调死亡动画和黑屏效果
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local DeathEffectManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 等待RemoteEvents文件夹
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

-- 创建死亡效果RemoteEvent
local deathEffectEvent = remoteEventsFolder:FindFirstChild("DeathEffect")
if not deathEffectEvent then
	deathEffectEvent = Instance.new("RemoteEvent")
	deathEffectEvent.Name = "DeathEffect"
	deathEffectEvent.Parent = remoteEventsFolder
end

-- 死亡处理状态管理
local deathStates = {}  -- 存储每个玩家的死亡状态

-- 死亡状态枚举（重构：移除WAITING_RESPAWN，简化为服务端主导的流程）
local DEATH_STATES = {
	NONE = "none",
	DYING = "dying",           -- 正在死亡（固定时长的死亡展示阶段）
	RESPAWNING = "respawning"  -- 正在复活
}

-- 配置参数（重构：简化为固定时长的服务端主导流程）
local DEATH_CONFIG = {
	DEATH_DISPLAY_TIME = 3.0,   -- 死亡展示总时长（固定3秒，服务端完全控制）
	RESPAWN_DELAY = 0.5         -- 复活延迟（角色生成后的额外等待时间）
}

-- 初始化玩家死亡状态
function DeathEffectManager.initializePlayerState(player)
	deathStates[player] = {
		state = DEATH_STATES.NONE,
		deathStartTime = 0,
		respawnConnection = nil
	}
end

-- 清理玩家死亡状态
function DeathEffectManager.cleanupPlayerState(player)
	local playerState = deathStates[player]
	if playerState and playerState.respawnConnection then
		playerState.respawnConnection:Disconnect()
	end
	deathStates[player] = nil
end

-- 获取玩家死亡状态
function DeathEffectManager.getPlayerDeathState(player)
	return deathStates[player] and deathStates[player].state or DEATH_STATES.NONE
end

-- 开始死亡流程（重构：服务端主导，固定时长，不依赖客户端响应）
function DeathEffectManager.startDeathSequence(player)
	if not player or not player.Character then
		warn("DeathEffectManager.startDeathSequence: 玩家或角色不存在")
		return false
	end

	local playerState = deathStates[player]
	if not playerState then
		DeathEffectManager.initializePlayerState(player)
		playerState = deathStates[player]
	end

	-- 检查是否已经在死亡流程中
	if playerState.state ~= DEATH_STATES.NONE then
		warn("DeathEffectManager.startDeathSequence: 玩家 " .. player.Name .. " 已经在死亡流程中，状态: " .. playerState.state)
		return false
	end

	-- 设置死亡状态
	playerState.state = DEATH_STATES.DYING
	playerState.deathStartTime = tick()

	-- V1.6: 通知WinStreakPurchaseManager处理玩家死亡
	if _G.WinStreakPurchaseManager and _G.WinStreakPurchaseManager.onPlayerDeath then
		spawn(function()
			local success, result = pcall(function()
				return _G.WinStreakPurchaseManager.onPlayerDeath(player)
			end)
			if not success then
				warn("通知WinStreakPurchaseManager玩家死亡失败: " .. tostring(result))
			end
		end)
	end

	local character = player.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		warn("玩家 " .. player.Name .. " 没有Humanoid组件")
		-- 即使没有Humanoid也要继续流程，避免卡死
		DeathEffectManager.executeServerDrivenDeathFlow(player, playerState)
		return false
	end

	-- 立即恢复死亡玩家的镜头到默认状态
	local cameraControlEvent = remoteEventsFolder:FindFirstChild("CameraControl")
	if cameraControlEvent then
		pcall(function()
			cameraControlEvent:FireClient(player, "restore")
		end)
	end

	-- 禁用死亡玩家的Leave按钮
	if _G.GameManager and _G.GameManager.disableLeaveButton then
		pcall(function()
			_G.GameManager.disableLeaveButton(player)
		end)
	end

	-- 通知客户端开始死亡效果（可选的视觉增强，不影响服务端流程）
	pcall(function()
		deathEffectEvent:FireClient(player, "startDeathEffect")
	end)

	-- 执行死亡逻辑
	spawn(function()
		-- 设置Humanoid属性优化死亡效果显示
		pcall(function()
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end)

		-- 杀死玩家，触发Roblox默认的死亡效果
		pcall(function()
			humanoid.Health = 0
		end)

		-- 执行服务端主导的死亡流程
		DeathEffectManager.executeServerDrivenDeathFlow(player, playerState)
	end)

	return true
end

-- 执行服务端主导的死亡流程（新增：核心重构逻辑）
function DeathEffectManager.executeServerDrivenDeathFlow(player, playerState)
	-- 等待固定的死亡展示时间
	wait(DEATH_CONFIG.DEATH_DISPLAY_TIME)

	-- 验证玩家状态仍然有效（玩家可能已离开游戏）
	if not player or not player.Parent then
		warn("玩家 " .. (player and player.Name or "未知") .. " 在死亡流程中离开了游戏")
		return
	end

	-- 验证死亡状态仍然正确（防止并发问题）
	if playerState.state ~= DEATH_STATES.DYING then
		warn("玩家 " .. player.Name .. " 死亡状态异常: " .. tostring(playerState.state) .. "，期望: " .. DEATH_STATES.DYING)
		-- 即使状态异常，也继续执行复活，避免卡死
	end

	-- 直接进入复活流程
	playerState.state = DEATH_STATES.RESPAWNING
	DeathEffectManager.respawnPlayer(player)
end

-- 处理客户端复活准备通知（重构：现在客户端通知是可选的，不影响服务端流程）
function DeathEffectManager.onClientReadyForRespawn(player)
	local playerState = deathStates[player]
	if not playerState then
		-- 玩家状态不存在，可能已经完成了死亡流程，这是正常的
		return
	end

	-- 客户端通知已收到（在新架构中，服务端已完全自主处理）
end

-- 复活玩家（重构：增强错误处理，确保流程可靠性）
function DeathEffectManager.respawnPlayer(player)
	local playerState = deathStates[player]
	if not playerState then
		warn("DeathEffectManager.respawnPlayer: 玩家 " .. (player and player.Name or "未知") .. " 状态不存在")
		return
	end

	-- 验证玩家仍然在线
	if not player or not player.Parent then
		warn("DeathEffectManager.respawnPlayer: 玩家 " .. (player and player.Name or "未知") .. " 已离开游戏")
		-- 清理状态
		DeathEffectManager.cleanupPlayerState(player)
		return
	end

	-- 开始复活流程

	-- 设置超时保护，防止LoadCharacter卡死
	local respawnTimeout = false
	spawn(function()
		wait(10) -- 10秒超时
		if playerState.state == DEATH_STATES.RESPAWNING then
			respawnTimeout = true
			warn("⚠️ 玩家 " .. player.Name .. " 复活超时，强制完成流程")
			-- 强制重置状态
			playerState.state = DEATH_STATES.NONE
			playerState.deathStartTime = 0
			-- 通知客户端结束效果（尽力而为）
			pcall(function()
				deathEffectEvent:FireClient(player, "endDeathEffect")
			end)
			-- V1.6: 通知WinStreakPurchaseManager超时复活
			if _G.WinStreakPurchaseManager and _G.WinStreakPurchaseManager.onPlayerRespawned then
				pcall(function()
					_G.WinStreakPurchaseManager.onPlayerRespawned(player)
				end)
			end
		end
	end)

	-- 先注册CharacterAdded监听器，再调用LoadCharacter
	local characterAddedConnection
	characterAddedConnection = player.CharacterAdded:Connect(function(character)
		if respawnTimeout then
			-- 已经超时处理过，断开连接即可
			characterAddedConnection:Disconnect()
			return
		end

		-- 成功生成角色，清理连接
		characterAddedConnection:Disconnect()

		-- 等待角色完全加载
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid then
			warn("⚠️ 玩家 " .. player.Name .. " 角色加载异常：缺少Humanoid")
		end

		wait(DEATH_CONFIG.RESPAWN_DELAY) -- 确保角色稳定

		if respawnTimeout then return end -- 双重检查超时

		-- 通知客户端结束死亡效果
		pcall(function()
			deathEffectEvent:FireClient(player, "endDeathEffect")
		end)

		-- 重置死亡状态
		playerState.state = DEATH_STATES.NONE
		playerState.deathStartTime = 0

		-- V2.0: 复活后重新设置菜单按钮状态
		-- 因为LoadCharacter会重置PlayerGui，所有按钮恢复到StarterGui的初始状态
		-- 通过GameInstance的setMenuVisibility来设置
		spawn(function()
			task.wait(0.5)  -- 增加等待时间，确保PlayerGui和LocalScript完全加载
			if _G.TableManager then
				local tableId = _G.TableManager.detectPlayerTable(player)
				if tableId then
					local gameInstance = _G.TableManager.getTableInstance(tableId)
					if gameInstance and gameInstance.setMenuVisibility then
						pcall(function()
							gameInstance:setMenuVisibility(player, true)  -- 设置所有按钮显示
						end)
					end
				else
					-- 玩家不在桌子上，直接通过RemoteEvent设置
					local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
					local menuControlEvent = remoteEventsFolder:FindFirstChild("MenuControl")
					if menuControlEvent then
						menuControlEvent:FireClient(player, "setMenuVisibility", {visible = true})
					end
				end
			end
		end)

		-- V1.6: 通知WinStreakPurchaseManager玩家复活完成
		if _G.WinStreakPurchaseManager and _G.WinStreakPurchaseManager.onPlayerRespawned then
			spawn(function()
				pcall(function()
					_G.WinStreakPurchaseManager.onPlayerRespawned(player)
				end)
			end)
		end
	end)

	-- 现在安全地重新生成角色
	local loadSuccess = pcall(function()
		player:LoadCharacter()
	end)

	if not loadSuccess then
		warn("⚠️ 玩家 " .. player.Name .. " LoadCharacter失败")
		-- 清理连接
		if characterAddedConnection then
			characterAddedConnection:Disconnect()
		end
		-- 备用处理：直接完成流程
		if not respawnTimeout then
			playerState.state = DEATH_STATES.NONE
			playerState.deathStartTime = 0
			pcall(function()
				deathEffectEvent:FireClient(player, "endDeathEffect")
			end)
		end
	end
end

-- 强制重置玩家死亡状态（重构：简化逻辑，主要用于清理）
function DeathEffectManager.forceResetPlayerState(player)
	local playerState = deathStates[player]
	if playerState then
		playerState.state = DEATH_STATES.NONE
		playerState.deathStartTime = 0
	end

	-- 通知客户端重置效果（尽力而为）
	pcall(function()
		deathEffectEvent:FireClient(player, "resetEffect")
	end)
end

-- 检查死亡流程超时（重构：简化逻辑，主要用于监控）
function DeathEffectManager.checkDeathTimeouts()
	local currentTime = tick()

	for player, playerState in pairs(deathStates) do
		if playerState.state ~= DEATH_STATES.NONE then
			local elapsedTime = currentTime - playerState.deathStartTime

			-- 如果死亡流程超过15秒还没完成，强制重置（应该很少触发，因为新架构是固定3秒）
			if elapsedTime > 15 then
				warn("⚠️ 玩家 " .. player.Name .. " 死亡流程异常超时(" .. elapsedTime .. "秒)，强制重置")
				DeathEffectManager.forceResetPlayerState(player)
			end
		end
	end
end

-- 提供给外部调用的死亡处理函数（替代原来的executePlayerDeathWithEffect）
function DeathEffectManager.handlePlayerDeath(player)
	return DeathEffectManager.startDeathSequence(player)
end

-- 处理玩家加入
function DeathEffectManager.onPlayerAdded(player)
	DeathEffectManager.initializePlayerState(player)
end

-- 处理玩家离开
function DeathEffectManager.onPlayerRemoving(player)
	DeathEffectManager.cleanupPlayerState(player)
end

-- 设置RemoteEvent处理
function DeathEffectManager.setupRemoteEvents()
	deathEffectEvent.OnServerEvent:Connect(function(player, action, data)
		if action == "readyForRespawn" then
			DeathEffectManager.onClientReadyForRespawn(player)
		end
	end)

end

-- 定期检查超时
function DeathEffectManager.setupTimeoutChecker()
	spawn(function()
		while true do
			wait(5)  -- 每5秒检查一次
			DeathEffectManager.checkDeathTimeouts()
		end
	end)
end

-- 初始化死亡效果管理器
function DeathEffectManager.initialize()

	-- 设置玩家事件监听
	Players.PlayerAdded:Connect(DeathEffectManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(DeathEffectManager.onPlayerRemoving)

	-- 处理已在线的玩家
	for _, player in pairs(Players:GetPlayers()) do
		DeathEffectManager.onPlayerAdded(player)
	end

	-- 设置RemoteEvent处理
	DeathEffectManager.setupRemoteEvents()

	-- 启动超时检查器
	DeathEffectManager.setupTimeoutChecker()

end

-- 启动管理器
DeathEffectManager.initialize()

-- 导出到全局供其他脚本使用
_G.DeathEffectManager = DeathEffectManager

return DeathEffectManager