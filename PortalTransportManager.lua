-- 脚本名称: PortalTransportManager
-- 脚本作用: 管理新手教程结束时的Portal交互和传送系统
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local PortalTransportManager = {}
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local Workspace = game.Workspace
local RunService = game:GetService("RunService")

-- Portal状态
local portalState = {
	portal = nil,
	promptPart = nil,  -- 🔧 V1.6新增：独立交互占位块
	effectPart = nil,  -- 🔧 V1.6新增：Portal.effect Part
	initialized = false,
	targetPlaceId = nil
}

-- 记录正在传送的玩家（防止重复传送）
local playerBeingTeleported = {}

-- ============================================
-- 初始化Portal
-- ============================================

function PortalTransportManager:initializePortal(targetPlaceId)
	-- 查找Portal模型
	local portal = Workspace:FindFirstChild("Portal")
	if not portal then
		warn("PortalTransportManager: Workspace中找不到Portal模型")
		return false
	end

	-- 设置Portal的PrimaryPart（如果还没有设置）
	local targetPart = nil
	if portal:IsA("Model") then
		local primaryPart = portal.PrimaryPart
		if not primaryPart then
			-- 如果没有PrimaryPart，尝试找第一个Part
			for _, child in pairs(portal:GetDescendants()) do
				if child:IsA("BasePart") then
					portal.PrimaryPart = child
					primaryPart = child
					break
				end
			end
		end
		targetPart = primaryPart
	elseif portal:IsA("BasePart") then
		targetPart = portal
	end

	-- 为Portal添加ClickDetector（如果没有的话）
	local clickDetector = nil
	for _, child in pairs(portal:GetDescendants()) do
		if child:IsA("ClickDetector") then
			clickDetector = child
			break
		end
	end

	if not clickDetector then
		-- 需要为Portal的主要Part添加ClickDetector
		if targetPart then
			clickDetector = Instance.new("ClickDetector")
			clickDetector.MaxActivationDistance = 50
			clickDetector.Parent = targetPart
		end
	end

	-- 🔧 V1.6新增：创建独立交互占位块，专门用于挂ProximityPrompt
	-- 这样即使Portal模型结构不规则，也能确保交互提示稳定显示
	local promptPart = portal:FindFirstChild("TutorialPromptPart")
	if not promptPart then
		promptPart = Instance.new("Part")
		promptPart.Name = "TutorialPromptPart"
		promptPart.Transparency = 1           -- 完全透明，不可见
		promptPart.Anchored = true
		promptPart.CanCollide = false
		promptPart.Size = Vector3.new(4, 4, 4)
		promptPart.Parent = portal
		print("[PortalTransportManager] ✓ 已创建交互占位块 TutorialPromptPart")
	end

	-- 设置占位块位置为Portal的主要位置
	if portal:IsA("Model") and portal.PrimaryPart then
		promptPart.CFrame = portal.PrimaryPart.CFrame
	elseif portal:IsA("BasePart") then
		promptPart.CFrame = portal.CFrame
	end

	-- 为交互占位块添加ProximityPrompt
	local prompt = promptPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TutorialPortalPrompt"
		prompt.ActionText = "Enter Portal"
		prompt.ObjectText = "Portal"
		prompt.HoldDuration = 1           -- 需要长按 1 秒
		prompt.MaxActivationDistance = 12 -- 可根据体验调整
		prompt.RequiresLineOfSight = false
		prompt.Parent = promptPart
		print("[PortalTransportManager] ✓ 已为交互占位块创建ProximityPrompt")
	end

	-- 保存占位块引用以便后续更新
	portalState.promptPart = promptPart

	-- 🔧 V1.6新增：准备Portal的effect Attachment，用于引导箭头
	-- Portal.Base 是指定的容器Part，我们需要在它下面找到或创建 Attachment01
	local effectPart = portal:FindFirstChild("Base")

	if not effectPart then
		-- 如果Portal下没有名叫Base的Part，创建一个
		effectPart = Instance.new("Part")
		effectPart.Name = "Base"
		effectPart.Transparency = 1  -- 完全透明
		effectPart.CanCollide = false
		effectPart.Size = Vector3.new(1, 1, 1)
		effectPart.Parent = portal
		print("[PortalTransportManager] ✓ 已创建Portal Base Part")
	else
		print("[PortalTransportManager] ✓ 找到Portal.Base Part")
	end

	-- 在 Base Part 下查找或创建 Attachment
	local effectAttachment = effectPart:FindFirstChildOfClass("Attachment")
	if not effectAttachment then
		effectAttachment = Instance.new("Attachment")
		effectAttachment.Name = "Attachment01"
		effectAttachment.Parent = effectPart
		print("[PortalTransportManager] ✓ 已在Portal.Base下创建Attachment01")
	else
		print("[PortalTransportManager] ✓ Portal.Base.Attachment已存在")
	end

	-- 保存 Base Part 的引用，便于后续使用
	portalState.effectPart = effectPart

	-- 保存状态
	portalState.portal = portal
	portalState.targetPlaceId = targetPlaceId
	portalState.initialized = true

	print("[PortalTransportManager] ✓ Portal已初始化（坐标将在教程结束后设置）")

	return true
