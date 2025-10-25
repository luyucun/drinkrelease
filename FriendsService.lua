-- 脚本名称: FriendsService
-- 脚本作用: 处理Roblox好友识别和金币加成计算
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local FriendsService = {}
FriendsService.__index = FriendsService

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- 检查环境
local isStudio = RunService:IsStudio()

-- 好友列表缓存
local friendsCache = {}
local FRIENDS_CACHE_EXPIRY = 300  -- 5分钟缓存有效期

-- 房间好友信息缓存
local roomFriendsCache = {}

-- ============================================
-- 获取玩家的Roblox好友列表（带缓存）
-- ============================================

function FriendsService:getFriendsListCached(player)
	if not player then return {} end

	local playerId = player.UserId
	local cache = friendsCache[playerId]

	-- 检查缓存是否有效
	if cache and (os.time() - cache.timestamp) < FRIENDS_CACHE_EXPIRY then
		return cache.friendIds
	end

	-- 🔧 V2.8修复：使用 Players:GetFriendsAsync（官方推荐API）
	local friendIds = {}
	local success, pages = pcall(function()
		-- Players:GetFriendsAsync 返回分页对象 FriendPages，不是直接的 table
		return Players:GetFriendsAsync(playerId)
	end)

	if success and pages then
		-- 🔧 V2.9修复：正确处理 FriendPages 分页
		repeat
			local currentPage = pages:GetCurrentPage()
			for _, friend in ipairs(currentPage) do
				-- GetFriendsAsync 返回的格式：{Id=..., Username=..., DisplayName=...}
				table.insert(friendIds, friend.Id)
			end

			-- 检查是否有下一页
			if pages.IsFinished then
				break
			end

			-- 移到下一页
			local pageSuccess, pageErr = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)

			if not pageSuccess then
				warn("[FriendsService] 分页失败: " .. tostring(pageErr))
				break
			end
		until false
	else
		-- 🔧 V2.8改进：更详细的错误处理和降级方案
		if isStudio then
			-- Studio 模式：打印提示但不报错
			print("[FriendsService] ⚠️ Studio 模式：好友接口不可用，建议在设置中启用 API Services")
			print("[FriendsService]   或在正式服务器上测试。使用默认好友列表。")
		else
			-- 正式服务器：记录警告但继续
			warn("[FriendsService] ❌ 获取好友列表失败: " .. player.Name)
		end

		-- 返回空列表，降级处理（无加成）
		return {}
	end

	-- 更新缓存
	friendsCache[playerId] = {
		timestamp = os.time(),
		friendIds = friendIds
	}

	return friendIds
end

-- ============================================
-- 检查两个玩家是否是好友
-- ============================================

function FriendsService:areFriends(player1, player2)
	if not player1 or not player2 then return false end
	if player1.UserId == player2.UserId then return false end

	local friends = self:getFriendsListCached(player1)

	for _, friendId in ipairs(friends) do
		if friendId == player2.UserId then
			return true
		end
	end

	return false
end

-- ============================================
-- 获取房间内的好友列表
-- ============================================

function FriendsService:getFriendsInRoom(player, players)
	if not player or not players then return {} end

	local friendIds = self:getFriendsListCached(player)
	local roomFriends = {}

	for _, friendId in ipairs(friendIds) do
		for _, otherPlayer in ipairs(players) do
			if otherPlayer and otherPlayer.UserId == friendId and otherPlayer.UserId ~= player.UserId then
				table.insert(roomFriends, friendId)
				break
			end
		end
	end

	return roomFriends
end

-- ============================================
-- 计算好友加成倍数
-- ============================================

function FriendsService:calculateBonus(friendCount)
	return friendCount * 0.2  -- 每个好友+20%
end

-- ============================================
-- 应用好友加成到金币
-- ============================================

function FriendsService:applyFriendsBonus(baseCoins, bonus)
	return math.floor(baseCoins * (1 + bonus))
end

-- ============================================
-- 更新房间内的好友关系
-- ============================================

