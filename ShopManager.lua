-- 脚本名称: ShopManager
-- 脚本作用: 服务端商店管理系统，处理商品购买、Robux购买、金币购买等逻辑
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local ShopManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

-- 引入配置和管理器
local ShopConfig = require(script.Parent.ShopConfig)

-- 检测是否在Studio环境
local isStudio = RunService:IsStudio()

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local shopEvent = remoteEventsFolder:WaitForChild("ShopEvent")

-- 商店状态管理
local shopState = {
	catalogById = {},           -- 商品ID索引 {id = product}
	cooldowns = {}              -- 购买冷却 {player = timestamp}
	-- 🔧 修复：移除pendingRobuxPurchases，UnifiedPurchaseManager处理所有购买
}

-- 初始化商店数据
function ShopManager.initialize()

	-- 缓存商品配置
	for _, product in ipairs(ShopConfig.getAllProducts()) do
		shopState.catalogById[product.id] = product
	end


	-- 设置事件监听
	ShopManager.setupEvents()

	print("ShopManager 初始化完成")
end

-- 设置事件监听
function ShopManager.setupEvents()
	-- 监听商店事件
	shopEvent.OnServerEvent:Connect(function(player, action, data)
		if action == "requestCatalog" then
			ShopManager.handleCatalogRequest(player)
		elseif action == "purchase" then
			ShopManager.handlePurchaseRequest(player, data)
		end
	end)

	-- 🔧 修复：移除不可靠的PromptProductPurchaseFinished监听
	-- 现在Robux购买通过UnifiedPurchaseManager的ProcessReceipt处理

end

-- 处理商品目录请求
function ShopManager.handleCatalogRequest(player)

	-- 发送精简的商品数据到客户端
	local clientProducts = ShopConfig.getClientProducts()
	shopEvent:FireClient(player, "catalogResponse", {
		products = clientProducts
	})

end

-- 处理购买请求
function ShopManager.handlePurchaseRequest(player, data)
	if not data or not data.productId then
		warn("ShopManager.handlePurchaseRequest: 缺少productId")
		return
	end

	local productId = data.productId

	-- 检查冷却时间
	if ShopManager.isOnCooldown(player) then
		shopEvent:FireClient(player, "purchaseFailed", {
			reason = "请稍等片刻再试"
		})
		return
	end

	-- 验证商品存在
	local product = shopState.catalogById[productId]
	if not product then
		warn("商品不存在: " .. productId)
		shopEvent:FireClient(player, "purchaseFailed", {
			reason = "商品不存在"
		})
		return
	end

	-- 🔧 修复：移除pendingRobuxPurchases检查，UnifiedPurchaseManager保证购买一致性

	-- 根据货币类型处理购买
	if product.currencyType == ShopConfig.CURRENCY_TYPES.ROBUX then
		ShopManager.handleRobuxPurchase(player, product)
	elseif product.currencyType == ShopConfig.CURRENCY_TYPES.GAME_COINS then
		ShopManager.handleCoinPurchase(player, product)
	else
		warn("未知的货币类型: " .. product.currencyType)
		shopEvent:FireClient(player, "purchaseFailed", {
			reason = "系统错误"
		})
	end
end

-- 处理Robux购买
function ShopManager.handleRobuxPurchase(player, product)

	-- 验证开发者商品ID
	if product.developerProductId == 0 then
		warn("商品 " .. product.name .. " 没有配置开发者商品ID")
		shopEvent:FireClient(player, "purchaseFailed", {
			reason = "该商品暂时无法购买"
		})
		return
	end

	-- 🔧 修复：移除pendingRobuxPurchases跟踪，UnifiedPurchaseManager处理购买逻辑

	-- 设置冷却时间
	ShopManager.setCooldown(player)

	-- 调用MarketplaceService提示购买
	MarketplaceService:PromptProductPurchase(player, product.developerProductId)
end

-- 处理金币购买
function ShopManager.handleCoinPurchase(player, product)

	-- 获取CoinManager
	if not _G.CoinManager then
		warn("CoinManager未加载，无法处理金币购买")
		shopEvent:FireClient(player, "purchaseFailed", {
			reason = "系统错误"
		})
		return
	end

	-- 检查金币余额
	if not _G.CoinManager.canAfford(player, product.price) then
		shopEvent:FireClient(player, "purchaseFailed", {
			reason = "insufficient_funds",
			required = product.price,
			current = _G.CoinManager.getCoins(player)
		})
		return
	end

	-- 扣除金币
	local success = _G.CoinManager.removeCoins(player, product.price, "Shop Purchase: " .. product.name)
	if not success then
		warn("扣除金币失败: 玩家 " .. player.Name)
		shopEvent:FireClient(player, "purchaseFailed", {
			reason = "扣除金币失败"
		})
		return
	end

	-- 设置冷却时间
	ShopManager.setCooldown(player)

	-- 发放奖励
	ShopManager.giveReward(player, product)

	-- 通知客户端购买成功
	shopEvent:FireClient(player, "purchaseSuccess", {
		productId = product.id,
		productName = product.name,
		currencyType = product.currencyType
	})

end

-- 🔧 修复：移除handleRobuxPurchaseFinished函数
-- Robux购买现在由UnifiedPurchaseManager通过ProcessReceipt处理

-- 发放奖励
function ShopManager.giveReward(player, product)

	if product.itemType == ShopConfig.ITEM_TYPES.COIN_PACK then
		-- 金币包
		if _G.CoinManager then
			_G.CoinManager.addCoins(player, product.rewardValue, "Shop Purchase: " .. product.name)
		else
			warn("CoinManager未加载，无法发放金币")
		end
	elseif product.itemType == ShopConfig.ITEM_TYPES.PROP then
		-- 道具
		if _G.PropManager then
			_G.PropManager.addProp(player, product.rewardValue, 1)
		else
			warn("PropManager未加载，无法发放道具")
		end
	else
		warn("未知的商品类型: " .. product.itemType)
	end
end

-- 检查冷却时间
function ShopManager.isOnCooldown(player)
	local lastPurchase = shopState.cooldowns[player]
	if not lastPurchase then
		return false
	end

	local currentTime = tick()
	local cooldownDuration = 3 -- 3秒冷却时间

	return (currentTime - lastPurchase) < cooldownDuration
end

-- 设置冷却时间
function ShopManager.setCooldown(player)
	shopState.cooldowns[player] = tick()
end

-- 重置桌子状态（在游戏重置时调用）
function ShopManager.resetTableState(tableId)
	-- 商店系统不需要桌子相关的状态重置
end

-- 玩家离开时清理
function ShopManager.onPlayerRemoving(player)
	-- 清理冷却时间
	shopState.cooldowns[player] = nil
	-- 🔧 修复：移除pendingRobuxPurchases清理，不再需要
end

-- 启动ShopManager
ShopManager.initialize()

-- 监听玩家离开
Players.PlayerRemoving:Connect(ShopManager.onPlayerRemoving)

-- 导出到全局供其他脚本使用
_G.ShopManager = ShopManager

return ShopManager