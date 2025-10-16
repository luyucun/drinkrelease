-- 脚本名称: EmoteInteractionManager
-- 脚本作用: NPC跳舞动作展示与购买交互，处理ProximityPrompt和动画循环
-- 🔧 修复：脚本类型应为 ModuleScript（不是 Script）
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local EmoteInteractionManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- 引入配置
local EmoteConfig = require(ReplicatedStorage:WaitForChild("EmoteConfig"))

-- 延迟加载EmoteDataManager
local EmoteDataManager = nil

-- NPC配置（与EmoteConfig关联）
local NPC_MODELS = {
	"Npc01",
	"Npc02",
	"Npc03"
}

-- 动画跟踪器缓存
local npcAnimationTracks = {}

-- ============================================
-- NPC动画播放
-- ============================================

-- 为单个NPC设置循环动画
local function setupNPCAnimation(npcModel, animationId)
	if not npcModel or not animationId then
		warn("❌ EmoteInteractionManager: NPC模型或动画ID无效")
		return false
	end

	-- 🔧 关键修复：优化NPC锚固设置，防止被推动的同时保持动画播放
	local function optimizeNPCAnchorage(model)
		-- 只锚固HumanoidRootPart，其他部件保持可动
		local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then
			humanoidRootPart = model:FindFirstChild("Torso") -- R6模型兼容
		end

		if humanoidRootPart then
			humanoidRootPart.Anchored = true  -- 锚固核心部件，防止被推动
		end

		-- 确保其他身体部件不被锚固，允许动画播放
		for _, part in pairs(model:GetChildren()) do
			if part:IsA("BasePart") and part ~= humanoidRootPart then
				part.Anchored = false  -- 身体部件保持可动

				-- 🔧 额外优化：设置CanCollide为false，减少与玩家的物理冲突
				if part.Name ~= "Head" then  -- 头部保持碰撞，用于ProximityPrompt检测
					part.CanCollide = false
				end
			end
		end
	end

	-- 执行锚固优化
	optimizeNPCAnchorage(npcModel)

	-- 查找Humanoid
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("❌ EmoteInteractionManager: NPC " .. npcModel.Name .. " 没有Humanoid")
		return false
	end

	-- 🔧 重要：设置Humanoid的PlatformStand为false，确保动画能正常播放
	humanoid.PlatformStand = false

	-- 🔧 额外优化：设置Sit为false，确保NPC不会因为意外坐下而影响动画
	humanoid.Sit = false

	-- 查找Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		-- 创建Animator
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- 创建Animation对象
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	-- 加载动画
	local success, animationTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not animationTrack then
		warn("❌ EmoteInteractionManager: 加载NPC动画失败: " .. npcModel.Name .. " - " .. tostring(animationTrack))
		return false
	end

	-- 设置循环
	animationTrack.Looped = true

	-- 🔧 设置动画优先级，确保覆盖默认姿势
	animationTrack.Priority = Enum.AnimationPriority.Action

	-- 播放动画
	animationTrack:Play()

	-- 🔧 新增：监听动画停止事件，如果意外停止则重新播放
	animationTrack.Stopped:Connect(function()
		-- 检查NPC和AnimationTrack是否仍然有效
		if npcModel and npcModel.Parent and animationTrack and npcAnimationTracks[npcModel] == animationTrack then
			-- 延迟一点再重新播放，避免立即重播导致的问题
			task.wait(0.1)
			if animationTrack and npcModel.Parent then
				animationTrack:Play()
			end
		end
	end)

	-- 缓存动画跟踪器
	npcAnimationTracks[npcModel] = animationTrack

	return true
end

-- 初始化所有NPC的动画
local function initializeAllNPCAnimations()
	local animationSellFolder = Workspace:FindFirstChild("AnimationSell")
	if not animationSellFolder then
		warn("❌ EmoteInteractionManager: 未找到 Workspace.AnimationSell 文件夹")
		return
	end

	-- 获取NPC关联的动作配置
	local npcEmotes = EmoteConfig.getNPCEmotes()

	-- 遍历所有NPC模型
	for _, npcName in ipairs(NPC_MODELS) do
		local npcModel = animationSellFolder:FindFirstChild(npcName)
		if npcModel then
			local emoteInfo = npcEmotes[npcName]
			if emoteInfo and emoteInfo.animationId then
				setupNPCAnimation(npcModel, emoteInfo.animationId)
			else
				warn("❌ EmoteInteractionManager: 未找到NPC " .. npcName .. " 的动作配置")
			end
		else
			warn("❌ EmoteInteractionManager: 未找到NPC模型: " .. npcName)
		end
	end
end

-- ============================================
-- ProximityPrompt交互
-- ============================================

