-- 脚本名称: WheelInteractionManager
-- 脚本作用: 转盘交互管理器，处理ProximityPrompt交互和转盘次数购买
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local WheelInteractionManager = {}
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- 依赖管理器
local WheelConfig = nil
local WheelDataManager = nil

-- 交互冷却
local interactionCooldowns = {}
local INTERACTION_COOLDOWN = 2 -- 2秒冷却

-- RemoteEvents (延迟初始化)
local wheelPurchaseEvent = nil
local wheelInteractionEvent = nil

-- 转盘模型引用
local wheelModel = nil

-- ============================================
-- 依赖加载
-- ============================================

-- 加载依赖配置
local function loadDependencies()
	-- 加载WheelConfig
	if not WheelConfig then
		local success, result = pcall(function()
			return require(ReplicatedStorage:WaitForChild("WheelConfig", 10))
		end)

		if success then
			WheelConfig = result
		else
			warn("❌ WheelInteractionManager: WheelConfig加载失败: " .. tostring(result))
			return false
		end
	end

	-- 等待WheelDataManager
	if not WheelDataManager then
		local timeout = 0
		while not _G.WheelDataManager and timeout < 30 do
			task.wait(0.5)
			timeout = timeout + 0.5
		end

		if _G.WheelDataManager then
			WheelDataManager = _G.WheelDataManager
		else
			warn("❌ WheelInteractionManager: WheelDataManager连接超时")
			return false
		end
	end

	return true
end

-- 初始化RemoteEvents
local function initializeRemoteEvents()
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEventsFolder then
		warn("❌ WheelInteractionManager: RemoteEvents文件夹不存在")
		return false
	end

	wheelPurchaseEvent = remoteEventsFolder:WaitForChild("WheelPurchase", 5)
	wheelInteractionEvent = remoteEventsFolder:WaitForChild("WheelInteraction", 5)

	if not wheelPurchaseEvent or not wheelInteractionEvent then
		warn("❌ WheelInteractionManager: 转盘RemoteEvents不存在")
		return false
	end

	return true
end

-- ============================================
-- 转盘模型管理
-- ============================================

-- 查找转盘模型
local function findWheelModel()
	-- 按需求查找正确的转盘模型名称：LuckyZhuanZhuan
	wheelModel = Workspace:FindFirstChild("LuckyZhuanZhuan")

	if wheelModel then
		return wheelModel
	end

	return nil
end

-- 设置转盘ProximityPrompt
local function setupWheelProximityPrompt()
	if not wheelModel then
		return
	end

	-- 寻找可交互的Part
	local targetPart = nil

	-- 优先查找特定名称的Part
	local specificParts = {"Base", "WheelBase", "InteractionPart", "Stand"}
	for _, partName in ipairs(specificParts) do
		local part = wheelModel:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			targetPart = part
			break
		end
	end

	-- 如果没找到特定Part，使用PrimaryPart或第一个BasePart
	if not targetPart then
		if wheelModel:IsA("Model") and wheelModel.PrimaryPart then
			targetPart = wheelModel.PrimaryPart
		else
			for _, child in pairs(wheelModel:GetChildren()) do
				if child:IsA("BasePart") then
					targetPart = child
					break
				end
			end
		end
	end

	if not targetPart then
		warn("WheelInteractionManager: 转盘模型缺少可交互的BasePart")
		return
	end

	-- 检查是否已存在ProximityPrompt
	local existingPrompt = targetPart:FindFirstChildOfClass("ProximityPrompt")
	if existingPrompt then
		-- 更新现有Prompt
		existingPrompt.ActionText = "Spin"
		existingPrompt.ObjectText = "Lucky Wheel"
		existingPrompt.HoldDuration = 0.5
		existingPrompt.MaxActivationDistance = 12
		existingPrompt.RequiresLineOfSight = false
		existingPrompt.Style = Enum.ProximityPromptStyle.Default
	else
		-- 创建新的ProximityPrompt
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Spin"
		prompt.ObjectText = "Lucky Wheel"
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.Parent = targetPart

		-- 绑定触发事件
		prompt.Triggered:Connect(function(player)
			WheelInteractionManager.onWheelPromptTriggered(player)
		end)
	end
end

-- ============================================
-- 交互处理逻辑
-- ============================================

