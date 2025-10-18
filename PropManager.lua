-- 脚本名称: PropManager
-- 脚本作用: 服务端道具管理系统，处理道具数据存储、购买、使用等逻辑
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local PropManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- 引入配置
local PropConfig = require(script.Parent.PropConfig)

-- 检测是否在Studio环境
local isStudio = RunService:IsStudio()

-- 数据存储
local PropDataStore = nil
if not isStudio then
	PropDataStore = DataStoreService:GetDataStore("PlayerPropData")
else
	-- Studio环境，跳过DataStore初始化
end

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

local propUpdateEvent = remoteEventsFolder:FindFirstChild("PropUpdate")
local propUseEvent = remoteEventsFolder:FindFirstChild("PropUse")
local propPurchaseEvent = remoteEventsFolder:FindFirstChild("PropPurchase")

-- 检查RemoteEvents状态

-- 创建RemoteEvents（如果不存在）
if not propUpdateEvent then
	propUpdateEvent = Instance.new("RemoteEvent")
	propUpdateEvent.Name = "PropUpdate"
	propUpdateEvent.Parent = remoteEventsFolder
end

if not propUseEvent then
	propUseEvent = Instance.new("RemoteEvent")
	propUseEvent.Name = "PropUse"
	propUseEvent.Parent = remoteEventsFolder
end

if not propPurchaseEvent then
	propPurchaseEvent = Instance.new("RemoteEvent")
	propPurchaseEvent.Name = "PropPurchase"
	propPurchaseEvent.Parent = remoteEventsFolder
end

-- 玩家道具数据
local playerPropData = {}

-- 默认道具数据（V2.0结构 - 支持新手礼包）
local DEFAULT_PROP_DATA = {
	props = {
		[1] = 0, -- 毒药验证
		[2] = 0, -- 跳过选择
		[3] = 0  -- 清除毒药
	},
	hasReceivedNewPlayerGift = false,  -- 🆕 V1.9: 是否已领取新手礼包
	version = 2  -- 🆕 数据版本号
}

-- 初始化玩家道具数据
function PropManager.initializePlayerData(player)

	local success = false
	local data = nil

	-- 仅在非Studio环境尝试从DataStore加载数据
	if PropDataStore then
		success, data = pcall(function()
			return PropDataStore:GetAsync("Player_" .. player.UserId)
		end)
	end

	if success and data then
		-- 🆕 V1.9: 数据迁移逻辑 - 将旧版本数据结构迁移到新版本
		if data and not data.version then
			-- 检测到旧数据格式（V1版本），执行迁移
			local migratedData = {
				props = data,  -- 旧数据直接作为props
				hasReceivedNewPlayerGift = false,  -- 默认未领取
				version = 2
			}

			data = migratedData

			-- 立即保存迁移后的数据
			playerPropData[player] = data
			PropManager.savePlayerData(player)
		end

		playerPropData[player] = data
	else
		-- 使用默认数据（深拷贝）
		playerPropData[player] = {
			props = {},
			hasReceivedNewPlayerGift = false,
			version = 2
		}

		-- 复制默认道具数量
		for propId, quantity in pairs(DEFAULT_PROP_DATA.props) do
			playerPropData[player].props[propId] = quantity
		end
	end

	-- 发送初始数据到客户端
	PropManager.syncPlayerData(player)
end

-- 保存玩家道具数据
function PropManager.savePlayerData(player)
	if not playerPropData[player] then return end

	-- 仅在非Studio环境保存到DataStore
	if not PropDataStore then
		if not isStudio then
			warn("PropDataStore未初始化，无法保存数据")
		end
		return
	end

	local success, error = pcall(function()
		PropDataStore:SetAsync("Player_" .. player.UserId, playerPropData[player])
	end)

	if not success then
		warn("保存玩家 " .. player.Name .. " 的道具数据失败: " .. tostring(error))
	end
end

-- 同步玩家数据到客户端
function PropManager.syncPlayerData(player)
	if not playerPropData[player] then
		warn("PropManager.syncPlayerData: 玩家 " .. player.Name .. " 数据不存在")
		return
	end

	-- 同步玩家道具数据到客户端

	if not propUpdateEvent then
		warn("PropManager.syncPlayerData: propUpdateEvent 不存在，无法同步数据")
		return
	end

	propUpdateEvent:FireClient(player, "syncData", {
		propData = playerPropData[player]
	})
end

-- 获取玩家道具数量
function PropManager.getPropQuantity(player, propId)
	if not playerPropData[player] or not PropConfig.isValidPropId(propId) then
		return 0
	end

	return playerPropData[player].props[propId] or 0
end

-- 增加道具数量
function PropManager.addProp(player, propId, quantity)
	if not playerPropData[player] or not PropConfig.isValidPropId(propId) then
		return false
	end

	quantity = quantity or 1
	local currentQuantity = playerPropData[player].props[propId] or 0
	playerPropData[player].props[propId] = currentQuantity + quantity

	-- 同步到客户端
	PropManager.syncPlayerData(player)

	-- 保存数据
	PropManager.savePlayerData(player)

	return true
