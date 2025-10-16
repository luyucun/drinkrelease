-- 脚本名称: SkinDataManager
-- 脚本作用: V2.0皮肤系统数据管理器,处理皮肤购买/切换/持久化
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinDataStore = DataStoreService:GetDataStore("PlayerSkinData_V1")

-- 🔧 关键修复：SkinConfig放在ReplicatedStorage中，直接从那里加载
local SkinConfig = nil

-- 安全加载SkinConfig，带错误处理
local function loadSkinConfig()
	if SkinConfig then
		return SkinConfig
	end

	-- 优先从ReplicatedStorage加载（因为SkinConfig位于ReplicatedStorage）
	local success, result = pcall(function()
		return require(ReplicatedStorage:WaitForChild("SkinConfig", 5))
	end)

	if success then
		SkinConfig = result
		print("✅ SkinConfig从ReplicatedStorage加载成功")
		return SkinConfig
	else
		warn("❌ 从ReplicatedStorage加载SkinConfig失败: " .. tostring(result))
	end

	-- 备用方案：尝试从ServerScriptService加载
	success, result = pcall(function()
		return require(script.Parent.SkinConfig)
	end)

	if success then
		SkinConfig = result
		print("⚠️ SkinConfig从ServerScriptService加载成功（备用方案）")
		return SkinConfig
	else
		warn("❌ 从ServerScriptService加载SkinConfig也失败: " .. tostring(result))
	end

	-- 最后的备用方案：创建一个基本的SkinConfig替代品
	warn("🚨 SkinConfig加载完全失败，使用最小化配置")
	SkinConfig = {
		isValidSkinId = function(skinId)
			-- 基本验证：检查是否为数字且在合理范围内
			return type(skinId) == "number" and skinId >= 1001 and skinId <= 9999
		end,
		getSkinInfo = function(skinId)
			-- 返回基本信息
			return {
				id = skinId,
				name = "Unknown Skin " .. skinId,
				price = 100,
				modelName = "Default01",
				displayModelName = "Default01Show",
				iconAssetId = ""
			}
		end,
		validateAllSkins = function()
			warn("SkinConfig.validateAllSkins: 使用最小化配置，跳过验证")
		end
	}
	return SkinConfig
end

local SkinDataManager = {}

-- 玩家皮肤数据缓存
-- 格式: {[player] = {ownedSkins = {1001, 1002}, equippedSkin = 1001, version = 1}}
local playerSkinData = {}

-- 购买锁,防止并发购买导致金币异常
local purchaseLocks = {}

-- 冷却记录,防止ProximityPrompt重复触发
local purchaseCooldowns = {}
local COOLDOWN_TIME = 2  -- 2秒冷却

-- 默认数据结构
local DEFAULT_SKIN_DATA = {
	ownedSkins = {},        -- 空列表,默认无皮肤
	equippedSkin = nil,     -- nil表示使用默认皮肤(Default01/Default02)
	version = 1
}

-- 获取/创建RemoteEvents文件夹
local function getRemoteEventsFolder()
	local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		folder.Parent = ReplicatedStorage
	end
	return folder
end

local remoteEventsFolder = getRemoteEventsFolder()

-- 创建RemoteEvents
local function createRemoteEvent(name)
	local existing = remoteEventsFolder:FindFirstChild(name)
	if existing then
		return existing
	end

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = name
	remoteEvent.Parent = remoteEventsFolder
	return remoteEvent
end

local SkinPurchaseEvent = createRemoteEvent("SkinPurchase")
local SkinEquipEvent = createRemoteEvent("SkinEquip")
local SkinDataSyncEvent = createRemoteEvent("SkinDataSync")

-- ============================================
-- 数据加载/保存
-- ============================================

