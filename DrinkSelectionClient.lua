-- 脚本名称: DrinkSelectionClient
-- 脚本作用: 客户端轮流选择奶茶的UI控制和交互处理
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local DrinkSelectionClient = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- 引入打字机效果模块
local TypewriterEffect = require(ReplicatedStorage:WaitForChild("TypewriterEffect"))

-- 获取当前玩家所在的桌子（根据tableId获取battleGroup）
local function getCurrentPlayerTable(tableId)
	local twoPlayerFolder = workspace:FindFirstChild("2Player")
	if not twoPlayerFolder then
		warn("DrinkSelectionClient: 找不到2Player文件夹")
		return nil
	end

	-- 如果提供了tableId，直接查找对应的桌子组
	if tableId then
		local targetGroup = twoPlayerFolder:FindFirstChild(tableId)
		if targetGroup then
			return targetGroup
		else
			warn("DrinkSelectionClient: 找不到指定的桌子组: " .. tableId)
		end
	end

	-- 回退：使用默认桌子
	local defaultTable = twoPlayerFolder:FindFirstChild("2player_group1")
	if defaultTable then
		return defaultTable
	end

	-- 最后回退：查找任意一个可用的桌子组
	for _, groupFolder in pairs(twoPlayerFolder:GetChildren()) do
		if groupFolder.Name:match("2player_group%d+") then
			local classicTable = groupFolder:FindFirstChild("ClassicTable")
			if classicTable then
				return groupFolder
			end
		end
	end

	warn("DrinkSelectionClient: 找不到任何可用的桌子组")
	return nil
end

-- 获取当前桌子的ClassicTable
local function getClassicTable(tableId)
	local battleGroup = getCurrentPlayerTable(tableId)
	if not battleGroup then return nil end

	return battleGroup:FindFirstChild("ClassicTable")
end

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local drinkSelectionEvent = remoteEventsFolder:WaitForChild("DrinkSelection")

-- UI状态
local uiState = {
	selectionActive = false,
	availableDrinks = {},
	poisonedDrinks = {},    -- 本玩家投毒的奶茶
	highlightConnections = {}
}

-- 显示选择UI
function DrinkSelectionClient.showSelectionUI(data)
	if data and data.availableDrinks then
		uiState.availableDrinks = data.availableDrinks
	end

	uiState.selectionActive = true

	-- 高亮可选择的奶茶
	DrinkSelectionClient.highlightAvailableDrinks()

	-- 显示选择提示UI
	DrinkSelectionClient.showSelectionTips()

end

-- 隐藏选择UI
function DrinkSelectionClient.hideSelectionUI()
	uiState.selectionActive = false

	-- 移除高亮效果
	DrinkSelectionClient.removeHighlights()

	-- 隐藏选择提示
	DrinkSelectionClient.hideSelectionTips()

end

-- 显示选择提示
function DrinkSelectionClient.showSelectionTips()
	local playerGui = player:WaitForChild("PlayerGui")
	local confirmGui = playerGui:FindFirstChild("Confirm")

	if confirmGui then
		local selectTips = confirmGui:FindFirstChild("SelectTips")
		if selectTips then
			selectTips.Visible = true
			-- 设置提示文本为轮到玩家选择（使用打字机效果）
			local tips = selectTips:FindFirstChild("Tips")
			if tips then
				TypewriterEffect.play(tips, "Please choose a drink to drink")
			else
				warn("未找到SelectTips下的Tips TextLabel")
			end
		else
			warn("未找到SelectTips UI")
		end
	else
		warn("未找到Confirm GUI")
	end
end

-- 隐藏选择提示
function DrinkSelectionClient.hideSelectionTips()
	local playerGui = player:WaitForChild("PlayerGui")
	local confirmGui = playerGui:FindFirstChild("Confirm")

	if confirmGui then
		local selectTips = confirmGui:FindFirstChild("SelectTips")
		if selectTips then
			selectTips.Visible = false
		end
	end
end

