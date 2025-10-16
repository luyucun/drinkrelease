-- 脚本名称: NewPlayerGiftClient
-- 脚本作用: 处理新手礼包UI交互、按钮显示/隐藏、购买弹框和提示
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer.StarterPlayerScripts

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 配置
local CONFIG = {
	NEW_PLAYER_GIFT_GAMEPASS_ID = 1503422953,  -- V1.9: 新手礼包通行证ID
	NOTIFICATION_DURATION = 3  -- 提示显示时间（秒）
}

-- 等待RemoteEvent
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local newPlayerGiftEvent = remoteEventsFolder:WaitForChild("NewPlayerGift", 10)

if not newPlayerGiftEvent then
	warn("NewPlayerGiftClient: NewPlayerGift RemoteEvent未找到")
	return
end

-- 等待UI元素
local menuGui = playerGui:WaitForChild("Menu", 10)
if not menuGui then
	warn("NewPlayerGiftClient: Menu GUI未找到")
	return
end

local newPlayerGiftButton = menuGui:WaitForChild("NewPlayerGift", 10)
if not newPlayerGiftButton then
	warn("NewPlayerGiftClient: NewPlayerGift按钮未找到,脚本终止")
	return
end

local newPlayerGiftGui = playerGui:WaitForChild("NewPlayerGift", 10)
if not newPlayerGiftGui then
	warn("NewPlayerGiftClient: NewPlayerGift GUI未找到,脚本终止")
	return
end

local bg = newPlayerGiftGui:WaitForChild("Bg", 10)
if not bg then
	warn("NewPlayerGiftClient: Bg Frame未找到,脚本终止")
	return
end

local closeBtn = bg:WaitForChild("CloseBtn", 10)
local buyBtn = bg:WaitForChild("Buy", 10)

if not closeBtn or not buyBtn then
	warn("NewPlayerGiftClient: CloseBtn或Buy按钮未找到,脚本终止")
	return
end

-- 🔒 防重复点击标志
local isProcessing = false
local lastClickTime = 0
local CLICK_COOLDOWN = 2  -- 2秒点击冷却

-- 显示新手礼包界面
local function showNewPlayerGiftUI()
	bg.Visible = true
end

-- 隐藏新手礼包界面
local function hideNewPlayerGiftUI()
	bg.Visible = false
end

-- 隐藏Menu中的NewPlayerGift按钮
local function hideNewPlayerGiftButton()
	if newPlayerGiftButton then
		newPlayerGiftButton.Visible = false
	end
end

-- 显示Menu中的NewPlayerGift按钮
local function showNewPlayerGiftButton()
	if newPlayerGiftButton then
		newPlayerGiftButton.Visible = true
	end
end

-- 显示提示（飘字）
local function showNotification(message)
	-- 尝试使用TextChatService的飘字功能(更可靠)
	local TextChatService = game:GetService("TextChatService")
	local StarterGui = game:GetService("StarterGui")

	-- 方法1: 使用StarterGui的SetCore (推荐,最稳定)
	local success = pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = message,
			Color = Color3.fromRGB(255, 255, 0),
			Font = Enum.Font.SourceSansBold,
			FontSize = Enum.FontSize.Size24
		})
	end)

	if success then
		return
	end

	-- 方法2: 如果方法1失败,创建临时UI提示
	local notificationGui = Instance.new("ScreenGui")
	notificationGui.Name = "NewPlayerGiftNotification"
	notificationGui.ResetOnSpawn = false
	notificationGui.DisplayOrder = 100  -- 确保显示在最上层

	local notificationLabel = Instance.new("TextLabel")
	notificationLabel.Name = "NotificationLabel"
	notificationLabel.Size = UDim2.new(0, 400, 0, 60)
	notificationLabel.Position = UDim2.new(0.5, -200, 0.3, 0)
	notificationLabel.AnchorPoint = Vector2.new(0, 0)
	notificationLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	notificationLabel.BackgroundTransparency = 0.3
	notificationLabel.BorderSizePixel = 0
	notificationLabel.Text = message
	notificationLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
	notificationLabel.TextSize = 24
	notificationLabel.Font = Enum.Font.SourceSansBold
	notificationLabel.TextScaled = false
	notificationLabel.Parent = notificationGui

	notificationGui.Parent = playerGui

	-- 自动移除
	spawn(function()
		wait(CONFIG.NOTIFICATION_DURATION)
		if notificationGui then
			notificationGui:Destroy()
		end
	end)
