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
	-- 直接增加玩家的邀请计数（使用假数据）
	addInviteCount = function(playerName, count)
		local player = Players:FindFirstChild(playerName)
		if not player then
			print("❌ 玩家不存在: " .. playerName)
			return
		end

		count = count or 1

		if _G.InviteManager then
			local playerData = _G.InviteManager:loadPlayerInviteData(player)
			playerData.invitedCount = playerData.invitedCount + count
			_G.InviteManager:savePlayerInviteData(player, playerData)
			print("✓ 已为玩家 " .. playerName .. " 增加 " .. count .. " 个邀请计数")
			print("  当前邀请总数: " .. playerData.invitedCount)
		end
	end,

	-- 查看玩家邀请状态
	showStatus = function(playerName)
		local player = Players:FindFirstChild(playerName)
		if not player then
			print("❌ 玩家不存在: " .. playerName)
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

	-- 重置玩家邀请数据
	reset = function(playerName)
		local player = Players:FindFirstChild(playerName)
		if not player then
			print("❌ 玩家不存在: " .. playerName)
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

	-- 🔧 新增：清理所有玩家的当日邀请记录
	clearAllDaily = function()
		if _G.InviteManager then
			print("[InviteDebug] 🔄 执行一键清理所有玩家当日邀请记录...")
			local result = _G.InviteManager:clearAllDailyInviteRecords()
			print("[InviteDebug] ✅ 清理完成，共清理 " .. tostring(result) .. " 个在线玩家的记录")
		else
			print("❌ InviteManager 未初始化")
		end
	end,

	-- 🔧 新增：清理单个玩家的当日邀请记录（按 UserId）
	clearDailyByUserId = function(userId)
		if not userId then
			print("❌ 用法: _G.InviteDebug.clearDailyByUserId(userId)")
			return
		end

		if _G.InviteManager then
			print("[InviteDebug] 🔄 清理 UserId=" .. tostring(userId) .. " 的当日邀请记录...")
			local success = _G.InviteManager:clearDailyInviteRecordByUserId(userId)
			if success then
				print("[InviteDebug] ✅ 清理成功")
			else
				print("[InviteDebug] ❌ 清理失败")
			end
		else
			print("❌ InviteManager 未初始化")
		end
	end,

	-- 🔧 新增：清理单个玩家的当日邀请记录（按玩家名）
	clearDailyByName = function(playerName)
		if not playerName then
			print("❌ 用法: _G.InviteDebug.clearDailyByName('玩家名')")
			return
		end

		local player = Players:FindFirstChild(playerName)
		if not player then
			print("❌ 玩家不存在: " .. playerName)
			return
		end

		if _G.InviteManager then
			print("[InviteDebug] 🔄 清理玩家 " .. playerName .. " 的当日邀请记录...")
			local success = _G.InviteManager:clearDailyInviteRecordByUserId(player.UserId)
			if success then
				print("[InviteDebug] ✅ 清理成功")
			else
				print("[InviteDebug] ❌ 清理失败")
			end
		else
			print("❌ InviteManager 未初始化")
		end
	end
}

print("[InviteSystemEntry] ✓ 邀请系统初始化完成")
print("[InviteSystemEntry] ✓ 调试命令:")
print("[InviteSystemEntry]   - _G.InviteDebug.addInviteCount('玩家名', 数量)")
print("[InviteSystemEntry]   - _G.InviteDebug.showStatus('玩家名')")
print("[InviteSystemEntry]   - _G.InviteDebug.reset('玩家名')")
print("[InviteSystemEntry]   - _G.InviteDebug.clearAllDaily()  -- 一键清理所有玩家当日记录")
print("[InviteSystemEntry]   - _G.InviteDebug.clearDailyByUserId(userId)  -- 清理指定 UserId")
print("[InviteSystemEntry]   - _G.InviteDebug.clearDailyByName('玩家名')  -- 清理指定玩家")