-- 显示等待提示（对手正在选择）
function DrinkSelectionClient.showWaitingTips()
	local playerGui = player:WaitForChild("PlayerGui")
	local confirmGui = playerGui:FindFirstChild("Confirm")

	if confirmGui then
		local selectTips = confirmGui:FindFirstChild("SelectTips")
		if selectTips then
			selectTips.Visible = true
			-- 修改提示文本为等待对手选择（使用打字机效果）
			local tips = selectTips:FindFirstChild("Tips")
			if tips then
				TypewriterEffect.play(tips, "The opponent is choosing a drink")
			else
				warn("未找到SelectTips下的Tips TextLabel")
			end
		else
			warn("未找到SelectTips UI")
		end
	else
		warn("未找到Confirm GUI")
	end
end

-- 隐藏等待提示
function DrinkSelectionClient.hideWaitingTips()
	local playerGui = player:WaitForChild("PlayerGui")
	local confirmGui = playerGui:FindFirstChild("Confirm")

	if confirmGui then
		local selectTips = confirmGui:FindFirstChild("SelectTips")
		if selectTips then
			selectTips.Visible = false
		end
	end
end

-- 显示下毒者的红色标识
function DrinkSelectionClient.showPoisonedDrinks()
	-- 这个功能现在通过PoisonIndicatorClient处理
end

-- 显示红色Num文本（给自己下毒的奶茶）
function DrinkSelectionClient.showRedNumForPoisonedDrinks(data)
	if not data or not data.poisonedDrinks then
		warn("showRedNumForPoisonedDrinks: 缺少毒药奶茶数据")
		return
	end

	local poisonedDrinks = data.poisonedDrinks
	local tableId = data.tableId  -- 获取服务端传递的桌子ID


	-- 获取正确的桌子
	local classicTable = getClassicTable(tableId)
	if not classicTable then
		warn("DrinkSelectionClient.showRedNumForPoisonedDrinks: 无法获取ClassicTable，桌子ID: " .. (tableId or "无"))
		return
	end

	-- 遍历所有被下毒的奶茶，将其Num改为红色
	for _, drinkIndex in ipairs(poisonedDrinks) do
		local drinkName = "Drink_" .. string.format("%02d", drinkIndex)
		local drinkModel = classicTable:FindFirstChild(drinkName)

		if drinkModel then
			local numPart = drinkModel:FindFirstChild("NumPart")
			if numPart then
				local billboardGui = numPart:FindFirstChild("BillboardGui")
				if billboardGui then
					local numLabel = billboardGui:FindFirstChild("Num")
					if numLabel and numLabel:IsA("TextLabel") then
						numLabel.TextColor3 = Color3.new(1, 0, 0) -- 红色
					else
						warn("奶茶 " .. drinkIndex .. " 未找到Num TextLabel")
					end
				else
					warn("奶茶 " .. drinkIndex .. " 未找到BillboardGui")
				end
			else
				warn("奶茶 " .. drinkIndex .. " 未找到NumPart")
			end
		else
			warn("未找到奶茶模型: " .. drinkName)
		end
	end

end

-- 重置所有Num颜色为默认
function DrinkSelectionClient.resetAllNumColors(tableId)
	-- 获取正确的桌子
	local classicTable = getClassicTable(tableId)
	if not classicTable then
		warn("DrinkSelectionClient.resetAllNumColors: 无法获取ClassicTable，桌子ID: " .. (tableId or "无"))
		return
	end

	for i = 1, 24 do
		local drinkName = "Drink_" .. string.format("%02d", i)
		local drinkModel = classicTable:FindFirstChild(drinkName)

		if drinkModel then
			local numPart = drinkModel:FindFirstChild("NumPart")
			if numPart then
				local billboardGui = numPart:FindFirstChild("BillboardGui")
				if billboardGui then
					local numLabel = billboardGui:FindFirstChild("Num")
					if numLabel then
						numLabel.TextColor3 = Color3.new(1, 1, 1) -- 默认白色
					end
				end
			end
		end
	end

end

