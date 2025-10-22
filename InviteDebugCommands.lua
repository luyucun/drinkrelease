-- 脚本名称: InviteDebugCommands
-- 脚本作用: 邀请系统的调试命令
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local InviteDebugCommands = {}

local Players = game:GetService("Players")

-- ============================================
-- 调试命令处理
-- ============================================

-- 监听聊天或控制台命令
local function setupDebugCommands()
	-- 这里可以集成与游戏现有的命令系统

	-- 创建一个全局函数供调试使用
	_G.InviteDebug = {
		-- 模拟邀请成功
		simulateInvite = function(inviterName, invitedName)
			local inviter = Players:FindFirstChild(inviterName)
			local invited = Players:FindFirstChild(invitedName)

			if not inviter or not invited then
				print("❌ 玩家不存在")
				return
			end

			if _G.InviteManager then
				_G.InviteManager:recordInvitedPlayer(inviter.UserId, invited.UserId)
				print("✓ 已模拟邀请: " .. inviterName .. " 邀请了 " .. invitedName)
			end
		end,

		-- 查看玩家邀请状态
		showStatus = function(playerName)
			local player = Players:FindFirstChild(playerName)
			if not player then
				print("❌ 玩家不存在")
				return
			end

			if _G.InviteManager then
				local status = _G.InviteManager:getInviteStatus(player)
				print("═══════════════════════════════════")
				print("玩家: " .. playerName)
				print("邀请人数: " .. status.invitedCount)
				print("已领取奖励:")
				for rewardId, claimed in pairs(status.claimedRewards) do
					print("  " .. rewardId .. ": " .. (claimed and "✓" or "✗"))
				end
				print("有未领取奖励: " .. (status.hasUnclaimedRewards and "是" or "否"))
				print("═══════════════════════════════════")
			end
		end,

		-- 重置指定玩家的邀请数据
		resetPlayer = function(playerName)
			local player = Players:FindFirstChild(playerName)
			if not player then
				print("❌ 玩家不存在")
				return
			end

			if _G.InviteManager then
				local defaultData = {
					invitedCount = 0,
					dailyInvitedCount = 0,
					lastResetTime = 0,
					claimedRewards = {
						reward_1 = false,
						reward_3 = false,
						reward_5 = false
					},
					invitedPlayerIds = {},
					inviteLinks = {}
				}
				_G.InviteManager:savePlayerInviteData(player, defaultData)
				print("✓ 已重置玩家 " .. playerName .. " 的邀请数据")
			end
		end,

		-- 重置所有在线玩家的邀请数据
		resetAll = function()
			if _G.InviteManager then
				for _, player in pairs(Players:GetPlayers()) do
					local defaultData = {
						invitedCount = 0,
						dailyInvitedCount = 0,
						lastResetTime = 0,
						claimedRewards = {
							reward_1 = false,
							reward_3 = false,
							reward_5 = false
						},
						invitedPlayerIds = {},
						inviteLinks = {}
					}
					_G.InviteManager:savePlayerInviteData(player, defaultData)
				end
				print("✓ 已重置所有在线玩家的邀请数据")
			end
		end,

		-- 生成邀请链接
		generateLink = function(playerName)
			local player = Players:FindFirstChild(playerName)
			if not player then
				print("❌ 玩家不存在")
				return
			end

			if _G.InviteManager then
				local link = _G.InviteManager:generateInviteLink(player)
				print("邀请链接: " .. link)
				print("完整URL (示例): https://www.roblox.com/games/" .. game.PlaceId .. "?" .. link)
			end
		end,

		-- 显示所有在线玩家的邀请信息
		listAll = function()
			if _G.InviteManager then
				print("═══════════════════════════════════")
				print("在线玩家邀请信息概览")
				print("═══════════════════════════════════")
				for _, player in pairs(Players:GetPlayers()) do
					local status = _G.InviteManager:getInviteStatus(player)
					print(player.Name .. ": 邀请" .. status.invitedCount .. "人")
				end
				print("═══════════════════════════════════")
			end
		end,

		-- 手动发放奖励（用于测试）
		grantReward = function(playerName, rewardId)
			local player = Players:FindFirstChild(playerName)
			if not player then
				print("❌ 玩家不存在")
				return
			end

			if _G.InviteManager then
				local success, message = _G.InviteManager:claimReward(player, rewardId)
				if success then
					print("✓ 已发放奖励 " .. rewardId .. " 给玩家 " .. playerName)
				else
					print("❌ 发放奖励失败: " .. message)
				end
			end
		end,

		-- 查看好友关系
		showFriends = function(playerName)
			local player = Players:FindFirstChild(playerName)
			if not player then
				print("❌ 玩家不存在")
				return
			end

			if _G.FriendsService then
				local friends = _G.FriendsService:getFriendsListCached(player)
				print("═══════════════════════════════════")
				print("玩家 " .. playerName .. " 的好友列表:")
				for _, friendId in ipairs(friends) do
					local friendPlayer = Players:GetPlayerByUserId(friendId)
					if friendPlayer then
						print("  - " .. friendPlayer.Name .. " (#" .. friendId .. ")")
					else
						print("  - 玩家#" .. friendId .. " (离线)")
					end
				end
				print("═══════════════════════════════════")
			end
		end
	}

	print("[InviteDebugCommands] ✓ 调试命令已注册")
	print("使用方法: _G.InviteDebug.simulateInvite('PlayerA', 'PlayerB')")
	print("          _G.InviteDebug.showStatus('PlayerName')")
	print("          _G.InviteDebug.generateLink('PlayerName')")
	print("          _G.InviteDebug.listAll()")
end

-- 初始化
setupDebugCommands()

return InviteDebugCommands
