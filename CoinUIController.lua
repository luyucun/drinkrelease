-- 脚本名称: CoinUIController
-- 脚本作用: 客户端金币UI显示和动画控制
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local CoinUIController = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local coinUpdateEvent = remoteEventsFolder:WaitForChild("CoinUpdate")

-- UI状态
local uiState = {
	currentCoins = 0,
	isAnimating = false,
	coinLabel = nil
}

-- 获取金币UI引用
local function getCoinUI()
	local playerGui = player:WaitForChild("PlayerGui")

	-- 等待Menu GUI从StarterGui复制到PlayerGui
	local menuGui = playerGui:WaitForChild("Menu", 10)
	if not menuGui then
		warn("未找到Menu GUI，请检查StarterGui中是否存在Menu ScreenGui")
		return nil
	end

	local imageButtonMoney = menuGui:WaitForChild("ImageButtonMoney", 5)
	if not imageButtonMoney then
		warn("未找到Menu GUI中的ImageButtonMoney")
		return nil
	end

	local coinNum = imageButtonMoney:WaitForChild("CoinNum", 5)
	if not coinNum then
		warn("未找到ImageButtonMoney中的CoinNum TextLabel")
		return nil
	end

	return coinNum
end

-- 更新金币显示
function CoinUIController.updateCoinDisplay(coinAmount)
	local coinLabel = getCoinUI()
	if not coinLabel then return end

	uiState.currentCoins = coinAmount
	uiState.coinLabel = coinLabel

	-- 格式化显示文本
	local formattedText = "$" .. coinAmount
	coinLabel.Text = formattedText

end

-- 播放金币增加动画
function CoinUIController.playCoinsAddedAnimation(coinLabel, amount)
	if not coinLabel or uiState.isAnimating then return end

	uiState.isAnimating = true

	-- 创建临时的+金币显示
	local tempLabel = Instance.new("TextLabel")
	tempLabel.Size = UDim2.new(0, 100, 0, 30)
	tempLabel.Position = UDim2.new(0, coinLabel.AbsolutePosition.X + 100, 0, coinLabel.AbsolutePosition.Y - 20)
	tempLabel.BackgroundTransparency = 1
	tempLabel.Text = "+" .. amount
	tempLabel.TextColor3 = Color3.new(0, 1, 0) -- 绿色
	tempLabel.TextScaled = true
	tempLabel.Font = Enum.Font.SourceSansBold
	tempLabel.TextStrokeTransparency = 0
	tempLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	tempLabel.Parent = coinLabel.Parent

	-- 主标签放大动画
	local originalSize = coinLabel.Size
	local scaleUpInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local scaleDownInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)

	local scaleUpTween = TweenService:Create(coinLabel, scaleUpInfo, {
		Size = originalSize + UDim2.new(0.2, 0, 0.2, 0)
	})

	local scaleDownTween = TweenService:Create(coinLabel, scaleDownInfo, {
		Size = originalSize
	})

	-- 临时标签上浮动画
	local floatInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local floatTween = TweenService:Create(tempLabel, floatInfo, {
		Position = tempLabel.Position + UDim2.new(0, 0, 0, -50),
		Transparency = 1
	})

	-- 播放动画序列
	scaleUpTween:Play()
	floatTween:Play()

	scaleUpTween.Completed:Connect(function()
		scaleDownTween:Play()
	end)

	scaleDownTween.Completed:Connect(function()
		uiState.isAnimating = false
	end)

	-- 1.5秒后清理临时标签
	game:GetService("Debris"):AddItem(tempLabel, 1.5)
end

-- 播放金币闪烁特效
function CoinUIController.playGlowEffect(coinLabel)
	if not coinLabel then return end

	-- 创建发光效果
	local glowFrame = Instance.new("Frame")
	glowFrame.Size = coinLabel.Size + UDim2.new(0.1, 0, 0.1, 0)
	glowFrame.Position = coinLabel.Position - UDim2.new(0.05, 0, 0.05, 0)
	glowFrame.BackgroundColor3 = Color3.new(1, 1, 0) -- 金色
	glowFrame.BackgroundTransparency = 0.8
	glowFrame.BorderSizePixel = 0
	glowFrame.Parent = coinLabel.Parent

	-- 创建圆角
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = glowFrame

	-- 脉冲动画
	local pulseInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
	local pulseTween = TweenService:Create(glowFrame, pulseInfo, {
		BackgroundTransparency = 0.95,
		Size = glowFrame.Size + UDim2.new(0.2, 0, 0.2, 0)
	})

	pulseTween:Play()

	-- 1.5秒后移除发光效果
	pulseTween.Completed:Connect(function()
		glowFrame:Destroy()
	end)
