-- 脚本名称: InviteMenuController
-- 脚本作用: 主菜单中的邀请按钮控制和好友加成显示
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local InviteMenuController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local inviteEvent = remoteEventsFolder:WaitForChild("InviteEvent")

-- UI引用
local menuGui = nil
local imageButtonInvite = nil
local redPoint = nil
-- 🔧 修复：移除好友加成UI相关引用
-- local friendAdd = nil
-- local addNum = nil

-- ============================================
-- 获取菜单UI引用
-- ============================================

local function getMenuUI()
	-- 等待Menu GUI从StarterGui复制到PlayerGui
	local menu = playerGui:WaitForChild("Menu", 10)
	if not menu then
		warn("[InviteMenuController] 未找到Menu GUI")
		return false
	end

	menuGui = menu
	imageButtonInvite = menuGui:FindFirstChild("ImageButtonInvite")

	if not imageButtonInvite then
		warn("[InviteMenuController] 未找到ImageButtonInvite按钮")
		return false
	end

	return true
end

-- ============================================
-- 初始化邀请按钮
-- ============================================

local function initializeInviteButton()
	if not imageButtonInvite then return end

	-- 创建或获取RedPoint
	redPoint = imageButtonInvite:FindFirstChild("RedPoint")
	if not redPoint then
		redPoint = Instance.new("ImageLabel")
		redPoint.Name = "RedPoint"
		redPoint.Image = "rbxasset://textures/ui/notification.png"  -- 红点图标
		redPoint.Size = UDim2.new(0, 20, 0, 20)
		redPoint.Position = UDim2.new(1, -5, 0, -5)
		redPoint.BackgroundTransparency = 1
		redPoint.Visible = false
		redPoint.Parent = imageButtonInvite
	end

	-- 点击打开邀请界面
	imageButtonInvite.MouseButton1Click:Connect(function()
		local inviteScreenGui = playerGui:FindFirstChild("Invite")
		if inviteScreenGui then
			inviteScreenGui.Enabled = not inviteScreenGui.Enabled
		end
	end)
end

-- ============================================
-- 初始化好友加成显示
-- ============================================

local function initializeFriendAddDisplay()
	-- 🔧 修复：完全移除好友加成显示功能
	-- 好友加成功能已被移除，不再需要UI显示

	-- V1.8: 监听邀请事件更新红点
	inviteEvent.OnClientEvent:Connect(function(action, data)
		if action == "statusResponse" then
			-- 更新红点显示
			if redPoint then
				redPoint.Visible = data.hasUnclaimedRewards or false
			end
		end
	end)

	-- V1.8: 新增：初始化时请求一次邀请状态
	inviteEvent:FireServer("requestStatus", {})
end

-- ============================================
-- 更新好友加成显示（已废弃）
-- ============================================

function InviteMenuController.updateFriendBonus(bonus)
	-- 🔧 修复：好友加成功能已移除，此函数保留仅为向后兼容
	-- 不再执行任何UI更新
end

-- ============================================
-- 初始化
-- ============================================

local function initialize()
	-- 等待玩家角色完全加载
	if not player.Character then
		player.CharacterAdded:Wait()
	end

	-- 额外等待确保UI完全复制
	task.wait(2)

	-- 获取UI引用
	if not getMenuUI() then
		warn("[InviteMenuController] 初始化失败，无法找到Menu UI")
		return
	end

	-- 初始化各个组件
	initializeInviteButton()
	initializeFriendAddDisplay()
end

initialize()

return InviteMenuController
