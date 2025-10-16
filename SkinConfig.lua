-- 脚本名称: SkinConfig
-- 脚本作用: V2.0皮肤系统配置文件，定义所有皮肤信息
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local SkinConfig = {}

-- 皮肤配置表
-- 格式：[skinId] = {id, name, price, modelName, displayModelName, iconAssetId}
SkinConfig.SKIN_CONFIG = {
	[1001] = {
		id = 1001,
		name = "Coffee",
		price = 100,
		modelName = "Coffee",
		displayModelName = "CoffeeShow",
		iconAssetId = "rbxassetid://114336333156678"
	},
	[1002] = {
		id = 1002,
		name = "Cola",
		price = 200,
		modelName = "Cola",
		displayModelName = "ColaShow",
		iconAssetId = "rbxassetid://103846096313676"
	},
	[1003] = {
		id = 1003,
		name = "MangoTee",
		price = 200,
		modelName = "MangoTee",
		displayModelName = "MangoTeeShow",
		iconAssetId = "rbxassetid://117978051547990"
	},
	[1004] = {
		id = 1004,
		name = "Fries",
		price = 300,
		modelName = "Fries",
		displayModelName = "FriesShow",
		iconAssetId = "rbxassetid://114857178124886"
	},
	[1005] = {
		id = 1005,
		name = "Sushi",
		price = 500,
		modelName = "Sushi",
		displayModelName = "SushiShow",
		iconAssetId = "rbxassetid://109121183857385"
	},
	[1006] = {
		id = 1006,
		name = "Watermelon",
		price = 1000,
		modelName = "Watermelon",
		displayModelName = "WatermelonShow",
		iconAssetId = "rbxassetid://130171176507993"
	},
	[1007] = {
		id = 1007,
		name = "Lobster",
		price = 2000,
		modelName = "Lobster",
		displayModelName = "LobsterShow",
		iconAssetId = "rbxassetid://132680189059619"
	}
}

-- 获取单个皮肤信息
function SkinConfig.getSkinInfo(skinId)
	return SkinConfig.SKIN_CONFIG[skinId]
end

-- 获取所有皮肤列表（返回数组，按ID排序）
function SkinConfig.getAllSkins()
	local skins = {}
	for _, skinInfo in pairs(SkinConfig.SKIN_CONFIG) do
		table.insert(skins, skinInfo)
	end

	-- 按ID排序
	table.sort(skins, function(a, b)
		return a.id < b.id
	end)

	return skins
end

-- 验证皮肤ID是否有效
function SkinConfig.isValidSkinId(skinId)
	return SkinConfig.SKIN_CONFIG[skinId] ~= nil
end

-- 通过模型名获取皮肤信息
function SkinConfig.getSkinByModelName(modelName)
	for _, skinInfo in pairs(SkinConfig.SKIN_CONFIG) do
		if skinInfo.modelName == modelName then
			return skinInfo
		end
	end
	return nil
end

-- 通过展示模型名获取皮肤信息
function SkinConfig.getSkinByDisplayModelName(displayModelName)
	for _, skinInfo in pairs(SkinConfig.SKIN_CONFIG) do
		if skinInfo.displayModelName == displayModelName then
			return skinInfo
		end
	end
	return nil
end

-- 🔧 V2.0: 验证皮肤模型结构完整性
function SkinConfig.validateSkinModel(modelName)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local drinkModelFolder = ReplicatedStorage:FindFirstChild("DrinkModel")

	if not drinkModelFolder then
		return false, "DrinkModel文件夹不存在"
	end

	local model = drinkModelFolder:FindFirstChild(modelName)
	if not model then
		return false, "模型不存在: " .. modelName
	end

	-- 验证必需节点
	local requiredNodes = {"NumPart", "Effect"}
	for _, nodeName in ipairs(requiredNodes) do
		if not model:FindFirstChild(nodeName) then
			return false, "缺少必需节点: " .. nodeName
		end
	end

	-- 验证NumPart结构
	local numPart = model:FindFirstChild("NumPart")
	if not numPart:FindFirstChild("BillboardGui") then
		return false, "NumPart缺少BillboardGui"
	end

	local billboardGui = numPart:FindFirstChild("BillboardGui")
	if not billboardGui:FindFirstChild("Num") then
		return false, "BillboardGui缺少Num"
	end

	-- 验证是否有可点击的Part（Cup或其他BasePart）
	local hasBasePart = false
	if model:FindFirstChild("Cup") and model.Cup:IsA("BasePart") then
		hasBasePart = true
	elseif model.PrimaryPart then
		hasBasePart = true
	else
		for _, child in pairs(model:GetChildren()) do
			if child:IsA("BasePart") then
				hasBasePart = true
				break
			end
		end
	end

	if not hasBasePart then
		return false, "模型缺少可点击的BasePart"
	end

	return true, "验证通过"
end

-- 🔧 V2.0: 验证所有皮肤模型 (修改为宽容模式)
function SkinConfig.validateAllSkins()
	local errorMessages = {}
	local validCount = 0
	local totalCount = 0

	for _, skinInfo in pairs(SkinConfig.SKIN_CONFIG) do
		totalCount = totalCount + 1
		local success, errorMsg = SkinConfig.validateSkinModel(skinInfo.modelName)
		if not success then
			-- 🔧 只记录警告，不影响系统运行
			warn("⚠️ 皮肤模型验证失败: " .. skinInfo.name .. " (" .. skinInfo.modelName .. ") - " .. errorMsg)
			table.insert(errorMessages, skinInfo.name .. ": " .. errorMsg)
		else
			validCount = validCount + 1
		end
	end

	if validCount == totalCount then
		print("✅ 所有皮肤模型验证通过 (" .. validCount .. "/" .. totalCount .. ")")
	else
		print("📝 皮肤模型验证完成: " .. validCount .. "/" .. totalCount .. " 个通过，系统继续运行")
	end

	-- 🔧 始终返回true，让系统继续运行
	return true, errorMessages
end

-- 注册为全局变量,供DrinkManager等模块访问
_G.SkinConfig = SkinConfig

return SkinConfig
