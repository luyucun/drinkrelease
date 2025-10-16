-- 脚本名称: WinStreakPurchaseClient
-- 脚本作用: V1.6 客户端连胜购买UI处理脚本
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local winStreakPurchaseEvent = remoteEventsFolder:WaitForChild("WinStreakPurchase")


-- 等待PlayerGui中的UI元素（而不是StarterGui）
local playerGui = player:WaitForChild("PlayerGui")

-- 使用FindFirstChild和重试机制，而不是WaitForChild
local function waitForUIComponent(parent, childName, timeout)
	timeout = timeout or 10
	local startTime = tick()

	while tick() - startTime < timeout do
		local child = parent:FindFirstChild(childName)
		if child then
			return child
		end
		wait(0.1)
	end

	return nil
end

local confirmGui = waitForUIComponent(playerGui, "Confirm", 15)
if not confirmGui then
	warn("❌ 未找到PlayerGui.Confirm，尝试检查StarterGui...")
	-- 回退到StarterGui检查
	local starterGui = game:GetService("StarterGui")
	confirmGui = starterGui:FindFirstChild("Confirm")
	if confirmGui then
	else
		error("❌ 既没有在PlayerGui也没有在StarterGui中找到Confirm")
	end
else
end

local buyWinsFrame = waitForUIComponent(confirmGui, "BuyWins", 10)
if not buyWinsFrame then
	error("❌ 未找到BuyWins Frame")
end

local noBtn = waitForUIComponent(buyWinsFrame, "NoBtn", 5)
if not noBtn then
	error("❌ 未找到NoBtn")
end

local yesBtn = waitForUIComponent(buyWinsFrame, "YesBtn", 5)
if not yesBtn then
	error("❌ 未找到YesBtn")
end

local streakNumLabel = waitForUIComponent(buyWinsFrame, "StreakNum", 5)
if not streakNumLabel then
	error("❌ 未找到StreakNum")
end


-- 处理玩家点击"是"按钮
local function onYesButtonClicked()

	-- 动态查找UI组件
	local currentPlayerGui = player:FindFirstChild("PlayerGui")
	if not currentPlayerGui then
		warn("PlayerGui不存在，无法处理Yes按钮点击")
		return
	end

	local currentConfirmGui = currentPlayerGui:FindFirstChild("Confirm")
	if not currentConfirmGui then
		warn("Confirm GUI不存在，无法处理Yes按钮点击")
		return
	end

	local currentBuyWinsFrame = currentConfirmGui:FindFirstChild("BuyWins")
	if not currentBuyWinsFrame then
		warn("BuyWins Frame不存在，无法处理Yes按钮点击")
		return
	end


	if not currentBuyWinsFrame.Visible then
		warn("UI未显示时点击了Yes按钮")
		return
	end


	-- 发送购买请求到服务端
	winStreakPurchaseEvent:FireServer("purchase")

	-- 注意：不再立即隐藏UI，等待服务端通过RemoteEvent通知隐藏
end

-- 处理玩家点击"否"按钮
local function onNoButtonClicked()

	-- 动态查找UI组件
	local currentPlayerGui = player:FindFirstChild("PlayerGui")
	if not currentPlayerGui then
		warn("PlayerGui不存在，无法处理No按钮点击")
		return
	end

	local currentConfirmGui = currentPlayerGui:FindFirstChild("Confirm")
	if not currentConfirmGui then
		warn("Confirm GUI不存在，无法处理No按钮点击")
		return
	end

	local currentBuyWinsFrame = currentConfirmGui:FindFirstChild("BuyWins")
	if not currentBuyWinsFrame then
		warn("BuyWins Frame不存在，无法处理No按钮点击")
		return
	end


	if not currentBuyWinsFrame.Visible then
		warn("UI未显示时点击了No按钮")
		return
	end


	-- 发送拒绝请求到服务端
	winStreakPurchaseEvent:FireServer("decline")

	-- 注意：不再立即隐藏UI，等待服务端通过RemoteEvent通知隐藏
end

