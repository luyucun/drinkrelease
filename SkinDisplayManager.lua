-- 脚本名称: SkinDisplayManager
-- 脚本作用: V2.0皮肤展示模型管理器,处理ProximityPrompt购买交互
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- 加载依赖 (从ReplicatedStorage加载,客户端和服务端共享)
local SkinConfig = require(ReplicatedStorage:WaitForChild("SkinConfig"))

local SkinDisplayManager = {}

-- ProximityPrompt触发冷却
local promptCooldowns = {}
local PROMPT_COOLDOWN_TIME = 2  -- 2秒冷却

-- ============================================
-- 展示模型初始化
-- ============================================

-- 为单个展示模型设置ProximityPrompt
local function setupProximityPrompt(displayModel, skinId)
	local skinInfo = SkinConfig.getSkinInfo(skinId)
	if not skinInfo then
		warn("皮肤配置不存在,跳过ProximityPrompt设置: " .. tostring(skinId))
		return
	end

	-- 查找可点击的Part(优先Cup,否则使用PrimaryPart或第一个BasePart)
	local targetPart = nil
	if displayModel:FindFirstChild("Cup") and displayModel.Cup:IsA("BasePart") then
		targetPart = displayModel.Cup
	elseif displayModel:IsA("Model") and displayModel.PrimaryPart then
		targetPart = displayModel.PrimaryPart
	else
		for _, child in pairs(displayModel:GetChildren()) do
			if child:IsA("BasePart") then
				targetPart = child
				break
			end
		end
	end

	if not targetPart then
		warn("展示模型缺少可点击的BasePart: " .. displayModel.Name)
		return
	end

	-- 检查是否已存在ProximityPrompt
	local existingPrompt = targetPart:FindFirstChildOfClass("ProximityPrompt")
	if existingPrompt then
		-- 已存在,只更新属性,不重新绑定事件(避免事件重复绑定)
		existingPrompt.ActionText = "Purchase"
		existingPrompt.ObjectText = skinInfo.name .. " - $" .. skinInfo.price
		existingPrompt.HoldDuration = 0.8  -- 长按0.8秒购买
		existingPrompt.MaxActivationDistance = 10
		existingPrompt.RequiresLineOfSight = false
		existingPrompt.Style = Enum.ProximityPromptStyle.Default
		-- 注意: 不重新绑定事件,避免重复绑定
	else
		-- 不存在,创建新的
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Purchase"
		prompt.ObjectText = skinInfo.name .. " - $" .. skinInfo.price
		prompt.HoldDuration = 0.8  -- 长按0.8秒购买
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.Parent = targetPart

		-- 监听触发事件
		prompt.Triggered:Connect(function(player)
			SkinDisplayManager.onPromptTriggered(player, skinId, displayModel)
		end)
	end
end

-- ProximityPrompt触发处理
function SkinDisplayManager.onPromptTriggered(player, skinId, displayModel)
	-- 验证模型仍然存在
	if not displayModel or not displayModel.Parent then
		warn("展示模型已被删除")
		return
	end

	-- 检查冷却
	local userId = player.UserId
	local now = tick()
	if promptCooldowns[userId] and (now - promptCooldowns[userId] < PROMPT_COOLDOWN_TIME) then
		return  -- 在冷却中,忽略
	end

	promptCooldowns[userId] = now

	-- 触发购买逻辑
	if not _G.SkinDataManager then
		warn("SkinDataManager未加载")
		return
	end

	local success, message = _G.SkinDataManager.purchaseSkin(player, skinId)

	-- 发送购买反馈到客户端(通过RemoteEvent)
	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEventsFolder then
		return
	end

	local purchaseEvent = remoteEventsFolder:FindFirstChild("SkinPurchase")
	if not purchaseEvent then
		return
	end

	if success then
		-- 购买成功,通知客户端显示成功提示
		purchaseEvent:FireClient(player, "notifySuccess", {
			skinId = skinId
		})
	elseif message == "already_owned" then
		-- 已拥有,通知客户端显示已拥有提示
		purchaseEvent:FireClient(player, "notifyAlreadyOwned", {
			skinId = skinId
		})
	elseif message == "insufficient_coins" then
		-- 金币不足,使用系统默认提示(不需要额外处理)
		-- 客户端会收到purchaseFailed事件
	end
end

-- 扫描并设置所有展示模型 (修改为可选展示)
function SkinDisplayManager.setupAllDisplayModels()
	local skinTemplate = Workspace:FindFirstChild("SkinTemplate")
	if not skinTemplate then
		print("📝 未找到Workspace.SkinTemplate文件夹，跳过展示模型设置")
		return
	end

	-- 遍历现有展示模型
	local setupCount = 0
	for _, displayModel in pairs(skinTemplate:GetChildren()) do
		if displayModel:IsA("Model") or displayModel:IsA("BasePart") then
			-- 根据展示模型名称查找对应的皮肤配置
			local skinInfo = SkinConfig.getSkinByDisplayModelName(displayModel.Name)
			if skinInfo then
				setupProximityPrompt(displayModel, skinInfo.id)
				setupCount = setupCount + 1
			else
				print("📝 展示模型 " .. displayModel.Name .. " 没有对应的皮肤配置，跳过")
			end
		end
	end

	print("✅ 展示模型ProximityPrompt设置完成，共设置 " .. setupCount .. " 个模型")
end

-- ============================================
-- 初始化
-- ============================================

function SkinDisplayManager.initialize()
	-- 等待SkinConfig和SkinDataManager加载
	task.wait(1)

	-- 设置所有展示模型的ProximityPrompt
	SkinDisplayManager.setupAllDisplayModels()

	-- 监听新模型添加(如果运行时添加新展示模型)
	local skinTemplate = Workspace:FindFirstChild("SkinTemplate")
	if skinTemplate then
		skinTemplate.ChildAdded:Connect(function(child)
			task.wait(0.5)  -- 等待模型完全加载

			if child:IsA("Model") or child:IsA("BasePart") then
				local skinInfo = SkinConfig.getSkinByDisplayModelName(child.Name)
				if skinInfo then
					setupProximityPrompt(child, skinInfo.id)
					print("✅ 动态添加展示模型: " .. child.Name)
				else
					print("📝 新添加的展示模型 " .. child.Name .. " 没有对应的皮肤配置，跳过")
				end
			end
		end)
		print("✅ SkinDisplayManager: 已监听SkinTemplate动态变化")
	else
		print("📝 SkinDisplayManager: SkinTemplate文件夹不存在，跳过动态监听")
	end

	print("✅ SkinDisplayManager 初始化完成")
end

-- 注册为全局管理器
_G.SkinDisplayManager = SkinDisplayManager

-- 自动初始化
SkinDisplayManager.initialize()

return SkinDisplayManager
