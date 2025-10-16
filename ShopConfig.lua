-- 脚本名称: ShopConfig
-- 脚本作用: 商店商品配置表，承载策划案的商品数据
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local ShopConfig = {}

-- 商品类型常量
ShopConfig.ITEM_TYPES = {
	COIN_PACK = 1,
	PROP = 2
}

-- 货币类型常量
ShopConfig.CURRENCY_TYPES = {
	ROBUX = 1,
	GAME_COINS = 2
}

-- 商店商品配置表
-- 字段说明：
-- id: 商品唯一ID
-- itemType: 商品类型 (1=金币包, 2=道具)
-- currencyType: 货币类型 (1=Robux, 2=游戏金币)
-- name: 商品名称
-- iconAssetId: 商品图标资源ID
-- price: 价格参数
-- developerProductId: 开发者商品ID (金币购买时为0)
-- currencyIconAssetId: 货币图标资源ID
-- rewardValue: 奖励数值 (金币包的金币数量或道具对应的propId)
ShopConfig.PRODUCTS = {
	-- Robux购买道具
	{
		id = 1001,
		itemType = ShopConfig.ITEM_TYPES.PROP,
		currencyType = ShopConfig.CURRENCY_TYPES.ROBUX,
		name = "Poison Detector",
		iconAssetId = "rbxassetid://137647977586347",
		price = 20,
		developerProductId = 3412860296,
		currencyIconAssetId = "rbxassetid://109846679063329",
		rewardValue = 1  -- propId
	},
	{
		id = 1002,
		itemType = ShopConfig.ITEM_TYPES.PROP,
		currencyType = ShopConfig.CURRENCY_TYPES.ROBUX,
		name = "Turn Skip",
		iconAssetId = "rbxassetid://106452668141606",
		price = 20,
		developerProductId = 3412860707,
		currencyIconAssetId = "rbxassetid://109846679063329",
		rewardValue = 2  -- propId
	},
	{
		id = 1003,
		itemType = ShopConfig.ITEM_TYPES.PROP,
		currencyType = ShopConfig.CURRENCY_TYPES.ROBUX,
		name = "Poison Cleaner",
		iconAssetId = "rbxassetid://135754569539747",
		price = 100,
		developerProductId = 3412860911,
		currencyIconAssetId = "rbxassetid://109846679063329",
		rewardValue = 3  -- propId
	},

	-- Robux购买金币包
	{
		id = 2001,
		itemType = ShopConfig.ITEM_TYPES.COIN_PACK,
		currencyType = ShopConfig.CURRENCY_TYPES.ROBUX,
		name = "250",
		iconAssetId = "rbxassetid://18209599044",
		price = 20,
		developerProductId = 3416643202,
		currencyIconAssetId = "rbxassetid://109846679063329",
		rewardValue = 250  -- 金币数量
	},
	{
		id = 2002,
		itemType = ShopConfig.ITEM_TYPES.COIN_PACK,
		currencyType = ShopConfig.CURRENCY_TYPES.ROBUX,
		name = "1200",
		iconAssetId = "rbxassetid://18209599044",
		price = 85,
		developerProductId = 3416643905,
		currencyIconAssetId = "rbxassetid://109846679063329",
		rewardValue = 1200  -- 金币数量
	},
	{
		id = 2003,
		itemType = ShopConfig.ITEM_TYPES.COIN_PACK,
		currencyType = ShopConfig.CURRENCY_TYPES.ROBUX,
		name = "2500",
		iconAssetId = "rbxassetid://18209599044",
		price = 150,
		developerProductId = 3416643906,
		currencyIconAssetId = "rbxassetid://109846679063329",
		rewardValue = 2500  -- 金币数量
	},
	{
		id = 2004,
		itemType = ShopConfig.ITEM_TYPES.COIN_PACK,
		currencyType = ShopConfig.CURRENCY_TYPES.ROBUX,
		name = "5000",
		iconAssetId = "rbxassetid://18209599044",
		price = 260,
		developerProductId = 3416643907,
		currencyIconAssetId = "rbxassetid://109846679063329",
		rewardValue = 5000  -- 金币数量
	},

	-- 金币购买道具
	{
		id = 3001,
		itemType = ShopConfig.ITEM_TYPES.PROP,
		currencyType = ShopConfig.CURRENCY_TYPES.GAME_COINS,
		name = "Poison Detector",
		iconAssetId = "rbxassetid://137647977586347",
		price = 250,
		developerProductId = 0,
		currencyIconAssetId = "rbxassetid://18209599044",
		rewardValue = 1  -- propId
	},
	{
		id = 3002,
		itemType = ShopConfig.ITEM_TYPES.PROP,
		currencyType = ShopConfig.CURRENCY_TYPES.GAME_COINS,
		name = "Turn Skip",
		iconAssetId = "rbxassetid://106452668141606",
		price = 250,
		developerProductId = 0,
		currencyIconAssetId = "rbxassetid://18209599044",
		rewardValue = 2  -- propId
	},
	{
		id = 3003,
		itemType = ShopConfig.ITEM_TYPES.PROP,
		currencyType = ShopConfig.CURRENCY_TYPES.GAME_COINS,
		name = "Poison Cleaner",
		iconAssetId = "rbxassetid://135754569539747",
		price = 1000,
		developerProductId = 0,
		currencyIconAssetId = "rbxassetid://18209599044",
		rewardValue = 3  -- propId
	}
}

-- 获取商品信息
function ShopConfig.getProduct(productId)
	for _, product in ipairs(ShopConfig.PRODUCTS) do
		if product.id == productId then
			return product
		end
	end
	return nil
end

-- 获取客户端精简商品数据
function ShopConfig.getClientProducts()
	local clientProducts = {}

	for _, product in ipairs(ShopConfig.PRODUCTS) do
		table.insert(clientProducts, {
			id = product.id,
			itemType = product.itemType,
			currencyType = product.currencyType,
			name = product.name,
			iconAssetId = product.iconAssetId,
			price = product.price,
			currencyIconAssetId = product.currencyIconAssetId
			-- 不传递 developerProductId 和 rewardValue 到客户端
		})
	end

	return clientProducts
end

-- 根据开发者商品ID查找商品
function ShopConfig.getProductByDeveloperProductId(developerProductId)
	for _, product in ipairs(ShopConfig.PRODUCTS) do
		if product.developerProductId == developerProductId then
			return product
		end
	end
	return nil
end

-- 验证商品是否存在
function ShopConfig.isValidProduct(productId)
	return ShopConfig.getProduct(productId) ~= nil
end


-- 获取所有商品列表
function ShopConfig.getAllProducts()
	return ShopConfig.PRODUCTS
end

print("ShopConfig 模块加载完成")

-- 导出到全局供其他脚本使用
_G.ShopConfig = ShopConfig

return ShopConfig