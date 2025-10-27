-- 脚本名称: TaskConfig
-- 脚本作用: 每日任务系统配置数据，客户端服务端共享
-- 脚本类型: ModuleScript
-- 放置位置: ReplicatedStorage
-- 版本: V1.8

local TaskConfig = {}

-- 奖励类型枚举
TaskConfig.REWARD_TYPES = {
	COINS = 1,        -- 金币
	WHEEL_SPINS = 2   -- 转盘次数
}

-- 任务配置表
-- 根据策划案V1.8任务表配置
TaskConfig.TASKS = {
	{
		id = 1,
		description = "Complete 1 matches",
		requiredMatches = 1,
		rewardType = TaskConfig.REWARD_TYPES.COINS,
		rewardAmount = 200,
		rewardIcon = "rbxassetid://18209599044"
	},
	{
		id = 2,
		description = "Complete 3 matches",
		requiredMatches = 3,
		rewardType = TaskConfig.REWARD_TYPES.COINS,
		rewardAmount = 300,
		rewardIcon = "rbxassetid://18209599044"
	},
	{
		id = 3,
		description = "Complete 5 matches",
		requiredMatches = 5,
		rewardType = TaskConfig.REWARD_TYPES.WHEEL_SPINS,
		rewardAmount = 2,
		rewardIcon = "rbxassetid://140226468670502"
	}
}

-- 系统配置
TaskConfig.SETTINGS = {
	RESET_HOUR_UTC = 0,  -- UTC0点重置
	SAVE_INTERVAL = 120  -- 数据保存间隔(秒)
}

-- ============================================
-- 辅助函数
-- ============================================

-- 根据任务ID获取任务配置
function TaskConfig.getTaskById(taskId)
	for _, task in ipairs(TaskConfig.TASKS) do
		if task.id == taskId then
			return task
		end
	end
	return nil
end

-- 获取任务总数
function TaskConfig.getTaskCount()
	return #TaskConfig.TASKS
end

-- 获取奖励显示文本
function TaskConfig.getRewardDisplayText(rewardType, amount)
	if rewardType == TaskConfig.REWARD_TYPES.COINS then
		return "Coins +" .. amount
	elseif rewardType == TaskConfig.REWARD_TYPES.WHEEL_SPINS then
		return "Wheel Spins +" .. amount
	else
		return "Unknown Reward"
	end
end

-- 验证配置完整性
function TaskConfig.validateConfiguration()
	local errors = {}

	-- 验证任务配置
	for _, task in ipairs(TaskConfig.TASKS) do
		if not task.id or not task.description or not task.requiredMatches then
			table.insert(errors, "任务ID " .. tostring(task.id) .. " 配置不完整")
		end

		if not task.rewardType or not task.rewardAmount or not task.rewardIcon then
			table.insert(errors, "任务ID " .. tostring(task.id) .. " 奖励配置不完整")
		end

		if task.requiredMatches <= 0 then
			table.insert(errors, "任务ID " .. tostring(task.id) .. " 要求对局数必须大于0")
		end

		if task.rewardAmount <= 0 then
			table.insert(errors, "任务ID " .. tostring(task.id) .. " 奖励数量必须大于0")
		end
	end

	-- 验证任务ID唯一性
	local idSet = {}
	for _, task in ipairs(TaskConfig.TASKS) do
		if idSet[task.id] then
			table.insert(errors, "任务ID " .. task.id .. " 重复")
		end
		idSet[task.id] = true
	end

	return #errors == 0, errors
end

-- 初始化时验证配置
local isValid, errors = TaskConfig.validateConfiguration()
if not isValid then
	warn("❌ TaskConfig 配置验证失败:")
	for _, error in ipairs(errors) do
		warn("  - " .. error)
	end
else
	print("✅ TaskConfig 配置验证通过")
end

print("✅ TaskConfig 配置加载完成，共 " .. TaskConfig.getTaskCount() .. " 个每日任务")

return TaskConfig
