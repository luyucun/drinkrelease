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
	dailyInvitedCount = 0,  -- 🔧 修复：改用dailyInvitedCount
	claimedRewards = {},
	nextResetTime = 0       -- 🔧 新增：缓存服务器的下次重置时间
}

-- ============================================
-- 获取UI引用
-- ============================================

local function getInviteUI()
	-- 等待Invite GUI从StarterGui复制到PlayerGui
	local inviteGui = playerGui:WaitForChild("Invite", 10)
	if not inviteGui then
		warn("[InvitationUI] 未找到Invite GUI")
		return false
	end

	inviteScreenGui = inviteGui
	inviteBg = inviteScreenGui:WaitForChild("InvitBg", 5)
	if not inviteBg then
		warn("[InvitationUI] 未找到InvitBg Frame")
		return false
	end

	closeButton = inviteBg:WaitForChild("CloseButton", 5)
	inviteButton = inviteBg:WaitForChild("InviteButton", 5)
	countdownTime = inviteBg:WaitForChild("CountDownTime", 5)
	scrollingFrame = inviteBg:WaitForChild("ScrollingFrame", 5)

	if not scrollingFrame then
		warn("[InvitationUI] 未找到ScrollingFrame")
		return false
	end

	rewardTemplate1 = scrollingFrame:WaitForChild("InviteReward1", 5)
	rewardTemplate3 = scrollingFrame:WaitForChild("InviteReward3", 5)
	rewardTemplate5 = scrollingFrame:WaitForChild("InviteReward5", 5)

	return true
end

-- ============================================
-- 倒计时显示（客户端本地计算）
-- ============================================

local countdownRunning = false

local function updateCountdown()
	-- 🔧 修复：避免重复启动倒计时
	if countdownRunning then return end
	countdownRunning = true

	spawn(function()
		while inviteScreenGui and inviteScreenGui.Enabled do
			if uiState.nextResetTime and uiState.nextResetTime > 0 then
				-- 🔧 修复：客户端本地计算倒计时，不再频繁请求服务器
				local remaining = uiState.nextResetTime - os.time()

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

					-- 🔧 倒计时结束，请求服务器刷新状态
					inviteEvent:FireServer("requestStatus", {})
				end
			end

			task.wait(1)  -- 每秒更新一次UI
		end

		countdownRunning = false
	end)
end

-- 监听状态响应
inviteEvent.OnClientEvent:Connect(function(action, data)
	if action == "statusResponse" then
		-- 🔧 修复：更新为dailyInvitedCount
		uiState.dailyInvitedCount = data.dailyInvitedCount or 0
		uiState.claimedRewards = data.claimedRewards

		-- 更新进度显示
		InvitationUI.updateProgressDisplay()
		InvitationUI.updateRedPoint()

		-- 🔧 修复：缓存服务器的下次重置时间，用于客户端本地倒计时
		if data.nextResetTime then
			uiState.nextResetTime = data.nextResetTime

			-- 立即更新一次倒计时显示
			local remaining = uiState.nextResetTime - os.time()
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
		-- 🔧 修复：使用dailyInvitedCount而不是invitedCount
		progressLabel.Text = uiState.dailyInvitedCount .. "/" .. requiredCount
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
				-- 🔧 修复：使用dailyInvitedCount判断
				local currentCanClaim = uiState.dailyInvitedCount >= requiredCount and not uiState.claimedRewards[rewardId]
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

			-- 🔧 修复：使用dailyInvitedCount而不是invitedCount
			if uiState.dailyInvitedCount >= requiredCount then
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
	-- 简单的控制台输出
	print("[Notification] " .. message)
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
			-- 🔧 V2.6 修复：使用官方推荐的 SocialService:PromptGameInvite()
			-- 替换已过时的 GuiService:OpenInvitePrompt()（仅在主机端可用）
			-- 新 API 支持 PC、手机、主机等所有平台
			local socialService = game:GetService("SocialService")

			local success, err = pcall(function()
				socialService:PromptGameInvite(player)
			end)

			if not success then
				warn("[InvitationUI] 打开邀请弹窗失败:", err)
				InvitationUI.showNotification("邀请功能暂时不可用")
			else
				-- 🔧 V2.1 新增：通知服务器"我发出了邀请"
				-- 服务器会记录这个待处理的邀请，5分钟内加入的玩家会被认定为邀请成功
				inviteEvent:FireServer("inviteSent", {})
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
end

initialize()

return InvitationUI
