-- 脚本名称: WheelClient
-- 脚本作用: 转盘系统客户端脚本，使用现有StarterGui-Wheel界面
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local WheelClient = {}
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 配置加载
local WheelConfig = nil

-- RemoteEvents
local wheelSpinEvent = nil
local wheelDataSyncEvent = nil
local wheelPurchaseEvent = nil
local wheelInteractionEvent = nil

-- UI元素引用 (使用现有的StarterGui-Wheel结构)
local wheelGui = nil
local wheelBg = nil
local wheelColorBg = nil
local spinButton = nil
local closeButton = nil
local spin5Button = nil
local spin20Button = nil
local spin50Button = nil
local remainingTimeLabel = nil
local freeCountDownLabel = nil

-- 菜单按钮元素
local menuGui = nil
local imageButtonWheel = nil
local wheelNumLabel = nil
local wheelAddLabel = nil

-- 状态管理
local isWheelUIVisible = false
local isSpinning = false
local currentSpinCount = 0
local freeTimerRemaining = 0

-- 音效
local tickSound = nil

-- ============================================
-- 配置和依赖加载
-- ============================================

-- 加载WheelConfig
local function loadWheelConfig()
	if WheelConfig then
		return true
	end

	local success, result = pcall(function()
		return require(ReplicatedStorage:WaitForChild("WheelConfig", 10))
	end)

	if success then
		WheelConfig = result
		return true
	else
		warn("❌ WheelClient: WheelConfig加载失败: " .. tostring(result))
		return false
	end
end

-- 初始化RemoteEvents
local function initializeRemoteEvents()
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEventsFolder then
		warn("❌ WheelClient: RemoteEvents文件夹不存在")
		return false
	end

	wheelSpinEvent = remoteEventsFolder:WaitForChild("WheelSpin", 5)
	wheelDataSyncEvent = remoteEventsFolder:WaitForChild("WheelDataSync", 5)
	wheelPurchaseEvent = remoteEventsFolder:WaitForChild("WheelPurchase", 5)
	wheelInteractionEvent = remoteEventsFolder:WaitForChild("WheelInteraction", 5)

	if not wheelSpinEvent or not wheelDataSyncEvent or not wheelPurchaseEvent or not wheelInteractionEvent then
		warn("❌ WheelClient: 转盘RemoteEvents加载失败")
		return false
	end

	return true
end

-- ============================================
-- UI元素初始化
-- ============================================

-- 初始化现有UI元素
local function initializeUIElements()
	-- 等待StarterGui加载
	task.wait(1)

	-- 查找Wheel界面
	wheelGui = playerGui:WaitForChild("Wheel", 10)
	if not wheelGui then
		warn("❌ WheelClient: 未找到StarterGui-Wheel界面")
		return false
	end

	wheelBg = wheelGui:FindFirstChild("WheelBg")
	if not wheelBg then
		warn("❌ WheelClient: 未找到WheelBg")
		return false
	end

	-- 转盘相关元素
	wheelColorBg = wheelBg:FindFirstChild("WheelColorBg")
	-- 🔧 修复：用户确认SpinButton在WheelBg下，不是WheelColorBg下
	spinButton = wheelBg:FindFirstChild("SpinButton")
	closeButton = wheelBg:FindFirstChild("CloseButton")

	-- 购买按钮
	spin5Button = wheelBg:FindFirstChild("Spin5")
	spin20Button = wheelBg:FindFirstChild("Spin20")
	spin50Button = wheelBg:FindFirstChild("Spin50")

	-- 显示标签
	local remainingTime = wheelBg:FindFirstChild("RemainingTime")
	remainingTimeLabel = remainingTime and remainingTime:FindFirstChild("Time")

	local freeCountDown = wheelBg:FindFirstChild("FreeCountDownTime")
	freeCountDownLabel = freeCountDown and freeCountDown:FindFirstChild("Time")

	-- 查找Menu界面中的转盘按钮
	menuGui = playerGui:WaitForChild("Menu", 10)
	if menuGui then
		imageButtonWheel = menuGui:FindFirstChild("ImageButtonWheel")
		if imageButtonWheel then
			wheelNumLabel = imageButtonWheel:FindFirstChild("Num")
			wheelAddLabel = imageButtonWheel:FindFirstChild("Add")
		end
	end

	return true
end

-- ============================================
-- 转盘动画系统
-- ============================================

