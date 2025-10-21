-- 脚本名称: TutorialGuideManager
-- 脚本作用: 管理新手教程的引导箭头系统
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local TutorialGuideManager = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- 引导箭头跟踪
local playerArrows = {} -- {[playerId] = {beam, attachmentOnSeat, attachmentOnPlayer}}

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
		print("[TutorialGuideManager] 玩家 " .. player.Name .. " 已有引导箭头，跳过重复创建")
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

	print("[TutorialGuideManager] ✓ 为玩家 " .. player.Name .. " 创建了引导箭头")

	return true
end

-- ============================================
-- 销毁引导箭头
-- ============================================

function TutorialGuideManager:hideGuidingArrow(player)
	if not player then return false end

	local playerId = player.UserId

	if not playerArrows[playerId] then
		print("[TutorialGuideManager] 玩家 " .. player.Name .. " 没有引导箭头，无需销毁")
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

	print("[TutorialGuideManager] ✓ 为玩家 " .. player.Name .. " 销毁了引导箭头")

	return true
end

-- ============================================
-- 处理玩家离开时的清理
-- ============================================

function TutorialGuideManager:cleanupOnPlayerLeaving(player)
	if not player then return end

	local playerId = player.UserId

	if playerArrows[playerId] then
		self:hideGuidingArrow(player)
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

return TutorialGuideManager