end

-- 消耗道具
function PropManager.consumeProp(player, propId, quantity)
	if not playerPropData[player] or not PropConfig.isValidPropId(propId) then
		return false
	end

	quantity = quantity or 1
	local currentQuantity = playerPropData[player].props[propId] or 0

	if currentQuantity < quantity then
		return false -- 数量不足
	end

	playerPropData[player].props[propId] = currentQuantity - quantity

	-- 同步到客户端
	PropManager.syncPlayerData(player)

	-- 保存数据
	PropManager.savePlayerData(player)

	return true
end

-- 处理道具使用
function PropManager.handlePropUse(player, propId)
	if not PropConfig.isValidPropId(propId) then
		return
	end

	local propInfo = PropConfig.getPropInfo(propId)

	-- 调试：检查玩家数据状态
	if not playerPropData[player] then
		warn("玩家 " .. player.Name .. " 的道具数据未初始化")
		propUseEvent:FireClient(player, "failed", {
			reason = "数据错误，请重新进入游戏"
		})
		return
	end

	-- 检查玩家是否有足够的道具
	local currentQuantity = PropManager.getPropQuantity(player, propId)

	if currentQuantity <= 0 then
		propUseEvent:FireClient(player, "failed", {
			reason = "没有该道具"
		})
		return
	end

	-- 检查是否在选择阶段且轮到该玩家
	local DrinkSelectionManager = nil
	if _G.DrinkSelectionManager then
		DrinkSelectionManager = _G.DrinkSelectionManager
	else
		-- 尝试require DrinkSelectionManager
		local serverScriptService = game:GetService("ServerScriptService")
		local drinkSelectionScript = serverScriptService:FindFirstChild("DrinkSelectionManager")
		if drinkSelectionScript then
			DrinkSelectionManager = require(drinkSelectionScript)
		end
	end

	if not DrinkSelectionManager then
		warn("无法获取DrinkSelectionManager")
		propUseEvent:FireClient(player, "failed", {
			reason = "系统错误"
		})
		return
	end

	-- 检查是否在选择阶段
	if not DrinkSelectionManager.isSelectionPhaseActive() then
		propUseEvent:FireClient(player, "failed", {
			reason = "Please wait for the opponent to choose"
		})
		return
	end

	-- 检查是否轮到该玩家
	local currentPlayer = DrinkSelectionManager.getCurrentPlayer()
	if currentPlayer ~= player then
		propUseEvent:FireClient(player, "failed", {
			reason = "Please wait for the opponent to choose"
		})
		return
	end

	-- 再次检查道具数量（防止并发问题）
	local finalQuantity = PropManager.getPropQuantity(player, propId)

	if finalQuantity <= 0 then
		propUseEvent:FireClient(player, "failed", {
			reason = "没有该道具"
		})
		return
	end

	-- 特殊检查：清除毒药道具的每局限用一次
	if propId == 3 and _G.PropEffectHandler and _G.PropEffectHandler.checkPoisonCleanUsage then
		local canUse, reason = _G.PropEffectHandler.checkPoisonCleanUsage(player)
		if not canUse then
			propUseEvent:FireClient(player, "failed", {
				reason = reason
			})
			return
		end
	end

	-- 消耗道具
	local success = PropManager.consumeProp(player, propId, 1)
	if not success then
		propUseEvent:FireClient(player, "failed", {
			reason = "使用道具失败"
		})
		return
	end

	-- 通知客户端使用成功
	propUseEvent:FireClient(player, "success", {
		propId = propId,
		propName = propInfo.name
	})

	-- 这里可以添加具体的道具效果处理
	-- 调用PropEffectHandler来处理道具效果
	if _G.PropEffectHandler and _G.PropEffectHandler.executePropEffect then
		local effectSuccess = _G.PropEffectHandler.executePropEffect(player, propId)
		if not effectSuccess then
			warn("道具效果执行失败，但道具已被消耗")
		end
	else
		warn("PropEffectHandler未加载，无法执行道具效果")
	end