end

-- ============================================
-- 处理Portal交互
-- ============================================

function PortalTransportManager:onPortalInteraction(player)
	if not player or not player:IsA("Player") then
		warn("PortalTransportManager: 无效的玩家对象")
		return false
	end

	-- 检查玩家是否已在传送中
	if playerBeingTeleported[player.UserId] then
		print("[PortalTransportManager] 玩家 " .. player.Name .. " 正在传送中，跳过重复交互")
		return false
	end

	print("[PortalTransportManager] 玩家 " .. player.Name .. " 与Portal交互")

	-- 标记玩家为正在传送
	playerBeingTeleported[player.UserId] = true

	-- 1秒后执行传送
	task.delay(1, function()
		if player and player.Parent and player:IsA("Player") then
			-- 调用传送函数
			self:teleportToMainPlace(player)
		end
		playerBeingTeleported[player.UserId] = nil
	end)

	return true
end

-- ============================================
-- 传送玩家回到主场景
-- ============================================

function PortalTransportManager:teleportToMainPlace(player)
	if not player or not player:IsA("Player") then
		warn("PortalTransportManager: 无效的玩家对象")
		return false
	end

	-- 获取默认Place的ID（通常是1，或者从配置中获取）
	local mainPlaceId = game.PlaceId  -- 当前Place的ID

	-- 如果有特定的主场景ID配置，使用配置的ID
	if portalState.targetPlaceId and portalState.targetPlaceId ~= mainPlaceId then
		mainPlaceId = portalState.targetPlaceId
	else
		-- 从_G中读取主场景ID（如果存在）
		if _G.MainPlaceId then
			mainPlaceId = _G.MainPlaceId
		end
	end

	-- 尝试传送玩家
	local success = false
	local errorMsg = nil

	local teleportAttempt = pcall(function()
		TeleportService:Teleport(mainPlaceId, player)
		success = true
	end)

	if not teleportAttempt then
		errorMsg = "TeleportService异常"
		print("[PortalTransportManager] ⚠️ 传送失败: " .. tostring(errorMsg))
	elseif not success then
		errorMsg = "传送未成功"
		print("[PortalTransportManager] ⚠️ 传送结果未确认: " .. tostring(errorMsg))
	end

	-- 即使传送失败，也标记玩家为已完成教程
	-- 这是容错处理
	if _G.TutorialCompleted then
		_G.TutorialCompleted[player.UserId] = true
		print("[PortalTransportManager] ! 虽然传送失败，但已标记玩家为教程完成")
	end

	if success then
		print("[PortalTransportManager] ✓ 成功传送玩家 " .. player.Name .. " 到主场景（PlaceId: " .. mainPlaceId .. "）")
	end

	return success, errorMsg
