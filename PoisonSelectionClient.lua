-- 脚本名称: PoisonSelectionClient
-- 脚本作用: 客户端毒药选择UI控制和交互处理
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local PoisonSelectionClient = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- 引入打字机效果模块
local TypewriterEffect = require(ReplicatedStorage:WaitForChild("TypewriterEffect"))

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local poisonSelectionEvent = remoteEventsFolder:WaitForChild("PoisonSelection")

-- UI状态
local uiState = {
	selectionActive = false,
	confirmationActive = false,
	selectedDrinkIndex = nil
}

-- 按钮事件连接引用（防止泄漏）
local buttonConnections = {
	yesBtn = nil,
	noBtn = nil
}

-- 按钮是否已初始化的标志
local buttonsInitialized = false

-- 获取UI引用
local function getConfirmUI()
	local playerGui = player:WaitForChild("PlayerGui")
	return playerGui:WaitForChild("Confirm")
end

-- 显示选择UI
function PoisonSelectionClient.showSelectionUI()
	local confirmUI = getConfirmUI()
	local confirmTips = confirmUI:FindFirstChild("ConfirmTips")

	if confirmTips then
		confirmTips.Visible = true
		uiState.selectionActive = true

		-- 设置毒药注入阶段的提示文本（使用打字机效果）
		local tips = confirmTips:FindFirstChild("Tips")
		if tips then
			TypewriterEffect.play(tips, "Click on a drink to inject poison")
		else
			warn("未找到ConfirmTips下的Tips TextLabel")
		end

	else
		warn("未找到ConfirmTips")
	end
end

-- 隐藏选择UI
function PoisonSelectionClient.hideSelectionUI()
	local confirmUI = getConfirmUI()
	local confirmTips = confirmUI:FindFirstChild("ConfirmTips")

	if confirmTips then
		confirmTips.Visible = false
		uiState.selectionActive = false
	end
end

-- 显示确认弹框
function PoisonSelectionClient.showConfirmation(drinkIndex)
	local confirmUI = getConfirmUI()
	local confirmBg = confirmUI:FindFirstChild("ConfirmBg")

	if confirmBg then
		confirmBg.Visible = true
		uiState.confirmationActive = true
		uiState.selectedDrinkIndex = drinkIndex

		-- 只在第一次显示时设置按钮事件，避免重复绑定
		if not buttonsInitialized then
			PoisonSelectionClient.setupConfirmationButtons(confirmBg)
			buttonsInitialized = true
		end

	else
		warn("未找到ConfirmBg")
	end
end

-- 隐藏确认弹框
function PoisonSelectionClient.hideConfirmation()
	local confirmUI = getConfirmUI()
	local confirmBg = confirmUI:FindFirstChild("ConfirmBg")

	if confirmBg then
		confirmBg.Visible = false
		uiState.confirmationActive = false
		uiState.selectedDrinkIndex = nil
	end
end

-- 设置确认按钮事件
function PoisonSelectionClient.setupConfirmationButtons(confirmBg)
	local yesBtn = confirmBg:FindFirstChild("YesBtn")
	local noBtn = confirmBg:FindFirstChild("NoBtn")

	-- 先断开旧的事件连接，防止泄漏
	if buttonConnections.yesBtn then
		buttonConnections.yesBtn:Disconnect()
		buttonConnections.yesBtn = nil
	end
	if buttonConnections.noBtn then
		buttonConnections.noBtn:Disconnect()
		buttonConnections.noBtn = nil
	end

	if yesBtn then
		buttonConnections.yesBtn = yesBtn.MouseButton1Click:Connect(function()
			PoisonSelectionClient.onConfirmSelection(true)
		end)
	else
		warn("未找到YesBtn")
	end

	if noBtn then
		buttonConnections.noBtn = noBtn.MouseButton1Click:Connect(function()
			PoisonSelectionClient.onConfirmSelection(false)
		end)
	else
		warn("未找到NoBtn")
	end
end

-- 处理确认选择
function PoisonSelectionClient.onConfirmSelection(confirmed)
	-- 发送确认结果到服务器
	poisonSelectionEvent:FireServer("confirm", {
		confirmed = confirmed,
		drinkIndex = uiState.selectedDrinkIndex
	})

	-- 不管选择什么，都隐藏确认弹框，让服务器决定下一步
	PoisonSelectionClient.hideConfirmation()

	if not confirmed then
		-- 隐藏选择UI，因为要直接进入下一阶段
		PoisonSelectionClient.hideSelectionUI()
	end
end

-- 隐藏所有UI
function PoisonSelectionClient.hideAllUI()
	PoisonSelectionClient.hideSelectionUI()
	PoisonSelectionClient.hideConfirmation()
	uiState.selectionActive = false
	uiState.confirmationActive = false
end
function PoisonSelectionClient.handleGameOver(data)
	PoisonSelectionClient.hideAllUI()

	-- 这里可以显示游戏结束UI
	-- 暂时只输出信息
