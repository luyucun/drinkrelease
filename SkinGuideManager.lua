-- 脚本名称: SkinGuideManager
-- 脚本作用: V1.9新手皮肤引导系统，引导新玩家前往皮肤购买区域
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local SkinGuideManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- 引导状态跟踪
local playerGuideStates = {} -- {[userId] = {arrowActive, distanceConnection, hasShownDaily}}

-- 配置
local CONFIG = {
	REQUIRED_COINS = 200,  -- 触发引导所需金币数
	DETECTION_DISTANCE = 10,  -- 到达目标的检测距离（与ProximityPrompt一致）
	GUIDE_ATTACHMENT_NAME = "GuideAttachment",  -- 目标位置Part名称
}

-- ============================================
-- 辅助函数：检查玩家是否为真实玩家
-- ============================================

local function isRealPlayer(player)
	if not player then return false end
	if typeof(player) ~= "Instance" then return false end
	if not player:IsA("Player") then return false end
	if not player.Parent then return false end
	return true
end

-- ============================================
-- 初始化玩家引导
-- ============================================

function SkinGuideManager:initializePlayerGuide(player)
	if not isRealPlayer(player) then
		return
	end

	local userId = player.UserId

	-- 检查是否已触发过引导（延迟等待PlayerDataService加载）
	local PlayerDataService = _G.PlayerDataService
	if not PlayerDataService then
		warn("[SkinGuideManager] PlayerDataService未加载，延迟3秒后重试")
		task.delay(3, function()
			if player and player.Parent then
				self:initializePlayerGuide(player)
			end
		end)
		return
	end

	local hasSkinGuideShown = PlayerDataService:hasSkinGuideShown(player)
	if hasSkinGuideShown then
		return
	end

	-- 初始化引导状态
	if not playerGuideStates[userId] then
		playerGuideStates[userId] = {
			arrowActive = false,
			distanceConnection = nil,
			hasShownDaily = false
		}
	end

	-- 延迟1秒后显示Daily界面（确保玩家完全加载）
	task.delay(1, function()
		if player and player.Parent then
			self:showDailyUI(player)
		end
	end)

	-- 开始监听金币变化
	self:listenToCoinChanges(player)
end

-- ============================================
-- 显示Daily界面
-- ============================================

function SkinGuideManager:showDailyUI(player)
	if not isRealPlayer(player) then return end

	local userId = player.UserId
	local state = playerGuideStates[userId]
	if not state then return end

	-- 防止重复显示
	if state.hasShownDaily then return end

	-- 通过RemoteEvent通知客户端显示Daily界面
	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEventsFolder then
		remoteEventsFolder = Instance.new("Folder")
		remoteEventsFolder.Name = "RemoteEvents"
		remoteEventsFolder.Parent = ReplicatedStorage
	end

	local skinGuideEvent = remoteEventsFolder:FindFirstChild("SkinGuideEvent")
	if not skinGuideEvent then
		skinGuideEvent = Instance.new("RemoteEvent")
		skinGuideEvent.Name = "SkinGuideEvent"
		skinGuideEvent.Parent = remoteEventsFolder
	end

	skinGuideEvent:FireClient(player, "showDailyUI")

	-- 标记已显示
	state.hasShownDaily = true
end

-- ============================================
-- 监听金币变化
-- ============================================

function SkinGuideManager:listenToCoinChanges(player)
	if not isRealPlayer(player) then return end

	local userId = player.UserId

	-- 立即检查一次当前金币数
	self:checkCoinsAndShowArrow(player)

	-- 注意：金币变化监听由CoinManager主动调用onCoinChanged
end

-- ============================================
-- 金币变化回调（由CoinManager调用）
-- ============================================

function SkinGuideManager:onCoinChanged(player, newCoinAmount)
	if not isRealPlayer(player) then return end

	local userId = player.UserId
	local state = playerGuideStates[userId]
	if not state then return end

	-- 如果箭头已经激活，跳过
	if state.arrowActive then return end

	-- 检查是否满足金币要求
	if newCoinAmount >= CONFIG.REQUIRED_COINS then
		self:showGuideArrow(player)
	end
end

