-- 脚本名称: FreeGiftInteractionManager
-- 脚本作用: V2.1 免费在线奖励 - 场景交互管理器
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- 功能：
--   1. 查找Workspace中的Chest模型
--   2. 为Chest创建并绑定ProximityPrompt
--   3. 监听Prompt触发事件，通知客户端打开FreeGift UI

local FreeGiftInteractionManager = {}
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 交互冷却
local interactionCooldowns = {}
local INTERACTION_COOLDOWN = 2  -- 2秒冷却时间

-- RemoteEvent (延迟初始化)
local freeGiftEvent = nil

-- Chest模型引用
local chestModel = nil

-- ============================================
-- Chest模型管理
-- ============================================

-- 查找Chest模型
local function findChestModel()
	-- 按需求查找Chest模型
	chestModel = Workspace:FindFirstChild("Chest")

	if not chestModel then
		warn("⚠️ FreeGiftInteractionManager: 未找到Workspace/Chest模型")
	end

	return chestModel
end

-- 设置Chest的ProximityPrompt
local function setupChestProximityPrompt()
	if not chestModel then
		warn("⚠️ FreeGiftInteractionManager: Chest模型不存在，跳过ProximityPrompt设置")
		return
	end

	-- 寻找可交互的Part
	local targetPart = nil

	-- 优先查找特定名称的Part
	local specificParts = {"Base", "ChestBase", "InteractionPart", "Body", "Main"}
	for _, partName in ipairs(specificParts) do
		local part = chestModel:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			targetPart = part
			break
		end
	end

	-- 如果没找到特定Part，使用PrimaryPart或第一个BasePart
	if not targetPart then
		if chestModel:IsA("Model") and chestModel.PrimaryPart then
			targetPart = chestModel.PrimaryPart
		else
			for _, child in pairs(chestModel:GetChildren()) do
				if child:IsA("BasePart") then
					targetPart = child
					break
				end
			end
		end
	end

	if not targetPart then
		warn("❌ FreeGiftInteractionManager: Chest模型缺少可交互的BasePart")
		return
	end

	-- 检查是否已存在ProximityPrompt
	local existingPrompt = targetPart:FindFirstChildOfClass("ProximityPrompt")
	if existingPrompt then
		-- 更新现有Prompt的属性
		existingPrompt.ActionText = "Open"
		existingPrompt.ObjectText = "Free Gift Chest"
		existingPrompt.HoldDuration = 0.5
		existingPrompt.MaxActivationDistance = 10
		existingPrompt.RequiresLineOfSight = false
		existingPrompt.Style = Enum.ProximityPromptStyle.Default

		-- 注意：不重新绑定事件，避免重复绑定
		-- 如果Prompt是在Studio中手动创建的，需要绑定事件
		-- 检查是否已经绑定过（通过检查Prompt的Attribute标记）
		if not existingPrompt:GetAttribute("EventBound") then
			existingPrompt.Triggered:Connect(function(player)
				FreeGiftInteractionManager.onChestPromptTriggered(player)
			end)
			existingPrompt:SetAttribute("EventBound", true)
		end
	else
		-- 创建新的ProximityPrompt
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Free Gift Chest"
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.Parent = targetPart

		-- 绑定触发事件
		prompt.Triggered:Connect(function(player)
			FreeGiftInteractionManager.onChestPromptTriggered(player)
		end)
		prompt:SetAttribute("EventBound", true)
	end
end

-- ============================================
-- 交互处理逻辑
-- ============================================

-- ProximityPrompt触发处理
function FreeGiftInteractionManager.onChestPromptTriggered(player)
	if not player or not player.Parent then
		return
	end

	-- 检查冷却
	local userId = player.UserId
	local now = tick()
	if interactionCooldowns[userId] and (now - interactionCooldowns[userId] < INTERACTION_COOLDOWN) then
		return  -- 在冷却中
	end

	interactionCooldowns[userId] = now

	-- 📊 埋点：UI打开事件
	if _G.FreeGiftAnalytics then
		_G.FreeGiftAnalytics.logUIOpened(player)
	end

	-- 验证RemoteEvent是否可用
	if not freeGiftEvent then
		warn("❌ FreeGiftInteractionManager: FreeGift RemoteEvent未初始化")
		return
	end

	-- 🔑 关键：通知客户端打开FreeGift UI
	local success, errorMsg = pcall(function()
		freeGiftEvent:FireClient(player, "openUI")
	end)

	if not success then
		warn("❌ FreeGiftInteractionManager: 通知客户端失败 - " .. tostring(errorMsg))
	end
end

-- ============================================
-- 初始化和启动
-- ============================================

-- 初始化RemoteEvent
local function initializeRemoteEvent()
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEventsFolder then
		warn("❌ FreeGiftInteractionManager: RemoteEvents文件夹不存在")
		return false
	end

	freeGiftEvent = remoteEventsFolder:WaitForChild("FreeGift", 5)
	if not freeGiftEvent then
		warn("❌ FreeGiftInteractionManager: FreeGift RemoteEvent不存在")
		return false
	end

	return true
end

-- 初始化管理器
function FreeGiftInteractionManager.initialize()
	-- 初始化RemoteEvent（延迟4秒等待RemoteEvents创建）
	task.spawn(function()
		task.wait(4)
		initializeRemoteEvent()
	end)

	-- 设置Chest模型交互（延迟5秒等待Workspace模型加载）
	task.spawn(function()
		task.wait(5)
		findChestModel()
		setupChestProximityPrompt()

		if not chestModel then
			warn("⚠️ FreeGiftInteractionManager: Chest模型未找到，功能将不可用")
			warn("   请确保Workspace中存在名为'Chest'的模型")
		end
	end)

	-- 监听玩家离开（清理冷却记录）
	Players.PlayerRemoving:Connect(function(player)
		interactionCooldowns[player.UserId] = nil
	end)
end

-- 启动管理器
FreeGiftInteractionManager.initialize()

-- 导出到全局
_G.FreeGiftInteractionManager = FreeGiftInteractionManager

return FreeGiftInteractionManager
