-- 脚本名称: EmoteDataManager
-- 脚本作用: 跳舞动作数据管理，处理DataStore、玩家拥有的动作、装备状态
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local EmoteDataManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- 引入配置
local EmoteConfig = require(ReplicatedStorage:WaitForChild("EmoteConfig"))

-- 检测是否在Studio环境
local isStudio = RunService:IsStudio()

-- DataStore
local EmoteDataStore = nil
if not isStudio then
	EmoteDataStore = DataStoreService:GetDataStore("PlayerEmoteData")
end

-- 玩家动作数据缓存
local playerEmoteData = {}  -- {[player] = EmoteData}

-- DataStore Key前缀
local KEY_PREFIX = "Emote_"

-- 默认数据结构（V2版本）
local DEFAULT_EMOTE_DATA = {
	ownedEmotes = {1001},  -- 默认拥有Default动作
	equippedEmote = 1001,   -- 默认装备Default动作
	version = 2
}

-- RemoteEvents（延迟加载）
local remoteEventsFolder = nil
local emoteDataSyncEvent = nil
local emoteEquipEvent = nil

-- 购买进行中标志（防止并发购买）
local purchaseInProgress = {}

-- ============================================
-- 工具函数
-- ============================================

-- 获取玩家的DataStore Key
local function getPlayerKey(player)
	return KEY_PREFIX .. player.UserId
end

-- 深拷贝动作列表
local function copyEmoteList(emoteList)
	local copy = {}
	for _, emoteId in ipairs(emoteList) do
		table.insert(copy, emoteId)
	end
	return copy
end

-- 检查列表中是否包含动作ID
local function containsEmote(emoteList, emoteId)
	return table.find(emoteList, emoteId) ~= nil
end

-- ============================================
-- RemoteEvents初始化
-- ============================================

local function getRemoteEvents()
	if not remoteEventsFolder then
		remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
		if not remoteEventsFolder then
			warn("EmoteDataManager: RemoteEvents文件夹加载超时")
			return false
		end
	end

	if not emoteDataSyncEvent then
		emoteDataSyncEvent = remoteEventsFolder:FindFirstChild("EmoteDataSync")
		if not emoteDataSyncEvent then
			-- 创建RemoteEvent
			emoteDataSyncEvent = Instance.new("RemoteEvent")
			emoteDataSyncEvent.Name = "EmoteDataSync"
			emoteDataSyncEvent.Parent = remoteEventsFolder
		end
	end

	if not emoteEquipEvent then
		emoteEquipEvent = remoteEventsFolder:FindFirstChild("EmoteEquip")
		if not emoteEquipEvent then
			-- 创建RemoteEvent
			emoteEquipEvent = Instance.new("RemoteEvent")
			emoteEquipEvent.Name = "EmoteEquip"
			emoteEquipEvent.Parent = remoteEventsFolder
		end
	end

	return true
end

-- ============================================
-- 数据迁移
-- ============================================

-- 从V1迁移到V2
local function migrateData(oldData)
	if not oldData then
		return nil
	end

	-- 检查版本号
	if oldData.version == 2 then
		-- 已是V2版本，验证数据完整性
		if not oldData.ownedEmotes or not oldData.equippedEmote then
			warn("EmoteDataManager: V2数据不完整，重建")
			return nil
		end
		return oldData
	end

	-- V1 -> V2 迁移
	local newData = {
		ownedEmotes = {},
		equippedEmote = 1001,
		version = 2
	}

	-- 将V1的键值对转换为数组
	for key, value in pairs(oldData) do
		if type(key) == "number" and value == true then
			-- V1格式：[emoteId] = true
			table.insert(newData.ownedEmotes, key)
		end
	end

	-- 确保包含默认动作1001
	if not containsEmote(newData.ownedEmotes, 1001) then
		table.insert(newData.ownedEmotes, 1001)
	end

	-- 排序（保持一致性）
	table.sort(newData.ownedEmotes)

	return newData
end

-- ============================================
-- 数据加载与保存
-- ============================================