-- ============================================
-- 手动检查金币并显示箭头（用于初始化时）
-- ============================================

function SkinGuideManager:checkCoinsAndShowArrow(player)
	if not isRealPlayer(player) then return end

	-- 获取玩家当前金币数
	local CoinManager = _G.CoinManager
	if not CoinManager or not CoinManager.getPlayerCoins then
		warn("[SkinGuideManager] CoinManager未加载或缺少getPlayerCoins方法")
		return
	end

	local currentCoins = CoinManager.getPlayerCoins(player)
	if not currentCoins then return end

	-- 检查是否满足条件
	if currentCoins >= CONFIG.REQUIRED_COINS then
		self:showGuideArrow(player)
	end
end

-- ============================================
-- 显示引导箭头
-- ============================================

function SkinGuideManager:showGuideArrow(player)
	if not isRealPlayer(player) then return end

	local userId = player.UserId
	local state = playerGuideStates[userId]
	if not state then return end

	-- 防止重复创建
	if state.arrowActive then return end

	-- 查找GuideAttachment
	local guideAttachment = Workspace:FindFirstChild(CONFIG.GUIDE_ATTACHMENT_NAME)
	if not guideAttachment then
		warn("[SkinGuideManager] 场景中找不到GuideAttachment，无法创建引导箭头")
		return
	end

	-- 检查玩家角色
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		warn("[SkinGuideManager] 玩家角色未加载，延迟创建箭头")
		-- 延迟重试
		task.delay(1, function()
			if player and player.Parent then
				self:showGuideArrow(player)
			end
		end)
		return
	end

	-- 复用TutorialGuideManager的箭头逻辑
	local success = self:createGuideBeam(player, guideAttachment)
	if success then
		state.arrowActive = true

		-- 开始距离检测
		self:startDistanceMonitoring(player, guideAttachment)
	end
end

-- ============================================
-- 创建引导Beam（复用TutorialGuideManager逻辑）
-- ============================================

function SkinGuideManager:createGuideBeam(player, targetPart)
	if not isRealPlayer(player) then return false end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	local humanoidRootPart = character.HumanoidRootPart

	-- 获取Arrow模板
	local arrowFolder = ReplicatedStorage:FindFirstChild("Arrow")
	if not arrowFolder then
		warn("[SkinGuideManager] ReplicatedStorage中找不到Arrow文件夹")
		return false
	end

	local arrowABeam = arrowFolder:FindFirstChild("Arrow_A")
	if not arrowABeam or not arrowABeam:FindFirstChild("Beam") then
		warn("[SkinGuideManager] Arrow_A中找不到Beam")
		return false
	end

	-- 克隆Beam
	local beamTemplate = arrowABeam:FindFirstChild("Beam")
	local beam = beamTemplate:Clone()

	-- V1.9: 在GuideAttachment下创建Attachment01
	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "SkinGuideAttachment01"
	targetAttachment.Parent = targetPart

	-- V1.9: 在玩家身上创建Attachment02
	local playerAttachment = Instance.new("Attachment")
	playerAttachment.Name = "SkinGuideAttachment02"
	playerAttachment.Parent = humanoidRootPart

	-- 配置Beam的连接点 (Attachment0连接目标，Attachment1连接玩家)
	beam.Attachment0 = targetAttachment
	beam.Attachment1 = playerAttachment

	-- 将Beam放到GuideAttachment上
	beam.Parent = targetPart

	-- 保存引导箭头数据到玩家状态
	local userId = player.UserId
	local state = playerGuideStates[userId]
	if state then
		state.beam = beam
		state.targetAttachment = targetAttachment
		state.playerAttachment = playerAttachment
	end

	return true
end

-- ============================================
-- 开始距离监测
-- ============================================

