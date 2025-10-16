-- 脚本名称: MuteButtonController
-- 脚本作用: V1.2 静音按钮客户端控制器
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer.StarterPlayerScripts
-- 功能：
--   1. 监听静音按钮点击事件
--   2. 管理按钮UI状态切换
--   3. 与服务端BGM管理器通信

local MuteButtonController = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- UI引用
local muteGui = nil
local muteButton = nil
local muteIcon = nil
local unmuteIcon = nil

-- 状态管理
local isMuted = false  -- 当前静音状态

-- RemoteEvent引用
local bgmControlEvent = nil

-- ============================================
-- UI初始化
-- ============================================

-- 查找UI组件
local function findUIComponents()
	-- 等待Mute ScreenGui
	muteGui = playerGui:WaitForChild("Mute", 10)
	if not muteGui then
		warn("❌ MuteButtonController: 未找到StarterGui/Mute")
		return false
	end

	-- 查找静音按钮
	muteButton = muteGui:FindFirstChild("ImageButtonEmote")
	if not muteButton then
		warn("❌ MuteButtonController: 未找到Mute/ImageButtonEmote按钮")
		return false
	end

	-- 查找静音状态图标
	muteIcon = muteButton:FindFirstChild("Mute")
	unmuteIcon = muteButton:FindFirstChild("Unmute")

	if not muteIcon then
		warn("⚠️ MuteButtonController: 未找到Mute图标，将创建默认图标")
		-- 创建默认Mute图标
		muteIcon = Instance.new("ImageLabel")
		muteIcon.Name = "Mute"
		muteIcon.Size = UDim2.new(1, 0, 1, 0)
		muteIcon.Position = UDim2.new(0, 0, 0, 0)
		muteIcon.BackgroundTransparency = 1
		muteIcon.Image = "rbxasset://textures/ui/VoiceChat/SpeakerLight.png"  -- 默认音频图标
		muteIcon.Parent = muteButton
	end

	if not unmuteIcon then
		warn("⚠️ MuteButtonController: 未找到Unmute图标，将创建默认图标")
		-- 创建默认Unmute图标
		unmuteIcon = Instance.new("ImageLabel")
		unmuteIcon.Name = "Unmute"
		unmuteIcon.Size = UDim2.new(1, 0, 1, 0)
		unmuteIcon.Position = UDim2.new(0, 0, 0, 0)
		unmuteIcon.BackgroundTransparency = 1
		unmuteIcon.Image = "rbxasset://textures/ui/VoiceChat/MuteLight.png"  -- 默认静音图标
		unmuteIcon.Visible = false
		unmuteIcon.Parent = muteButton
	end

	return true
end

-- 初始化RemoteEvent
local function initializeRemoteEvent()
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEventsFolder then
		warn("❌ MuteButtonController: RemoteEvents文件夹不存在")
		return false
	end

	bgmControlEvent = remoteEventsFolder:WaitForChild("BgmControl", 5)
	if not bgmControlEvent then
		warn("❌ MuteButtonController: BgmControl RemoteEvent不存在")
		return false
	end

	return true
end

-- ============================================
-- UI状态管理
-- ============================================

-- 更新按钮UI状态
local function updateButtonState()
	if muteIcon then
		muteIcon.Visible = not isMuted
	end

	if unmuteIcon then
		unmuteIcon.Visible = isMuted
	end
end

-- 设置静音状态
local function setMuteState(newMuteState)
	if type(newMuteState) ~= "boolean" then
		warn("MuteButtonController: 无效的静音状态")
		return
	end

	local oldState = isMuted
	isMuted = newMuteState

	-- 更新UI（如果状态改变）
	if oldState ~= isMuted then
		updateButtonState()

		-- 发送状态到服务端
		if bgmControlEvent then
			bgmControlEvent:FireServer("setMuted", isMuted)
		end
	end
end

-- ============================================
-- 事件处理
-- ============================================

-- 处理静音按钮点击
local function onMuteButtonClicked()
	-- 切换静音状态
	setMuteState(not isMuted)
end

-- 处理服务端响应
local function onServerResponse(action, ...)
	if action == "muteStateResponse" then
		local serverMuteState = ...
		if type(serverMuteState) == "boolean" then
			-- 同步服务端状态（但不发送回服务端）
			local oldState = isMuted
			isMuted = serverMuteState
			if oldState ~= isMuted then
				updateButtonState()
			end
		end

	elseif action == "setLocalVolume" then
		-- 设置本地BGM音量
		local targetVolume = ...
		if type(targetVolume) == "number" then
			local SoundService = game:GetService("SoundService")
			local bgmSound = SoundService:FindFirstChild("bgm")
			if bgmSound and bgmSound:IsA("Sound") then
				bgmSound.Volume = targetVolume
			end
		end

	elseif action == "bgmStatusResponse" then
		-- 调试信息（可选）
		local status = ...
		if status then
			print("🎵 BGM状态:", status)
		end

	else
		warn("MuteButtonController: 未知的服务端响应 - " .. tostring(action))
	end
end

-- ============================================
-- 初始化
-- ============================================

-- 初始化控制器
function MuteButtonController.initialize()
	-- 查找UI组件
	local uiFound = findUIComponents()
	if not uiFound then
		warn("❌ MuteButtonController: UI初始化失败")
		return false
	end

	-- 初始化RemoteEvent
	local eventInitialized = initializeRemoteEvent()
	if not eventInitialized then
		warn("❌ MuteButtonController: RemoteEvent初始化失败")
		return false
	end

	-- 设置初始状态（默认未静音）
	isMuted = false
	updateButtonState()

	-- 绑定按钮点击事件
	if muteButton then
		muteButton.Activated:Connect(onMuteButtonClicked)
	end

	-- 监听服务端响应
	if bgmControlEvent then
		bgmControlEvent.OnClientEvent:Connect(onServerResponse)
	end

	-- 从服务端获取初始静音状态（可选）
	task.spawn(function()
		task.wait(1)  -- 等待服务端完全初始化
		if bgmControlEvent then
			bgmControlEvent:FireServer("getMuted")
		end
	end)

	return true
end

-- 获取当前静音状态（调试用）
function MuteButtonController.isMuted()
	return isMuted
end

-- 手动设置静音状态（调试用）
function MuteButtonController.setMuted(newState)
	setMuteState(newState)
end

-- ============================================
-- 启动
-- ============================================

-- 等待PlayerGui加载完成后初始化
task.spawn(function()
	-- 等待足够时间让UI加载
	task.wait(3)

	local success = MuteButtonController.initialize()
	if success then
		-- 导出到全局（调试用）
		_G.MuteButtonController = MuteButtonController
	else
		warn("❌ MuteButtonController: 初始化失败，静音功能不可用")
	end
end)

return MuteButtonController