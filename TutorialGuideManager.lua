-- 脚本名称: TutorialGuideManager
-- 脚本作用: 管理新手教程的引导箭头系统
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local TutorialGuideManager = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- 引导箭头跟踪
local playerArrows = {} -- {[playerId] = {beam, attachmentOnSeat, attachmentOnPlayer}}
local portalArrows = {} -- {[playerId] = {beam, attachmentOnPlayer}} -- 🔧 V1.6新增：Portal指引箭头

-- ============================================
-- 创建引导箭头
-- ============================================

function TutorialGuideManager:showGuidingArrow(player, targetSeat)
	if not player or not player:IsA("Player") then
		warn("TutorialGuideManager: 无效的玩家对象")
		return false
	end

	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		warn("TutorialGuideManager: 玩家角色或HumanoidRootPart不存在")
		return false
	end

	if not targetSeat or not targetSeat:IsA("Seat") then
		warn("TutorialGuideManager: 无效的座位对象")
		return false
	end

	local playerId = player.UserId

	-- 检查是否已有箭头
	if playerArrows[playerId] then
		return false
	end

	-- 获取Arrow模板
	local arrowFolder = ReplicatedStorage:FindFirstChild("Arrow")
	if not arrowFolder then
		warn("TutorialGuideManager: ReplicatedStorage中找不到Arrow文件夹")
		return false
	end

	local arrowABeam = arrowFolder:FindFirstChild("Arrow_A")
	if not arrowABeam or not arrowABeam:FindFirstChild("Beam") then
		warn("TutorialGuideManager: Arrow_A中找不到Beam")
		return false
	end

	-- 克隆Beam
	local beamTemplate = arrowABeam:FindFirstChild("Beam")
	local beam = beamTemplate:Clone()

	-- 在座位上创建Attachment01
	local seatAttachment = Instance.new("Attachment")
	seatAttachment.Name = "Attachment01"
	seatAttachment.Parent = targetSeat

	-- 在玩家身上创建Attachment02
	local playerAttachment = Instance.new("Attachment")
	playerAttachment.Name = "Attachment02"
	playerAttachment.Parent = player.Character.HumanoidRootPart

	-- 配置Beam的连接点
	beam.Attachment0 = seatAttachment
	beam.Attachment1 = playerAttachment

	-- 将Beam放到座位上
	beam.Parent = targetSeat

	-- 保存引导箭头数据
	playerArrows[playerId] = {
		beam = beam,
		attachmentOnSeat = seatAttachment,
		attachmentOnPlayer = playerAttachment
	}

	return true
end

-- ============================================
-- 销毁引导箭头
-- ============================================

function TutorialGuideManager:hideGuidingArrow(player)
	if not player then return false end

	local playerId = player.UserId

	if not playerArrows[playerId] then
		return false
	end

	local arrowData = playerArrows[playerId]

	-- 销毁Beam
	if arrowData.beam and arrowData.beam.Parent then
		pcall(function()
			arrowData.beam:Destroy()
		end)
	end

	-- 销毁座位上的Attachment
	if arrowData.attachmentOnSeat and arrowData.attachmentOnSeat.Parent then
		pcall(function()
			arrowData.attachmentOnSeat:Destroy()
		end)
	end

	-- 销毁玩家身上的Attachment
	if arrowData.attachmentOnPlayer and arrowData.attachmentOnPlayer.Parent then
		pcall(function()
			arrowData.attachmentOnPlayer:Destroy()
		end)
	end

	-- 清理缓存
	playerArrows[playerId] = nil

	return true
end

-- ============================================
-- 处理玩家离开时的清理
-- ============================================

function TutorialGuideManager:cleanupOnPlayerLeaving(player)
	if not player then return end

	local playerId = player.UserId

	-- 清理座椅引导箭头
	if playerArrows[playerId] then
		self:hideGuidingArrow(player)
	end

	-- 🔧 V1.6新增：清理Portal引导箭头
	if portalArrows[playerId] then
		self:hidePortalArrow(player)
	end
end

-- ============================================
-- 处理Character更新时的箭头重建
-- ============================================

function TutorialGuideManager:onCharacterRespawned(player, targetSeat)
	if not player then return end

	-- 先销毁旧箭头
	self:hideGuidingArrow(player)

	-- 等待新Character加载
	wait(0.5)

	-- 重新创建箭头
	self:showGuidingArrow(player, targetSeat)
end

-- ============================================
-- 获取引导箭头状态（调试用）
-- ============================================

function TutorialGuideManager:getArrowStatus(player)
	if not player then return nil end

	local playerId = player.UserId

	if not playerArrows[playerId] then
		return nil
	end

	local arrowData = playerArrows[playerId]

	return {
		playerId = playerId,
		playerName = player.Name,
		hasBeam = arrowData.beam ~= nil and arrowData.beam.Parent ~= nil,
		hasSeatAttachment = arrowData.attachmentOnSeat ~= nil and arrowData.attachmentOnSeat.Parent ~= nil,
		hasPlayerAttachment = arrowData.attachmentOnPlayer ~= nil and arrowData.attachmentOnPlayer.Parent ~= nil
	}
