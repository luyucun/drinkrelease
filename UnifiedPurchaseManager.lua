-- 脚本名称: UnifiedPurchaseManager
-- 脚本作用: 统一的开发者商品购买处理，支持商店和转盘系统
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local UnifiedPurchaseManager = {}
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 延迟加载依赖
local ShopConfig = nil
local WheelConfig = nil
local WheelDataManager = nil

-- 🔧 关键修复：依赖就绪标志（必须在函数定义前声明）
local dependenciesReady = false

-- 购买处理器注册表
local purchaseHandlers = {}

-- 🔧 关键修复：购买幂等性检查 - 防止重复处理
local processedReceipts = {} -- {[receiptId] = {timestamp = tick(), playerId = userId}}
local RECEIPT_CACHE_DURATION = 600 -- 保留10分钟的记录

-- 清理过期的收据记录
local function cleanupOldReceipts()
	local currentTime = tick()
	local toRemove = {}

	for receiptId, data in pairs(processedReceipts) do
		if currentTime - data.timestamp > RECEIPT_CACHE_DURATION then
			table.insert(toRemove, receiptId)
		end
	end

	for _, receiptId in ipairs(toRemove) do
		processedReceipts[receiptId] = nil
	end
end

-- ============================================
-- 依赖加载
-- ============================================

-- 加载ShopConfig
local function loadShopConfig()
	if not ShopConfig then
		local success, result = pcall(function()
			return require(game.ServerScriptService:WaitForChild("ShopConfig", 10))
		end)
		if success then
			ShopConfig = result
		else
			warn("❌ UnifiedPurchaseManager: ShopConfig加载失败: " .. tostring(result))
		end
	end
	return ShopConfig ~= nil
end

-- 加载WheelConfig
local function loadWheelConfig()
	if not WheelConfig then
		local success, result = pcall(function()
			return require(ReplicatedStorage:WaitForChild("WheelConfig", 10))
		end)
		if success then
			WheelConfig = result
		else
			warn("❌ UnifiedPurchaseManager: WheelConfig加载失败: " .. tostring(result))
		end
	end
	return WheelConfig ~= nil
end

-- 等待WheelDataManager
local function loadWheelDataManager()
	if not WheelDataManager then
		local timeout = 0
		while not _G.WheelDataManager and timeout < 30 do
			task.wait(0.5)
			timeout = timeout + 0.5
		end
		if _G.WheelDataManager then
			WheelDataManager = _G.WheelDataManager
		else
			warn("❌ UnifiedPurchaseManager: WheelDataManager连接超时")
		end
	end
	return WheelDataManager ~= nil
end

-- ============================================
-- 商店商品处理
-- ============================================

-- 处理商店商品购买
local function handleShopProduct(player, productInfo, receiptInfo)
	-- 发放奖励
	if productInfo.itemType == 1 then -- 金币包
		if _G.CoinManager and _G.CoinManager.addCoins then
			-- 🔧 关键修复：使用pcall保护Manager调用
			local callSuccess, addSuccess = pcall(function()
				return _G.CoinManager.addCoins(player, productInfo.rewardValue, "商店购买: " .. productInfo.name)
			end)

			if not callSuccess then
				warn("❌ 金币发放调用异常: " .. player.Name .. " - " .. tostring(addSuccess))
				return false
			end

			if not addSuccess then
				warn("❌ 金币发放失败: " .. player.Name)
				return false
			end
		else
			warn("CoinManager未加载，无法发放金币")
			return false
		end
	elseif productInfo.itemType == 2 then -- 道具
		if _G.PropManager and _G.PropManager.addProp then
			-- 🔧 关键修复：使用pcall保护Manager调用
			local callSuccess, addSuccess = pcall(function()
				return _G.PropManager.addProp(player, productInfo.rewardValue, 1, "商店购买: " .. productInfo.name)
			end)

			if not callSuccess then
				warn("❌ 道具发放调用异常: " .. player.Name .. " - " .. tostring(addSuccess))
				return false
			end

			if not addSuccess then
				warn("❌ 道具发放失败: " .. player.Name)
				return false
			end
		else
			warn("PropManager未加载，无法发放道具")
			return false
		end
	else
		warn("未知的商品类型: " .. tostring(productInfo.itemType))
		return false
	end

	-- 通知客户端（通过ShopManager的事件系统）
	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if remoteEventsFolder then
		local shopEvent = remoteEventsFolder:FindFirstChild("ShopEvent")
		if shopEvent and player.Parent then
			-- 🔧 关键修复：使用pcall保护RemoteEvent调用
			pcall(function()
				shopEvent:FireClient(player, "purchaseSuccess", {
					productId = productInfo.id,
					productName = productInfo.name,
					currencyType = 1 -- ROBUX
				})
			end)
		end
	end

	return true
