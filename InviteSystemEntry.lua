-- 脚本名称: InviteSystemEntry
-- 脚本作用: 邀请系统的入口和初始化
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- 等待必要的系统初始化
task.wait(1)

-- 初始化InviteManager
local InviteManager = require(script.Parent:WaitForChild("InviteManager"))
InviteManager.initialize()

-- 初始化FriendsService
local FriendsService = require(script.Parent:WaitForChild("FriendsService"))
FriendsService.initialize()

-- ============================================
-- 添加简单的调试命令
-- ============================================

_G.InviteDebug = {
	-- 🔧 新增：模拟真实邀请（测试邀请记录功能）
	simulateInvite = function(inviterName, invitedName)
		local inviter = Players:FindFirstChild(inviterName)
		local invited = Players:FindFirstChild(invitedName)

		if not inviter or not invited then
			return
		end

		if _G.InviteManager then
			_G.InviteManager:recordInvitedPlayer(inviter.UserId, invited.UserId)
		end
	end,

	-- 直接增加玩家的邀请计数（使用假数据）
	addInviteCount = function(playerName, count)
		local player = Players:FindFirstChild(playerName)
		if not player then
			return
		end

		count = count or 1

		if _G.InviteManager then
			local playerData = _G.InviteManager:loadPlayerInviteData(player)
			-- 🔧 修复：改用dailyInvitedCount
			playerData.dailyInvitedCount = playerData.dailyInvitedCount + count
			_G.InviteManager:savePlayerInviteData(player, playerData)
		end
	end,

	-- 查看玩家邀请状态
	showStatus = function(playerName)
		local player = Players:FindFirstChild(playerName)
		if not player then
			return
		end

		if _G.InviteManager then
			_G.InviteManager:getInviteStatus(player)
		end
	end,

	-- 重置玩家邀请数据
	reset = function(playerName)
		local player = Players:FindFirstChild(playerName)
		if not player then
			return
		end

		if _G.InviteManager then
			-- 🔧 修复：使用新的数据结构
			local defaultData = {
				dailyInvitedCount = 0,
				lastResetTime = 0,
				claimedRewards = {
					reward_1 = false,
					reward_3 = false,
					reward_5 = false
				},
				dailyInvitedPlayers = {}
			}
			_G.InviteManager:savePlayerInviteData(player, defaultData)
		end
	end,

	-- 🔧 修复：移除已废弃的clearAllDaily等函数，因为新数据结构已自动处理
}