-- 显示清除毒药效果（红色→绿色Num）
function DrinkSelectionClient.showPoisonCleanEffect(data)
	if not data or not data.drinkIndex or not data.phase then
		warn("showPoisonCleanEffect: 缺少必要数据")
		return
	end

	local drinkIndex = data.drinkIndex
	local phase = data.phase
	local duration = data.duration or 1
	local tableId = data.tableId  -- 获取服务端传递的桌子ID


	-- 查找奶茶的Num元素（使用正确的桌子ID）
	local classicTable = getClassicTable(tableId)
	if not classicTable then
		warn("DrinkSelectionClient.showPoisonCleanEffect: 无法获取ClassicTable，桌子ID: " .. (tableId or "无"))
		return
	end

	local drinkName = "Drink_" .. string.format("%02d", drinkIndex)
	local drinkModel = classicTable:FindFirstChild(drinkName)
	if not drinkModel then
		warn("找不到奶茶模型: " .. drinkName)
		return
	end

	local numPart = drinkModel:FindFirstChild("NumPart")
	if not numPart then return end

	local billboardGui = numPart:FindFirstChild("BillboardGui")
	if not billboardGui then return end

	local numLabel = billboardGui:FindFirstChild("Num")
	if not numLabel then return end

	-- 设置颜色
	local targetColor
	if phase == "red" then
		targetColor = Color3.new(1, 0, 0) -- 红色
	elseif phase == "green" then
		targetColor = Color3.new(0, 1, 0) -- 绿色
	else
		warn("未知的颜色阶段: " .. phase)
		return
	end

	-- 应用颜色
	numLabel.TextColor3 = targetColor

	-- 绿色阶段不恢复白色，保持绿色
end

-- 显示飘字消息
function DrinkSelectionClient.showFloatingMessage(data)
	if not data or not data.message then
		warn("showFloatingMessage: 缺少消息数据")
		return
	end

	local message = data.message
	local color = data.color or Color3.new(1, 1, 0)
	local duration = data.duration or 3


	-- 创建屏幕GUI显示飘字
	local playerGui = player:WaitForChild("PlayerGui")

	-- 创建ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FloatingMessage"
	screenGui.Parent = playerGui

	-- 创建背景Frame
	local frame = Instance.new("Frame")
	frame.Name = "MessageFrame"
	frame.Size = UDim2.new(0, 400, 0, 60)
	frame.Position = UDim2.new(0.5, -200, 0.2, 0) -- 屏幕上方居中
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	-- 添加圆角
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	-- 创建文本标签
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "MessageText"
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.Position = UDim2.new(0, 0, 0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = message
	textLabel.TextColor3 = color
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.SourceSansBold
	textLabel.Parent = frame


	-- 淡入动画
	frame.BackgroundTransparency = 1
	textLabel.TextTransparency = 1

	local fadeInTween = TweenService:Create(frame,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0.3}
	)

	local textFadeInTween = TweenService:Create(textLabel,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{TextTransparency = 0}
	)

	fadeInTween:Play()
	textFadeInTween:Play()

	-- 延迟后淡出并删除
	spawn(function()
		wait(duration - 0.5) -- 提前0.5秒开始淡出

		local fadeOutTween = TweenService:Create(frame,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 1}
		)

		local textFadeOutTween = TweenService:Create(textLabel,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{TextTransparency = 1}
		)

		fadeOutTween:Play()
		textFadeOutTween:Play()

		fadeOutTween.Completed:Connect(function()
			screenGui:Destroy()
		end)
	end)
end

-- 更新SelectTips文本
function DrinkSelectionClient.updateSelectTips(data)
	if not data or not data.text then
		warn("updateSelectTips: 缺少文本数据")
		return
	end


	-- 查找SelectTips UI - 正确路径：StarterGui - Confirm - SelectTips - Tips
	local playerGui = player:WaitForChild("PlayerGui")
	local confirmGui = playerGui:FindFirstChild("Confirm")

	if confirmGui then
		local selectTips = confirmGui:FindFirstChild("SelectTips")
		if selectTips then
			local tips = selectTips:FindFirstChild("Tips")
			if tips and tips:IsA("TextLabel") then
				TypewriterEffect.play(tips, data.text)
			else
				warn("找不到SelectTips中的Tips TextLabel")
			end
		else
			warn("找不到Confirm中的SelectTips")
		end
	else
		warn("找不到Confirm GUI")
	end