-- 初始化玩家数据
function EmoteDataManager.initializePlayerData(player)
	if not player then
		warn("EmoteDataManager.initializePlayerData: player为空")
		return
	end

	local success = false
	local data = nil

	-- 仅在非Studio环境尝试从DataStore加载
	if EmoteDataStore then
		success, data = pcall(function()
			return EmoteDataStore:GetAsync(getPlayerKey(player))
		end)

		if not success then
			warn("EmoteDataManager: 加载玩家 " .. player.Name .. " 数据失败: " .. tostring(data))
			data = nil
		end
	end

	-- 数据处理
	if success and data then
		-- 尝试迁移数据
		data = migrateData(data)

		if not data then
			-- 迁移失败，使用默认数据
			warn("EmoteDataManager: 玩家 " .. player.Name .. " 数据迁移失败，使用默认数据")
			data = {
				ownedEmotes = copyEmoteList(DEFAULT_EMOTE_DATA.ownedEmotes),
				equippedEmote = DEFAULT_EMOTE_DATA.equippedEmote,
				version = DEFAULT_EMOTE_DATA.version
			}
		else
			-- 验证装备的动作是否有效且已拥有
			if not EmoteConfig.isValidEmoteId(data.equippedEmote) or
			   not containsEmote(data.ownedEmotes, data.equippedEmote) then
				warn("EmoteDataManager: 玩家 " .. player.Name .. " 装备动作无效，重置为默认")
				data.equippedEmote = 1001
			end

			-- 确保拥有默认动作
			if not containsEmote(data.ownedEmotes, 1001) then
				table.insert(data.ownedEmotes, 1001)
				table.sort(data.ownedEmotes)
			end
		end
	else
		-- 新玩家或加载失败，使用默认数据
		data = {
			ownedEmotes = copyEmoteList(DEFAULT_EMOTE_DATA.ownedEmotes),
			equippedEmote = DEFAULT_EMOTE_DATA.equippedEmote,
			version = DEFAULT_EMOTE_DATA.version
		}
	end

	-- 缓存数据
	playerEmoteData[player] = data

	-- 保存一次（确保迁移后的数据持久化）
	if success and data.version == 2 then
		EmoteDataManager.savePlayerData(player)
	end

	-- 同步到客户端
	task.wait(0.5)  -- 延迟一下，确保客户端准备好
	EmoteDataManager.syncPlayerData(player)
end

-- 保存玩家数据
function EmoteDataManager.savePlayerData(player)
	if not player or not playerEmoteData[player] then
		return
	end

	-- 仅在非Studio环境保存到DataStore
	if not EmoteDataStore then
		if not isStudio then
			warn("EmoteDataStore未初始化，无法保存数据")
		end
		return
	end

	local success, error = pcall(function()
		EmoteDataStore:SetAsync(getPlayerKey(player), playerEmoteData[player])
	end)

	if not success then
		warn("EmoteDataManager: 保存玩家 " .. player.Name .. " 数据失败: " .. tostring(error))
	end
end

-- 同步数据到客户端
function EmoteDataManager.syncPlayerData(player)
	if not player or not player.Parent then
		return
	end

	local data = playerEmoteData[player]
	if not data then
		-- 🔧 修复：数据未初始化（可能是玩家刚加入），静默尝试初始化
		-- 不输出警告，因为这是正常的初始化竞态条件
		task.spawn(function()
			EmoteDataManager.initializePlayerData(player)
		end)
		return
	end

	-- 确保RemoteEvents已初始化
	if not getRemoteEvents() then
		warn("EmoteDataManager.syncPlayerData: RemoteEvents未初始化")
		return
	end

	-- 发送数据到客户端
	if emoteDataSyncEvent and player.Parent then
		local success, error = pcall(function()
			emoteDataSyncEvent:FireClient(player, "syncData", {
				ownedEmotes = copyEmoteList(data.ownedEmotes),
				equippedEmote = data.equippedEmote
			})
		end)

		if not success then
			warn("EmoteDataManager: 同步数据到客户端失败: " .. tostring(error))
		end
	end
end

-- ============================================
-- 查询接口
-- ============================================

-- 检查玩家是否拥有动作
function EmoteDataManager.hasEmote(player, emoteId)
	if not player or not emoteId then
		return false
	end

	-- 验证动作ID有效性
	if not EmoteConfig.isValidEmoteId(emoteId) then
		return false
	end

	local data = playerEmoteData[player]
	if not data then
		return false
	end

	return containsEmote(data.ownedEmotes, emoteId)