end

-- 显示奖励通知
function CoinUIController.showRewardNotification(amount, reason, newTotal)
	local coinLabel = getCoinUI()
	if not coinLabel then return end


	-- 先更新显示
	CoinUIController.updateCoinDisplay(newTotal)

	-- 播放动画（暂时禁用发光效果）
	CoinUIController.playCoinsAddedAnimation(coinLabel, amount)
	-- CoinUIController.playGlowEffect(coinLabel) -- 已禁用：避免黄色闪烁
end

-- 检查UI是否存在，如果不存在则创建
function CoinUIController.ensureCoinUIExists()
	local playerGui = player:WaitForChild("PlayerGui")

	-- 使用WaitForChild等待UI从StarterGui复制过来
	local menuGui = playerGui:WaitForChild("Menu", 10)

	if not menuGui then
		warn("Menu GUI未从StarterGui复制到PlayerGui，请检查:")
		warn("1. StarterGui中是否存在Menu ScreenGui")
		warn("2. Menu ScreenGui的ResetOnSpawn属性是否正确")
		warn("3. 玩家是否已完全加载")
		return false
	end

	local imageButtonMoney = menuGui:WaitForChild("ImageButtonMoney", 5)
	if not imageButtonMoney then
		warn("Menu GUI中缺少ImageButtonMoney")
		return false
	end

	local coinNum = imageButtonMoney:WaitForChild("CoinNum", 5)
	if not coinNum then
		warn("ImageButtonMoney中缺少CoinNum TextLabel")
		return false
	end

	return true
end

-- 设置UI位置和样式（可选的自动配置）
function CoinUIController.setupCoinUIStyle()
	local coinLabel = getCoinUI()
	if not coinLabel then return end

	-- 确保文本格式正确
	if coinLabel.Text == "" or not coinLabel.Text:match("%$%d+") then
		coinLabel.Text = "$0"
	end

	-- 设置基本样式（不修改颜色）
	coinLabel.TextScaled = true
	-- 移除了 TextColor3 设置，保持原有颜色

end

-- 处理服务器事件
function CoinUIController.setupRemoteEvents()
	coinUpdateEvent.OnClientEvent:Connect(function(action, data)
		if action == "updateUI" then
			local coinAmount = data.coins or 0
			CoinUIController.updateCoinDisplay(coinAmount)

		elseif action == "showReward" then
			local amount = data.amount or 0
			local reason = data.reason or "未知"
			local newTotal = data.newTotal or 0

			CoinUIController.showRewardNotification(amount, reason, newTotal)
		end
	end)

end

-- 初始化时自动请求当前金币数量
function CoinUIController.requestInitialCoins()
	-- 延迟请求，确保服务器端已准备好
	wait(3)

	-- 如果有需要，可以添加请求当前金币的RemoteFunction
	-- 目前服务器端会在玩家加入时自动发送数据
end

-- 初始化金币UI控制器
function CoinUIController.initialize()

	-- 等待玩家角色完全加载
	if not player.Character then
		player.CharacterAdded:Wait()
	end

	-- 额外等待确保UI完全复制
	wait(2)

	-- 检查UI是否存在
	if not CoinUIController.ensureCoinUIExists() then
		warn("金币UI初始化失败，请检查StarterGui设置")
		return
	end

	-- 设置UI样式
	CoinUIController.setupCoinUIStyle()

	-- 设置远程事件监听
	CoinUIController.setupRemoteEvents()

	-- 请求初始金币数据
	spawn(function()
		CoinUIController.requestInitialCoins()
	end)

end

-- 启动控制器
CoinUIController.initialize()

return CoinUIController