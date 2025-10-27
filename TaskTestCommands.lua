-- 脚本名称: TaskTestCommands
-- 脚本作用: 每日任务系统测试命令 (仅用于开发测试)
-- 脚本类型: Script
-- 放置位置: ServerScriptService (测试完成后可删除)
-- 版本: V1.8

local Players = game:GetService("Players")

-- 等待TaskDataManager加载
task.wait(3)

if not _G.TaskDataManager then
	warn("[TaskTestCommands] ❌ TaskDataManager未加载")
	return
end

print("[TaskTestCommands] ✅ 测试命令已激活")

-- ============================================
-- 测试命令
-- ============================================

-- 命令1: 模拟完成一局对战
local function simulateMatchComplete(player)
	if not player or not player.Parent then
		warn("[TaskTestCommands] 玩家无效")
		return
	end

	local success = _G.TaskDataManager:incrementMatchCount(player)
	if success then
		print("[TaskTestCommands] ✓ 已为玩家 " .. player.Name .. " 增加1局对局计数")
	else
		warn("[TaskTestCommands] ❌ 增加对局计数失败")
	end
end

-- 命令2: 重置玩家任务数据
local function resetPlayerTasks(player)
	if not player or not player.Parent then
		warn("[TaskTestCommands] 玩家无效")
		return
	end

	_G.TaskDataManager:resetDailyTaskData(player)
	print("[TaskTestCommands] ✓ 已重置玩家 " .. player.Name .. " 的任务数据")
end

-- 命令3: 打印玩家任务状态
local function printPlayerStatus(player)
	if not player or not player.Parent then
		warn("[TaskTestCommands] 玩家无效")
		return
	end

	local status = _G.TaskDataManager:getTaskStatus(player)
	print("========== 玩家任务状态: " .. player.Name .. " ==========")
	print("已完成对局数: " .. status.dailyMatchesCompleted)
	print("已领取奖励: ")
	for taskKey, claimed in pairs(status.claimedRewards) do
		print("  " .. taskKey .. ": " .. tostring(claimed))
	end
	print("有未领取奖励: " .. tostring(status.hasUnclaimedRewards))
	print("下次重置时间: " .. os.date("%Y-%m-%d %H:%M:%S", status.nextResetTime))
	print("======================================================")
end

-- ============================================
-- 聊天命令监听
-- ============================================

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		-- 命令: /task_add - 增加1局对局
		if message == "/task_add" then
			simulateMatchComplete(player)

		-- 命令: /task_add5 - 增加5局对局
		elseif message == "/task_add5" then
			for i = 1, 5 do
				simulateMatchComplete(player)
				task.wait(0.1)
			end

		-- 命令: /task_reset - 重置任务
		elseif message == "/task_reset" then
			resetPlayerTasks(player)

		-- 命令: /task_status - 查看状态
		elseif message == "/task_status" then
			printPlayerStatus(player)
		end
	end)
end)

print("[TaskTestCommands] 测试命令列表:")
print("  /task_add     - 增加1局对局计数")
print("  /task_add5    - 增加5局对局计数")
print("  /task_reset   - 重置任务数据")
print("  /task_status  - 查看任务状态")