-- 播放转盘旋转动画 (修正版本 - 基于角度触发音效)
local function playSpinAnimation(finalAngle, duration)
	if not wheelColorBg then
		return
	end

	-- 重置旋转
	wheelColorBg.Rotation = 0

	-- 创建旋转动画
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out,
		0,
		false,
		0
	)

	local tween = TweenService:Create(wheelColorBg, tweenInfo, {
		Rotation = finalAngle
	})

	-- 🔧 修复：基于实际旋转角度播放音效，而不是固定时间间隔
	-- 每转过60度播放一次音效，随着转盘速度变慢，音效间隔也会变长
	if tickSound then
		task.spawn(function()
			local lastSoundAngle = 0  -- 上次播放音效时的角度
			local soundAngleInterval = 60  -- 每60度播放一次音效
			local checkInterval = 0.01  -- 检查间隔（秒），更频繁的检查确保精确度

			-- 持续监控旋转角度直到动画结束
			local startTime = tick()
			while tick() - startTime < duration do
				if not wheelColorBg or not wheelColorBg.Parent then
					break  -- 如果转盘对象被销毁，停止监控
				end

				-- 获取当前旋转角度
				local currentAngle = wheelColorBg.Rotation

				-- 检查是否跨越了下一个音效触发点
				local nextSoundAngle = lastSoundAngle + soundAngleInterval
				if currentAngle >= nextSoundAngle then
					-- 播放音效
					if tickSound and tickSound.Parent then
						tickSound:Play()
					end
					-- 更新上次播放音效的角度
					lastSoundAngle = nextSoundAngle
				end

				task.wait(checkInterval)
			end
		end)
	end

	-- 启动动画
	tween:Play()

	return tween
end

-- 显示奖励结果动画 (使用游戏默认样式)
local function showRewardAnimation(message)
	-- 简单的聊天提示
	if game:GetService("StarterGui") then
		game:GetService("StarterGui"):SetCore("ChatMakeSystemMessage", {
			Text = "🎁 " .. message;
			Color = Color3.fromRGB(255, 215, 0);
		})
	end
end

-- 播放转盘次数增加动画
local function playSpinCountAddAnimation(addedCount)
	if not wheelAddLabel or not imageButtonWheel then
		return
	end

	-- 设置文本
	wheelAddLabel.Text = "+" .. addedCount

	-- 设置起始位置
	wheelAddLabel.Position = UDim2.new(1.338, 0, 0.2, 0)
	wheelAddLabel.Visible = true

	-- 创建向上移动动画
	local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(wheelAddLabel, tweenInfo, {
		Position = UDim2.new(1.338, 0, 0, 0)
	})

	tween:Play()

	-- 动画完成后隐藏
	tween.Completed:Connect(function()
		wheelAddLabel.Visible = false
	end)
end

-- ============================================
-- 事件处理
-- ============================================

-- 处理转盘数据同步
local function onWheelDataSync(action, data)
	if action == "dataUpdate" then
		currentSpinCount = data.spinCount or 0
		updateSpinCountDisplay()

	elseif action == "timerUpdate" then
		freeTimerRemaining = data.remainingTime or 0
		updateFreeTimerDisplay()

	elseif action == "spinCountAdded" then
		currentSpinCount = data.newSpinCount or 0
		updateSpinCountDisplay()

		-- 播放获得次数动画
		if data.addedCount and data.addedCount > 0 then
			playSpinCountAddAnimation(data.addedCount)
		end
	end
end

-- 处理转盘旋转事件
local function onWheelSpin(action, data)
	if action == "spinStart" then
		isSpinning = true
		updateSpinButton()

		-- 播放转盘动画
		if data.finalAngle and data.animationDuration then
			playSpinAnimation(data.finalAngle, data.animationDuration)
		end

	elseif action == "spinComplete" then
		isSpinning = false
		updateSpinButton()

		-- 显示奖励
		if data.success and data.message then
			showRewardAnimation(data.message)
		end

		-- 请求更新转盘次数
		if wheelInteractionEvent then
			wheelInteractionEvent:FireServer("checkSpinCount")
		end

	elseif action == "spinFailed" then
		isSpinning = false
		updateSpinButton()

		-- 显示失败消息
		local errorMessage = "转盘失败"
		if data.reason == "no_spins_available" then
			errorMessage = "转盘次数不足"
		elseif data.reason == "spin_in_progress" then
			errorMessage = "转盘进行中"
		end

		showRewardAnimation(errorMessage)
	end
end

-- 处理交互事件
local function onWheelInteraction(action, data)
	if action == "noSpinsAvailable" then
		-- 提示购买转盘次数
		showRewardAnimation("转盘次数不足，请购买")

	elseif action == "promptTriggered" then
		-- ProximityPrompt被触发，打开转盘界面
		WheelClient.showWheelUI()

	elseif action == "spinCountUpdate" then
		currentSpinCount = data.spinCount or 0
		updateSpinCountDisplay()
	end
end

-- 处理购买事件
local function onWheelPurchase(action, data)
	if action == "purchaseSuccess" then
		currentSpinCount = data.newSpinCount or 0
		updateSpinCountDisplay()
		showRewardAnimation("购买成功！获得 " .. (data.spinsAdded or 0) .. " 次转盘")

	elseif action == "purchaseFailed" then
		local errorMessage = "购买失败"
		if data.reason == "invalid_product" then
			errorMessage = "无效商品"
		elseif data.reason == "marketplace_error" then
			errorMessage = "商店错误"
		end
		showRewardAnimation(errorMessage)
	end
end

-- ============================================
-- UI更新函数
-- ============================================

