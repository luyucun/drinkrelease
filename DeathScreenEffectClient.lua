-- 脚本名称: DeathScreenEffectClient
-- 脚本作用: 客户端死亡黑屏效果控制，处理屏幕淡入淡出动画
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts
-- 重构说明: 现在是纯视觉增强脚本，不影响服务端游戏逻辑

local DeathScreenEffectClient = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local deathEffectEvent = remoteEventsFolder:FindFirstChild("DeathEffect")

-- 如果RemoteEvent不存在，等待它被创建
if not deathEffectEvent then
	deathEffectEvent = remoteEventsFolder:WaitForChild("DeathEffect")
end

-- 黑屏效果状态
local effectState = {
	isActive = false,
	screenGui = nil,
	blackFrame = nil,
	currentTween = nil
}

-- 动画配置（重构：优化为更快的节奏配合服务端3秒流程）
local ANIMATION_CONFIG = {
	FADE_TO_GRAY_TIME = 0.3,      -- 变灰时间（加快节奏）
	FADE_TO_BLACK_TIME = 0.7,     -- 变黑时间（加快节奏）
	BLACK_HOLD_TIME = 1.5,        -- 保持黑屏时间（配合服务端3秒总流程）
	FADE_OUT_TIME = 0.5,          -- 淡出时间（加快节奏）
	GRAY_COLOR = Color3.new(0.3, 0.3, 0.3),  -- 灰色
	BLACK_COLOR = Color3.new(0, 0, 0),        -- 黑色
	EASING_STYLE = Enum.EasingStyle.Quad,
	EASING_DIRECTION = Enum.EasingDirection.InOut
}

-- 创建黑屏UI
function DeathScreenEffectClient.createDeathScreenUI()
	if effectState.screenGui then
		effectState.screenGui:Destroy()
	end

	-- 创建ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DeathScreenEffect"
	screenGui.DisplayOrder = 1000  -- 确保在最顶层
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false  -- 防止重生时被删除
	screenGui.Parent = player:WaitForChild("PlayerGui")

	-- 创建黑色Frame
	local blackFrame = Instance.new("Frame")
	blackFrame.Name = "BlackScreen"
	blackFrame.Size = UDim2.new(1, 0, 1, 0)
	blackFrame.Position = UDim2.new(0, 0, 0, 0)
	blackFrame.BackgroundColor3 = ANIMATION_CONFIG.BLACK_COLOR
	blackFrame.BackgroundTransparency = 1  -- 初始完全透明
	blackFrame.BorderSizePixel = 0
	blackFrame.ZIndex = 1000
	blackFrame.Parent = screenGui

	effectState.screenGui = screenGui
	effectState.blackFrame = blackFrame

	return screenGui, blackFrame
end

-- 停止当前动画
function DeathScreenEffectClient.stopCurrentTween()
	if effectState.currentTween then
		effectState.currentTween:Cancel()
		effectState.currentTween = nil
	end
end

-- 开始死亡黑屏效果
function DeathScreenEffectClient.startDeathEffect()
	if effectState.isActive then
		return
	end

	effectState.isActive = true

	-- 创建或获取UI元素
	if not effectState.screenGui or not effectState.blackFrame then
		DeathScreenEffectClient.createDeathScreenUI()
	end

	local blackFrame = effectState.blackFrame

	-- 停止之前的动画
	blackFrame.BackgroundColor3 = ANIMATION_CONFIG.GRAY_COLOR
	blackFrame.BackgroundTransparency = 1

	local fadeToGrayTween = TweenService:Create(
		blackFrame,
		TweenInfo.new(
			ANIMATION_CONFIG.FADE_TO_GRAY_TIME,
			ANIMATION_CONFIG.EASING_STYLE,
			ANIMATION_CONFIG.EASING_DIRECTION
		),
		{BackgroundTransparency = 0.3}  -- 半透明灰色
	)

	effectState.currentTween = fadeToGrayTween
	fadeToGrayTween:Play()

	fadeToGrayTween.Completed:Connect(function()
		if not effectState.isActive then return end

		-- 阶段2: 从灰色变为黑色
		blackFrame.BackgroundColor3 = ANIMATION_CONFIG.BLACK_COLOR

		local fadeToBlackTween = TweenService:Create(
			blackFrame,
			TweenInfo.new(
				ANIMATION_CONFIG.FADE_TO_BLACK_TIME,
				ANIMATION_CONFIG.EASING_STYLE,
				ANIMATION_CONFIG.EASING_DIRECTION
			),
			{BackgroundTransparency = 0}  -- 完全不透明黑色
		)

		effectState.currentTween = fadeToBlackTween
		fadeToBlackTween:Play()

		fadeToBlackTween.Completed:Connect(function()
			if not effectState.isActive then return end

			-- 阶段3: 保持黑屏一段时间，然后发送可选的完成通知
			spawn(function()
				wait(ANIMATION_CONFIG.BLACK_HOLD_TIME)

				if not effectState.isActive then
					return
				end

				-- 重构：发送readyForRespawn现在是完全可选的增强功能
				-- 即使发送失败也不影响游戏，因为服务端会在3秒后自动处理
				local success, errorMsg = pcall(function()
					deathEffectEvent:FireServer("readyForRespawn")
				end)

				-- 通知成功或失败都不影响游戏，服务端会自动处理

				-- 移除重试逻辑，因为现在这个通知是完全可选的
				-- 服务端会在固定时间后自动完成复活流程
			end)
		end)
	end)