function SkinGuideManager:startDistanceMonitoring(player, targetPart)
	if not isRealPlayer(player) then return end

	local userId = player.UserId
	local state = playerGuideStates[userId]
	if not state then return end

	-- 清理旧的连接
	if state.distanceConnection then
		state.distanceConnection:Disconnect()
		state.distanceConnection = nil
	end

	-- 使用Heartbeat监听距离
	state.distanceConnection = RunService.Heartbeat:Connect(function()
		-- 验证玩家和角色仍然有效
		if not player or not player.Parent then
			self:stopDistanceMonitoring(player)
			return
		end

		local character = player.Character
		if not character or not character:FindFirstChild("HumanoidRootPart") then
			return
		end

		-- 计算距离
		local playerPos = character.HumanoidRootPart.Position
		local targetPos = targetPart.Position
		local distance = (playerPos - targetPos).Magnitude

		-- 检查是否到达目标
		if distance <= CONFIG.DETECTION_DISTANCE then
			self:hideGuideArrow(player)
			self:markGuideCompleted(player)
		end
	end)
end

-- ============================================
-- 停止距离监测
-- ============================================

function SkinGuideManager:stopDistanceMonitoring(player)
	if not player then return end

	local userId = player.UserId
	local state = playerGuideStates[userId]
	if not state then return end

	if state.distanceConnection then
		state.distanceConnection:Disconnect()
		state.distanceConnection = nil
	end
end

-- ============================================
-- 隐藏引导箭头
-- ============================================

function SkinGuideManager:hideGuideArrow(player)
	if not player then return end

	local userId = player.UserId
	local state = playerGuideStates[userId]
	if not state then return end

	-- 停止距离监测
	self:stopDistanceMonitoring(player)

	-- 销毁Beam
	if state.beam and state.beam.Parent then
		pcall(function()
			state.beam:Destroy()
		end)
		state.beam = nil
	end

	-- 销毁目标Attachment
	if state.targetAttachment and state.targetAttachment.Parent then
		pcall(function()
			state.targetAttachment:Destroy()
		end)
		state.targetAttachment = nil
	end

	-- 销毁玩家Attachment
	if state.playerAttachment and state.playerAttachment.Parent then
		pcall(function()
			state.playerAttachment:Destroy()
		end)
		state.playerAttachment = nil
	end

	-- 标记箭头未激活
	state.arrowActive = false
end

-- ============================================
-- 标记引导完成
-- ============================================

function SkinGuideManager:markGuideCompleted(player)
	if not isRealPlayer(player) then return end

	local PlayerDataService = _G.PlayerDataService
	if not PlayerDataService then
		warn("[SkinGuideManager] PlayerDataService未加载，无法保存引导状态")
		return
	end

	-- 保存到DataStore
	local success = PlayerDataService:setSkinGuideShown(player, true)
	if success then
	else
		warn("[SkinGuideManager] 引导完成状态保存失败: " .. player.Name)
	end
end

-- ============================================
-- 玩家离开清理
-- ============================================

function SkinGuideManager:onPlayerRemoving(player)
	if not player then return end

	local userId = player.UserId

	-- 清理箭头
	self:hideGuideArrow(player)

	-- 清理状态
	if playerGuideStates[userId] then
		playerGuideStates[userId] = nil
	end
end

-- ============================================
-- 初始化系统
-- ============================================

function SkinGuideManager:initialize()
	-- 提前创建RemoteEvent，确保客户端能正常连接
	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEventsFolder then
		remoteEventsFolder = Instance.new("Folder")
		remoteEventsFolder.Name = "RemoteEvents"
		remoteEventsFolder.Parent = ReplicatedStorage
	end

	local skinGuideEvent = remoteEventsFolder:FindFirstChild("SkinGuideEvent")
	if not skinGuideEvent then
		skinGuideEvent = Instance.new("RemoteEvent")
		skinGuideEvent.Name = "SkinGuideEvent"
		skinGuideEvent.Parent = remoteEventsFolder
	end

	-- 检查必需组件
	local guideAttachment = Workspace:FindFirstChild(CONFIG.GUIDE_ATTACHMENT_NAME)
	if not guideAttachment then
		warn("[SkinGuideManager] ⚠️ Workspace中未找到GuideAttachment，引导箭头将无法显示")
		warn("[SkinGuideManager] 请在Workspace中创建一个名为'GuideAttachment'的Part作为引导目标")
	end

	-- 监听玩家离开
	Players.PlayerRemoving:Connect(function(player)
		self:onPlayerRemoving(player)
	end)
end

-- 注册为全局管理器
_G.SkinGuideManager = SkinGuideManager

return SkinGuideManager