end

-- ============================================
-- 🔧 V1.6新增：创建Portal指引箭头
-- ============================================

function TutorialGuideManager:showPortalArrow(player, portalAttachment)
	if not player or not player:IsA("Player") then
		warn("[TutorialGuideManager] 无效的玩家对象")
		return false
	end

	-- 🔧 关键修复：重新获取最新的Character，确保不是旧Character
	local character = player.Character
	if not character then
		warn("[TutorialGuideManager] 玩家角色不存在")
		return false
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		warn("[TutorialGuideManager] 玩家HumanoidRootPart不存在")
		return false
	end

	if not portalAttachment or not portalAttachment:IsA("Attachment") then
		warn("[TutorialGuideManager] 无效的Portal Attachment对象")
		return false
	end

	local playerId = player.UserId

	-- 🔧 幂等保护：检查是否已有Portal箭头
	if portalArrows[playerId] then
		return false
	end


	-- 获取Arrow模板
	local arrowFolder = ReplicatedStorage:FindFirstChild("Arrow")
	if not arrowFolder then
		warn("[TutorialGuideManager] ReplicatedStorage中找不到Arrow文件夹")
		return false
	end

	local arrowABeam = arrowFolder:FindFirstChild("Arrow_A")
	if not arrowABeam or not arrowABeam:FindFirstChild("Beam") then
		warn("[TutorialGuideManager] Arrow_A中找不到Beam")
		return false
	end


	-- 克隆Beam
	local beamTemplate = arrowABeam:FindFirstChild("Beam")

	local beam = beamTemplate:Clone()

	-- 在玩家身上创建Attachment02
	local playerAttachment = Instance.new("Attachment")
	playerAttachment.Name = "PortalArrowAttachment"
	playerAttachment.Parent = humanoidRootPart

	-- 配置Beam的连接点：Attachment0指向Portal，Attachment1指向玩家
	beam.Attachment0 = portalAttachment
	beam.Attachment1 = playerAttachment

	-- 🔧 关键修复：强制设置Beam为可见状态
	-- 问题：克隆的Beam可能有透明度序列，导致部分透明
	beam.Enabled = true
	beam.Transparency = NumberSequence.new(0.2)  -- 设置为20%透明度（80%可见）
	beam.FaceCamera = true  -- 确保面向相机
	beam.Width0 = 2  -- 设置起始宽度
	beam.Width1 = 2  -- 设置结束宽度

	-- 🔧 修复：使用模板Beam的原始颜色，不要硬编码红色
	-- 保持与初始引导Beam相同的颜色属性
	if beamTemplate.Color then
		beam.Color = beamTemplate.Color
	end


	-- 🔧 关键修复：确保Beam没有其他Parent
	-- 如果Beam从某个地方克隆而来可能仍然有Parent引用
	-- 必须先将其从当前Parent移除
	if beam.Parent then
		beam.Parent = nil
	end


	-- 将Beam放到Workspace中，确保可见
	-- 🔧 修复：不要放在Portal下，直接放在Workspace或ReplicatedStorage中
	beam.Parent = game:GetService("Workspace")

	-- 保存Portal箭头数据
	portalArrows[playerId] = {
		beam = beam,
		attachmentOnPlayer = playerAttachment
	}

	return true
end

-- ============================================
-- 🔧 V1.6新增：销毁Portal指引箭头
-- ============================================

function TutorialGuideManager:hidePortalArrow(player)
	if not player then return false end

	local playerId = player.UserId

	if not portalArrows[playerId] then
		return false
	end

	local arrowData = portalArrows[playerId]

	-- 销毁Beam
	if arrowData.beam and arrowData.beam.Parent then
		pcall(function()
			arrowData.beam:Destroy()
		end)
	end

	-- 销毁玩家身上的Attachment
	if arrowData.attachmentOnPlayer and arrowData.attachmentOnPlayer.Parent then
		pcall(function()
			arrowData.attachmentOnPlayer:Destroy()
		end)
	end

	-- 清理缓存
	portalArrows[playerId] = nil

	return true
end

-- ============================================
-- 🔧 V2.0新增：显示提示消息
-- ============================================

function TutorialGuideManager:showMessage(player, message)
	if not player or not player:IsA("Player") then
		warn("[TutorialGuideManager] 无效的玩家对象")
		return false
	end

	if not message or type(message) ~= "string" then
		warn("[TutorialGuideManager] 无效的消息内容")
		return false
	end

	-- 通过RemoteEvent发送消息给客户端显示
	-- 假设已有一个RemoteEvent用于GUI通信
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local showMessageEvent = ReplicatedStorage:FindFirstChild("ShowTutorialMessageRemote")

	if showMessageEvent then
		-- 如果RemoteEvent存在，使用它
		pcall(function()
			showMessageEvent:FireClient(player, message)
		end)
	else
		-- 降级处理：在服务器console输出
		print("[TutorialGuideManager] 向玩家 " .. player.Name .. " 显示消息: " .. message)
	end

	return true
end

return TutorialGuideManager