function FriendsService:updateRoomFriends(tableId, players)
	if not tableId or not players then return end

	-- 创建房间玩家ID列表
	local playerIds = {}
	for _, player in ipairs(players) do
		if player then
			table.insert(playerIds, player.UserId)
		end
	end

	-- 为每个玩家计算房间内的好友
	local roomFriendMap = {}

	for _, player in ipairs(players) do
		if player then
			-- 获取该玩家的好友列表
			local friendIds = self:getFriendsListCached(player)

			-- 找出既是好友又在房间内的玩家
			local roomFriends = {}
			for _, friendId in ipairs(friendIds) do
				-- 检查这个好友是否在房间内
				for _, playerId in ipairs(playerIds) do
					if friendId == playerId and friendId ~= player.UserId then
						table.insert(roomFriends, friendId)
						break
					end
				end
			end

			-- 计算加成倍数
			local bonusMultiplier = #roomFriends * 0.2

			-- 缓存房间好友信息
			roomFriendMap[player.UserId] = {
				friends = roomFriends,
				bonus = bonusMultiplier,
				friendCount = #roomFriends
			}
		end
	end

	-- 存储到房间缓存
	roomFriendsCache[tableId] = roomFriendMap
end

-- ============================================
-- 获取玩家在某房间的加成倍数
-- ============================================

function FriendsService:getRoomFriendsBonus(player, tableId)
	if not player or not tableId then return 0 end

	-- 检查是否在新手场景中
	if _G.TutorialMode then
		return 0
	end

	-- 检查是否是NPC
	if _G.TutorialBotService and _G.TutorialBotService:isBot(player) then
		return 0
	end

	-- 🔧 关键修复：实时获取当前桌子的玩家列表，不依赖缓存
	local currentPlayers = {}
	if _G.TableManager then
		local gameInstance = _G.TableManager.getTableInstance(tableId)
		if gameInstance then
			if gameInstance.gameState.player1 then
				table.insert(currentPlayers, gameInstance.gameState.player1)
			end
			if gameInstance.gameState.player2 then
				table.insert(currentPlayers, gameInstance.gameState.player2)
			end
		end
	end

	-- 实时计算房间内的好友数
	local roomFriends = self:getFriendsInRoom(player, currentPlayers)
	local friendCount = #roomFriends

	-- 计算加成倍数：每个好友+20%
	local bonus = friendCount * 0.2

	print("[FriendsService] 实时计算好友加成 - 玩家: " .. player.Name ..
		  ", 房间好友数: " .. friendCount .. ", 加成: " .. (bonus * 100) .. "%")

	return bonus
end

-- ============================================
-- 获取玩家在某房间的好友数
-- ============================================

function FriendsService:getRoomFriendCount(player, tableId)
	if not player or not tableId then return 0 end

	if not roomFriendsCache[tableId] then
		return 0
	end

	return roomFriendsCache[tableId][player.UserId] and roomFriendsCache[tableId][player.UserId].friendCount or 0
end

-- ============================================
-- 清理房间缓存
-- ============================================

function FriendsService:clearRoomCache(tableId)
	if tableId then
		roomFriendsCache[tableId] = nil
	end
end

-- ============================================
-- 清理玩家好友缓存
-- ============================================

function FriendsService:clearPlayerCache(player)
	if player then
		friendsCache[player.UserId] = nil
	end
end

-- ============================================
-- 初始化
-- ============================================

function FriendsService.initialize()
	-- 玩家离开时清理缓存
	Players.PlayerRemoving:Connect(function(player)
		FriendsService:clearPlayerCache(player)
	end)

	-- 🔧 V2.8新增：在 Studio 模式下，给出明确的设置提示
	if isStudio then
		print("[FriendsService] ℹ️ 检测到 Studio 环境")
		print("[FriendsService] 要在 Studio 中测试好友功能，请：")
		print("[FriendsService] 1. 前往 Game Settings > Security > Enable API Services")
		print("[FriendsService] 2. 勾选 'Allow HTTP Requests'")
		print("[FriendsService] 3. 或者直接在正式服务器上测试")
	end

	print("[FriendsService] ✓ 初始化完成 (使用 Players:GetFriendsAsync API)")
end

-- 全局导出
_G.FriendsService = FriendsService

return FriendsService
