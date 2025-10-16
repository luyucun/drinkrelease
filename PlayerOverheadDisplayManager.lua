-- 脚本名称: PlayerOverheadDisplayManager
-- 脚本作用: V1.5 管理玩家头顶连胜信息显示，处理BillboardGui的创建、更新和管理
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local PlayerOverheadDisplayManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 玩家头顶显示状态管理
local playerOverheadDisplays = {} -- {player = {billboardGui = gui, connection = conn}}

-- 显示配置参数
local DISPLAY_CONFIG = {
	HEIGHT_OFFSET = Vector3.new(0, 3, 0),  -- 相对于头部的高度偏移 (X, Y, Z) - 调整这里的Y值来改变高度
	SIZE = UDim2.new(0, 200, 0, 50),       -- BillboardGui尺寸
}

-- 配置修改函数（可在游戏运行时调用）
function PlayerOverheadDisplayManager.setHeightOffset(offsetY)
	DISPLAY_CONFIG.HEIGHT_OFFSET = Vector3.new(0, offsetY, 0)

	-- 更新所有现有显示的高度
	for player, displayData in pairs(playerOverheadDisplays) do
		if displayData.attachment then
			displayData.attachment.Position = DISPLAY_CONFIG.HEIGHT_OFFSET
		end
	end
end

-- 获取当前高度设置
function PlayerOverheadDisplayManager.getHeightOffset()
	return DISPLAY_CONFIG.HEIGHT_OFFSET.Y
end

-- 等待Victory模板
local victoryTemplate = nil

-- 安全地获取Victory模板
local function getVictoryTemplate()
	if not victoryTemplate then
		victoryTemplate = ReplicatedStorage:FindFirstChild("Victory")
		if not victoryTemplate then
			warn("PlayerOverheadDisplayManager: ReplicatedStorage中未找到Victory Part")
			return nil
		end

		local billboardGui = victoryTemplate:FindFirstChild("BillboardGui")
		if not billboardGui then
			warn("PlayerOverheadDisplayManager: Victory下未找到BillboardGui模板")
			return nil
		end

	end

	return victoryTemplate
end

-- 获取玩家当前连胜数值
local function getPlayerWinStreak(player)
	if not _G.RankingDataManager then
		warn("PlayerOverheadDisplayManager: RankingDataManager不可用")
		return 0
	end

	local playerData = _G.RankingDataManager.getPlayerRankingData(player)
	if playerData and playerData.consecutiveWins then
		return playerData.consecutiveWins
	end

	return 0
end

-- 为玩家创建头顶连胜显示
function PlayerOverheadDisplayManager.createOverheadDisplay(player)
	if not player or not player.Character then
		warn("PlayerOverheadDisplayManager: 玩家或角色不存在: " .. (player and player.Name or "未知"))
		return false
	end

	-- 清理现有显示（如果存在）
	PlayerOverheadDisplayManager.removeOverheadDisplay(player)

	-- 获取Victory模板
	local template = getVictoryTemplate()
	if not template then
		warn("无法获取Victory模板")
		return false
	end

	local templateGui = template:FindFirstChild("BillboardGui")
	if not templateGui then
		warn("Victory模板中未找到BillboardGui")
		return false
	end

	-- 查找玩家头部
	local character = player.Character
	local head = character:FindFirstChild("Head")
	if not head then
		warn("玩家 " .. player.Name .. " 没有Head部件")
		return false
	end

	-- 克隆BillboardGui
	local clonedGui = templateGui:Clone()
	clonedGui.Name = "WinStreakDisplay_" .. player.Name
	-- ✅ 移除强制Size设置，保留Victory模板的原始尺寸
	-- clonedGui.Size = DISPLAY_CONFIG.SIZE  -- 已删除，使用模板原始Size

	-- 创建Attachment来控制显示位置
	local attachment = Instance.new("Attachment")
	attachment.Name = "WinStreakAttachment_" .. player.Name
	attachment.Position = DISPLAY_CONFIG.HEIGHT_OFFSET
	attachment.Parent = head

	-- 将BillboardGui附加到Attachment上
	clonedGui.Adornee = attachment
	clonedGui.Parent = workspace

	-- 设置连胜数值
	local numLabel = clonedGui:FindFirstChild("Num")
	if numLabel and numLabel:IsA("TextLabel") then
		local winStreak = getPlayerWinStreak(player)
		numLabel.Text = tostring(winStreak)
	else
		warn("BillboardGui模板中未找到Num TextLabel")
		clonedGui:Destroy()
		return false
	end

	-- 缓存显示组件
	playerOverheadDisplays[player] = {
		billboardGui = clonedGui,
		attachment = attachment,
		lastWinStreak = getPlayerWinStreak(player)
	}

	return true
end

-- 移除玩家头顶连胜显示
function PlayerOverheadDisplayManager.removeOverheadDisplay(player)
	if not player then return end

	local displayData = playerOverheadDisplays[player]
	if displayData then
		-- 销毁BillboardGui
		if displayData.billboardGui then
			displayData.billboardGui:Destroy()
		end

		-- 销毁Attachment
		if displayData.attachment then
			displayData.attachment:Destroy()
		end

		-- 清理缓存
		playerOverheadDisplays[player] = nil
	end