-- ProximityPrompt触发处理
function WheelInteractionManager.onWheelPromptTriggered(player)
	-- 检查冷却
	local userId = player.UserId
	local now = tick()
	if interactionCooldowns[userId] and (now - interactionCooldowns[userId] < INTERACTION_COOLDOWN) then
		return -- 在冷却中
	end

	interactionCooldowns[userId] = now

	-- 验证依赖
	if not loadDependencies() then
		return
	end

	-- 检查转盘次数
	local spinCount = WheelDataManager.getSpinCount(player)

	-- 🔧 修复：无论转盘次数是否足够，都打开转盘界面
	-- 触发转盘界面打开
	if wheelInteractionEvent and player.Parent then
		wheelInteractionEvent:FireClient(player, "promptTriggered", {
			spinCount = spinCount
		})
	end

	-- 🔧 修复：只在次数不足时显示提示，避免重复消息
	-- 不再单独发送noSpinsAvailable，让客户端在点击转盘按钮时处理
end

-- ============================================
-- 购买系统 (移除原购买处理函数，现由UnifiedPurchaseManager处理)
-- ============================================

-- 🔧 修复：移除onDeveloperProductPurchase函数
-- 转盘商品购买现在由UnifiedPurchaseManager统一处理

-- 处理客户端购买请求
local function onPurchaseRequest(player, action, data)
	if action == "requestPurchase" and data and data.productName then
		if not loadDependencies() then
			return
		end

		-- 查找商品配置
		local productInfo = WheelConfig.DEVELOPER_PRODUCTS[data.productName]
		if not productInfo then
			warn("WheelInteractionManager: 无效的商品名称 - " .. data.productName)

			if wheelPurchaseEvent and player.Parent then
				wheelPurchaseEvent:FireClient(player, "purchaseFailed", {
					reason = "invalid_product"
				})
			end
			return
		end

		-- 发起购买
		local success, errorMsg = pcall(function()
			MarketplaceService:PromptProductPurchase(player, productInfo.id)
		end)

		if not success then
			warn("WheelInteractionManager: 购买提示失败 - " .. tostring(errorMsg))

			if wheelPurchaseEvent and player.Parent then
				wheelPurchaseEvent:FireClient(player, "purchaseFailed", {
					reason = "marketplace_error"
				})
			end
		end

	elseif action == "getProductInfo" then
		-- 返回商品信息
		if wheelPurchaseEvent and player.Parent then
			wheelPurchaseEvent:FireClient(player, "productInfo", {
				products = WheelConfig.DEVELOPER_PRODUCTS
			})
		end
	end
end

-- 处理交互请求
local function onInteractionRequest(player, action, data)
	if action == "checkSpinCount" then
		-- 返回当前转盘次数
		if wheelInteractionEvent and player.Parent then
			local spinCount = WheelDataManager and WheelDataManager.getSpinCount(player) or 0
			wheelInteractionEvent:FireClient(player, "spinCountUpdate", {
				spinCount = spinCount
			})
		end

	elseif action == "triggerSpin" then
		-- 手动触发转盘（来自UI按钮）
		WheelInteractionManager.onWheelPromptTriggered(player)
	end
end

-- ============================================
-- 初始化和启动
-- ============================================

-- 初始化管理器
function WheelInteractionManager.initialize()
	-- 延迟加载依赖
	task.spawn(function()
		task.wait(3) -- 等待其他系统初始化
		loadDependencies()
	end)

	-- 初始化RemoteEvents
	task.spawn(function()
		task.wait(4) -- 等待RemoteEvents创建
		if initializeRemoteEvents() then
			-- 设置事件监听
			wheelPurchaseEvent.OnServerEvent:Connect(onPurchaseRequest)
			wheelInteractionEvent.OnServerEvent:Connect(onInteractionRequest)
		end
	end)

	-- 设置转盘模型交互
	task.spawn(function()
		task.wait(5) -- 等待转盘模型加载
		findWheelModel()
		setupWheelProximityPrompt()
	end)

	-- 🔧 修复：移除MarketplaceService.ProcessReceipt直接赋值
	-- 现在由UnifiedPurchaseManager统一处理所有开发者商品购买

	-- 监听玩家离开
	Players.PlayerRemoving:Connect(function(player)
		interactionCooldowns[player.UserId] = nil
	end)
end

-- 启动管理器
WheelInteractionManager.initialize()

-- 导出到全局
_G.WheelInteractionManager = WheelInteractionManager

return WheelInteractionManager