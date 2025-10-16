-- 脚本名称: FreeGiftClient
-- 脚本作用: V2.1 免费在线奖励 - 客户端UI控制
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer/StarterPlayerScripts
-- 功能：
--   1. 监听服务端事件，控制UI显示/隐藏
--   2. 实时更新进度条和时间显示
--   3. 处理Claim按钮点击
--   4. 显示成功/失败提示

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 等待UI加载（添加30秒超时，防止infinite yield）
local freeGiftGui = playerGui:WaitForChild("FreeGift", 30)

-- 如果UI不存在，提前退出脚本
if not freeGiftGui then
	warn("⚠️ FreeGiftClient: FreeGift UI not found in PlayerGui. This feature requires the FreeGift ScreenGui to be present in StarterGui.")
	warn("   Please ensure the FreeGift ScreenGui is properly set up in StarterGui before using this feature.")
	return
end

local bgFrame = freeGiftGui:WaitForChild("Bg", 10)
if not bgFrame then
	warn("⚠️ FreeGiftClient: Bg Frame not found in FreeGift UI")
	return
end

local progressBar = bgFrame:WaitForChild("ProgressBar", 10)
local progressImage = progressBar and progressBar:WaitForChild("Progress", 10)
local timeLabel = progressBar and progressBar:WaitForChild("Time", 10)
local claimBtn = bgFrame:WaitForChild("Claim", 10)
local claimBtnLabel = claimBtn and claimBtn:WaitForChild("Name", 10)  -- Claim按钮下的TextLabel
local closeBtn = bgFrame:WaitForChild("CloseBtn", 10)

-- 验证所有必需的UI元素都存在
if not progressBar or not progressImage or not timeLabel or not claimBtn or not claimBtnLabel or not closeBtn then
	warn("⚠️ FreeGiftClient: One or more required UI elements not found. Feature disabled.")
	warn("   Missing elements detected. Please verify the FreeGift UI hierarchy.")
	return
end

-- RemoteEvent
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local freeGiftEvent = remoteEventsFolder:WaitForChild("FreeGift")

-- 本地状态
local currentSeconds = 0
local isClaimed = false
local isUIOpen = false
local localTimer = nil
local canClaim = false

-- 配置
local REQUIRED_SECONDS = 10 * 60  -- 10分钟 = 600秒
local SYNC_INTERVAL = 30          -- 每30秒同步一次

-- ========== 时间格式化 ==========

-- 格式化时间：MM:SS（支持1000+分钟）
local function formatTime(seconds)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", minutes, secs)
end

-- ========== UI更新 ==========

-- 更新进度条和时间显示
local function updateProgress(seconds, claimed, eligible)
	currentSeconds = seconds
	isClaimed = claimed
	canClaim = eligible or false

	-- 更新时间文本
	timeLabel.Text = formatTime(seconds)

	-- 更新进度条（最大1.0）
	local percent = math.min(seconds / REQUIRED_SECONDS, 1)
	progressImage.Size = UDim2.new(percent, 0, 1, 0)

	-- 更新Claim按钮状态
	if claimed then
		claimBtnLabel.Text = "Claimed"
		claimBtn.Active = false
		claimBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)  -- 灰色
	elseif canClaim then
		claimBtnLabel.Text = "Claim Reward"
		claimBtn.Active = true
		claimBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)  -- 绿色
	else
		claimBtnLabel.Text = "Not Ready"
		claimBtn.Active = false
		claimBtn.BackgroundColor3 = Color3.fromRGB(150, 150, 150)  -- 浅灰色
	end
end

-- ========== 本地计时器 ==========

-- 启动本地计时器（客户端模拟，每30秒同步）
local function startLocalTimer()
	if localTimer then
		task.cancel(localTimer)
	end

	local syncCounter = 0

	localTimer = task.spawn(function()
		while isUIOpen and not isClaimed do
			task.wait(1)

			-- 检查UI是否还打开
			if not isUIOpen then
				break
			end

			-- 本地增加1秒（仅UI显示用）
			currentSeconds = currentSeconds + 1
			updateProgress(currentSeconds, isClaimed, canClaim)

			-- 每30秒向服务端同步校正
			syncCounter = syncCounter + 1
			if syncCounter >= SYNC_INTERVAL then
				syncCounter = 0
				freeGiftEvent:FireServer("requestProgress")
			end
		end
	end)
end

-- 停止本地计时器
local function stopLocalTimer()
	if localTimer then
		task.cancel(localTimer)
		localTimer = nil
	end
end

-- ========== UI控制 ==========

-- 打开UI
local function openUI()
	isUIOpen = true
	bgFrame.Visible = true

	-- 请求当前进度
	freeGiftEvent:FireServer("requestProgress")

	-- 启动本地计时器（等待服务端返回后再启动）
	task.wait(0.1)  -- 短暂延迟等待进度返回
	startLocalTimer()
end

-- 关闭UI
local function closeUI()
	isUIOpen = false
	bgFrame.Visible = false

	-- 停止本地计时器
	stopLocalTimer()
end

-- ========== 提示消息 ==========

-- 显示系统消息
local function showMessage(text, color)
	local success, error = pcall(function()
		game.StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = text,
			Color = color,
			Font = Enum.Font.SourceSansBold,
			FontSize = Enum.FontSize.Size18
		})
	end)

	if not success then
		warn("FreeGiftClient: 显示消息失败 - " .. tostring(error))
	end
end

-- ========== 事件监听 ==========

-- 监听服务端事件
freeGiftEvent.OnClientEvent:Connect(function(action, data)
	if action == "openUI" then
		openUI()

	elseif action == "progressUpdate" then
		if data then
			updateProgress(data.seconds or 0, data.claimed or false, data.canClaim or false)
		end

	elseif action == "claimResult" then
		if data and data.success then
			-- 成功提示
			showMessage("✅ Claim successful!", Color3.new(0, 1, 0))

			-- 更新状态
			isClaimed = true
			updateProgress(currentSeconds, true, false)

			-- 停止计时器
			stopLocalTimer()

		else
			-- 失败提示
			local message = (data and data.message) or "Condition not met"
			showMessage("❌ " .. message, Color3.new(1, 0, 0))
		end

	elseif action == "claimed" then
		-- 玩家已领取（来自其他源，例如Chest检查）
		isClaimed = true
		updateProgress(currentSeconds, true, false)
		stopLocalTimer()
	end
end)

-- 按钮事件
claimBtn.MouseButton1Click:Connect(function()
	if not claimBtn.Active then
		return
	end

	-- 防抖：禁用按钮1秒
	claimBtn.Active = false
	claimBtnLabel.Text = "Claiming..."

	task.delay(1, function()
		if not isClaimed then
			claimBtn.Active = canClaim
			if canClaim then
				claimBtnLabel.Text = "Claim Reward"
			else
				claimBtnLabel.Text = "Not Ready"
			end
		end
	end)

	-- 发送领取请求
	freeGiftEvent:FireServer("claim")
end)

closeBtn.MouseButton1Click:Connect(function()
	closeUI()
end)

-- ========== 初始化 ==========

-- 隐藏UI
bgFrame.Visible = false

-- 初始化按钮状态
claimBtn.Active = false
claimBtnLabel.Text = "Not Ready"