end

-- 更新玩家连胜显示数值
function PlayerOverheadDisplayManager.updatePlayerWinStreak(player)
	if not player then return end

	local displayData = playerOverheadDisplays[player]
	if not displayData or not displayData.billboardGui then
		-- 如果没有显示，尝试创建
		PlayerOverheadDisplayManager.createOverheadDisplay(player)
		return
	end

	local currentWinStreak = getPlayerWinStreak(player)

	-- 只有当数值发生变化时才更新
	if displayData.lastWinStreak ~= currentWinStreak then
		local numLabel = displayData.billboardGui:FindFirstChild("Num")
		if numLabel and numLabel:IsA("TextLabel") then
			numLabel.Text = tostring(currentWinStreak)
			displayData.lastWinStreak = currentWinStreak
		end
	end
end

-- 更新所有在线玩家的连胜显示
function PlayerOverheadDisplayManager.updateAllPlayersWinStreak()
	for _, player in pairs(Players:GetPlayers()) do
		if player and player.Character then
			PlayerOverheadDisplayManager.updatePlayerWinStreak(player)
		end
	end
end

-- 处理玩家角色生成事件
function PlayerOverheadDisplayManager.onCharacterAdded(player, character)
	local head = character:WaitForChild("Head", 10)
	if head then
		-- 稍微延迟确保角色完全加载
		wait(1)
		PlayerOverheadDisplayManager.createOverheadDisplay(player)
	else
		warn("玩家 " .. player.Name .. " 的Head部件加载失败")
	end
end

-- 处理玩家角色移除事件
function PlayerOverheadDisplayManager.onCharacterRemoving(player, character)
	PlayerOverheadDisplayManager.removeOverheadDisplay(player)
end

-- 处理玩家离开事件
function PlayerOverheadDisplayManager.onPlayerRemoving(player)
	PlayerOverheadDisplayManager.removeOverheadDisplay(player)
end

-- 设置玩家事件监听
function PlayerOverheadDisplayManager.setupPlayerEvents()
	-- 处理已存在的玩家
	for _, player in pairs(Players:GetPlayers()) do
		if player.Character then
			spawn(function()
				PlayerOverheadDisplayManager.onCharacterAdded(player, player.Character)
			end)
		end

		-- 监听角色生成和移除
		player.CharacterAdded:Connect(function(character)
			PlayerOverheadDisplayManager.onCharacterAdded(player, character)
		end)

		player.CharacterRemoving:Connect(function(character)
			PlayerOverheadDisplayManager.onCharacterRemoving(player, character)
		end)
	end

	-- 监听新玩家加入
	Players.PlayerAdded:Connect(function(player)

		if player.Character then
			spawn(function()
				PlayerOverheadDisplayManager.onCharacterAdded(player, player.Character)
			end)
		end

		-- 监听角色生成和移除
		player.CharacterAdded:Connect(function(character)
			PlayerOverheadDisplayManager.onCharacterAdded(player, character)
		end)

		player.CharacterRemoving:Connect(function(character)
			PlayerOverheadDisplayManager.onCharacterRemoving(player, character)
		end)
	end)

	-- 监听玩家离开
	Players.PlayerRemoving:Connect(function(player)
		PlayerOverheadDisplayManager.onPlayerRemoving(player)
	end)

end

-- 启动定期更新（可选，用于同步检查）
function PlayerOverheadDisplayManager.startPeriodicUpdate()
	spawn(function()
		while true do
			wait(10) -- 每10秒检查一次
			PlayerOverheadDisplayManager.updateAllPlayersWinStreak()
		end
	end)

end

-- 初始化管理器
function PlayerOverheadDisplayManager.initialize()

	-- 等待依赖系统加载
	local attempts = 0
	while not _G.RankingDataManager and attempts < 30 do
		wait(1)
		attempts = attempts + 1
	end

	if not _G.RankingDataManager then
		warn("PlayerOverheadDisplayManager: RankingDataManager加载失败，头顶显示可能无法正常工作")
	else
	end

	-- 设置事件监听
	PlayerOverheadDisplayManager.setupPlayerEvents()

	-- 启动定期更新
	PlayerOverheadDisplayManager.startPeriodicUpdate()

end

-- 手动触发连胜更新（供其他系统调用）
function PlayerOverheadDisplayManager.onWinStreakChanged(player)
	if player then
		PlayerOverheadDisplayManager.updatePlayerWinStreak(player)
	end
end

-- 获取状态信息（调试用）
function PlayerOverheadDisplayManager.getStatus()
	local status = {
		totalDisplays = 0,
		activeDisplays = {}
	}

	for player, displayData in pairs(playerOverheadDisplays) do
		status.totalDisplays = status.totalDisplays + 1
		status.activeDisplays[player.Name] = {
			hasGui = displayData.billboardGui ~= nil,
			lastWinStreak = displayData.lastWinStreak
		}
	end

	return status
end

-- 启动管理器
PlayerOverheadDisplayManager.initialize()

-- 导出到全局供其他脚本使用
_G.PlayerOverheadDisplayManager = PlayerOverheadDisplayManager

return PlayerOverheadDisplayManager