-- 为NPC创建ProximityPrompt
local function createProximityPrompt(npcModel, emoteId)
	if not npcModel or not emoteId then
		return nil
	end

	-- 获取动作信息
	local emoteInfo = EmoteConfig.getEmoteInfo(emoteId)
	if not emoteInfo then
		warn("EmoteInteractionManager: 无效的动作ID: " .. tostring(emoteId))
		return nil
	end

	-- 🔧 修复：ProximityPrompt 必须挂在 BasePart 或 Attachment 上才能正常显示
	-- 查找 HumanoidRootPart（最常用的挂载点）
	local humanoidRootPart = npcModel:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		-- 如果没有 HumanoidRootPart，尝试查找 Torso（R6模型）
		humanoidRootPart = npcModel:FindFirstChild("Torso")
	end

	if not humanoidRootPart or not humanoidRootPart:IsA("BasePart") then
		warn("EmoteInteractionManager: NPC " .. npcModel.Name .. " 没有 HumanoidRootPart 或 Torso")
		return nil
	end

	-- 查找或创建ProximityPrompt（挂在 HumanoidRootPart 上）
	local prompt = humanoidRootPart:FindFirstChild("EmotePrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "EmotePrompt"
		prompt.Parent = humanoidRootPart  -- 挂载到 BasePart
	end

	-- 配置ProximityPrompt
	prompt.ActionText = "Purchase " .. emoteInfo.name
	prompt.ObjectText = emoteInfo.coinPrice .. " Coins"
	prompt.HoldDuration = 0.5  -- 🔧 修改：长按0.5秒
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true

	return prompt
end

-- 处理购买请求
local function handlePurchaseRequest(player, emoteId, npcModel)
	if not player or not emoteId then
		return
	end

	-- 延迟加载EmoteDataManager
	if not EmoteDataManager then
		EmoteDataManager = require(script.Parent.EmoteDataManager)
	end

	-- 获取动作信息
	local emoteInfo = EmoteConfig.getEmoteInfo(emoteId)
	if not emoteInfo then
		warn("EmoteInteractionManager: 无效的动作ID: " .. tostring(emoteId))
		return
	end

	-- 检查是否已拥有
	if EmoteDataManager.hasEmote(player, emoteId) then
		-- 提示已拥有
		EmoteInteractionManager.sendNotification(player, "Already Owned", false)
		return
	end

	-- 尝试购买
	local success, errorMsg = EmoteDataManager.purchaseEmote(player, emoteId)

	if success then
		-- 购买成功提示
		EmoteInteractionManager.sendNotification(player, "Successfully purchased " .. emoteInfo.name .. "!", true)
	else
		-- 购买失败提示
		if errorMsg == "Not Enough Coins" then
			EmoteInteractionManager.sendNotification(player, "Not Enough Coins", false)
		elseif errorMsg == "Purchase in progress" then
			EmoteInteractionManager.sendNotification(player, "Purchase in progress", false)
		else
			EmoteInteractionManager.sendNotification(player, "Purchase failed", false)
		end
	end
end

-- 设置单个NPC的ProximityPrompt
local function setupNPCPrompt(npcModel, emoteId)
	local prompt = createProximityPrompt(npcModel, emoteId)
	if not prompt then
		return
	end

	-- 监听触发事件
	prompt.Triggered:Connect(function(player)
		if not player or not player.Parent then
			return
		end

		-- 处理购买
		handlePurchaseRequest(player, emoteId, npcModel)
	end)
end

-- 初始化所有NPC的ProximityPrompt
local function initializeAllNPCPrompts()
	local animationSellFolder = Workspace:FindFirstChild("AnimationSell")
	if not animationSellFolder then
		warn("EmoteInteractionManager: 未找到 Workspace.AnimationSell 文件夹")
		return
	end

	-- 获取NPC关联的动作配置
	local npcEmotes = EmoteConfig.getNPCEmotes()

	-- 遍历所有NPC模型
	for npcName, emoteInfo in pairs(npcEmotes) do
		local npcModel = animationSellFolder:FindFirstChild(npcName)
		if npcModel then
			setupNPCPrompt(npcModel, emoteInfo.id)
		else
			warn("EmoteInteractionManager: 未找到NPC模型: " .. npcName)
		end
	end
end

-- ============================================
-- 通知系统
-- ============================================

-- 🔧 修复：使用 StarterGui:SetCore 实现真实的右下角通知
-- 发送通知给客户端
function EmoteInteractionManager.sendNotification(player, message, isSuccess)
	if not player or not player.Parent then
		return
	end

	-- 通过RemoteEvent发送通知
	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEventsFolder then
		warn("EmoteInteractionManager: RemoteEvents文件夹不存在")
		return
	end

	local notificationEvent = remoteEventsFolder:FindFirstChild("ShowNotification")
	if not notificationEvent then
		warn("EmoteInteractionManager: ShowNotification RemoteEvent不存在")
		return
	end

	-- 发送通知数据到客户端
	local success, error = pcall(function()
		notificationEvent:FireClient(player, {
			message = message,
			isSuccess = isSuccess,
			duration = 3
		})
	end)

	if not success then
		warn("EmoteInteractionManager: 发送通知失败: " .. tostring(error))
	end
end

-- ============================================
-- 初始化
-- ============================================

function EmoteInteractionManager.initialize()
	-- 延迟初始化，确保Workspace完全加载
	task.wait(2)

	-- 初始化NPC动画
	initializeAllNPCAnimations()

	-- 初始化ProximityPrompt
	initializeAllNPCPrompts()
end

-- 导出到全局
_G.EmoteInteractionManager = EmoteInteractionManager

return EmoteInteractionManager
