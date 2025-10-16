-- 脚本名称: EmoteConfig
-- 脚本作用: 跳舞动作配置表，定义所有动作的信息
-- 脚本类型: ModuleScript
-- 放置位置: ReplicatedStorage

local EmoteConfig = {}

-- 动作配置表
EmoteConfig.EMOTES = {
	[1001] = {
		id = 1001,
		name = "Default",
		animationId = "rbxassetid://113375965758912",
		coinPrice = 0,  -- 0表示默认免费动作
		iconAssetId = "rbxassetid://92389161580514",
		npcModel = nil  -- 默认动作不关联NPC
	},
	[1002] = {
		id = 1002,
		name = "Make You Mine",
		animationId = "rbxassetid://87686948832992",
		coinPrice = 1000,
		iconAssetId = "rbxassetid://129734246719629",
		npcModel = "Npc01"
	},
	[1003] = {
		id = 1003,
		name = "Blackpink Dance",
		animationId = "rbxassetid://79979515443365",
		coinPrice = 1000,
		iconAssetId = "rbxassetid://139926150123724",
		npcModel = "Npc02"
	},
	[1004] = {
		id = 1004,
		name = "SkinWalker",
		animationId = "rbxassetid://70432904702322",
		coinPrice = 2000,
		iconAssetId = "rbxassetid://129394006090948",
		npcModel = "Npc03"
	}
}

-- 获取动作信息（返回深拷贝，防止外部修改）
function EmoteConfig.getEmoteInfo(emoteId)
	if not emoteId or type(emoteId) ~= "number" then
		return nil
	end

	local emote = EmoteConfig.EMOTES[emoteId]
	if not emote then
		return nil
	end

	-- 返回深拷贝
	return {
		id = emote.id,
		name = emote.name,
		animationId = emote.animationId,
		coinPrice = emote.coinPrice,
		iconAssetId = emote.iconAssetId,
		npcModel = emote.npcModel
	}
end

-- 获取所有动作（返回深拷贝的数组）
function EmoteConfig.getAllEmotes()
	local emotes = {}
	for emoteId, emote in pairs(EmoteConfig.EMOTES) do
		table.insert(emotes, {
			id = emote.id,
			name = emote.name,
			animationId = emote.animationId,
			coinPrice = emote.coinPrice,
			iconAssetId = emote.iconAssetId,
			npcModel = emote.npcModel
		})
	end

	-- 按ID排序
	table.sort(emotes, function(a, b)
		return a.id < b.id
	end)

	return emotes
end

-- 验证动作ID有效性
function EmoteConfig.isValidEmoteId(emoteId)
	if not emoteId or type(emoteId) ~= "number" then
		return false
	end
	return EmoteConfig.EMOTES[emoteId] ~= nil
end

-- 获取默认动作ID
function EmoteConfig.getDefaultEmoteId()
	return 1001
end

-- 根据NPC名称获取动作ID
function EmoteConfig.getEmoteIdByNpcName(npcName)
	if not npcName or type(npcName) ~= "string" then
		return nil
	end

	for emoteId, emote in pairs(EmoteConfig.EMOTES) do
		if emote.npcModel == npcName then
			return emoteId
		end
	end

	return nil
end

-- 获取所有付费动作（价格 > 0）
function EmoteConfig.getPurchasableEmotes()
	local emotes = {}
	for emoteId, emote in pairs(EmoteConfig.EMOTES) do
		if emote.coinPrice > 0 then
			table.insert(emotes, {
				id = emote.id,
				name = emote.name,
				animationId = emote.animationId,
				coinPrice = emote.coinPrice,
				iconAssetId = emote.iconAssetId,
				npcModel = emote.npcModel
			})
		end
	end

	-- 按ID排序
	table.sort(emotes, function(a, b)
		return a.id < b.id
	end)

	return emotes
end

-- 获取NPC关联的动作列表
function EmoteConfig.getNPCEmotes()
	local npcEmotes = {}
	for emoteId, emote in pairs(EmoteConfig.EMOTES) do
		if emote.npcModel then
			npcEmotes[emote.npcModel] = {
				id = emote.id,
				name = emote.name,
				animationId = emote.animationId,
				coinPrice = emote.coinPrice,
				iconAssetId = emote.iconAssetId,
				npcModel = emote.npcModel
			}
		end
	end
	return npcEmotes
end

return EmoteConfig