end
-- 🔧 修复：移除冗余的开发者商品购买处理函数
-- 道具购买现在通过ShopManager + UnifiedPurchaseManager统一处理
-- 保留函数接口用于兼容性，但重定向到正确的购买流程
function PropManager.handleDeveloperProductPurchase(player, propId)
	if not PropConfig.isValidPropId(propId) then
		return
	end

	local propInfo = PropConfig.getPropInfo(propId)

	-- 获取开发者商品ID
	local developerProductId = propInfo.robuxProductId
	if developerProductId == 0 then
		warn("道具 " .. propInfo.name .. " 没有配置开发者商品ID")
		propPurchaseEvent:FireClient(player, "failed", {
			reason = "该道具暂时无法购买"
		})
		return
	end

	-- 🔧 修复：重定向到ShopManager处理购买
	-- PropManager的道具商品已在ShopConfig中定义，应使用统一的购买系统
	if _G.ShopManager and _G.ShopManager.handlePurchaseRequest then
		-- 查找对应的ShopConfig商品ID
		local shopProductId = nil
		if _G.ShopConfig and _G.ShopConfig.getProductByDeveloperProductId then
			local shopProduct = _G.ShopConfig.getProductByDeveloperProductId(developerProductId)
			if shopProduct then
				shopProductId = shopProduct.id
			end
		end

		if shopProductId then
			-- 使用ShopManager的统一购买流程
			_G.ShopManager.handlePurchaseRequest(player, {productId = shopProductId})
		else
			-- ✅ 修复：增强日志信息，便于调试ShopConfig配置问题
			print("⚠️ PropManager: 开发者商品ID " .. developerProductId .. " 未在ShopConfig中定义")
			print("   道具: " .. propInfo.name .. " (ID: " .. propId .. ")")
			print("   使用备用购买方案，直接调用Robux购买")
			MarketplaceService:PromptProductPurchase(player, developerProductId)
		end
	else
		-- 备用方案：直接调用MarketplaceService
		warn("PropManager: ShopManager未加载，使用备用购买方案")
		MarketplaceService:PromptProductPurchase(player, developerProductId)
	end
end

-- 处理玩家加入
function PropManager.onPlayerAdded(player)
	-- 延迟初始化，等待其他系统加载
	spawn(function()
		wait(2)
		PropManager.initializePlayerData(player)
	end)
end

-- 处理玩家离开
function PropManager.onPlayerRemoving(player)
	if playerPropData[player] then
		PropManager.savePlayerData(player)
		playerPropData[player] = nil
	end
end

-- 设置事件监听
function PropManager.setupEvents()
	-- 玩家加入/离开事件
	Players.PlayerAdded:Connect(PropManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(PropManager.onPlayerRemoving)

	-- 处理已存在的玩家
	for _, player in pairs(Players:GetPlayers()) do
		PropManager.onPlayerAdded(player)
	end

	-- 道具使用事件
	propUseEvent.OnServerEvent:Connect(function(player, action, data)
		if action == "useProp" and data.propId then
			PropManager.handlePropUse(player, data.propId)
		end
	end)

	-- 道具购买事件
	propPurchaseEvent.OnServerEvent:Connect(function(player, action, data)
		if action == "buyDeveloperProduct" and data.propId then
			PropManager.handleDeveloperProductPurchase(player, data.propId)
		end
	end)

	-- PropManager 事件监听已设置
end

-- 初始化PropManager
function PropManager.initialize()
	PropManager.setupEvents()
end

-- 启动PropManager
PropManager.initialize()

-- V1.9: 新手礼包相关接口函数

-- 检查玩家是否已领取新手礼包
-- 🔧 V1.9.1: 修复数据未加载时的返回值问题
-- 返回值：true=已领取, false=未领取, nil=数据未加载
function PropManager.hasReceivedNewPlayerGift(player)
	if not playerPropData[player] then
		-- 数据未加载，返回nil（而不是false）
		-- 调用方需要处理nil的情况
		return nil
	end

	return playerPropData[player].hasReceivedNewPlayerGift or false
end

-- 标记玩家已领取新手礼包
function PropManager.markNewPlayerGiftReceived(player)
	if not playerPropData[player] then
		warn("PropManager.markNewPlayerGiftReceived: 玩家 " .. player.Name .. " 数据不存在")
		return false
	end

	playerPropData[player].hasReceivedNewPlayerGift = true

	-- 保存数据
	PropManager.savePlayerData(player)

	return true
end

-- 发放新手礼包道具（验证毒药×3 + 跳过阶段×3）
function PropManager.grantNewPlayerGiftProps(player)
	if not playerPropData[player] then
		warn("PropManager.grantNewPlayerGiftProps: 玩家 " .. player.Name .. " 数据不存在")
		return false
	end

	-- 发放道具1（验证毒药）×3
	local success1 = PropManager.addProp(player, 1, 3)

	-- 发放道具2（跳过阶段）×3
	local success2 = PropManager.addProp(player, 2, 3)

	if success1 and success2 then
		return true
	else
		warn("PropManager.grantNewPlayerGiftProps: 道具发放失败")
		return false
	end
end

-- 检查玩家数据是否已加载（供GamePassManager使用）
function PropManager.isPlayerDataLoaded(player)
	return playerPropData[player] ~= nil
end

-- 🧪 测试用：重置玩家的新手礼包领取状态（仅用于开发测试）
function PropManager.resetNewPlayerGiftForTesting(player)
	if not player then
		warn("PropManager.resetNewPlayerGiftForTesting: 玩家参数为空")
		return false
	end

	if not playerPropData[player] then
		warn("PropManager.resetNewPlayerGiftForTesting: 玩家 " .. player.Name .. " 数据未加载")
		return false
	end

	-- 重置领取标志
	playerPropData[player].hasReceivedNewPlayerGift = false

	-- 立即保存
	PropManager.savePlayerData(player)

	return true
end

-- 导出到全局供其他脚本使用
_G.PropManager = PropManager

return PropManager