end

-- ============================================
-- 转盘商品处理
-- ============================================

-- 处理转盘商品购买
local function handleWheelProduct(player, productInfo, receiptInfo)
	-- 发放转盘次数
	if WheelDataManager and WheelDataManager.addSpinCount then
		-- 🔧 关键修复：使用pcall保护Manager调用
		local callSuccess, addSuccess = pcall(function()
			return WheelDataManager.addSpinCount(player, productInfo.spins, "purchase_" .. receiptInfo.ProductId)
		end)

		if not callSuccess then
			warn("❌ 转盘次数发放调用异常: " .. player.Name .. " - " .. tostring(addSuccess))
			return false
		end

		if not addSuccess then
			warn("❌ 转盘次数发放失败: " .. player.Name)
			return false
		end
	else
		warn("WheelDataManager未加载，无法发放转盘次数")
		return false
	end

	-- 通知客户端（通过WheelInteractionManager的事件系统）
	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if remoteEventsFolder then
		local wheelPurchaseEvent = remoteEventsFolder:FindFirstChild("WheelPurchase")
		if wheelPurchaseEvent and player.Parent then
			-- 🔧 关键修复：使用pcall保护RemoteEvent和Manager调用
			pcall(function()
				wheelPurchaseEvent:FireClient(player, "purchaseSuccess", {
					productId = receiptInfo.ProductId,
					spinsAdded = productInfo.spins,
					newSpinCount = WheelDataManager.getSpinCount(player)
				})
			end)
		end
	end

	return true
end

-- ============================================
-- 统一购买处理回调
-- ============================================

