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
local friendAdd = nil
local addNum = nil

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
	if not menuGui then return end

	-- 创建或获取FriendAdd框架
	friendAdd = menuGui:FindFirstChild("FriendAdd")
	if not friendAdd then
		friendAdd = Instance.new("Frame")
		friendAdd.Name = "FriendAdd"
		friendAdd.Size = UDim2.new(0, 80, 0, 30)
		friendAdd.Position = UDim2.new(0, 10, 0, 10)
		friendAdd.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		friendAdd.BackgroundTransparency = 0.5
		friendAdd.Parent = menuGui
	end

	-- 创建或获取AddNum标签
	addNum = friendAdd:FindFirstChild("AddNum")
	if not addNum then
		addNum = Instance.new("TextLabel")
		addNum.Name = "AddNum"
		addNum.Size = UDim2.new(1, 0, 1, 0)
		addNum.BackgroundTransparency = 1
		addNum.TextColor3 = Color3.fromRGB(255, 200, 0)
		addNum.TextScaled = true
		addNum.Font = Enum.Font.GothamBold
		addNum.Text = "+0%"
		addNum.Parent = friendAdd
	end

	-- V1.8: 监听邀请事件更新红点和好友加成
	inviteEvent.OnClientEvent:Connect(function(action, data)
		if action == "statusResponse" then
			-- 更新红点显示
			if redPoint then
				redPoint.Visible = data.hasUnclaimedRewards or false
			end

			-- V1.8: 新增：更新好友加成显示（按策划稿显示百分比）
			if data.friendCount and data.friendCount > 0 then
				InviteMenuController.updateFriendBonus(data.friendCount * 0.2)
			else
				InviteMenuController.updateFriendBonus(0)
			end
		end
	end)

	-- V1.8: 新增：初始化时请求一次邀请状态，获取好友加成
	inviteEvent:FireServer("requestStatus", {})
end

-- ============================================
-- 更新好友加成显示
-- ============================================

function InviteMenuController.updateFriendBonus(bonus)
	if addNum then
		-- V1.8: 按策划稿显示百分比格式（例如 +0%, +20%, +40% 等）
		local percentageBonus = math.floor(bonus * 100)
		addNum.Text = string.format("+%d%%", percentageBonus)
	end
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