-- 初始化玩家皮肤数据
function SkinDataManager.initializePlayerData(player)
	if playerSkinData[player] then
		warn("玩家数据已存在,跳过初始化: " .. player.Name)
		return
	end

	local userId = player.UserId
	local success, data = pcall(function()
		return SkinDataStore:GetAsync("Player_" .. userId)
	end)

	if success and data then
		-- 加载成功,验证数据完整性
		if type(data.ownedSkins) ~= "table" then
			data.ownedSkins = {}
		else
			-- 🔧 修复：验证ownedSkins数组中的每个元素都是有效的数字皮肤ID
			local validSkins = {}
			local skinConfig = loadSkinConfig()
			for _, skinId in ipairs(data.ownedSkins) do
				if type(skinId) == "number" and skinConfig.isValidSkinId(skinId) then
					table.insert(validSkins, skinId)
				else
					warn("SkinDataManager: 移除无效皮肤ID: " .. tostring(skinId))
				end
			end
			data.ownedSkins = validSkins
		end
		if type(data.equippedSkin) ~= "number" and data.equippedSkin ~= nil then
			data.equippedSkin = nil
		elseif data.equippedSkin then
			local skinConfig = loadSkinConfig()
			if not skinConfig.isValidSkinId(data.equippedSkin) then
				-- 🔧 修复：如果装备的皮肤ID无效，重置为nil
				warn("SkinDataManager: 重置无效装备皮肤ID: " .. tostring(data.equippedSkin))
				data.equippedSkin = nil
			end
		end
		if not data.version then
			data.version = 1
		end

		playerSkinData[player] = data
	else
		-- 加载失败或新玩家,使用默认数据
		playerSkinData[player] = {
			ownedSkins = {},
			equippedSkin = nil,
			version = 1
		}
	end

	-- 立即同步数据到客户端
	SkinDataManager.syncDataToClient(player)
end

-- 保存玩家皮肤数据
function SkinDataManager.savePlayerData(player)
	if not playerSkinData[player] then
		warn("玩家数据不存在,无法保存: " .. player.Name)
		return false
	end

	local userId = player.UserId
	local data = playerSkinData[player]

	local success, errorMsg = pcall(function()
		SkinDataStore:SetAsync("Player_" .. userId, data)
	end)

	if not success then
		warn("保存玩家皮肤数据失败: " .. player.Name .. " - " .. tostring(errorMsg))
		return false
	end

	return true
end

-- 玩家离开时保存数据
local function onPlayerRemoving(player)
	SkinDataManager.savePlayerData(player)
	playerSkinData[player] = nil
	purchaseLocks[player.UserId] = nil
	purchaseCooldowns[player.UserId] = nil
end

-- ============================================
-- 数据查询接口
-- ============================================

-- 检查玩家是否拥有皮肤
function SkinDataManager.hasSkin(player, skinId)
	local data = playerSkinData[player]
	if not data then
		return false
	end

	for _, ownedId in ipairs(data.ownedSkins) do
		if ownedId == skinId then
			return true
		end
	end

	return false
end

-- 获取玩家当前装备的皮肤ID
function SkinDataManager.getEquippedSkin(player)
	local data = playerSkinData[player]
	if not data then
		return nil
	end

	return data.equippedSkin
end

-- 获取玩家拥有的所有皮肤
function SkinDataManager.getOwnedSkins(player)
	local data = playerSkinData[player]
	if not data then
		return {}
	end

	return data.ownedSkins
end

-- 检查玩家数据是否已加载
function SkinDataManager.isPlayerDataLoaded(player)
	return playerSkinData[player] ~= nil
end

-- ============================================
-- 购买逻辑
-- ============================================