-- 主要的ProcessReceipt回调
local function onDeveloperProductPurchase(receiptInfo)
	-- 🔧 关键修复：幂等性检查 - 防止重复处理同一购买
	local receiptId = receiptInfo.PurchaseId
	if processedReceipts[receiptId] then
		-- 这个购买已经处理过了
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		warn("UnifiedPurchaseManager: 玩家不在线 - UserId: " .. receiptInfo.PlayerId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 🔧 关键修复：依赖未就绪时返回NotProcessedYet，让Roblox稍后重试
	-- 这样可以避免脚本启动窗口期内的购买被默认标记为已完成
	if not dependenciesReady then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 1. 首先尝试商店商品
	if loadShopConfig() and ShopConfig.getProductByDeveloperProductId then
		local shopProduct = ShopConfig.getProductByDeveloperProductId(receiptInfo.ProductId)
		if shopProduct then
			local success = handleShopProduct(player, shopProduct, receiptInfo)
			if success then
				-- 🔧 关键修复：记录已处理的收据ID
				processedReceipts[receiptId] = {
					timestamp = tick(),
					playerId = receiptInfo.PlayerId
				}
				return Enum.ProductPurchaseDecision.PurchaseGranted
			else
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
	end

	-- 2. 然后尝试转盘商品
	if loadWheelConfig() and loadWheelDataManager() then
		local wheelProduct = nil
		-- 查找转盘商品
		for _, product in pairs(WheelConfig.DEVELOPER_PRODUCTS) do
			if product.id == receiptInfo.ProductId then
				wheelProduct = product
				break
			end
		end

		if wheelProduct then
			local success = handleWheelProduct(player, wheelProduct, receiptInfo)
			if success then
				-- 🔧 关键修复：记录已处理的收据ID
				processedReceipts[receiptId] = {
					timestamp = tick(),
					playerId = receiptInfo.PlayerId
				}
				return Enum.ProductPurchaseDecision.PurchaseGranted
			else
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
	end

	-- 3. 如果都不匹配，检查是否有其他注册的处理器
	for _, handler in pairs(purchaseHandlers) do
		local result = handler(receiptInfo, player)
		if result ~= nil then
			-- 🔧 关键修复：如果处理成功，记录收据ID
			if result == Enum.ProductPurchaseDecision.PurchaseGranted then
				processedReceipts[receiptId] = {
					timestamp = tick(),
					playerId = receiptInfo.PlayerId
				}
			end
			return result
		end
	end

	-- 4. 最后，未知商品
	warn("UnifiedPurchaseManager: 未知的开发者商品ID - " .. receiptInfo.ProductId)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ============================================
-- 公共接口
-- ============================================

-- 注册自定义购买处理器
function UnifiedPurchaseManager.registerHandler(name, handler)
	purchaseHandlers[name] = handler
end

-- 移除购买处理器
function UnifiedPurchaseManager.removeHandler(name)
	purchaseHandlers[name] = nil
end

-- 初始化管理器
function UnifiedPurchaseManager.initialize()
	-- 🔧 关键修复：立即注册ProcessReceipt回调，防止启动窗口期内购买丢失
	-- 回调内会检查dependenciesReady标志，未就绪时返回NotProcessedYet让Roblox重试
	MarketplaceService.ProcessReceipt = onDeveloperProductPurchase

	-- 异步加载依赖
	task.spawn(function()
		-- 加载核心配置（阻塞式，确保完成）
		loadShopConfig()
		loadWheelConfig()
		loadWheelDataManager()

		-- 标记核心依赖已就绪
		dependenciesReady = true
	end)

	-- 🔧 注册连胜恢复商品处理器
	task.spawn(function()
		task.wait(3) -- 等待WinStreakPurchaseManager加载
		if _G.WinStreakPurchaseManager then
			UnifiedPurchaseManager.registerHandler("winstreak_restore", function(receiptInfo, player)
				-- 处理连胜恢复商品 (ProductId: 3414342081)
				if receiptInfo.ProductId == 3414342081 then
					-- 🔧 关键修复：使用pcall保护Manager调用
					local callSuccess, success = pcall(function()
						return _G.WinStreakPurchaseManager.onPurchaseSuccess(player)
					end)

					if not callSuccess then
						warn("❌ 连胜恢复调用异常: " .. player.Name .. " - " .. tostring(success))
						return Enum.ProductPurchaseDecision.NotProcessedYet
					end

					if success then
						return Enum.ProductPurchaseDecision.PurchaseGranted
					else
						return Enum.ProductPurchaseDecision.NotProcessedYet
					end
				end
				return nil -- 不是连胜恢复商品，让其他处理器处理
			end)
		end
	end)

	-- 🔧 注册毒药选择额外毒药商品处理器
	task.spawn(function()
		task.wait(4) -- 等待PoisonSelectionManager加载
		if _G.PoisonSelectionManager then
			UnifiedPurchaseManager.registerHandler("poison_extra", function(receiptInfo, player)
				-- 处理额外毒药商品 (ProductId: 3416569819)
				if receiptInfo.ProductId == 3416569819 then
					-- 检查PoisonSelectionManager是否有处理接口
					if _G.PoisonSelectionManager.onDeveloperProductPurchaseSuccess then
						-- 🔧 关键修复：使用pcall保护Manager调用
						local callSuccess, success = pcall(function()
							return _G.PoisonSelectionManager.onDeveloperProductPurchaseSuccess(player, receiptInfo.ProductId)
						end)

						if not callSuccess then
							warn("❌ 额外毒药购买调用异常: " .. player.Name .. " - " .. tostring(success))
							return Enum.ProductPurchaseDecision.NotProcessedYet
						end

						if success then
							return Enum.ProductPurchaseDecision.PurchaseGranted
						else
							return Enum.ProductPurchaseDecision.NotProcessedYet
						end
					else
						warn("❌ UnifiedPurchaseManager: PoisonSelectionManager.onDeveloperProductPurchaseSuccess方法不存在")
						return Enum.ProductPurchaseDecision.NotProcessedYet
					end
				end
				return nil -- 不是额外毒药商品，让其他处理器处理
			end)
		end
	end)

	-- 🔧 关键修复：启动定期清理任务，防止processedReceipts无限增长
	task.spawn(function()
		while true do
			task.wait(60) -- 每60秒清理一次过期记录
			cleanupOldReceipts()
		end
	end)
end

-- 启动管理器
UnifiedPurchaseManager.initialize()

-- 导出到全局
_G.UnifiedPurchaseManager = UnifiedPurchaseManager

return UnifiedPurchaseManager