end

-- ============================================
-- 设置主场景PlaceId
-- ============================================

function PortalTransportManager:setMainPlaceId(placeId)
	portalState.targetPlaceId = placeId
	print("[PortalTransportManager] ✓ 已设置主场景PlaceId: " .. placeId)
end

-- ============================================
-- 重新定位Portal坐标（用于教程结束后）
-- ============================================

function PortalTransportManager:repositionPortal(x, y, z)
	if not portalState.portal or not portalState.portal.Parent then
		warn("[PortalTransportManager] Portal不存在或已被销毁，无法重新定位")
		return false
	end

	local portal = portalState.portal

	-- 如果是Model类型
	if portal:IsA("Model") then
		local primaryPart = portal.PrimaryPart
		if not primaryPart then
			-- 如果没有PrimaryPart，尝试找第一个Part
			for _, child in pairs(portal:GetDescendants()) do
				if child:IsA("BasePart") then
					portal.PrimaryPart = child
					primaryPart = child
					break
				end
			end
		end

		if primaryPart then
			portal:SetPrimaryPartCFrame(CFrame.new(x, y, z))

			-- 🔧 V1.6新增：同时更新交互占位块的位置
			if portalState.promptPart then
				portalState.promptPart.CFrame = CFrame.new(x, y, z)
				print("[PortalTransportManager] ✓ 已同步更新交互占位块位置")
			end

			print("[PortalTransportManager] ✓ 已将Portal重新定位到: " .. x .. ", " .. y .. ", " .. z)
			return true
		end
	elseif portal:IsA("BasePart") then
		-- 如果Portal是单个Part
		portal.Position = Vector3.new(x, y, z)

		-- 🔧 V1.6新增：同时更新交互占位块的位置
		if portalState.promptPart then
			portalState.promptPart.Position = Vector3.new(x, y, z)
			print("[PortalTransportManager] ✓ 已同步更新交互占位块位置")
		end

		print("[PortalTransportManager] ✓ 已将Portal重新定位到: " .. x .. ", " .. y .. ", " .. z)
		return true
	end

	return false
end

-- ============================================
-- 获取Portal状态
-- ============================================

function PortalTransportManager:getPortalStatus()
	return {
		initialized = portalState.initialized,
		portalExists = portalState.portal ~= nil and portalState.portal.Parent ~= nil,
		targetPlaceId = portalState.targetPlaceId,
		playersBeingTeleported = playerBeingTeleported
	}
end

-- ============================================
-- 清理资源
-- ============================================

function PortalTransportManager:cleanup()
	playerBeingTeleported = {}
	portalState.initialized = false
	print("[PortalTransportManager] ✓ 已清理Portal传送资源")
end

-- 🔧 V1.6: 监听玩家离开事件，清理传送标记防止卡顿
local function setupPlayerLeavingHandler()
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		if playerBeingTeleported[player.UserId] then
			playerBeingTeleported[player.UserId] = nil
			print("[PortalTransportManager] ✓ 清理玩家 " .. player.Name .. " 的传送标记")
		end
	end)
end

-- 🔧 V1.6: 设置超时清理机制，防止标记永久存在
local function setupTimeoutCleanup()
	spawn(function()
		while true do
			task.wait(10)  -- 每10秒检查一次

			-- 遍历所有被标记为正在传送的玩家
			for userId, _ in pairs(playerBeingTeleported) do
				-- 如果玩家已离线或已经超过5秒，清理标记
				local player = game:GetService("Players"):FindFirstChild(tostring(userId))
				if not player then
					-- 玩家已离线
					playerBeingTeleported[userId] = nil
					print("[PortalTransportManager] ✓ 自动清理已离线玩家的传送标记: " .. userId)
				end
			end
		end
	end)
end

-- 在模块加载时初始化这些处理器
setupPlayerLeavingHandler()
setupTimeoutCleanup()

return PortalTransportManager