end

-- 显示毒药验证结果
function DrinkSelectionClient.showPoisonVerifyResult(data)
	if not data or not data.drinkIndex or not data.color then
		warn("showPoisonVerifyResult: 缺少必要数据")
		return
	end

	local drinkIndex = data.drinkIndex
	local isPoisoned = data.isPoisoned
	local color = data.color
	local tableId = data.tableId  -- 获取服务端传递的桌子ID


	-- 查找奶茶的Num元素（使用正确的桌子ID）
	local classicTable = getClassicTable(tableId)
	if not classicTable then
		warn("DrinkSelectionClient.showPoisonVerifyResult: 无法获取ClassicTable，桌子ID: " .. (tableId or "无"))
		return
	end

	local drinkName = "Drink_" .. string.format("%02d", drinkIndex)
	local drinkModel = classicTable:FindFirstChild(drinkName)
	if not drinkModel then
		warn("找不到奶茶模型: " .. drinkName .. "，桌子ID: " .. (tableId or "无"))
		return
	end

	local numPart = drinkModel:FindFirstChild("NumPart")
	if not numPart then return end

	local billboardGui = numPart:FindFirstChild("BillboardGui")
	if not billboardGui then return end

	local numLabel = billboardGui:FindFirstChild("Num")
	if not numLabel then return end

	-- 设置验证结果颜色
	numLabel.TextColor3 = color

end

-- 高亮可选择的奶茶
function DrinkSelectionClient.highlightAvailableDrinks()
	DrinkSelectionClient.removeHighlights()

	local classicTable = getClassicTable() -- 使用默认桌子（向后兼容）
	if not classicTable then
		warn("DrinkSelectionClient.highlightAvailableDrinks: 无法获取ClassicTable")
		return
	end

	for _, drinkIndex in ipairs(uiState.availableDrinks) do
		local drinkName = "Drink_" .. string.format("%02d", drinkIndex)
		local drinkModel = classicTable:FindFirstChild(drinkName)

		if drinkModel then
			DrinkSelectionClient.addHighlightEffect(drinkModel, drinkIndex)
		end
	end
end

-- 添加高亮效果
function DrinkSelectionClient.addHighlightEffect(drinkModel, drinkIndex)
	-- 创建选择光效
	local selectionEffect = Instance.new("SelectionBox")
	selectionEffect.Name = "SelectionHighlight"
	selectionEffect.Color3 = Color3.new(0, 1, 0) -- 绿色高亮
	selectionEffect.LineThickness = 0.2
	selectionEffect.Transparency = 0.3

	-- 找到主要部件进行高亮
	local targetPart = drinkModel.PrimaryPart or drinkModel:FindFirstChildOfClass("Part")
	if targetPart then
		selectionEffect.Adornee = targetPart
		selectionEffect.Parent = targetPart

		-- 添加脉冲动画
		local pulseInfo = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local pulseTween = TweenService:Create(selectionEffect, pulseInfo, {
			Transparency = 0.8
		})
		pulseTween:Play()

		uiState.highlightConnections[drinkIndex] = {
			effect = selectionEffect,
			tween = pulseTween
		}
	end
end

-- 移除高亮效果
function DrinkSelectionClient.removeHighlights()
	for drinkIndex, connection in pairs(uiState.highlightConnections) do
		if connection.effect then
			connection.effect:Destroy()
		end
		if connection.tween then
			connection.tween:Cancel()
		end
	end

	uiState.highlightConnections = {}
end

-- 注意：奶茶点击现在由服务器端DrinkManager统一处理
-- 客户端通过RemoteEvents接收结果，不再直接处理点击事件

-- 显示饮用结果
function DrinkSelectionClient.showResult(data)
	local targetPlayerName = data.targetPlayer
	local result = data.result
	local color = data.color
	local drinkIndex = data.drinkIndex

	-- 在目标玩家头顶显示结果
	local targetPlayer = Players:FindFirstChild(targetPlayerName)
	if targetPlayer and targetPlayer.Character then
		DrinkSelectionClient.createResultDisplay(targetPlayer.Character, result, color)
	end