end

-- 处理胜利
function PoisonSelectionClient.handleVictory(data)
	PoisonSelectionClient.hideAllUI()

	-- 这里可以显示胜利UI
	-- 暂时只输出信息
end

-- V1.4: 开始毒药注入视觉效果
function PoisonSelectionClient.startPoisonEffect(drinkIndex)

	-- 检测玩家所在的桌子
	local tableId = PoisonSelectionClient.detectPlayerTable()
	if not tableId then
		warn("无法检测玩家所在的桌子，使用默认桌子")
		tableId = "2player_group1"
	end

	-- 找到对应的奶茶模型
	local workspace = game.Workspace
	local twoPlayerFolder = workspace:FindFirstChild("2Player")
	if not twoPlayerFolder then
		warn("未找到2Player文件夹")
		return
	end

	local battleGroup = twoPlayerFolder:FindFirstChild(tableId)
	if not battleGroup then
		warn("未找到桌子: " .. tableId)
		return
	end

	local classicTable = battleGroup:FindFirstChild("ClassicTable")
	if not classicTable then
		warn("未找到ClassicTable")
		return
	end

	local drinkName = "Drink_" .. string.format("%02d", drinkIndex)
	local drinkModel = classicTable:FindFirstChild(drinkName)
	if not drinkModel then
		warn("未找到奶茶模型: " .. drinkName)
		return
	end

	-- 找到Effect Part
	local effectPart = drinkModel:FindFirstChild("Effect")
	if not effectPart then
		warn("奶茶 " .. drinkIndex .. " 未找到Effect Part")
		return
	end

	-- 从ReplicatedStorage获取Poison粒子效果
	local replicatedStorage = game:GetService("ReplicatedStorage")
	local poisonPart = replicatedStorage:FindFirstChild("Poison")
	if not poisonPart then
		warn("ReplicatedStorage中未找到Poison Part")
		return
	end

	-- 复制所有ParticleEmitter
	local copiedEmitters = {}
	for _, child in pairs(poisonPart:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			local clonedEmitter = child:Clone()
			clonedEmitter.Parent = effectPart
			table.insert(copiedEmitters, clonedEmitter)

			clonedEmitter.Enabled = true
		end
	end

	-- 2秒后清理效果
	spawn(function()
		wait(2)

		-- 移除所有复制的粒子效果
		for _, emitter in pairs(copiedEmitters) do
			if emitter and emitter.Parent then
				emitter.Enabled = false
				emitter:Destroy()
			end
		end

	end)
end

-- 检测玩家所在的桌子（客户端版本）
function PoisonSelectionClient.detectPlayerTable()
	local player = Players.LocalPlayer
	if not player.Character then return nil end

	local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return nil end

	local playerPosition = humanoidRootPart.Position
	local workspace = game.Workspace
	local twoPlayerFolder = workspace:FindFirstChild("2Player")
	if not twoPlayerFolder then return nil end

	local closestTableId = nil
	local closestDistance = math.huge

	-- 遍历所有桌子，找到最近的
	for _, child in pairs(twoPlayerFolder:GetChildren()) do
		if child.Name:match("^2player_group%d+$") then
			local classicTable = child:FindFirstChild("ClassicTable")
			if classicTable then
				local tablePart = classicTable:FindFirstChild("TablePart")
				if tablePart then
					local distance = (playerPosition - tablePart.Position).Magnitude
					if distance < closestDistance and distance < 20 then
						closestDistance = distance
						closestTableId = child.Name
					end
				end
			end
		end
	end

	return closestTableId
end

-- 设置RemoteEvent处理
function PoisonSelectionClient.setupRemoteEvents()
	poisonSelectionEvent.OnClientEvent:Connect(function(action, data)
		if action == "showSelectionUI" then
			PoisonSelectionClient.showSelectionUI()
		elseif action == "hideSelectionUI" then
			PoisonSelectionClient.hideSelectionUI()
		elseif action == "showConfirmation" then
			PoisonSelectionClient.showConfirmation(data.drinkIndex)
		elseif action == "hideConfirmation" then
			PoisonSelectionClient.hideConfirmation()
		elseif action == "hideAll" then
			PoisonSelectionClient.hideAllUI()
		elseif action == "startPoisonEffect" then
			PoisonSelectionClient.startPoisonEffect(data.drinkIndex)
		elseif action == "gameOver" then
			PoisonSelectionClient.handleGameOver(data)
		elseif action == "victory" then
			PoisonSelectionClient.handleVictory(data)
		end
	end)

end

-- 初始化
function PoisonSelectionClient.initialize()
	PoisonSelectionClient.setupRemoteEvents()
	-- 不再监听奶茶点击，由服务器端DrinkManager统一处理
end

-- 启动客户端控制器
PoisonSelectionClient.initialize()

return PoisonSelectionClient