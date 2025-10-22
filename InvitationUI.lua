-- 脚本名称: InvitationUI
-- 脚本作用: 邀请好友界面的客户端交互逻辑
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local InvitationUI = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local inviteEvent = remoteEventsFolder:WaitForChild("InviteEvent")

-- UI引用（等待从StarterGui复制到PlayerGui）
local inviteScreenGui = nil
local inviteBg = nil
local closeButton = nil
local inviteButton = nil
local countdownTime = nil
local scrollingFrame = nil

-- 奖励项模板
local rewardTemplate1 = nil
local rewardTemplate3 = nil
local rewardTemplate5 = nil

-- UI状态
local uiState = {
	invitedCount = 0,
	claimedRewards = {}
}

-- ============================================
-- 获取UI引用
-- ============================================

local function getInviteUI()
	-- 等待Invite GUI从StarterGui复制到PlayerGui
	local inviteGui = playerGui:WaitForChild("Invite", 10)
	if not inviteGui then
		warn("❌ [InvitationUI] 未找到Invite GUI，PlayerGui中的内容:")
		for _, child in pairs(playerGui:GetChildren()) do
			warn("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return false
	end

	print("[InvitationUI] ✓ 找到Invite GUI")
	inviteScreenGui = inviteGui
	inviteBg = inviteScreenGui:WaitForChild("InvitBg", 5)
	if not inviteBg then
		warn("❌ [InvitationUI] 未找到Invite GUI中的InvitBg Frame")
		return false
	end

	print("[InvitationUI] ✓ 找到InvitBg")
	closeButton = inviteBg:WaitForChild("CloseButton", 5)
	inviteButton = inviteBg:WaitForChild("InviteButton", 5)
	countdownTime = inviteBg:WaitForChild("CountDownTime", 5)
	scrollingFrame = inviteBg:WaitForChild("ScrollingFrame", 5)

	if not scrollingFrame then
		warn("❌ [InvitationUI] 未找到InvitBg中的ScrollingFrame")
		return false
	end

	print("[InvitationUI] ✓ 找到ScrollingFrame")
	rewardTemplate1 = scrollingFrame:WaitForChild("InviteReward1", 5)
	rewardTemplate3 = scrollingFrame:WaitForChild("InviteReward3", 5)
	rewardTemplate5 = scrollingFrame:WaitForChild("InviteReward5", 5)

	print("[InvitationUI] ✓ 所有UI元素加载完成")
	return true
end

-- ============================================
-- 倒计时显示
-- ============================================

local function updateCountdown()
	spawn(function()
		while inviteScreenGui and inviteScreenGui.Enabled do
			-- 请求服务端时间
			inviteEvent:FireServer("requestStatus", {})
			task.wait(1)
		end
	end)
end

-- 监听状态响应
inviteEvent.OnClientEvent:Connect(function(action, data)
	if action == "statusResponse" then
		uiState.invitedCount = data.invitedCount
		uiState.claimedRewards = data.claimedRewards

		-- 更新进度显示
		InvitationUI.updateProgressDisplay()
		InvitationUI.updateRedPoint()

		-- 计算倒计时
		if data.nextResetTime then
			local remaining = data.nextResetTime - os.time()
			if remaining > 0 then
				local hours = math.floor(remaining / 3600)
				local minutes = math.floor((remaining % 3600) / 60)
				local seconds = remaining % 60

				if countdownTime then
					countdownTime.Text = string.format("Refresh in: %02d:%02d:%02d", hours, minutes, seconds)
				end
			else
				if countdownTime then
					countdownTime.Text = "Refresh in: 00:00:00"
				end
			end
		end

	elseif action == "rewardSuccess" then
		-- 奖励领取成功
		InvitationUI.onRewardSuccess(data.rewardId)

	elseif action == "rewardFailed" then
		-- 奖励领取失败
		InvitationUI.showNotification(data.reason)
	end
end)

-- ============================================
-- 更新进度显示
-- ============================================

function InvitationUI.updateProgressDisplay()
	if not rewardTemplate1 or not rewardTemplate3 or not rewardTemplate5 then
		return
	end

	-- 更新reward_1
	InvitationUI.updateRewardProgress(rewardTemplate1, "reward_1", 1)

	-- 更新reward_3
	InvitationUI.updateRewardProgress(rewardTemplate3, "reward_3", 3)

	-- 更新reward_5
	InvitationUI.updateRewardProgress(rewardTemplate5, "reward_5", 5)
end

function InvitationUI.updateRewardProgress(rewardFrame, rewardId, requiredCount)
	if not rewardFrame then return end

	local progressLabel = rewardFrame:FindFirstChild("Prograss")
	local claimButton = rewardFrame:FindFirstChild("Claim")

	if progressLabel then
		progressLabel.Text = uiState.invitedCount .. "/" .. requiredCount
	end

	if claimButton then
		local textLabel = claimButton:FindFirstChild("Text")

		if uiState.claimedRewards[rewardId] then
			-- 已领取
			if textLabel then
				textLabel.Text = "Claimed"
			end
		else
			-- 未领取
			if textLabel then
				textLabel.Text = "Claim"
			end
		end

		-- 设置点击事件（避免重复连接）
		if not claimButton:FindFirstChild("_InviteConnected") then
			claimButton.MouseButton1Click:Connect(function()
				-- 再次检查是否可以领取（防止已领取后仍可点击）
				local currentCanClaim = uiState.invitedCount >= requiredCount and not uiState.claimedRewards[rewardId]
				if currentCanClaim then
					inviteEvent:FireServer("claimReward", {rewardId = rewardId})
				end
			end)

			-- 标记已连接
			local marker = Instance.new("BoolValue")
			marker.Name = "_InviteConnected"
			marker.Parent = claimButton
		end
	end
end

-- ============================================
-- 奖励领取成功处理
-- ============================================

function InvitationUI.onRewardSuccess(rewardId)
	-- 更新UI状态
	uiState.claimedRewards[rewardId] = true
	InvitationUI.updateProgressDisplay()
	InvitationUI.updateRedPoint()

	-- 播放成功动画
	InvitationUI.showNotification("奖励已领取!")
end

-- ============================================
-- 更新红点提示
-- ============================================

function InvitationUI.updateRedPoint()
	if not playerGui then return end

	local menuGui = playerGui:FindFirstChild("Menu")
	if not menuGui then return end

	local inviteButtonUI = menuGui:FindFirstChild("ImageButtonInvite")
	if not inviteButtonUI then return end

	local redPoint = inviteButtonUI:FindFirstChild("RedPoint")
	if not redPoint then return end

	-- 检查是否有未领取的奖励
	local hasUnclaimedRewards = false
	for rewardId, claimed in pairs(uiState.claimedRewards) do
		if not claimed then
			local requiredCount = 0
			if rewardId == "reward_1" then requiredCount = 1
			elseif rewardId == "reward_3" then requiredCount = 3
			elseif rewardId == "reward_5" then requiredCount = 5
			end

			if uiState.invitedCount >= requiredCount then
				hasUnclaimedRewards = true
				break
			end
		end
	end

	redPoint.Visible = hasUnclaimedRewards
end

-- ============================================
-- 显示通知
-- ============================================

function InvitationUI.showNotification(message)
	-- 查找通知系统
	local notification = playerGui:FindFirstChild("ShowNotification")
	if notification then
		-- 调用现有的通知系统
		local notificationEvent = remoteEventsFolder:FindFirstChild("ShowNotification")
		if notificationEvent then
			notificationEvent:FireServer(message)
		end
	else
		-- 简单的控制台输出
		print("[Notification] " .. message)
	end
end

-- ============================================
-- 关闭按钮
-- ============================================

local function setupCloseButton()
	if closeButton then
		closeButton.MouseButton1Click:Connect(function()
			if inviteScreenGui then
				inviteScreenGui.Enabled = false
			end
		end)
	end
end

-- ============================================
-- 邀请按钮 - 调出 Roblox 系统邀请页面
-- ============================================

local function setupInviteButton()
	if inviteButton then
		inviteButton.MouseButton1Click:Connect(function()
			-- 尝试调用 Roblox 系统邀请功能
			local success = pcall(function()
				local guiService = game:GetService("GuiService")
				-- 尝试打开系统邀请对话框
				guiService:OpenInvitePrompt()
				print("[InvitationUI] ✓ 已打开系统邀请页面")
			end)

			-- 如果系统邀请失败，显示邀请链接供手动分享
			if not success then
				pcall(function()
					inviteEvent:FireServer("generateLink", {})
					print("[InvitationUI] 系统邀请不可用，已生成邀请链接")
				end)
			end
		end)
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
	wait(2)

	-- 获取UI引用
	if not getInviteUI() then
		warn("[InvitationUI] 初始化失败，无法找到Invite UI")
		return
	end

	-- 设置按钮事件
	setupCloseButton()
	setupInviteButton()

	-- 初始时请求状态
	inviteEvent:FireServer("requestStatus", {})

	-- 启动倒计时更新
	updateCountdown()

	-- 监听屏幕启用事件
	if inviteScreenGui then
		inviteScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if inviteScreenGui.Enabled then
				-- 界面打开时更新状态
				inviteEvent:FireServer("requestStatus", {})
				updateCountdown()
			end
		end)
	end

	print("[InvitationUI] ✓ 初始化完成")
end

initialize()

return InvitationUI