-- 显示连胜购买UI
local function showWinStreakPurchaseUI(streakCount)

	-- 动态查找UI组件（防止初始化时组件不存在）
	local currentPlayerGui = player:FindFirstChild("PlayerGui")
	if not currentPlayerGui then
		warn("❌ PlayerGui不存在，无法显示UI")
		return
	end

	local currentConfirmGui = currentPlayerGui:FindFirstChild("Confirm")
	if not currentConfirmGui then
		warn("❌ Confirm GUI不存在，无法显示UI")
		return
	end

	local currentBuyWinsFrame = currentConfirmGui:FindFirstChild("BuyWins")
	if not currentBuyWinsFrame then
		warn("❌ BuyWins Frame不存在，无法显示UI")
		return
	end

	local currentStreakNumLabel = currentBuyWinsFrame:FindFirstChild("StreakNum")
	if not currentStreakNumLabel then
		warn("❌ StreakNum Label不存在，无法显示UI")
		return
	end

	-- 动态查找并连接按钮事件
	local currentYesBtn = currentBuyWinsFrame:FindFirstChild("YesBtn")
	local currentNoBtn = currentBuyWinsFrame:FindFirstChild("NoBtn")

	if currentYesBtn then
		currentYesBtn.MouseButton1Click:Connect(function()
			onYesButtonClicked()
		end)
	else
		warn("❌ YesBtn不存在，无法连接事件")
	end

	if currentNoBtn then
		currentNoBtn.MouseButton1Click:Connect(function()
			onNoButtonClicked()
		end)
	else
		warn("❌ NoBtn不存在，无法连接事件")
	end

	-- 检查是否已显示
	if currentBuyWinsFrame.Visible then
		return
	end


	-- 更新连胜数显示
	currentStreakNumLabel.Text = tostring(streakCount)

	-- 设置Frame可见
	currentBuyWinsFrame.Visible = true

end

-- 隐藏连胜购买UI
local function hideWinStreakPurchaseUI()

	-- 动态查找UI组件
	local currentPlayerGui = player:FindFirstChild("PlayerGui")
	if not currentPlayerGui then
		warn("❌ PlayerGui不存在，无法隐藏UI")
		return
	end

	local currentConfirmGui = currentPlayerGui:FindFirstChild("Confirm")
	if not currentConfirmGui then
		warn("❌ Confirm GUI不存在，无法隐藏UI")
		return
	end

	local currentBuyWinsFrame = currentConfirmGui:FindFirstChild("BuyWins")
	if not currentBuyWinsFrame then
		warn("❌ BuyWins Frame不存在，无法隐藏UI")
		return
	end

	if not currentBuyWinsFrame.Visible then
		return
	end


	-- 隐藏Frame
	currentBuyWinsFrame.Visible = false

end

-- 处理购买成功
local function onPurchaseSuccess(data)
	local restoredStreak = data and data.restoredStreak or 0

	-- 隐藏购买UI
	hideWinStreakPurchaseUI()
end

-- 处理购买失败
local function onPurchaseFailed(data)
	local reason = data and data.reason or "未知错误"
	warn("连胜购买失败: " .. reason)

	-- 隐藏购买UI
	hideWinStreakPurchaseUI()
end

-- 设置RemoteEvent监听
local function setupRemoteEventListeners()
	winStreakPurchaseEvent.OnClientEvent:Connect(function(action, data)

		if action == "showUI" then
			local streakCount = data and data.streakCount or 0
			showWinStreakPurchaseUI(streakCount)

		elseif action == "hideUI" then
			hideWinStreakPurchaseUI()

		elseif action == "purchaseSuccess" then
			onPurchaseSuccess(data)

		elseif action == "purchaseFailed" then
			onPurchaseFailed(data)

		else
			warn("未知的连胜购买客户端事件: " .. action)
		end
	end)

end

-- 初始化UI状态
local function initializeUI()
	-- 确保UI初始状态为隐藏
	buyWinsFrame.Visible = false

end

-- 错误处理：确保UI组件存在
local function validateUIComponents()
	local components = {
		{buyWinsFrame, "BuyWins Frame"},
		{noBtn, "NoBtn Button"},
		{yesBtn, "YesBtn Button"},
		{streakNumLabel, "StreakNum Label"}
	}

	for _, component in ipairs(components) do
		if not component[1] then
			error("连胜购买UI组件缺失: " .. component[2])
		end
	end

end

-- 主初始化函数
local function initialize()

	-- 验证UI组件
	validateUIComponents()

	-- 初始化UI状态
	initializeUI()

	-- 设置RemoteEvent监听（按钮事件现在在UI显示时动态连接）
	setupRemoteEventListeners()

end

-- 等待所有依赖加载完成后初始化
spawn(function()
	-- 确保所有UI元素已加载
	wait(1)

	-- 开始初始化
	initialize()
end)

-- 调试功能：手动显示UI（仅用于测试）
local function debugShowUI(streakCount)
	showWinStreakPurchaseUI(streakCount or 5)
end

-- 调试功能：手动隐藏UI（仅用于测试）
local function debugHideUI()
	hideWinStreakPurchaseUI()
end

-- 导出调试功能到全局（仅在开发环境中使用）
if game:GetService("RunService"):IsStudio() then
	_G.DebugWinStreakPurchaseUI = {
		show = debugShowUI,
		hide = debugHideUI,
		getVisible = function()
			return buyWinsFrame.Visible
		end,
		getStreakText = function()
			return streakNumLabel.Text
		end
	}
end