-- 更新转盘次数显示
function updateSpinCountDisplay()
	-- 更新转盘界面内的显示
	if remainingTimeLabel then
		remainingTimeLabel.Text = currentSpinCount
	end

	-- 更新菜单按钮上的数字显示
	if wheelNumLabel then
		wheelNumLabel.Text = currentSpinCount
		-- 如果次数为0，隐藏数字标签
		wheelNumLabel.Visible = currentSpinCount > 0
	end
end

-- 更新免费倒计时显示
function updateFreeTimerDisplay()
	if freeCountDownLabel then
		if freeTimerRemaining <= 0 then
			freeCountDownLabel.Text = "00:00"
		else
			local minutes = math.floor(freeTimerRemaining / 60)
			local seconds = freeTimerRemaining % 60
			freeCountDownLabel.Text = string.format("%02d:%02d", minutes, seconds)
		end
	end
end

-- 更新旋转按钮状态
function updateSpinButton()
	if spinButton then
		-- 🔧 修复：只有在转盘进行中时才禁用按钮，次数为0时仍可点击
		spinButton.Active = not isSpinning
	end
end

-- ============================================
-- UI控制函数
-- ============================================

-- 显示转盘UI
function WheelClient.showWheelUI()
	if wheelGui then
		wheelGui.Enabled = true
		isWheelUIVisible = true

		-- 请求最新数据
		if wheelDataSyncEvent then
			wheelDataSyncEvent:FireServer("requestData")
		end
		if wheelInteractionEvent then
			wheelInteractionEvent:FireServer("checkSpinCount")
		end
	end
end

-- 隐藏转盘UI
function WheelClient.hideWheelUI()
	if wheelGui then
		-- 🔧 需求修复：如果正在转盘中，通知服务端立即结算奖励
		if isSpinning and wheelSpinEvent then
			wheelSpinEvent:FireServer("forceComplete")
			-- 🔧 修复：立即更新本地状态，确保状态同步
			isSpinning = false
			updateSpinButton()
		end

		wheelGui.Enabled = false
		isWheelUIVisible = false
	end
end

-- 切换转盘UI显示状态
function WheelClient.toggleWheelUI()
	if isWheelUIVisible then
		WheelClient.hideWheelUI()
	else
		WheelClient.showWheelUI()
	end
end

-- ============================================
-- 事件绑定
-- ============================================

-- 绑定UI事件
local function bindUIEvents()
	-- 旋转按钮
	if spinButton then
		spinButton.MouseButton1Click:Connect(function()
			-- 🔧 修复：移除次数检查，允许次数为0时也能点击（服务端会处理）
			if not isSpinning and wheelSpinEvent then
				wheelSpinEvent:FireServer("requestSpin")
			end
		end)
	else
		warn("❌ WheelClient: SpinButton未找到，无法绑定点击事件")
	end

	-- 关闭按钮
	if closeButton then
		closeButton.MouseButton1Click:Connect(function()
			WheelClient.hideWheelUI()
		end)
	end

	-- 购买按钮
	if spin5Button then
		spin5Button.MouseButton1Click:Connect(function()
			if wheelPurchaseEvent then
				wheelPurchaseEvent:FireServer("requestPurchase", {productName = "SPIN_5"})
			end
		end)
	end

	if spin20Button then
		spin20Button.MouseButton1Click:Connect(function()
			if wheelPurchaseEvent then
				wheelPurchaseEvent:FireServer("requestPurchase", {productName = "SPIN_20"})
			end
		end)
	end

	if spin50Button then
		spin50Button.MouseButton1Click:Connect(function()
			if wheelPurchaseEvent then
				wheelPurchaseEvent:FireServer("requestPurchase", {productName = "SPIN_50"})
			end
		end)
	end
end

-- ============================================
-- 初始化和启动
-- ============================================

-- 初始化客户端
function WheelClient.initialize()
	-- 加载依赖
	task.spawn(function()
		task.wait(2) -- 等待ReplicatedStorage加载
		loadWheelConfig()
	end)

	-- 初始化RemoteEvents
	task.spawn(function()
		task.wait(3) -- 等待RemoteEvents创建
		if initializeRemoteEvents() then
			-- 绑定RemoteEvent监听
			wheelDataSyncEvent.OnClientEvent:Connect(onWheelDataSync)
			wheelSpinEvent.OnClientEvent:Connect(onWheelSpin)
			wheelInteractionEvent.OnClientEvent:Connect(onWheelInteraction)
			wheelPurchaseEvent.OnClientEvent:Connect(onWheelPurchase)
		end
	end)

	-- 初始化UI
	task.spawn(function()
		task.wait(1) -- 等待PlayerGui加载
		if initializeUIElements() then
			bindUIEvents()
		end
	end)

	-- 加载音效
	task.spawn(function()
		if loadWheelConfig() and WheelConfig.SETTINGS.TICK_SOUND_ID then
			tickSound = Instance.new("Sound")
			tickSound.SoundId = "rbxassetid://" .. WheelConfig.SETTINGS.TICK_SOUND_ID
			tickSound.Volume = 0.5
			tickSound.Parent = SoundService
		end
	end)
end

-- 启动客户端
WheelClient.initialize()

-- 导出到全局供其他脚本调用
_G.WheelClient = WheelClient

return WheelClient