-- 内部购买逻辑(已上锁状态下调用)
local function purchaseSkinInternal(player, skinId)
	-- 1. 验证玩家数据已加载
	if not playerSkinData[player] then
		return false, "data_not_loaded"
	end

	-- 2. 验证皮肤ID有效
	local skinConfig = loadSkinConfig()
	if not skinConfig.isValidSkinId(skinId) then
		return false, "invalid_skin"
	end

	-- 3. 检查是否已拥有
	if SkinDataManager.hasSkin(player, skinId) then
		return false, "already_owned"
	end

	-- 4. 检查金币余额
	local skinInfo = skinConfig.getSkinInfo(skinId)
	local currentCoins = 0

	if _G.CoinManager and _G.CoinManager.getCoins then
		currentCoins = _G.CoinManager.getCoins(player)
	else
		warn("CoinManager未加载,无法验证金币")
		return false, "coin_manager_not_loaded"
	end

	if currentCoins < skinInfo.price then
		return false, "insufficient_coins"
	end

	-- 5. 扣除金币
	local success = false
	if _G.CoinManager and _G.CoinManager.removeCoins then
		success = _G.CoinManager.removeCoins(player, skinInfo.price, "购买皮肤:" .. skinInfo.name)
	else
		return false, "coin_manager_not_loaded"
	end

	if not success then
		return false, "coin_deduction_failed"
	end

	-- 6. 添加到拥有列表 (防止重复添加)
	-- 双重检查: 即使之前检查过,这里再检查一次以防万一
	local alreadyExists = false
	for _, ownedId in ipairs(playerSkinData[player].ownedSkins) do
		if ownedId == skinId then
			alreadyExists = true
			break
		end
	end

	if not alreadyExists then
		table.insert(playerSkinData[player].ownedSkins, skinId)
	else
		warn(string.format("警告: 皮肤%d已在玩家%s的列表中,跳过添加", skinId, player.Name))
	end

	-- 7. 自动装备新购买的皮肤
	playerSkinData[player].equippedSkin = skinId

	-- 8. 保存数据
	SkinDataManager.savePlayerData(player)

	-- 9. 同步数据到客户端
	SkinDataManager.syncDataToClient(player)

	return true, "success"
end

-- 购买皮肤(带购买锁)
function SkinDataManager.purchaseSkin(player, skinId)
	local userId = player.UserId

	-- 检查冷却
	local now = tick()
	if purchaseCooldowns[userId] and (now - purchaseCooldowns[userId] < COOLDOWN_TIME) then
		return false, "cooldown"
	end

	-- 检查是否正在购买
	if purchaseLocks[userId] then
		return false, "purchasing"
	end

	-- 立即上锁
	purchaseLocks[userId] = true
	purchaseCooldowns[userId] = now

	-- 执行购买逻辑
	local success, message = purchaseSkinInternal(player, skinId)

	-- 解锁
	purchaseLocks[userId] = nil

	return success, message
end

-- ============================================
-- 直投逻辑 (新增功能)
-- ============================================

-- 直接投放皮肤接口 (绕过金币验证)
function SkinDataManager.grantSkin(player, skinId, source)
	source = source or "direct_grant"

	-- 1. 验证玩家数据已加载
	if not playerSkinData[player] then
		warn("SkinDataManager.grantSkin: 玩家数据未加载 - " .. player.Name)
		return false, "data_not_loaded"
	end

	-- 2. 验证皮肤ID有效
	local skinConfig = loadSkinConfig()
	if not skinConfig.isValidSkinId(skinId) then
		warn("SkinDataManager.grantSkin: 皮肤ID无效 - " .. skinId)
		return false, "invalid_skin"
	end

	-- 3. 检查是否已拥有（允许重复投放，返回成功避免报错）
	if SkinDataManager.hasSkin(player, skinId) then
		print("SkinDataManager.grantSkin: 玩家已拥有皮肤 - " .. player.Name .. ", skinId: " .. skinId)
		return true, "already_owned"
	end

	-- 4. 添加到拥有列表
	table.insert(playerSkinData[player].ownedSkins, skinId)

	-- 5. 记录投放日志
	print("✅ [SkinDataManager] 直投皮肤成功: " .. player.Name .. " 获得皮肤 " .. skinId .. " (来源: " .. source .. ")")

	-- 6. 保存数据
	SkinDataManager.savePlayerData(player)

	-- 7. 同步到客户端
	SkinDataManager.syncDataToClient(player)

	return true, "success"
end

