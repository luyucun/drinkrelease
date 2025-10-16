-- 脚本名称: TableManager
-- 脚本作用: 管理所有对战桌子，为每张桌子创建独立的游戏实例
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local TableManager = {}
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引入单桌游戏实例管理器
local GameInstance = require(script.Parent.GameInstance)

-- 桌子管理状态
local tableInstances = {} -- 存储所有桌子的游戏实例
local playerToTable = {}  -- 玩家ID到桌子ID的映射

-- 配置
local TABLE_CONFIG = {
	MAX_TABLES = 20,           -- 最大桌子数量
	TABLE_NAME_PREFIX = "2player_group",  -- 桌子名称前缀
	WORKSPACE_PATH = "2Player" -- 桌子父文件夹路径
}

-- 扫描并初始化所有桌子
function TableManager.scanAndInitializeTables()

	local workspace = game.Workspace
	local twoPlayerFolder = workspace:FindFirstChild(TABLE_CONFIG.WORKSPACE_PATH)

	if not twoPlayerFolder then
		warn("未找到桌子容器: Workspace." .. TABLE_CONFIG.WORKSPACE_PATH)
		return false
	end

	local initializedCount = 0

	-- 扫描所有符合命名规范的桌子
	for _, child in pairs(twoPlayerFolder:GetChildren()) do
		if child.Name:match("^" .. TABLE_CONFIG.TABLE_NAME_PREFIX .. "%d+$") then
			local tableId = child.Name

			-- 验证桌子结构
			if TableManager.validateTableStructure(child) then
				-- 为每张桌子创建独立的游戏实例
				local gameInstance = GameInstance.new(tableId, child)
				tableInstances[tableId] = gameInstance

				initializedCount = initializedCount + 1
			else
				warn("❌ 桌子 " .. tableId .. " 结构验证失败，跳过初始化")
			end
		end
	end


	return initializedCount > 0
end

-- 验证桌子结构
function TableManager.validateTableStructure(tableFolder)
	-- 检查必需的组件
	local requiredComponents = {
		"ClassicTable",
		"ClassicChair1",
		"ClassicChair2"
	}

	for _, componentName in ipairs(requiredComponents) do
		if not tableFolder:FindFirstChild(componentName) then
			warn("桌子 " .. tableFolder.Name .. " 缺少组件: " .. componentName)
			return false
		end
	end

	-- 检查座位
	local chair1 = tableFolder:FindFirstChild("ClassicChair1")
	local chair2 = tableFolder:FindFirstChild("ClassicChair2")

	if not (chair1:FindFirstChild("Seat") and chair2:FindFirstChild("Seat")) then
		warn("桌子 " .. tableFolder.Name .. " 座位配置不完整")
		return false
	end

	return true
end

-- 获取指定玩家所在的桌子
function TableManager.getPlayerTable(player)
	local tableId = playerToTable[player.UserId]
	if tableId then
		return tableInstances[tableId]
	end
	return nil
end

-- 为玩家分配桌子（玩家坐下时调用）
function TableManager.assignPlayerToTable(player, tableId)
	-- 清理玩家之前的桌子映射
	local previousTable = playerToTable[player.UserId]
	if previousTable and previousTable ~= tableId then
	end

	playerToTable[player.UserId] = tableId
end

-- 移除玩家的桌子映射（玩家离开座位或离开游戏时调用）
function TableManager.removePlayerFromTable(player)
	local tableId = playerToTable[player.UserId]
	if tableId then
		playerToTable[player.UserId] = nil
		return tableId
	end
	return nil
end

-- 获取所有桌子状态（调试用）
-- Debug function - prints removed for production
function TableManager.getAllTableStatus()
end

-- 处理玩家离开服务器
function TableManager.onPlayerRemoving(player)
	local tableId = TableManager.removePlayerFromTable(player)
	if tableId and tableInstances[tableId] then
		-- 通知对应桌子的游戏实例处理玩家离开
		tableInstances[tableId]:onPlayerRemoving(player)
	end
end

-- 获取桌子实例（供其他脚本调用）
function TableManager.getTableInstance(tableId)
	return tableInstances[tableId]
end

-- 获取所有桌子实例
function TableManager.getAllTableInstances()
	return tableInstances
end

-- 根据玩家位置自动检测所在桌子
function TableManager.detectPlayerTable(player)
	if not player.Character then return nil end

	local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return nil end

	-- 方法1：首先检查玩家映射
	local mappedTableId = playerToTable[player.UserId]
	if mappedTableId and tableInstances[mappedTableId] then
		local gameInstance = tableInstances[mappedTableId]
		if gameInstance:isPlayerInSeats(player) then
			return mappedTableId
		end
	end

	-- 方法2：遍历所有桌子检测座位占用
	for tableId, gameInstance in pairs(tableInstances) do
		if gameInstance:isPlayerInSeats(player) then
			-- 更新映射
			playerToTable[player.UserId] = tableId
			return tableId
		end
	end

	-- 方法3：根据距离检测（作为后备方案）
	local playerPosition = humanoidRootPart.Position
	local closestTableId = nil
	local closestDistance = math.huge

	for tableId, gameInstance in pairs(tableInstances) do
		local tablePosition = gameInstance.tablePart.Position
		local distance = (playerPosition - tablePosition).Magnitude

		if distance < closestDistance and distance < 20 then -- 20是最大检测距离
			closestDistance = distance
			closestTableId = tableId
		end
	end

	if closestTableId then
		return closestTableId
	end

	return nil
end

-- 初始化桌子管理器
function TableManager.initialize()

	-- 扫描并初始化所有桌子
	local success = TableManager.scanAndInitializeTables()

	if not success then
		warn("TableManager 初始化失败 - 没有找到有效的桌子")
		return false
	end

	-- 设置玩家离开监听
	Players.PlayerRemoving:Connect(TableManager.onPlayerRemoving)

	-- 启动定期清理检查（每30秒检查一次）
	TableManager.startPeriodicCleanup()

	return true
end

-- 定期清理检查：检查并清理可能遗留奶茶的桌子
function TableManager.startPeriodicCleanup()
	spawn(function()
		while true do
			wait(30) -- 每30秒检查一次
			TableManager.performCleanupCheck()
		end
	end)
end

-- 执行清理检查
function TableManager.performCleanupCheck()
	for tableId, gameInstance in pairs(tableInstances) do
		if gameInstance then
			local status = gameInstance:getStatus()

			-- 检查是否存在异常状态：游戏进行中但没有玩家
			if status.phase ~= "waiting" and status.playerCount == 0 then
				warn("发现异常桌子 " .. tableId .. " - 游戏进行中但无玩家，执行强制清理")
				-- 强制重置到等待状态（这会清理奶茶）
				gameInstance:resetToWaiting()
			end

			-- 检查是否存在奶茶遗留但游戏状态为waiting的情况
			if status.phase == "waiting" then
				-- 尝试清理可能遗留的奶茶
				local DrinkManager = require(script.Parent.DrinkManager)
				if DrinkManager.clearDrinksForTable then
					DrinkManager.clearDrinksForTable(tableId)
				end
			end
		end
	end
end

-- 启动桌子管理器
TableManager.initialize()

-- 导出到全局供其他脚本使用
_G.TableManager = TableManager

return TableManager