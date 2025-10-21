-- 脚本名称: TutorialEnvironmentManager
-- 脚本作用: 管理新手教程场景的环境清理，特别是座位移除
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local TutorialEnvironmentManager = {}

-- 缓存教程场景中需要清理的座位
local tutorialSeat2 = nil
local seatRemoved = false

-- ============================================
-- 初始化教程环境座位缓存
-- ============================================

function TutorialEnvironmentManager:initializeTutorialSeat(chair2Model)
	if not chair2Model then
		warn("[TutorialEnvironmentManager] 传入的Chair2模型为空")
		return false
	end

	-- 获取Chair2下的Seat
	local seat = chair2Model:FindFirstChild("Seat")
	if not seat then
		warn("[TutorialEnvironmentManager] Chair2下找不到Seat")
		return false
	end

	tutorialSeat2 = seat
	seatRemoved = false
	print("[TutorialEnvironmentManager] ✓ 已缓存教程场景Chair2 Seat: " .. seat.Name)
	return true
end

-- ============================================
-- 移除教程座位
-- ============================================

function TutorialEnvironmentManager:removeTutorialSeat()
	-- 🔧 幂等检查：如果已经移除过，直接返回
	if seatRemoved then
		print("[TutorialEnvironmentManager] 座位已经移除过，跳过重复移除")
		return true
	end

	-- 验证座位引用是否有效
	if not tutorialSeat2 or not tutorialSeat2.Parent then
		warn("[TutorialEnvironmentManager] 座位引用无效或已被销毁，无法移除")
		seatRemoved = true  -- 标记为已移除（实际上是不存在）
		return false
	end

	-- 销毁座位
	local seatName = tutorialSeat2.Name
	local parentName = tutorialSeat2.Parent.Name

	pcall(function()
		tutorialSeat2:Destroy()
	end)

	-- 标记为已移除
	seatRemoved = true
	tutorialSeat2 = nil

	print("[TutorialEnvironmentManager] ✓ 已移除教程座位: " .. parentName .. "/" .. seatName)
	print("[TutorialEnvironmentManager] → 玩家将无法再次入座，必须前往Portal")

	-- 🔧 V1.6修复: 游戏结束时重新定位Portal到指定坐标
	local PortalTransportManager = _G.PortalTransportManager
	if PortalTransportManager then
		-- 将Portal移动到指定坐标：30.506, 1.509, -30.38
		PortalTransportManager:repositionPortal(30.506, 1.509, -30.38)
		print("[TutorialEnvironmentManager] ✓ 已重新定位Portal到教程完成坐标")
	else
		warn("[TutorialEnvironmentManager] PortalTransportManager不可用，无法重新定位Portal")
	end

	return true
end

-- ============================================
-- 检查座位是否已被移除
-- ============================================

function TutorialEnvironmentManager:isSeatRemoved()
	return seatRemoved
end

-- ============================================
-- 获取座位状态（调试用）
-- ============================================

function TutorialEnvironmentManager:getSeatStatus()
	return {
		cached = tutorialSeat2 ~= nil,
		removed = seatRemoved,
		seatValid = tutorialSeat2 ~= nil and tutorialSeat2.Parent ~= nil,
		seatName = tutorialSeat2 and tutorialSeat2.Name or "nil"
	}
end

return TutorialEnvironmentManager