end

-- 调起GamePass购买
local function promptGamePassPurchase()
	local success, errorMessage = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, CONFIG.NEW_PLAYER_GIFT_GAMEPASS_ID)
	end)

	if not success then
		warn("NewPlayerGiftClient: 调起GamePass购买失败: " .. tostring(errorMessage))
		showNotification("Purchase failed, please try again")
	end
end

-- 🔒 检查点击冷却
local function isInClickCooldown()
	local currentTime = tick()
	if currentTime - lastClickTime < CLICK_COOLDOWN then
		return true
	end
	lastClickTime = currentTime
	return false
end

-- 处理Buy按钮点击
local function onBuyButtonClicked()
	-- 🔒 检查是否正在处理
	if isProcessing then
		warn("NewPlayerGiftClient: 正在处理中，请稍后")
		return
	end

	-- 🔒 检查点击冷却
	if isInClickCooldown() then
		warn("NewPlayerGiftClient: 点击过快，请稍后再试")
		return
	end

	-- 🔒 立即标记为处理中
	isProcessing = true

	-- 调起GamePass购买弹框
	promptGamePassPurchase()

	-- 短暂等待后清除处理标志（购买弹框是异步的）
	spawn(function()
		wait(1)
		isProcessing = false
	end)
end

-- 处理Close按钮点击
local function onCloseButtonClicked()
	hideNewPlayerGiftUI()
end

-- 处理NewPlayerGift按钮点击（Menu中的按钮）
local function onNewPlayerGiftButtonClicked()
	showNewPlayerGiftUI()
end

-- 设置按钮事件监听
buyBtn.MouseButton1Click:Connect(onBuyButtonClicked)
closeBtn.MouseButton1Click:Connect(onCloseButtonClicked)
newPlayerGiftButton.MouseButton1Click:Connect(onNewPlayerGiftButtonClicked)

-- 监听MarketplaceService的购买完成事件
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(playerWhoClicked, gamePassId, wasPurchased)
	if playerWhoClicked ~= player then return end
	if gamePassId ~= CONFIG.NEW_PLAYER_GIFT_GAMEPASS_ID then return end

	if wasPurchased then
		-- 购买成功，通知服务端领取奖励
		hideNewPlayerGiftUI()

		-- 显示等待提示
		showNotification("Purchase successful! Please wait...")

		-- 🔧 增加延迟到5秒，确保Roblox完成GamePass所有权更新
		-- Roblox的GamePass所有权更新通常需要3-5秒
		spawn(function()
			wait(5)
			newPlayerGiftEvent:FireServer("claimReward", {})
		end)
	else
		-- 购买取消或失败，关闭界面
		hideNewPlayerGiftUI()
	end
end)

-- 监听服务端事件
newPlayerGiftEvent.OnClientEvent:Connect(function(action, data)
	if action == "success" then
		-- 奖励发放成功
		showNotification("Purchase Successful!")
		hideNewPlayerGiftButton()
		hideNewPlayerGiftUI()
	elseif action == "failed" then
		-- 奖励发放失败
		local reason = data and data.reason or "Unknown error"
		showNotification("Purchase failed: " .. reason)
	elseif action == "hideButton" then
		-- 隐藏按钮（已领取过）
		hideNewPlayerGiftButton()
		hideNewPlayerGiftUI()
	elseif action == "alreadyReceived" then
		-- 已领取过
		showNotification("You have already received this gift")
		hideNewPlayerGiftButton()
		hideNewPlayerGiftUI()
	elseif action == "notOwned" then
		-- 未拥有GamePass或验证失败
		local message = data and data.message or "GamePass verification failed"
		showNotification(message)
	end
end)

-- 初始化：向服务端请求检查状态
spawn(function()
	wait(3)  -- 等待服务端初始化
	newPlayerGiftEvent:FireServer("checkStatus", {})
end)

-- 初始化：默认隐藏新手礼包界面
hideNewPlayerGiftUI()