end

-- 结束死亡黑屏效果（重构：现在由服务端主动调用，客户端配合）
function DeathScreenEffectClient.endDeathEffect()
	if not effectState.isActive then
		-- 效果已经结束，这是正常的
		return
	end

	if not effectState.blackFrame then
		effectState.isActive = false
		return
	end

	-- 停止当前动画
	DeathScreenEffectClient.stopCurrentTween()

	-- 阶段4: 快速淡出黑屏
	local fadeOutTween = TweenService:Create(
		effectState.blackFrame,
		TweenInfo.new(
			ANIMATION_CONFIG.FADE_OUT_TIME,
			ANIMATION_CONFIG.EASING_STYLE,
			ANIMATION_CONFIG.EASING_DIRECTION
		),
		{BackgroundTransparency = 1}  -- 完全透明
	)

	effectState.currentTween = fadeOutTween
	fadeOutTween:Play()

	fadeOutTween.Completed:Connect(function()
		effectState.isActive = false

		-- 清理UI
		if effectState.screenGui then
			effectState.screenGui:Destroy()
			effectState.screenGui = nil
			effectState.blackFrame = nil
		end
	end)
end

-- 强制重置效果（用于异常情况）
function DeathScreenEffectClient.resetEffect()

	DeathScreenEffectClient.stopCurrentTween()
	effectState.isActive = false

	if effectState.screenGui then
		effectState.screenGui:Destroy()
		effectState.screenGui = nil
		effectState.blackFrame = nil
	end
end

-- 处理玩家重生
function DeathScreenEffectClient.onPlayerRespawned()
	-- 延迟一点确保角色完全加载
	wait(0.1)
	DeathScreenEffectClient.endDeathEffect()
end

-- 设置RemoteEvent处理
function DeathScreenEffectClient.setupRemoteEvents()
	deathEffectEvent.OnClientEvent:Connect(function(action, data)
		if action == "startDeathEffect" then
			DeathScreenEffectClient.startDeathEffect()
		elseif action == "endDeathEffect" then
			DeathScreenEffectClient.endDeathEffect()
		elseif action == "resetEffect" then
			DeathScreenEffectClient.resetEffect()
		end
	end)

end

-- 监听玩家角色重生
function DeathScreenEffectClient.setupCharacterSpawnedListener()
	-- 监听当前角色
	if player.Character then
		local humanoid = player.Character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			-- 这里可以作为备用触发方式，主要还是通过RemoteEvent
		end)
	end

	-- 监听角色重生
	player.CharacterAdded:Connect(function(character)

		-- 监听新角色的死亡
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
		end)

		-- 如果死亡效果正在进行中，等待一小段时间后结束效果
		if effectState.isActive then
			spawn(function()
				wait(0.5)  -- 等待角色完全加载
				DeathScreenEffectClient.onPlayerRespawned()
			end)
		end
	end)
end

-- 初始化
function DeathScreenEffectClient.initialize()
	DeathScreenEffectClient.setupRemoteEvents()
	DeathScreenEffectClient.setupCharacterSpawnedListener()

end

-- 启动客户端控制器
DeathScreenEffectClient.initialize()

return DeathScreenEffectClient