end

-- 创建结果显示
function DrinkSelectionClient.createResultDisplay(character, resultText, resultColor)
	local head = character:FindFirstChild("Head")
	if not head then return end

	-- 创建BillboardGui显示结果
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "DrinkResult"
	billboardGui.Size = UDim2.new(4, 0, 2, 0)
	billboardGui.StudsOffset = Vector3.new(0, 3, 0)
	billboardGui.Parent = head

	-- 创建文本标签
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = resultText
	textLabel.TextColor3 = resultColor
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.SourceSansBold
	textLabel.TextStrokeTransparency = 0
	textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	textLabel.Parent = billboardGui

	-- 添加动画效果
	local animInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local scaleTween = TweenService:Create(textLabel, animInfo, {
		TextScaled = true
	})
	scaleTween:Play()

	-- 3秒后移除显示
	game:GetService("Debris"):AddItem(billboardGui, 3)
end

-- 显示游戏胜利
function DrinkSelectionClient.handleGameWin(data)
	local reason = data.reason
	local opponent = data.opponent

	local reasonText = ""
	if reason == "opponent_poisoned" then
		reasonText = "Opponent was poisoned!"
	elseif reason == "opponent_left" then
		reasonText = "Opponent left the game!"
	else
		reasonText = "You Win!"
	end


	-- 显示胜利UI
	DrinkSelectionClient.showGameEndUI("Victory!", reasonText, Color3.new(0, 1, 0))
end

-- 显示游戏失败
function DrinkSelectionClient.handleGameLose(data)
	local reason = data.reason


	-- 显示失败UI
	DrinkSelectionClient.showGameEndUI("Defeat!", "You Lose!", Color3.new(1, 0, 0))
end

-- 显示游戏平局
function DrinkSelectionClient.handleGameDraw(data)
	local reason = data.reason


	-- 显示平局UI
	DrinkSelectionClient.showGameEndUI("Draw!", "It's a Draw!", Color3.new(0.5, 0.5, 0.5))
end