end

-- 获取玩家装备的动作ID
function EmoteDataManager.getEquippedEmote(player)
	if not player then
		return 1001  -- 默认动作
	end

	local data = playerEmoteData[player]
	if not data then
		return 1001
	end

	-- 验证装备的动作是否有效且已拥有
	if EmoteConfig.isValidEmoteId(data.equippedEmote) and
	   containsEmote(data.ownedEmotes, data.equippedEmote) then
		return data.equippedEmote
	end

	-- 无效时返回默认
	return 1001
end

-- 获取玩家已拥有的动作列表
function EmoteDataManager.getOwnedEmotes(player)
	if not player then
		return {1001}
	end

	local data = playerEmoteData[player]
	if not data then
		return {1001}
	end

	-- 返回副本，防止外部修改
	return copyEmoteList(data.ownedEmotes)
end

-- ============================================
-- 修改接口
-- ============================================

-- 发放单个动作
function EmoteDataManager.grantEmote(player, emoteId, reason)
	if not player or not emoteId then
		warn("EmoteDataManager.grantEmote: 参数无效")
		return false
	end

	-- 验证动作ID
	if not EmoteConfig.isValidEmoteId(emoteId) then
		warn("EmoteDataManager.grantEmote: 无效的动作ID: " .. tostring(emoteId))
		return false
	end

	local data = playerEmoteData[player]
	if not data then
		warn("EmoteDataManager.grantEmote: 玩家 " .. player.Name .. " 数据不存在")
		return false
	end

	-- 检查是否已拥有
	if containsEmote(data.ownedEmotes, emoteId) then
		return true  -- 已拥有也返回true
	end

	-- 添加动作
	table.insert(data.ownedEmotes, emoteId)
	table.sort(data.ownedEmotes)

	-- 保存数据
	EmoteDataManager.savePlayerData(player)

	-- 同步到客户端
	EmoteDataManager.syncPlayerData(player)

	return true
end

-- 批量发放动作
function EmoteDataManager.grantEmotes(player, emoteIds, reason)
	if not player or not emoteIds or type(emoteIds) ~= "table" then
		warn("EmoteDataManager.grantEmotes: 参数无效")
		return false
	end

	local success = true
	for _, emoteId in ipairs(emoteIds) do
		if not EmoteDataManager.grantEmote(player, emoteId, reason) then
			success = false
		end
	end

	return success
end

-- 购买动作（带金币验证）
function EmoteDataManager.purchaseEmote(player, emoteId)
	if not player or not emoteId then
		warn("EmoteDataManager.purchaseEmote: 参数无效")
		return false, "Invalid parameters"
	end

	-- 防止并发购买
	if purchaseInProgress[player] then
		warn("EmoteDataManager.purchaseEmote: 玩家 " .. player.Name .. " 购买进行中")
		return false, "Purchase in progress"
	end

	purchaseInProgress[player] = true

	-- 验证动作ID
	if not EmoteConfig.isValidEmoteId(emoteId) then
		purchaseInProgress[player] = nil
		return false, "Invalid emote ID"
	end

	-- 检查是否已拥有
	if EmoteDataManager.hasEmote(player, emoteId) then
		purchaseInProgress[player] = nil
		return false, "Already Owned"
	end

	-- 获取价格
	local emoteInfo = EmoteConfig.getEmoteInfo(emoteId)
	if not emoteInfo then
		purchaseInProgress[player] = nil
		return false, "Emote not found"
	end

	local price = emoteInfo.coinPrice

	-- 验证金币
	if not _G.CoinManager or not _G.CoinManager.getCoins or not _G.CoinManager.removeCoins then
		warn("EmoteDataManager.purchaseEmote: CoinManager未加载")
		purchaseInProgress[player] = nil
		return false, "System error"
	end

	local currentCoins = _G.CoinManager.getCoins(player)
	if currentCoins < price then
		purchaseInProgress[player] = nil
		return false, "Not Enough Coins"
	end

	-- 扣除金币
	local removeSuccess = _G.CoinManager.removeCoins(player, price, "购买跳舞动作: " .. emoteInfo.name)
	if not removeSuccess then
		purchaseInProgress[player] = nil
		return false, "Failed to deduct coins"
	end

	-- 发放动作
	local grantSuccess = EmoteDataManager.grantEmote(player, emoteId, "购买")
	if not grantSuccess then
		-- 回滚金币
		_G.CoinManager.addCoins(player, price, "购买失败回滚")
		purchaseInProgress[player] = nil
		return false, "Failed to grant emote"
	end

	-- 自动装备新购买的动作
	EmoteDataManager.equipEmote(player, emoteId)

	purchaseInProgress[player] = nil

	return true
