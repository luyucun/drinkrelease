-- 脚本名称: PropConfig
-- 脚本作用: 道具系统配置文件，定义所有道具的基本信息
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local PropConfig = {}

-- 道具配置表
PropConfig.PROPS = {
	[1] = {
		id = 1,
		name = "Poison Detector",
		description = "Detect if a drink contains poison",
		coinPrice = 50,        -- 金币价格
		robuxProductId = 3412860296,    -- Robux开发者道具ID（暂时设为0，需要配置）
		iconAssetId = "17449975508",      -- 图标资源ID（需要上传到Roblox）
		rarity = "Common",     -- 稀有度
		category = "Detection" -- 道具分类
	},

	[2] = {
		id = 2,
		name = "Turn Skip",
		description = "Skip your turn without drinking",
		coinPrice = 30,
		robuxProductId = 3412860707,
		iconAssetId = "17449975508",
		rarity = "Common",
		category = "Action"
	},

	[3] = {
		id = 3,
		name = "Poison Cleaner",
		description = "Remove opponent's poison from a drink",
		coinPrice = 80,
		robuxProductId = 3412860911,
		iconAssetId = "17449975508",
		rarity = "Rare",
		category = "Counter"
	}
}

-- 道具效果类型枚举
PropConfig.EFFECT_TYPES = {
	POISON_DETECT = "poison_detect",
	TURN_SKIP = "turn_skip",
	POISON_CLEAN = "poison_clean"
}

-- 将道具ID映射到效果类型
PropConfig.PROP_EFFECTS = {
	[1] = PropConfig.EFFECT_TYPES.POISON_DETECT,
	[2] = PropConfig.EFFECT_TYPES.TURN_SKIP,
	[3] = PropConfig.EFFECT_TYPES.POISON_CLEAN
}

-- 道具使用条件
PropConfig.USE_CONDITIONS = {
	PLAYER_TURN_ONLY = true,  -- 仅在玩家回合时可用
	REQUIRE_QUANTITY = true,  -- 需要道具数量≥1
	GAME_PHASE_SELECTION = true -- 仅在选择奶茶阶段可用
}

-- 获取道具信息
function PropConfig.getPropInfo(propId)
	return PropConfig.PROPS[propId]
end

-- 获取道具效果类型
function PropConfig.getPropEffect(propId)
	return PropConfig.PROP_EFFECTS[propId]
end

-- 获取所有道具列表
function PropConfig.getAllProps()
	return PropConfig.PROPS
end

-- 验证道具ID是否有效
function PropConfig.isValidPropId(propId)
	return PropConfig.PROPS[propId] ~= nil
end

-- 获取道具名称
function PropConfig.getPropName(propId)
	local propInfo = PropConfig.getPropInfo(propId)
	return propInfo and propInfo.name or "Unknown Prop"
end

-- 获取道具价格
function PropConfig.getPropPrice(propId)
	local propInfo = PropConfig.getPropInfo(propId)
	return propInfo and propInfo.coinPrice or 0
end

print("PropConfig 配置文件已加载")

return PropConfig