-- 显示游戏结束UI
function DrinkSelectionClient.showGameEndUI(title, subtitle, titleColor)
	local playerGui = player:WaitForChild("PlayerGui")

	-- 创建游戏结束UI
	local gameEndGui = Instance.new("ScreenGui")
	gameEndGui.Name = "GameEndGui"
	gameEndGui.Parent = playerGui

	-- 背景
	local background = Instance.new("Frame")
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.new(0, 0, 0)
	background.BackgroundTransparency = 0.5
	background.Parent = gameEndGui

	-- 主标题
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(0.8, 0, 0.3, 0)
	titleLabel.Position = UDim2.new(0.1, 0, 0.2, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = ""  -- 初始为空，使用打字机效果
	titleLabel.TextColor3 = titleColor
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.SourceSansBold
	titleLabel.TextStrokeTransparency = 0
	titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	titleLabel.Parent = gameEndGui

	-- 使用打字机效果显示标题
	TypewriterEffect.playFast(titleLabel, title)

	-- 副标题
	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Size = UDim2.new(0.6, 0, 0.1, 0)
	subtitleLabel.Position = UDim2.new(0.2, 0, 0.55, 0)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Text = ""  -- 初始为空，使用打字机效果
	subtitleLabel.TextColor3 = Color3.new(1, 1, 1)
	subtitleLabel.TextScaled = true
	subtitleLabel.Font = Enum.Font.SourceSans
	subtitleLabel.Parent = gameEndGui

	-- 延迟显示副标题（等标题打完）
	spawn(function()
		wait(0.3)
		TypewriterEffect.play(subtitleLabel, subtitle)
	end)

	-- 5秒后自动移除
	game:GetService("Debris"):AddItem(gameEndGui, 5)
end

-- 显示奖励
function DrinkSelectionClient.showReward(data)
	local rewardType = data.type
	local amount = data.amount


	-- 这里可以显示奖励动画
	-- 暂时只输出日志
end

-- 停止饮用动画（关键修复：客户端实现动画停止逻辑）
-- 🔧 修复V5：这是解决其他客户端看到无限循环动画的关键
function DrinkSelectionClient.stopDrinkingAnimationForPlayer(targetPlayerName, drinkIndex)
	if not targetPlayerName then
		warn("DrinkSelectionClient.stopDrinkingAnimationForPlayer: 缺少目标玩家名称")
		return
	end

	-- 找到目标玩家
	local targetPlayer = game:GetService("Players"):FindFirstChild(targetPlayerName)
	if not targetPlayer or not targetPlayer.Character then
		-- 玩家可能已离开，无需处理
		return
	end

	local character = targetPlayer.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	-- 🔑 关键修复：遍历所有正在播放的动画轨道
	-- 找到喝奶茶动画对应的 track 并停止它
	local playingTracks = animator:GetPlayingAnimationTracks()
	local DRINKING_ANIMATION_ID = "rbxassetid://71655128068947"

	for _, track in ipairs(playingTracks) do
		-- 检查这是否是喝奶茶的动画
		if track and track.Animation and track.Animation.AnimationId == DRINKING_ANIMATION_ID then
			-- 停止动画
			pcall(function()
				track:Stop(0.1)  -- 淡出0.1秒
			end)
		end
	end

	-- 🔑 补充修复：移除手中的奶茶（如果有的话）
	-- 从 DrinkHandManager 中移除手持道具
	if _G.DrinkHandManager and _G.DrinkHandManager.removeDrinkFromHand then
		pcall(function()
			_G.DrinkHandManager.removeDrinkFromHand(targetPlayer)
		end)
	end
end

-- 注意：奶茶点击检测现在完全由服务器端DrinkManager处理
-- 客户端不再直接监听点击事件，避免重复处理导致双击问题

-- 设置RemoteEvent处理
function DrinkSelectionClient.setupRemoteEvents()
	drinkSelectionEvent.OnClientEvent:Connect(function(action, data)
		if action == "showSelectionUI" then
			DrinkSelectionClient.showSelectionUI(data)
		elseif action == "hideSelectionUI" then
			DrinkSelectionClient.hideSelectionUI()
		elseif action == "showSelectTips" then
			DrinkSelectionClient.showSelectionTips()
		elseif action == "hideSelectTips" then
			DrinkSelectionClient.hideSelectionTips()
		elseif action == "showWaitingTips" then
			DrinkSelectionClient.showWaitingTips()
		elseif action == "hideWaitingTips" then
			DrinkSelectionClient.hideWaitingTips()
		elseif action == "showRedNumForPoison" then
			if data and data.poisonedDrinks then
				DrinkSelectionClient.showRedNumForPoisonedDrinks(data)
			end
		elseif action == "showPoisonedDrinks" then
			DrinkSelectionClient.showPoisonedDrinks()
		elseif action == "showResult" then
			DrinkSelectionClient.showResult(data)
		elseif action == "showReward" then
			DrinkSelectionClient.showReward(data)
		elseif action == "showPoisonCleanEffect" then
			DrinkSelectionClient.showPoisonCleanEffect(data)
		elseif action == "showFloatingMessage" then
			DrinkSelectionClient.showFloatingMessage(data)
		elseif action == "updateSelectTips" then
			DrinkSelectionClient.updateSelectTips(data)
		elseif action == "showPoisonVerifyResult" then
			DrinkSelectionClient.showPoisonVerifyResult(data)
		elseif action == "stopDrinkingAnimation" then
			-- 🔧 修复V5：处理停止饮用动画的指令
			-- 这是解决其他客户端看到无限循环动画的关键
			if data and data.targetPlayer then
				DrinkSelectionClient.stopDrinkingAnimationForPlayer(data.targetPlayer, data.drinkIndex)
			end
		end
	end)

end

-- 初始化
function DrinkSelectionClient.initialize()
	DrinkSelectionClient.setupRemoteEvents()
	-- 注意：移除了setupDrinkClickDetection()，现在由服务器端DrinkManager统一处理点击
end

-- 启动客户端控制器
DrinkSelectionClient.initialize()

return DrinkSelectionClient