-- 批量投放皮肤接口
function SkinDataManager.grantSkins(player, skinIds, source)
	if not skinIds or type(skinIds) ~= "table" then
		warn("SkinDataManager.grantSkins: skinIds必须是数组")
		return {}
	end

	local results = {}
	for _, skinId in ipairs(skinIds) do
		local success, message = SkinDataManager.grantSkin(player, skinId, source)
		table.insert(results, {skinId = skinId, success = success, message = message})
	end

	print("📦 [SkinDataManager] 批量投放完成: " .. player.Name .. " 处理 " .. #skinIds .. " 个皮肤")
	return results
end

-- ============================================
-- 装备逻辑
-- ============================================

-- 装备皮肤
function SkinDataManager.equipSkin(player, skinId)
	-- 1. 验证玩家数据已加载
	if not playerSkinData[player] then
		return false, "data_not_loaded"
	end

	-- 2. 验证皮肤ID有效
	local skinConfig = loadSkinConfig()
	if not skinConfig.isValidSkinId(skinId) then
		return false, "invalid_skin"
	end

	-- 3. 检查是否拥有该皮肤
	if not SkinDataManager.hasSkin(player, skinId) then
		return false, "not_owned"
	end

	-- 4. 检查玩家是否在对局中(禁止对局中切换)
	if _G.TableManager then
		local tableId = _G.TableManager.detectPlayerTable(player)
		if tableId then
			local gameInstance = _G.TableManager.getTableInstance(tableId)
			if gameInstance and gameInstance.gameState.gamePhase ~= "waiting" then
				-- 玩家在对局中,不允许切换
				return false, "in_game"
			end
		end
	end

	-- 5. 装备皮肤
	playerSkinData[player].equippedSkin = skinId

	-- 6. 保存数据
	SkinDataManager.savePlayerData(player)

	-- 7. 同步数据到客户端
	SkinDataManager.syncDataToClient(player)

	return true, "success"
end

-- ============================================
-- 客户端通信
-- ============================================

-- 同步数据到客户端
function SkinDataManager.syncDataToClient(player)
	if not playerSkinData[player] then
		return
	end

	SkinDataSyncEvent:FireClient(player, "sync", {
		ownedSkins = playerSkinData[player].ownedSkins,
		equippedSkin = playerSkinData[player].equippedSkin
	})
end

-- 处理客户端购买请求
local function onPurchaseRequest(player, action, data)
	if action == "purchase" and data and data.skinId then
		local success, message = SkinDataManager.purchaseSkin(player, data.skinId)

		-- 发送购买结果到客户端
		if success then
			SkinPurchaseEvent:FireClient(player, "purchaseSuccess", {
				skinId = data.skinId,
				ownedSkins = playerSkinData[player].ownedSkins,
				equippedSkin = playerSkinData[player].equippedSkin
			})
		else
			SkinPurchaseEvent:FireClient(player, "purchaseFailed", {
				skinId = data.skinId,
				reason = message
			})
		end
	end
end

-- 处理客户端切换请求
local function onEquipRequest(player, action, data)
	if action == "equip" and data and data.skinId then
		local success, message = SkinDataManager.equipSkin(player, data.skinId)

		-- 发送切换结果到客户端
		if success then
			SkinEquipEvent:FireClient(player, "equipSuccess", {
				skinId = data.skinId,
				equippedSkin = playerSkinData[player].equippedSkin
			})
		else
			SkinEquipEvent:FireClient(player, "equipFailed", {
				skinId = data.skinId,
				reason = message
			})
		end
	end
end

-- ============================================
-- 初始化
-- ============================================

function SkinDataManager.initialize()
	-- 监听RemoteEvents
	SkinPurchaseEvent.OnServerEvent:Connect(onPurchaseRequest)
	SkinEquipEvent.OnServerEvent:Connect(onEquipRequest)

	-- 监听玩家加入
	Players.PlayerAdded:Connect(function(player)
		SkinDataManager.initializePlayerData(player)
	end)

	-- 监听玩家离开
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- 为已存在的玩家初始化数据
	for _, player in ipairs(Players:GetPlayers()) do
		SkinDataManager.initializePlayerData(player)
	end
end

-- 启动时验证所有皮肤模型
task.spawn(function()
	task.wait(2)  -- 等待游戏完全加载
	local skinConfig = loadSkinConfig()
	if skinConfig and skinConfig.validateAllSkins then
		skinConfig.validateAllSkins()
	else
		warn("SkinDataManager: 无法验证皮肤模型，SkinConfig不可用")
	end
end)

-- 注册为全局管理器
_G.SkinDataManager = SkinDataManager

-- 自动初始化
SkinDataManager.initialize()

return SkinDataManager