end

-- 装备动作
function EmoteDataManager.equipEmote(player, emoteId)
	if not player or not emoteId then
		warn("EmoteDataManager.equipEmote: 参数无效")
		return false
	end

	-- 验证动作ID
	if not EmoteConfig.isValidEmoteId(emoteId) then
		warn("EmoteDataManager.equipEmote: 无效的动作ID: " .. tostring(emoteId))
		return false
	end

	local data = playerEmoteData[player]
	if not data then
		warn("EmoteDataManager.equipEmote: 玩家 " .. player.Name .. " 数据不存在")
		return false
	end

	-- 检查是否拥有
	if not containsEmote(data.ownedEmotes, emoteId) then
		warn("EmoteDataManager.equipEmote: 玩家 " .. player.Name .. " 未拥有动作 " .. emoteId)
		return false
	end

	-- 更新装备
	data.equippedEmote = emoteId

	-- 保存数据
	EmoteDataManager.savePlayerData(player)

	-- 同步到客户端
	EmoteDataManager.syncPlayerData(player)

	return true
end

-- ============================================
-- RemoteEvent处理
-- ============================================

function EmoteDataManager.setupRemoteEvents()
	if not getRemoteEvents() then
		warn("EmoteDataManager.setupRemoteEvents: RemoteEvents初始化失败")
		return
	end

	-- 处理数据同步请求
	emoteDataSyncEvent.OnServerEvent:Connect(function(player, action)
		if action == "requestSync" then
			EmoteDataManager.syncPlayerData(player)
		end
	end)

	-- 处理装备请求
	emoteEquipEvent.OnServerEvent:Connect(function(player, emoteId)
		-- 验证参数
		if type(emoteId) ~= "number" then
			warn("EmoteDataManager: 收到无效的装备请求，玩家: " .. player.Name .. ", emoteId: " .. tostring(emoteId))
			return
		end

		-- 装备动作
		EmoteDataManager.equipEmote(player, emoteId)

		-- 无论成功失败都同步数据（确保客户端状态一致）
		EmoteDataManager.syncPlayerData(player)
	end)
end

-- ============================================
-- 玩家事件处理
-- ============================================

function EmoteDataManager.onPlayerAdded(player)
	-- 延迟初始化，等待其他系统加载
	task.spawn(function()
		task.wait(2)
		EmoteDataManager.initializePlayerData(player)
	end)
end

function EmoteDataManager.onPlayerRemoving(player)
	if playerEmoteData[player] then
		EmoteDataManager.savePlayerData(player)
		playerEmoteData[player] = nil
	end

	-- 清理购买标志
	if purchaseInProgress[player] then
		purchaseInProgress[player] = nil
	end
end

-- ============================================
-- 初始化
-- ============================================

function EmoteDataManager.initialize()
	-- 设置玩家事件
	Players.PlayerAdded:Connect(EmoteDataManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(EmoteDataManager.onPlayerRemoving)

	-- 处理已存在的玩家
	for _, player in pairs(Players:GetPlayers()) do
		EmoteDataManager.onPlayerAdded(player)
	end

	-- 设置RemoteEvent处理
	EmoteDataManager.setupRemoteEvents()

	-- 定期自动保存（每5分钟）
	task.spawn(function()
		while true do
			task.wait(300)  -- 5分钟
			for player, _ in pairs(playerEmoteData) do
				if player.Parent then
					EmoteDataManager.savePlayerData(player)
				end
			end
		end
	end)
end

-- 导出到全局
_G.EmoteDataManager = EmoteDataManager

return EmoteDataManager
