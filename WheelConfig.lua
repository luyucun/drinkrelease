-- 脚本名称: WheelConfig
-- 脚本作用: 转盘系统配置数据，客户端服务端共享
-- 脚本类型: ModuleScript
-- 放置位置: ReplicatedStorage

local WheelConfig = {}

-- 奖励类型枚举
WheelConfig.REWARD_TYPES = {
	COINS = 1,        -- 金币
	TURN_SKIP = 2,    -- 跳过道具 (PropId = 2)
	POISON_DETECT = 3, -- 验证道具 (PropId = 1)
	SKIN = 4          -- 皮肤
}

-- 转盘奖励配置 (按需求表格配置)
WheelConfig.WHEEL_REWARDS = {
	[1] = {type = 4, value = 1007, weight = 3},   -- 皮肤ID 1007 (龙虾-最高级)
	[2] = {type = 1, value = 20, weight = 40},    -- 20金币
	[3] = {type = 2, value = 1, weight = 8},      -- 1个跳过道具
	[4] = {type = 1, value = 50, weight = 25},    -- 50金币
	[5] = {type = 3, value = 1, weight = 8},      -- 1个验证道具
	[6] = {type = 1, value = 100, weight = 16}    -- 100金币
}

-- 开发者商品配置
WheelConfig.DEVELOPER_PRODUCTS = {
	SPIN_5 = {id = 3426739532, spins = 5},    -- 5次转盘
	SPIN_20 = {id = 3426739799, spins = 20},  -- 20次转盘
	SPIN_50 = {id = 3426739998, spins = 50}   -- 50次转盘
}

-- 系统配置
WheelConfig.SETTINGS = {
	FREE_SPIN_INTERVAL = 300,             -- 免费次数间隔(5分钟 = 300秒)
	FIRST_FREE_SPIN_INTERVAL = 180,       -- 🎁 新玩家首次免费次数间隔(3分钟 = 180秒)
	SPIN_ANIMATION_DURATION = 3,          -- 转盘动画时长(秒)
	FULL_ROTATIONS = 5,                   -- 转盘完整旋转圈数
	TICK_SOUND_ID = 9120658649,           -- 音效资源ID
	DEGREES_PER_POSITION = 60             -- 每个位置对应的角度
}

-- 计算总权重
function WheelConfig.getTotalWeight()
	local total = 0
	for _, reward in pairs(WheelConfig.WHEEL_REWARDS) do
		total = total + reward.weight
	end
	return total
end

-- 根据权重随机选择奖励位置
function WheelConfig.getRandomRewardPosition()
	local totalWeight = WheelConfig.getTotalWeight()
	local randomValue = math.random(1, totalWeight)
	local currentWeight = 0

	for position, reward in pairs(WheelConfig.WHEEL_REWARDS) do
		currentWeight = currentWeight + reward.weight
		if randomValue <= currentWeight then
			return position, reward
		end
	end

	-- 备用返回位置1
	return 1, WheelConfig.WHEEL_REWARDS[1]
end

-- 获取奖励显示文本
function WheelConfig.getRewardDisplayText(rewardType, value)
	if rewardType == WheelConfig.REWARD_TYPES.COINS then
		return "金币+" .. value
	elseif rewardType == WheelConfig.REWARD_TYPES.TURN_SKIP then
		return "跳过道具+" .. value
	elseif rewardType == WheelConfig.REWARD_TYPES.POISON_DETECT then
		return "验证道具+" .. value
	elseif rewardType == WheelConfig.REWARD_TYPES.SKIN then
		-- 尝试获取皮肤名称
		if _G.SkinConfig and _G.SkinConfig.getSkinInfo then
			local skinInfo = _G.SkinConfig.getSkinInfo(value)
			if skinInfo then
				return "皮肤: " .. skinInfo.name
			end
		end
		return "皮肤ID: " .. value
	else
		return "未知奖励"
	end
end

-- 验证配置完整性
function WheelConfig.validateConfiguration()
	local errors = {}

	-- 验证奖励配置
	for position, reward in pairs(WheelConfig.WHEEL_REWARDS) do
		if not reward.type or not reward.value or not reward.weight then
			table.insert(errors, "位置" .. position .. "的奖励配置不完整")
		end

		if reward.weight <= 0 then
			table.insert(errors, "位置" .. position .. "的权重必须大于0")
		end
	end

	-- 验证开发者商品配置
	for name, product in pairs(WheelConfig.DEVELOPER_PRODUCTS) do
		if not product.id or not product.spins then
			table.insert(errors, "开发者商品" .. name .. "配置不完整")
		end

		if product.spins <= 0 then
			table.insert(errors, "开发者商品" .. name .. "的次数必须大于0")
		end
	end

	return #errors == 0, errors
end

-- ============================================
-- 🔧 新增：动态权重计算（排除已拥有皮肤）
-- ============================================

-- 获取玩家特定的有效奖励列表（排除已拥有的皮肤）
function WheelConfig.getValidRewardsForPlayer(player)
	-- 🔧 修复：验证player参数有效性
	if not player or not player.Parent or not player.Name then
		warn("🎰 WheelConfig: 无效的玩家参数，使用原始奖励配置")
		return WheelConfig.WHEEL_REWARDS
	end

	local validRewards = {}

	for position, reward in pairs(WheelConfig.WHEEL_REWARDS) do
		local shouldInclude = true

		-- 如果是皮肤奖励，检查玩家是否已拥有
		if reward.type == WheelConfig.REWARD_TYPES.SKIN then
			if _G.SkinDataManager and _G.SkinDataManager.hasSkin then
				local success, hasSkin = pcall(function()
					return _G.SkinDataManager.hasSkin(player, reward.value)
				end)

				if success and hasSkin then
					shouldInclude = false
					print("🎰 WheelConfig: 玩家 " .. player.Name .. " 已拥有皮肤 " .. reward.value .. "，排除该奖励 (位置" .. position .. ")")
				elseif not success then
					warn("🎰 WheelConfig: 检查皮肤拥有状态失败，保留奖励: " .. tostring(hasSkin))
				end
			else
				warn("🎰 WheelConfig: SkinDataManager未加载，无法检查皮肤拥有状态")
			end
		end

		if shouldInclude then
			validRewards[position] = reward
		end
	end

	return validRewards
end

-- 计算玩家特定的总权重
function WheelConfig.getTotalWeightForPlayer(player)
	local validRewards = WheelConfig.getValidRewardsForPlayer(player)
	local total = 0
	for _, reward in pairs(validRewards) do
		total = total + reward.weight
	end
	return total
end

-- 为特定玩家获取随机奖励位置（核心功能）
function WheelConfig.getRandomRewardPositionForPlayer(player)
	-- 🔧 修复：验证player参数有效性
	if not player or not player.Parent or not player.Name then
		warn("🎰 WheelConfig: 无效的玩家参数，使用原始逻辑")
		return WheelConfig.getRandomRewardPosition()
	end

	local validRewards = WheelConfig.getValidRewardsForPlayer(player)
	-- 🔧 修复：避免重复计算，直接从validRewards计算总权重
	local totalWeight = 0
	for _, reward in pairs(validRewards) do
		totalWeight = totalWeight + reward.weight
	end

	-- 如果没有有效奖励，回退到原始逻辑
	if totalWeight == 0 then
		warn("🎰 WheelConfig: 玩家 " .. player.Name .. " 没有有效奖励，使用原始逻辑")
		return WheelConfig.getRandomRewardPosition()
	end

	local randomValue = math.random(1, totalWeight)
	local currentWeight = 0

	-- 按位置顺序遍历确保一致性
	local sortedPositions = {}
	for position in pairs(validRewards) do
		table.insert(sortedPositions, position)
	end
	table.sort(sortedPositions)

	for _, position in ipairs(sortedPositions) do
		local reward = validRewards[position]
		currentWeight = currentWeight + reward.weight
		if randomValue <= currentWeight then
			print("🎰 WheelConfig: 玩家 " .. player.Name .. " 中奖位置: " .. position .. " (权重: " .. reward.weight .. "/" .. totalWeight .. ")")
			return position, reward
		end
	end

	-- 备用返回第一个有效奖励
	local firstPosition = sortedPositions[1]
	if firstPosition then
		warn("🎰 WheelConfig: 权重计算异常，返回第一个有效奖励 (位置" .. firstPosition .. ")")
		return firstPosition, validRewards[firstPosition]
	end

	-- 最终备用方案
	warn("🎰 WheelConfig: 严重错误 - 无法获取有效奖励，使用原始逻辑")
	return WheelConfig.getRandomRewardPosition()
end

-- 初始化时验证配置
local isValid, errors = WheelConfig.validateConfiguration()
if not isValid then
	warn("❌ WheelConfig 配置验证失败:")
	for _, error in ipairs(errors) do
		warn("  - " .. error)
	end
else
	print("✅ WheelConfig 配置验证通过")
end

print("✅ WheelConfig 配置加载完成，总权重: " .. WheelConfig.getTotalWeight())

return WheelConfig