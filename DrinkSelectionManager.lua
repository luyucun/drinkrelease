-- 脚本名称: DrinkSelectionManager
-- 脚本作用: 管理轮流选择奶茶系统，控制选择顺序和结果判定
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local DrinkSelectionManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 🔧 修复：创建独立的随机数生成器，确保真正的随机性
local FirstPlayerRandom = Random.new()
local AutoSelectRandom = Random.new()

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local drinkSelectionEvent = remoteEventsFolder:WaitForChild("DrinkSelection")
local cameraControlEvent = remoteEventsFolder:WaitForChild("CameraControl")
local poisonIndicatorEvent = remoteEventsFolder:WaitForChild("PoisonIndicator")
local seatLockEvent = remoteEventsFolder:WaitForChild("SeatLock")

-- 引入其他管理器
local DrinkManager = require(script.Parent.DrinkManager)
local DrinkHandManager = nil  -- V1.5新增：手持道具管理器（延迟加载）
local CountdownManager = nil

-- CoinManager是Script类型，不能直接require，需要等待其加载
local CoinManager = nil

-- 延迟加载CoinManager
spawn(function()
	-- 等待CoinManager脚本创建全局引用
	local serverScriptService = game:GetService("ServerScriptService")
	local coinManagerScript = serverScriptService:WaitForChild("CoinManager", 10)

	if coinManagerScript then
		-- 等待CoinManager模块在_G中可用
		while not _G.CoinManager do
			wait(0.1)
		end
		CoinManager = _G.CoinManager
	else
		warn("DrinkSelectionManager: 未找到CoinManager脚本")
	end
end)

-- ========== 多桌状态隔离核心重构 V2.0 ==========
-- 按桌子隔离的选择状态
local selectionStates = {} -- {[tableId] = SelectionStateData}

-- 单个桌子的选择状态数据结构
local function createNewSelectionState()
	return {
		activePhase = false,
		player1 = nil,
		player2 = nil,
		currentPlayer = nil,
		waitingPlayer = nil,
		selectionOrder = {},
		gameResult = nil,
		availableDrinks = {},
		startTime = 0,
		isProcessingSelection = false,  -- 🔒 防止回合跳过：标记是否正在处理选择
	}
end

-- 获取或创建桌子的选择状态
local function getSelectionState(tableId)
	if not tableId then
		warn("getSelectionState: tableId为空")
		return nil
	end

	if not selectionStates[tableId] then
		selectionStates[tableId] = createNewSelectionState()
	end

	return selectionStates[tableId]
end

-- 通过玩家获取桌子ID
local function getTableIdFromPlayer(player)
	if not player then return nil end

	-- 方法1: 使用TableManager检测
	if _G.TableManager and _G.TableManager.detectPlayerTable then
		local tableId = _G.TableManager.detectPlayerTable(player)
		if tableId then return tableId end
	end

	-- 方法2: 遍历所有选择状态查找
	for tableId, state in pairs(selectionStates) do
		if state.player1 == player or state.player2 == player then
			return tableId
		end
	end

	return nil
end

-- 清理桌子状态(对局结束时调用)
function DrinkSelectionManager.cleanupTableState(tableId)
	if selectionStates[tableId] then
		selectionStates[tableId] = nil
	end
end

-- 兼容旧代码: 获取玩家桌子ID (已弃用,仅向后兼容)
local function getTableIdFromCurrentPlayers()
	-- 尝试从任意活跃的选择状态中获取
	for tableId, state in pairs(selectionStates) do
		if state.activePhase then
			return tableId
		end
	end
	return nil
end
-- ========== 多桌状态隔离核心重构结束 ==========

-- ========== V1.4 倒计时功能 ==========
-- 启动选择阶段回合倒计时
function DrinkSelectionManager.startSelectionTurnCountdown(tableId, currentPlayer)
	-- 延迟加载CountdownManager
	if not CountdownManager then
		CountdownManager = _G.CountdownManager
		if not CountdownManager then
			warn("DrinkSelectionManager: CountdownManager未加载")
			return false
		end
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState or not selectionState.activePhase then
		warn("DrinkSelectionManager: 选择阶段未激活")
		return false
	end

	local config = CountdownManager.getConfig()
	local countdownTypes = CountdownManager.getCountdownTypes()

	-- 设置倒计时选项
	local options = {
		currentPlayer = currentPlayer,
		onTimeout = function(tableId)
			DrinkSelectionManager.onSelectionTurnTimeout(tableId)
		end,
		onUpdate = function(tableId, remainingTime)
			DrinkSelectionManager.onSelectionTurnUpdate(tableId, remainingTime)
		end,
		onWarning = function(tableId, remainingTime)
			DrinkSelectionManager.onSelectionTurnWarning(tableId, remainingTime)
		end,
		customData = {
			phase = "drink_selection",
			uiPath = "SelectTips"
		}
	}

	-- 启动倒计时
	local success = CountdownManager.startCountdown(
		tableId,
		countdownTypes.SELECTION_PHASE,
		config.SELECTION_PHASE_DURATION,
		selectionState.players or {selectionState.player1, selectionState.player2},
		options
	)

	if not success then
		warn("DrinkSelectionManager: 启动选择回合倒计时失败")
		return false
	end

	print("DrinkSelectionManager: 选择回合倒计时已启动 - 桌子: " .. tableId .. ", 当前玩家: " .. currentPlayer.Name)
	return true
end

-- 选择阶段回合倒计时超时处理
function DrinkSelectionManager.onSelectionTurnTimeout(tableId)
	print("DrinkSelectionManager: 选择回合倒计时超时 - 桌子: " .. tableId)

	local selectionState = getSelectionState(tableId)
	if not selectionState or not selectionState.activePhase then
		return
	end

	local currentPlayer = selectionState.currentPlayer
	if not currentPlayer then
		warn("DrinkSelectionManager: 当前玩家为空，无法执行自动选择")
		return
	end

	-- 为当前玩家自动选择奶茶
	DrinkSelectionManager.autoSelectDrinkForPlayer(tableId, currentPlayer)
end

-- 为玩家自动选择奶茶
function DrinkSelectionManager.autoSelectDrinkForPlayer(tableId, player)
	print("DrinkSelectionManager: 自动选择奶茶 - 玩家: " .. player.Name .. ", 桌子: " .. tableId)

	local selectionState = getSelectionState(tableId)
	if not selectionState or #selectionState.availableDrinks == 0 then
		warn("DrinkSelectionManager: 没有可用的奶茶进行自动选择")
		return
	end

	-- 🔧 修复：使用独立的随机数生成器，确保真正的随机性
	local randomIndex = AutoSelectRandom:NextInteger(1, #selectionState.availableDrinks)
	local selectedDrinkIndex = selectionState.availableDrinks[randomIndex]

	print("DrinkSelectionManager: 已为玩家 " .. player.Name .. " 自动选择奶茶 " .. selectedDrinkIndex)

	-- 执行选择逻辑
	DrinkSelectionManager.onPlayerSelectDrink(player, selectedDrinkIndex)
end

-- 选择阶段回合倒计时更新
function DrinkSelectionManager.onSelectionTurnUpdate(tableId, remainingTime)
	-- 可以在这里添加实时更新逻辑
	-- 目前由CountdownManager自动发送给客户端
end

-- 选择阶段进入警告阶段
function DrinkSelectionManager.onSelectionTurnWarning(tableId, remainingTime)
	print("DrinkSelectionManager: 选择回合进入警告阶段 - 桌子: " .. tableId .. ", 剩余: " .. string.format("%.1f", remainingTime) .. "秒")
	-- 警告阶段的处理（如字体变红）由客户端CountdownClient处理
end

-- 停止选择阶段倒计时
function DrinkSelectionManager.stopSelectionTurnCountdown(tableId)
	if CountdownManager and CountdownManager.stopCountdown then
		CountdownManager.stopCountdown(tableId)
		print("DrinkSelectionManager: 选择回合倒计时已停止 - 桌子: " .. tableId)
	end
end

-- 切换到下一个玩家的倒计时
function DrinkSelectionManager.switchPlayerCountdown(tableId, newCurrentPlayer)
	-- 停止当前倒计时
	DrinkSelectionManager.stopSelectionTurnCountdown(tableId)

	-- 更新CountdownManager中的当前玩家
	if CountdownManager and CountdownManager.switchCurrentPlayer then
		CountdownManager.switchCurrentPlayer(tableId, newCurrentPlayer)
	end

	-- 重新启动倒计时
	DrinkSelectionManager.startSelectionTurnCountdown(tableId, newCurrentPlayer)
end
-- ========== V1.4 倒计时功能结束 ==========

-- 开始选择阶段
function DrinkSelectionManager.startSelectionPhase(player1, player2)
	-- 检测桌子ID (两个玩家应该在同一张桌子)
	local tableId = getTableIdFromPlayer(player1) or getTableIdFromPlayer(player2)
	if not tableId then
		warn("DrinkSelectionManager.startSelectionPhase: 无法检测桌子ID")
		return false
	end


	-- 在ReplicatedStorage中设置标志(按桌子隔离)
	local drinkSelectionFlag = ReplicatedStorage:FindFirstChild("DrinkSelectionActive_" .. tableId)
	if not drinkSelectionFlag then
		drinkSelectionFlag = Instance.new("BoolValue")
		drinkSelectionFlag.Name = "DrinkSelectionActive_" .. tableId
		drinkSelectionFlag.Parent = ReplicatedStorage
	end
	drinkSelectionFlag.Value = true

	-- 更新对应桌子的游戏阶段为selection
	if _G.TableManager then
		local gameInstance = _G.TableManager.getTableInstance(tableId)
		if gameInstance then
			gameInstance.gameState.gamePhase = "selection"
		else
			warn("未找到桌子 " .. tableId .. " 的GameInstance")
		end
	end

	-- 获取该桌子的状态
	local selectionState = getSelectionState(tableId)
	if not selectionState then
		warn("无法创建桌子 " .. tableId .. " 的选择状态")
		return false
	end

	-- 重置状态
	selectionState.activePhase = true
	selectionState.player1 = player1
	selectionState.player2 = player2
	selectionState.selectionOrder = {}
	selectionState.gameResult = nil
	selectionState.startTime = tick()
	selectionState.isProcessingSelection = false  -- 🔒 初始化处理标志

	-- 初始化可选择的奶茶列表（1-24）
	selectionState.availableDrinks = {}
	for i = 1, 24 do
		table.insert(selectionState.availableDrinks, i)
	end

	-- 随机决定首先选择的玩家
	DrinkSelectionManager.randomizeFirstPlayer(tableId)

	-- 为下毒者显示红色标识(只对该桌子玩家)
	DrinkSelectionManager.showPoisonedDrinksToPlayers(tableId)

	-- 为所有玩家显示红色Num文本(只对该桌子玩家)
	DrinkSelectionManager.showRedNumForAllPlayers(tableId)

	-- 验证毒药注入情况
	DrinkManager.debugPrintPoisonDataForTable(tableId)

	-- 🔑 关键修复：游戏开始时重新启用SeatLockController的自动锁定功能
	-- 确保游戏期间玩家坐下时会被锁定（只能通过Leave按钮离开）
	-- 🔧 简化：直接通知客户端启用自动锁定
	if player1 and player1.Parent then
		pcall(function()
			-- 通过RemoteEvent直接控制客户端座位系统
			local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if remoteEventsFolder then
				local seatControlEvent = remoteEventsFolder:FindFirstChild("SeatControl")
				if seatControlEvent then
					seatControlEvent:FireClient(player1, "setGameActive", true)
				end
			end
		end)
	end
	if player2 and player2.Parent then
		pcall(function()
			-- 通过RemoteEvent直接控制客户端座位系统
			local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if remoteEventsFolder then
				local seatControlEvent = remoteEventsFolder:FindFirstChild("SeatControl")
				if seatControlEvent then
					seatControlEvent:FireClient(player2, "setGameActive", true)
				end
			end
		end)
	end

	-- 开始第一轮选择
	DrinkSelectionManager.startPlayerTurn(tableId)

	return true
end

-- 随机决定首先选择的玩家
function DrinkSelectionManager.randomizeFirstPlayer(tableId)
	local selectionState = getSelectionState(tableId)
	if not selectionState then return end

	-- 🔧 修复：使用独立的随机数生成器，确保真正的随机性
	local randomChoice = FirstPlayerRandom:NextInteger(1, 2)

	if randomChoice == 1 then
		selectionState.currentPlayer = selectionState.player1
		selectionState.waitingPlayer = selectionState.player2
	else
		selectionState.currentPlayer = selectionState.player2
		selectionState.waitingPlayer = selectionState.player1
	end

end

-- 为下毒者显示红色标识
function DrinkSelectionManager.showPoisonedDrinksToPlayers(tableId)
	local selectionState = getSelectionState(tableId)
	if not selectionState then return end

	-- 获取每个玩家下毒的奶茶信息
	local player1PoisonedDrinks = {}
	local player2PoisonedDrinks = {}

	-- 检查所有奶茶的毒药信息（使用正确的桌子ID）
	for drinkIndex = 1, 24 do
		local poisonInfo = DrinkManager.getDrinkPoisonInfoForTable(tableId, drinkIndex)

		if #poisonInfo > 0 then
			local poisoner = poisonInfo[1] -- 获取第一个下毒者
			if poisoner == selectionState.player1 then
				table.insert(player1PoisonedDrinks, drinkIndex)
			elseif poisoner == selectionState.player2 then
				table.insert(player2PoisonedDrinks, drinkIndex)
			end
		end
	end

	-- 发送给各自的客户端(只对该桌子玩家)
	if #player1PoisonedDrinks > 0 and selectionState.player1 and selectionState.player1.Parent then
		poisonIndicatorEvent:FireClient(selectionState.player1, "showPoisonIndicators", {
			poisonedDrinks = player1PoisonedDrinks
		})
	end

	if #player2PoisonedDrinks > 0 and selectionState.player2 and selectionState.player2.Parent then
		poisonIndicatorEvent:FireClient(selectionState.player2, "showPoisonIndicators", {
			poisonedDrinks = player2PoisonedDrinks
		})
	end
end

-- 为所有玩家显示红色Num文本
function DrinkSelectionManager.showRedNumForAllPlayers(tableId)
	if not tableId then
		warn("showRedNumForAllPlayers: tableId为空")
		return
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState then
		warn("showRedNumForAllPlayers: 无法获取桌子 " .. tableId .. " 的状态")
		return
	end

	-- 为玩家1显示红色Num
	local player1PoisonedDrinks = {}
	for drinkIndex = 1, 24 do
		local poisonInfo = DrinkManager.getDrinkPoisonInfoForTable(tableId, drinkIndex)

		if #poisonInfo > 0 then
			for _, poisoner in ipairs(poisonInfo) do
				if poisoner == selectionState.player1 then
					table.insert(player1PoisonedDrinks, drinkIndex)
					break
				end
			end
		end
	end

	-- 为玩家2显示红色Num
	local player2PoisonedDrinks = {}
	for drinkIndex = 1, 24 do
		local poisonInfo = DrinkManager.getDrinkPoisonInfoForTable(tableId, drinkIndex)

		if #poisonInfo > 0 then
			for _, poisoner in ipairs(poisonInfo) do
				if poisoner == selectionState.player2 then
					table.insert(player2PoisonedDrinks, drinkIndex)
					break
				end
			end
		end
	end

	-- 发送给各自的客户端(只对该桌子玩家)
	if #player1PoisonedDrinks > 0 and selectionState.player1 and selectionState.player1.Parent then
		drinkSelectionEvent:FireClient(selectionState.player1, "showRedNumForPoison", {
			poisonedDrinks = player1PoisonedDrinks,
			tableId = tableId  -- 传递桌子ID给客户端
		})
	end

	if #player2PoisonedDrinks > 0 and selectionState.player2 and selectionState.player2.Parent then
		drinkSelectionEvent:FireClient(selectionState.player2, "showRedNumForPoison", {
			poisonedDrinks = player2PoisonedDrinks,
			tableId = tableId  -- 传递桌子ID给客户端
		})
	end

end

-- 测试用：手动为指定奶茶注入毒药（仅用于测试）
function DrinkSelectionManager.testPoisonDrink(drinkIndex, player)

	-- 获取当前桌子ID
	local tableId = getTableIdFromCurrentPlayers()
	if tableId then
		DrinkManager.poisonDrinkForTable(tableId, drinkIndex, player)
	else
		-- 备用方案：使用默认方法
		warn("无法获取桌子ID，使用默认毒药注入方法")
		DrinkManager.poisonDrink(drinkIndex, player)
	end
end

-- 开始玩家回合
function DrinkSelectionManager.startPlayerTurn(tableId)
	if not tableId then
		warn("startPlayerTurn: tableId为空")
		return
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState or not selectionState.activePhase then
		warn("startPlayerTurn: 桌子 " .. tableId .. " 选择阶段未激活")
		return
	end

	-- 显示当前玩家的SelectTips UI
	DrinkSelectionManager.showSelectTips(selectionState.currentPlayer)

	-- 隐藏等待玩家的SelectTips UI，并显示等待提示
	DrinkSelectionManager.hideSelectTips(selectionState.waitingPlayer)
	DrinkSelectionManager.showWaitingTips(selectionState.waitingPlayer)

	-- 为当前玩家显示红色Num文本（自己下毒的奶茶）
	DrinkSelectionManager.showRedNumForCurrentPlayer(selectionState.currentPlayer)

	-- 切换镜头焦点到选择状态(只对该桌子玩家)
	if selectionState.currentPlayer and selectionState.currentPlayer.Parent then
		cameraControlEvent:FireClient(selectionState.currentPlayer, "enterSelect")
	end
	if selectionState.waitingPlayer and selectionState.waitingPlayer.Parent then
		cameraControlEvent:FireClient(selectionState.waitingPlayer, "enterSelect")
	end

	-- V1.4: 启动当前玩家的倒计时
	DrinkSelectionManager.startSelectionTurnCountdown(tableId, selectionState.currentPlayer)
end

-- 显示SelectTips UI
function DrinkSelectionManager.showSelectTips(player)
	if not player then return end

	drinkSelectionEvent:FireClient(player, "showSelectTips")
end

-- 隐藏SelectTips UI
function DrinkSelectionManager.hideSelectTips(player)
	if not player then return end

	drinkSelectionEvent:FireClient(player, "hideSelectTips")
end

-- 显示等待提示UI
function DrinkSelectionManager.showWaitingTips(player)
	if not player then return end

	drinkSelectionEvent:FireClient(player, "showWaitingTips")
end

-- 隐藏等待提示UI
function DrinkSelectionManager.hideWaitingTips(player)
	if not player then return end

	drinkSelectionEvent:FireClient(player, "hideWaitingTips")
end

-- 为当前玩家显示红色Num文本
function DrinkSelectionManager.showRedNumForCurrentPlayer(player)
	if not player then return end

	-- 获取当前桌子ID
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		warn("showRedNumForCurrentPlayer: 无法获取玩家 " .. player.Name .. " 的桌子ID")
		return
	end

	-- 获取该玩家下毒的奶茶（使用正确的桌子ID）
	local poisonedDrinks = {}
	for drinkIndex = 1, 24 do
		local poisonInfo = DrinkManager.getDrinkPoisonInfoForTable(tableId, drinkIndex)

		if #poisonInfo > 0 then
			for _, poisoner in ipairs(poisonInfo) do
				if poisoner == player then
					table.insert(poisonedDrinks, drinkIndex)
					break
				end
			end
		end
	end

	-- 发送给客户端显示红色Num
	if player and player.Parent then
		drinkSelectionEvent:FireClient(player, "showRedNumForPoison", {
			poisonedDrinks = poisonedDrinks,
			tableId = tableId  -- 传递桌子ID给客户端
		})
	end

end

-- 显示道具UI
function DrinkSelectionManager.showPropsUI(player)
	if not player then return end

	-- 通过RemoteEvent通知客户端显示道具UI
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local propUpdateEvent = remoteEventsFolder:FindFirstChild("PropUpdate")
	if propUpdateEvent then
		propUpdateEvent:FireClient(player, "showPropsUI")
	end
end

-- 隐藏道具UI
function DrinkSelectionManager.hidePropsUI(player)
	if not player then return end

	-- 通过RemoteEvent通知客户端隐藏道具UI
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local propUpdateEvent = remoteEventsFolder:FindFirstChild("PropUpdate")
	if propUpdateEvent then
		propUpdateEvent:FireClient(player, "hidePropsUI")
	end
end

-- 获取当前选择玩家（供道具系统使用）
function DrinkSelectionManager.getCurrentPlayer(tableId)
	-- 如果没有传tableId,尝试向后兼容:查找任意活跃的桌子
	if not tableId then
		for tid, state in pairs(selectionStates) do
			if state.activePhase and state.currentPlayer then
				return state.currentPlayer
			end
		end
		return nil
	end

	local selectionState = getSelectionState(tableId)
	return selectionState and selectionState.currentPlayer or nil
end

-- 获取对手玩家（供道具系统使用）
function DrinkSelectionManager.getOpponent(player, tableId)
	-- 如果没有传tableId,尝试从玩家检测
	if not tableId then
		tableId = getTableIdFromPlayer(player)
	end

	if not tableId then
		warn("getOpponent: 无法获取玩家 " .. (player and player.Name or "未知") .. " 的桌子ID")
		return nil
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState then
		return nil
	end

	if player == selectionState.player1 then
		return selectionState.player2
	elseif player == selectionState.player2 then
		return selectionState.player1
	end
	return nil
end

-- 显示选择UI
function DrinkSelectionManager.showSelectionUI(player, tableId)
	if not player then return end

	-- 如果没有传tableId,尝试从玩家检测
	if not tableId then
		tableId = getTableIdFromPlayer(player)
	end

	-- 获取该桌子的可用奶茶列表
	local availableDrinks = {}
	if tableId then
		local selectionState = getSelectionState(tableId)
		if selectionState then
			availableDrinks = selectionState.availableDrinks
		end
	end

	drinkSelectionEvent:FireClient(player, "showSelectionUI", {
		availableDrinks = availableDrinks
	})
end

-- 隐藏选择UI
function DrinkSelectionManager.hideSelectionUI(player)
	if not player then return end

	drinkSelectionEvent:FireClient(player, "hideSelectionUI")
end

-- 玩家选择奶茶
function DrinkSelectionManager.onPlayerSelectDrink(player, drinkIndex)
	-- 检查道具系统是否处理了这次选择（如毒药验证）
	if _G.PropEffectHandler and _G.PropEffectHandler.handleDrinkSelection then
		local handled = _G.PropEffectHandler.handleDrinkSelection(player, drinkIndex)
		if handled then
			return
		end
	end

	-- 获取玩家所在的桌子ID
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		warn("玩家 " .. player.Name .. " 不在任何桌子上")
		return
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState or not selectionState.activePhase then
		warn("桌子 " .. tableId .. " 选择阶段未激活")
		return
	end

	if player ~= selectionState.currentPlayer then
		warn("不是该玩家的回合: " .. player.Name .. "，当前回合: " .. (selectionState.currentPlayer and selectionState.currentPlayer.Name or "无"))
		return
	end

	-- 🔒 关键修复：检查是否正在处理选择，防止同一玩家在wait期间重复选择
	if selectionState.isProcessingSelection then
		warn("正在处理选择中，请等待当前选择完成: " .. player.Name)
		return
	end

	-- 🔒 立即设置处理标志，阻止后续重复点击
	selectionState.isProcessingSelection = true

	-- 检查奶茶是否还可选择
	local drinkAvailable = false
	for i, availableDrink in ipairs(selectionState.availableDrinks) do
		if availableDrink == drinkIndex then
			drinkAvailable = true
			table.remove(selectionState.availableDrinks, i)
			break
		end
	end

	if not drinkAvailable then
		warn("奶茶 " .. drinkIndex .. " 不可选择")
		-- 🔒 发生错误时重置处理标志
		selectionState.isProcessingSelection = false
		return
	end


	-- 记录选择
	table.insert(selectionState.selectionOrder, {
		player = player,
		drinkIndex = drinkIndex
	})

	-- 隐藏当前玩家的选择提示
	DrinkSelectionManager.hideSelectTips(selectionState.currentPlayer)
	-- 🔧 修复：同时隐藏等待玩家的SelectTips，避免在饮用阶段显示倒计时UI
	DrinkSelectionManager.hideSelectTips(selectionState.waitingPlayer)
	-- 保持等待玩家的等待提示显示，让他们知道对方正在饮用

	-- 执行饮用流程(传递tableId)
	DrinkSelectionManager.executeDrinking(player, drinkIndex, tableId)
end

-- V1.5新增: 播放喝饮料动作并处理手持道具
function DrinkSelectionManager.playDrinkingAnimation(player, drinkIndex, tableId)
	if not player or not player.Character then
		warn("playDrinkingAnimation: 玩家或其角色无效")
		return false
	end

	if not tableId then
		tableId = getTableIdFromPlayer(player)
	end

	if not tableId then
		warn("playDrinkingAnimation: 无法获取桌子ID")
		return false
	end

	-- 延迟加载DrinkHandManager
	if not DrinkHandManager then
		local success, module = pcall(function()
			return require(script.Parent.DrinkHandManager)
		end)
		if success then
			DrinkHandManager = module
		else
			warn("playDrinkingAnimation: 无法加载DrinkHandManager")
			return false
		end
	end

	local character = player.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

	if not humanoid or not animator then
		warn("playDrinkingAnimation: 玩家 " .. player.Name .. " 缺少Humanoid或Animator")
		return false
	end

	-- 喝饮料动作ID (V1.5)
	local DRINKING_ANIMATION_ID = "rbxassetid://71655128068947"
	local DRINKING_ANIMATION_DURATION = 3.0  -- 动作长度（秒）

	-- 🔧 修复1：获取桌子上对应位置的奶茶模型，而不是玩家自己装备的皮肤
	-- 根据drinkIndex确定应该复制哪个模型（奇数位置=玩家A的皮肤，偶数位置=玩家B的皮肤）
	local drinkState = DrinkManager.getTableState(tableId)
	local player1, player2 = DrinkManager.getPlayersFromTable(tableId)
	local drinkModelOnTable = drinkState.activeDrinks[drinkIndex]

	-- 如果桌子上还有模型，从桌子上的模型获取其模型名称来确定皮肤
	local originalDrinkModel = nil
	if drinkModelOnTable then
		-- 从桌子上的模型获取源模型信息
		originalDrinkModel = DrinkManager.getPlayerSkinModel(player1, tableId, drinkIndex)
		if drinkIndex % 2 == 0 and player2 then
			originalDrinkModel = DrinkManager.getPlayerSkinModel(player2, tableId, drinkIndex)
		end
	end

	-- 备用方案：如果找不到桌子模型，才用玩家自己的皮肤
	if not originalDrinkModel then
		originalDrinkModel = DrinkManager.getPlayerSkinModel(player, tableId, drinkIndex)
	end

	if not originalDrinkModel then
		warn("playDrinkingAnimation: 无法获取奶茶原始模型 (奶茶 " .. drinkIndex .. ")")
		return false
	end

	print(string.format("[DrinkSelectionManager] ✅ 成功获取原始奶茶模型: %s", originalDrinkModel.Name))

	-- 克隆奶茶模型用于手持
	local handDrinkModel = DrinkManager.deepCloneModel(originalDrinkModel)
	if not handDrinkModel then
		warn("playDrinkingAnimation: 无法克隆奶茶模型")
		return false
	end

	-- 🔧 关键修复：为克隆的模型设置Parent，否则attachDrinkToHand会检测到模型无效
	handDrinkModel.Parent = workspace
	print(string.format("[DrinkSelectionManager] ✅ 成功克隆奶茶模型用于手持"))

	-- 🔧 修复：记录玩家是否在座位上，但不强制站立（保持坐着状态播放动画）
	local wasSeated = false
	local originalSeat = nil
	if humanoid.Sit and humanoid.SeatPart then
		wasSeated = true
		originalSeat = humanoid.SeatPart  -- 记录原始座位
		print(string.format("[DrinkSelectionManager] 📍 玩家 %s 保持坐着状态播放喝奶茶动画", player.Name))
		-- 不再强制站立，让玩家在座位上播放动画
	end

	-- 2. 加载并播放动画
	local success, animationTrack = pcall(function()
		local animation = Instance.new("Animation")
		animation.AnimationId = DRINKING_ANIMATION_ID

		local track = animator:LoadAnimation(animation)
		animation:Destroy()

		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false

		return track
	end)

	if not success or not animationTrack then
		warn("playDrinkingAnimation: 动画加载失败")
		if handDrinkModel and handDrinkModel.Parent then
			handDrinkModel:Destroy()
		end
		return false
	end

	print(string.format("[DrinkSelectionManager] ✅ 动画加载成功，开始播放"))

	-- 3. 将奶茶附着到玩家手中
	local attachSuccess = DrinkHandManager.attachDrinkToHand(player, handDrinkModel, drinkIndex, tableId)
	if not attachSuccess then
		warn("playDrinkingAnimation: 奶茶附着到手失败")
		animationTrack:Destroy()
		if handDrinkModel and handDrinkModel.Parent then
			handDrinkModel:Destroy()
		end
		return false
	end

	print(string.format("[DrinkSelectionManager] 📍 奶茶已附着到 %s 的右手", player.Name))

	-- 4. 播放动画
	animationTrack:Play(0.1)  -- 淡入0.1秒

	-- 5. 等待动画完成
	task.delay(DRINKING_ANIMATION_DURATION, function()
		if not player or not player.Parent then
			print("[DrinkSelectionManager] ⚠️ 动画完成时玩家已离线")
			return
		end

		-- 从手中移除奶茶
		local removeSuccess = DrinkHandManager.removeDrinkFromHand(player)
		if removeSuccess then
			print(string.format("[DrinkSelectionManager] ✅ 已从 %s 手中移除奶茶", player.Name))
		end

		-- 销毁手持奶茶模型
		if handDrinkModel and handDrinkModel.Parent then
			pcall(function()
				handDrinkModel:Destroy()
			end)
		end

		-- 停止并销毁动画
		pcall(function()
			animationTrack:Stop(0.1)
			animationTrack:Destroy()
		end)

		-- 🔧 修复：确保玩家继续坐在原始座位上，避免座位状态变化导致对局结束
		if wasSeated and originalSeat and player and player.Parent and player.Character then
			local finalHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if finalHumanoid then
				-- 检查玩家是否仍然坐在原始座位上
				if finalHumanoid.SeatPart == originalSeat then
					print(string.format("[DrinkSelectionManager] ✅ 玩家 %s 成功保持在原座位上", player.Name))
				else
					-- 如果由于某种原因离开了座位，尝试重新坐回原座位
					if originalSeat and not originalSeat.Occupant then
						-- 将玩家移动到座位附近
						local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
						if rootPart then
							rootPart.CFrame = originalSeat.CFrame + Vector3.new(0, 2, 0)
							wait(0.1)
							finalHumanoid.Sit = true
							print(string.format("[DrinkSelectionManager] 🔄 已将玩家 %s 重新坐回原座位", player.Name))
						end
					else
						print(string.format("[DrinkSelectionManager] ⚠️ 原座位已被占用，玩家 %s 保持当前状态", player.Name))
					end
				end
			end
		end

		print(string.format("[DrinkSelectionManager] 🎬 玩家 %s 的喝饮料动作播放完成", player.Name))
	end)

	return true
end

-- 执行饮用流程
function DrinkSelectionManager.executeDrinking(player, drinkIndex, tableId)
	if not tableId then
		tableId = getTableIdFromPlayer(player)
	end

	if not tableId then
		warn("executeDrinking: 无法获取桌子ID")
		return
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState then
		warn("executeDrinking: 无法获取桌子 " .. tableId .. " 的状态")
		return
	end


	-- 聚焦镜头到饮用玩家(只对该桌子玩家)
	if selectionState.player1 and selectionState.player1.Parent then
		cameraControlEvent:FireClient(selectionState.player1, "focusOnDrinking", {targetPlayer = player.Name})
	end
	if selectionState.player2 and selectionState.player2.Parent then
		cameraControlEvent:FireClient(selectionState.player2, "focusOnDrinking", {targetPlayer = player.Name})
	end

	-- 先移除桌上的奶茶模型
	DrinkManager.removeDrinkForTable(tableId, drinkIndex)

	-- V1.5新增: 播放喝饮料动作
	-- 动作播放过程中会从DrinkModel文件夹直接获取模型，不依赖桌子状态
	local animationSuccess = DrinkSelectionManager.playDrinkingAnimation(player, drinkIndex, tableId)

	if not animationSuccess then
		warn("executeDrinking: 动作播放失败，继续使用原流程")
		-- 回退：使用原始等待逻辑
		wait(1)
	else
		-- 动作播放成功，等待其完成（根据动画时长3.0秒）
		wait(3.0)
	end

	-- 立刻检查是否中毒（使用正确的桌子ID）
	local isPoisoned = DrinkManager.isDrinkPoisonedForTable(tableId, drinkIndex)
	local poisonInfo = DrinkManager.getDrinkPoisonInfoForTable(tableId, drinkIndex)

	-- 立刻显示结果(传递tableId)
	DrinkSelectionManager.showDrinkingResult(player, drinkIndex, isPoisoned, poisonInfo, tableId)

	-- 立刻判定游戏是否结束
	if isPoisoned then
		-- 立即结束游戏
		DrinkSelectionManager.endGame(player, "poisoned", poisonInfo, tableId)
	else
		-- 立即继续游戏或结束(传递tableId)
		DrinkSelectionManager.continueOrEndGame(player, drinkIndex, tableId)
	end
end

-- 执行玩家死亡和复活（重构：配合新的服务端主导架构）
function DrinkSelectionManager.executePlayerDeathWithEffect(player)
	if not player or not player.Character then
		warn("DrinkSelectionManager.executePlayerDeathWithEffect: 玩家 " .. (player and player.Name or "未知") .. " 没有角色")
		return
	end


	-- 使用新的死亡效果管理器处理完整的死亡流程
	if _G.DeathEffectManager and _G.DeathEffectManager.handlePlayerDeath then
		local success = _G.DeathEffectManager.handlePlayerDeath(player)
		if success then
		else
			warn("⚠️ 死亡效果管理器处理失败，使用备用方法")
			-- 备用方案：使用原始死亡逻辑
			DrinkSelectionManager.executePlayerDeathFallback(player)
		end
	else
		warn("⚠️ DeathEffectManager未加载，使用备用死亡逻辑")
		-- 备用方案：使用原始死亡逻辑
		DrinkSelectionManager.executePlayerDeathFallback(player)
	end
end

-- 备用死亡处理方法（原版本逻辑，作为后备方案）
function DrinkSelectionManager.executePlayerDeathFallback(player)

	-- 立即恢复死亡玩家的镜头到默认状态
	cameraControlEvent:FireClient(player, "restore")

	-- 禁用死亡玩家的Leave按钮
	if _G.GameManager and _G.GameManager.disableLeaveButton then
		_G.GameManager.disableLeaveButton(player)
	end

	local character = player.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		-- 设置Humanoid的死亡时间，让死亡效果显示更久
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		-- 立即杀死玩家，触发Roblox默认的死亡效果（身体变碎片）
		humanoid.Health = 0

		-- 等待足够时间让死亡效果完全显示
		wait(3)

		-- 重新生成角色（Roblox会自动在SpawnLocation复活）
		player:LoadCharacter()
	else
		warn("玩家 " .. player.Name .. " 没有Humanoid")
	end
end

-- 执行玩家死亡和复活（原版本，保留作为备用）
function DrinkSelectionManager.executePlayerDeath(player)
	if not player or not player.Character then
		warn("玩家 " .. player.Name .. " 没有角色")
		return
	end


	-- 立即恢复死亡玩家的镜头到默认状态
	cameraControlEvent:FireClient(player, "restore")

	-- 禁用死亡玩家的Leave按钮
	if _G.GameManager and _G.GameManager.disableLeaveButton then
		_G.GameManager.disableLeaveButton(player)
	end

	local character = player.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		-- 记录玩家当前座位位置
		local currentSeat = nil
		local workspace = game.Workspace
		local twoPlayerFolder = workspace:FindFirstChild("2Player")
		if twoPlayerFolder then
			local battleGroup = twoPlayerFolder:FindFirstChild("2player_group1")
			if battleGroup then
				local seat1 = battleGroup:FindFirstChild("Seat1")
				local seat2 = battleGroup:FindFirstChild("Seat2")

				if seat1 and seat1.Occupant and seat1.Occupant.Parent == character then
					currentSeat = seat1
				elseif seat2 and seat2.Occupant and seat2.Occupant.Parent == character then
					currentSeat = seat2
				end
			end
		end

		-- 立即杀死玩家
		humanoid.Health = 0

		-- 等待一小段时间确保死亡处理完成
		wait(1)

		-- 重新生成角色（Roblox会自动在SpawnLocation复活）
		player:LoadCharacter()
	else
		warn("玩家 " .. player.Name .. " 没有Humanoid")
	end
end

-- 显示饮用结果
function DrinkSelectionManager.showDrinkingResult(player, drinkIndex, isPoisoned, poisonInfo, tableId)
	if not tableId then
		tableId = getTableIdFromPlayer(player)
	end

	if not tableId then
		warn("showDrinkingResult: 无法获取桌子ID")
		return
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState then
		warn("showDrinkingResult: 无法获取桌子 " .. tableId .. " 的状态")
		return
	end

	local resultText = isPoisoned and "Poison!" or "Safe!"
	local resultColor = isPoisoned and Color3.new(1, 0, 0) or Color3.new(0, 1, 0)

	-- 在玩家头顶显示结果(只对该桌子玩家)
	if selectionState.player1 and selectionState.player1.Parent then
		drinkSelectionEvent:FireClient(selectionState.player1, "showResult", {
			targetPlayer = player.Name,
			result = resultText,
			color = resultColor,
			drinkIndex = drinkIndex
		})
	end

	if selectionState.player2 and selectionState.player2.Parent then
		drinkSelectionEvent:FireClient(selectionState.player2, "showResult", {
			targetPlayer = player.Name,
			result = resultText,
			color = resultColor,
			drinkIndex = drinkIndex
		})
	end

end

-- 继续游戏或结束
function DrinkSelectionManager.continueOrEndGame(player, drinkIndex, tableId)
	if not tableId then
		tableId = getTableIdFromPlayer(player)
	end

	if not tableId then
		warn("continueOrEndGame: 无法获取桌子ID")
		return
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState then
		warn("continueOrEndGame: 无法获取桌子 " .. tableId .. " 的状态")
		return
	end

	-- 如果所有奶茶都被选择完，游戏平局结束
	if #selectionState.availableDrinks == 0 then
		DrinkSelectionManager.endGame(nil, "draw", {}, tableId)
		return
	end

	-- 给饮用安全奶茶的玩家奖励金币
	DrinkSelectionManager.rewardSafeDrinking(player)

	-- 立刻切换到下一个玩家(传递tableId)
	DrinkSelectionManager.switchToNextPlayer(tableId)
end

-- 奖励安全饮用
function DrinkSelectionManager.rewardSafeDrinking(player)
	if not player then return end

	-- 检查CoinManager是否可用
	if CoinManager and CoinManager.rewardSafeDrinking then
		-- 使用CoinManager奖励金币
		local success = CoinManager.rewardSafeDrinking(player)

		if success then
		else
			warn("玩家 " .. player.Name .. " 金币奖励发放失败")
		end
	else
		-- CoinManager未加载，给出提示但不影响游戏流程
	end

	-- 注意：奖励动画现在由CoinManager的UI系统处理
	-- 不再需要通过drinkSelectionEvent发送showReward
end

-- 切换到下一个玩家
function DrinkSelectionManager.switchToNextPlayer(tableId)
	if not tableId then
		warn("switchToNextPlayer: tableId为空")
		return
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState then
		warn("switchToNextPlayer: 无法获取桌子 " .. tableId .. " 的状态")
		return
	end

	-- 隐藏当前等待玩家的等待提示
	DrinkSelectionManager.hideWaitingTips(selectionState.waitingPlayer)

	-- 交换当前玩家和等待玩家
	local temp = selectionState.currentPlayer
	selectionState.currentPlayer = selectionState.waitingPlayer
	selectionState.waitingPlayer = temp

	-- 🔒 清除处理标志，允许新一轮的选择
	selectionState.isProcessingSelection = false

	-- V1.4: 切换倒计时到新的当前玩家
	DrinkSelectionManager.switchPlayerCountdown(tableId, selectionState.currentPlayer)

	-- 开始下一轮(传递tableId)
	DrinkSelectionManager.startPlayerTurn(tableId)
end

-- 结束游戏
function DrinkSelectionManager.endGame(loser, reason, additionalInfo, tableId)
	-- 如果没有传tableId,尝试从loser获取
	if not tableId and loser then
		tableId = getTableIdFromPlayer(loser)
	end

	if not tableId then
		warn("endGame: 无法获取桌子ID")
		return
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState then
		warn("endGame: 无法获取桌子 " .. tableId .. " 的状态")
		return
	end

	-- V1.4: 停止选择阶段倒计时
	DrinkSelectionManager.stopSelectionTurnCountdown(tableId)

	selectionState.activePhase = false
	selectionState.gameResult = {
		loser = loser,
		reason = reason,
		info = additionalInfo
	}
	-- 🔒 清除处理标志
	selectionState.isProcessingSelection = false

	-- 隐藏所有玩家的提示UI
	if selectionState.player1 and selectionState.player1.Parent then
		DrinkSelectionManager.hideSelectTips(selectionState.player1)
		DrinkSelectionManager.hideWaitingTips(selectionState.player1)
		DrinkSelectionManager.hidePropsUI(selectionState.player1)
	end
	if selectionState.player2 and selectionState.player2.Parent then
		DrinkSelectionManager.hideSelectTips(selectionState.player2)
		DrinkSelectionManager.hideWaitingTips(selectionState.player2)
		DrinkSelectionManager.hidePropsUI(selectionState.player2)
	end

	-- 清理桌子上的所有奶茶（使用正确的桌子ID）
	DrinkManager.clearDrinksForTable(tableId)

	-- 立即通知GameManager游戏已进入结果阶段，防止重复获胜判定
	local gamePhaseFlag = ReplicatedStorage:FindFirstChild("GamePhaseFlag")
	if not gamePhaseFlag then
		gamePhaseFlag = Instance.new("StringValue")
		gamePhaseFlag.Name = "GamePhaseFlag"
		gamePhaseFlag.Parent = ReplicatedStorage
	end
	gamePhaseFlag.Value = "result"

	local winner = nil
	if reason == "poisoned" and loser then
		-- 中毒者败北，另一个玩家获胜
		winner = (loser == selectionState.player1) and selectionState.player2 or selectionState.player1

		-- 🔑 验证winner有效性
		if not winner then
			warn("DrinkSelectionManager.endGame: 无法确定获胜者")
			return
		end

		-- 记录排行榜数据
		DrinkSelectionManager.recordGameResultToRanking(winner, loser)

		-- 🔑 立即设置赢家镜头到桌面俯视，避免镜头停留在失败者身后
		DrinkSelectionManager.setWinnerPrepareCamera(winner)

		-- 播放获胜者的胜利动作（所有人可见，禁用移动）
		-- 🔑 等待镜头切换完成（CameraController tweenTime=1.1s）后再播放，视觉体验更流畅
		if _G.VictoryAnimationManager and _G.VictoryAnimationManager.playVictoryAnimation then
			local animSuccess = _G.VictoryAnimationManager.playVictoryAnimation(winner, {
				delayBeforePlay = 1.2,  -- 等待镜头tween完成（1.1s）+ 0.1s缓冲
			})
			if not animSuccess then
				warn("DrinkSelectionManager: 胜利动作播放失败")
			end
		else
			warn("DrinkSelectionManager: VictoryAnimationManager未加载，跳过动作播放")
		end

		-- 执行失败玩家的死亡和复活（带黑屏死亡效果）
		DrinkSelectionManager.executePlayerDeathWithEffect(loser)

		-- 延迟重置获胜玩家到等待状态，等待失败方死亡流程完成
		DrinkSelectionManager.resetWinnerToWaitingStateDelayed(winner, loser)

	elseif reason == "draw" then

		-- 平局时没有胜负，不记录排行榜数据

		-- 平局时为两个玩家都立即重置到等待状态
		DrinkSelectionManager.resetWinnerToWaitingState(selectionState.player1)
		DrinkSelectionManager.resetWinnerToWaitingState(selectionState.player2)
	end

	-- 游戏状态已经被立即重置，不需要再等待5秒
end

-- 为获胜玩家立即重置到等待状态
function DrinkSelectionManager.resetWinnerToWaitingState(player)
	if not player then return end


	-- 通过TableManager和GameInstance立即重置游戏状态
	if _G.TableManager then
		local tableId = _G.TableManager.detectPlayerTable(player)
		if tableId then
			local gameInstance = _G.TableManager.getTableInstance(tableId)
			if gameInstance then

				-- 获取该桌子的选择状态(用于检查死亡流程)
				local selectionState = getSelectionState(tableId)

				-- 首先设置游戏阶段为waiting，确保座位检测逻辑正确工作
				gameInstance.gameState.gamePhase = "waiting"

				-- 清理游戏状态
				gameInstance.gameState.isCountingDown = false
				gameInstance.gameState.poisonSelections = {}

				-- 🔑 关键修复：游戏结束时禁用SeatLockController的自动锁定功能
				-- 这样玩家重新坐下时不会被自动锁定，可以自由使用Leave按钮离开
				if selectionState.player1 and selectionState.player1.Parent then
					pcall(function()
						-- 通过RemoteEvent直接控制客户端座位系统
						local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
						if remoteEventsFolder then
							local seatControlEvent = remoteEventsFolder:FindFirstChild("SeatControl")
							if seatControlEvent then
								seatControlEvent:FireClient(selectionState.player1, "setGameActive", false)
							end
						end
					end)
				end
				if selectionState.player2 and selectionState.player2.Parent then
					pcall(function()
						-- 通过RemoteEvent直接控制客户端座位系统
						local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
						if remoteEventsFolder then
							local seatControlEvent = remoteEventsFolder:FindFirstChild("SeatControl")
							if seatControlEvent then
								seatControlEvent:FireClient(selectionState.player2, "setGameActive", false)
							end
						end
					end)
				end

				-- 禁用AirWall，恢复自由通行
				gameInstance:disableAirWalls()

				-- 显示Menu界面（退出对局状态）
				-- 根据用户需求：死亡玩家复活后和获胜玩家都应该隐藏death和skin按钮，只显示shop按钮
				-- V1.9: NewPlayerGift按钮根据领取状态决定是否显示
				if gameInstance.gameState.player1 then
					local shouldShowGift_end1 = true  -- 默认显示
					if _G.PropManager and _G.PropManager.hasReceivedNewPlayerGift then
						local hasReceived = _G.PropManager.hasReceivedNewPlayerGift(gameInstance.gameState.player1)
						-- 只有明确已领取时才隐藏
						if hasReceived == true then
							shouldShowGift_end1 = false
						end
					end

					gameInstance:setSpecificMenuVisibility(gameInstance.gameState.player1, {
						shop = true,
						death = false,
						skin = true,  -- V2.0: 皮肤按钮任何情况下都显示
						newPlayerGift = shouldShowGift_end1  -- V1.9: 根据领取状态决定
					})
				end
				if gameInstance.gameState.player2 then
					local shouldShowGift_end2 = true  -- 默认显示
					if _G.PropManager and _G.PropManager.hasReceivedNewPlayerGift then
						local hasReceived = _G.PropManager.hasReceivedNewPlayerGift(gameInstance.gameState.player2)
						-- 只有明确已领取时才隐藏
						if hasReceived == true then
							shouldShowGift_end2 = false
						end
					end

					gameInstance:setSpecificMenuVisibility(gameInstance.gameState.player2, {
						shop = true,
						death = false,
						skin = true,  -- V2.0: 皮肤按钮任何情况下都显示
						newPlayerGift = shouldShowGift_end2  -- V1.9: 根据领取状态决定
					})
				end

				-- 清理桌子上的奶茶模型
				DrinkManager.clearDrinksForTable(tableId)

				-- 显示BillboardGui
				gameInstance.billboardGui.Enabled = true

				-- 短暂等待，确保所有状态更新完成
				wait(0.2)

				-- 现在手动重新检测座位状态（这会触发正确的状态更新）
				-- 但要考虑到可能有玩家正在死亡流程中
				local actualPlayersInSeats = 0
				local actualPlayer1 = nil
				local actualPlayer2 = nil

				-- 检查座位1
				if gameInstance.seat1.Occupant then
					local player1 = Players:GetPlayerFromCharacter(gameInstance.seat1.Occupant.Parent)
					if player1 then
						actualPlayer1 = player1
						actualPlayersInSeats = actualPlayersInSeats + 1
					end
				end

				-- 检查座位2
				if gameInstance.seat2.Occupant then
					local player2 = Players:GetPlayerFromCharacter(gameInstance.seat2.Occupant.Parent)
					if player2 then
						actualPlayer2 = player2
						actualPlayersInSeats = actualPlayersInSeats + 1
					end
				end

				-- 检查是否有玩家正在死亡流程中（但排除已强制清理的状态）
				local playersInDeathProcess = 0
				if _G.DeathEffectManager and selectionState then
					-- 检查原来的player1是否在死亡流程中
					if selectionState.player1 and _G.DeathEffectManager.getPlayerDeathState(selectionState.player1) ~= "none" then
						local deathState = _G.DeathEffectManager.getPlayerDeathState(selectionState.player1)
						playersInDeathProcess = playersInDeathProcess + 1
					end
					-- 检查原来的player2是否在死亡流程中
					if selectionState.player2 and _G.DeathEffectManager.getPlayerDeathState(selectionState.player2) ~= "none" then
						local deathState = _G.DeathEffectManager.getPlayerDeathState(selectionState.player2)
						playersInDeathProcess = playersInDeathProcess + 1
					end
				end

				-- 解决思路3: 只计算座位上的实际玩家，不包含死亡流程中的玩家
				-- 这样可以避免"看起来1个人但显示2个人"的问题
				local totalPlayers = actualPlayersInSeats

				-- 更新游戏状态
				gameInstance.gameState.player1 = actualPlayer1
				gameInstance.gameState.player2 = actualPlayer2
				gameInstance.gameState.playersReady = totalPlayers

				-- 解决思路3: 强制更新显示状态
				gameInstance:updatePlayerCount()

				-- 🔑 关键修复：不依赖humanoid.Sit判断，而是检查玩家是否真的坐在座位上
				-- 原因：humanoid.Sit可能因为物理接触而误报，导致错误的"胜利者已在座位上"判断

				-- 🔑 新增保护：检查是否有胜利动画正在进行，避免多系统冲突
				local isVictoryAnimationActive = _G.VictoryAnimationInProgress and _G.VictoryAnimationInProgress[player]
				if isVictoryAnimationActive then
					print(string.format("⚠️ 玩家 %s 正在播放胜利动画，跳过座位状态检查以避免冲突", player.Name))
				elseif player and player.Parent and player.Character then
					local humanoid = player.Character:FindFirstChildOfClass("Humanoid")

					if humanoid then
						-- 🔑 修复：检查玩家是否真的坐在座位上（有SeatPart）而不只是Sit=true
						if humanoid.SeatPart then
							print(string.format("✅ 胜利者 %s 真实在座位上 (SeatPart: %s)", player.Name, humanoid.SeatPart.Name))
							-- 🔑 立即启用Leave按钮，避免玩家被困
							gameInstance:enableLeaveButton(player)
							print(string.format("✅ 已为玩家 %s 启用Leave按钮", player.Name))
						else
							-- 🔑 胜利者不在座位上，这是正常的（胜利动画结束后应该站立）
							print(string.format("ℹ️ 胜利者 %s 未在座位上，这是正常的（动画结束后应该站立）", player.Name))

							-- 🔑 强制确保角色站立状态
							if humanoid.Sit then
								humanoid.Sit = false
								print(string.format("🔄 强制胜利者 %s 站立，修正异常的Sit状态", player.Name))
							end

							-- 只需要确保座位可用状态已恢复，不强制坐下
							local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
							if rootPart then
								-- 查找玩家附近5单位内的座位，确保状态已恢复
								local nearbyParts = workspace:GetPartBoundsInRadius(rootPart.Position, 5)
								for _, part in ipairs(nearbyParts) do
									if part:IsA("Seat") then
										-- 只确保座位可用，不强制坐下
										if part.Disabled then
											part.Disabled = false  -- 恢复座位可用状态
										end
										if part.Transparency > 0 then
											part.Transparency = 0   -- 恢复座位可见性
										end
										print(string.format("✅ 已恢复座位 %s 的可用状态（玩家可自由选择是否坐下）", part.Name))
									end
								end
							end
						end
					end
				end

				-- 短暂等待，确保座位操作完成
				wait(0.2)

				-- 重新检测座位状态（因为刚才可能改变了）
				actualPlayersInSeats = 0
				actualPlayer1 = nil
				actualPlayer2 = nil

				-- 检查座位1
				if gameInstance.seat1.Occupant then
					local player1 = Players:GetPlayerFromCharacter(gameInstance.seat1.Occupant.Parent)
					if player1 then
						actualPlayer1 = player1
						actualPlayersInSeats = actualPlayersInSeats + 1
					end
				end

				-- 检查座位2
				if gameInstance.seat2.Occupant then
					local player2 = Players:GetPlayerFromCharacter(gameInstance.seat2.Occupant.Parent)
					if player2 then
						actualPlayer2 = player2
						actualPlayersInSeats = actualPlayersInSeats + 1
					end
				end

				-- 更新游戏状态
				gameInstance.gameState.player1 = actualPlayer1
				gameInstance.gameState.player2 = actualPlayer2
				gameInstance.gameState.playersReady = actualPlayersInSeats
				gameInstance:updatePlayerCount()

				-- 🔑 关键修复：为两个玩家都设置镜头和按钮状态
				-- 胜利者应该已经被强制坐回座位，无条件设置准备状态镜头
				-- 失败者如果不在座位，使用restore镜头

				-- 检查player1状态
				if actualPlayer1 and actualPlayer1.Parent and actualPlayer1.Character then
					-- player1（可能是胜利者）始终设置准备状态镜头
					local cameraData = {
						tableId = tableId,
						tablePosition = gameInstance.tablePart.Position
					}
					cameraControlEvent:FireClient(actualPlayer1, "enterPrepare", cameraData)

					-- 确保Leave按钮启用（如果在座位上）
					local humanoid1 = actualPlayer1.Character:FindFirstChildOfClass("Humanoid")
					if humanoid1 and humanoid1.Sit then
						gameInstance:enableLeaveButton(actualPlayer1)
					end
					print(string.format("✅ 玩家 %s 镜头已设置为准备状态", actualPlayer1.Name))
				end

				-- 检查player2状态
				if actualPlayer2 and actualPlayer2.Parent and actualPlayer2.Character then
					local humanoid2 = actualPlayer2.Character:FindFirstChildOfClass("Humanoid")
					if humanoid2 and humanoid2.Sit then
						-- player2在座位上，设置准备状态镜头
						local cameraData = {
							tableId = tableId,
							tablePosition = gameInstance.tablePart.Position
						}
						cameraControlEvent:FireClient(actualPlayer2, "enterPrepare", cameraData)
						gameInstance:enableLeaveButton(actualPlayer2)
						print(string.format("✅ 玩家 %s 镜头已恢复到准备状态", actualPlayer2.Name))
					else
						-- player2不在座位上（失败者在SpawnLocation），恢复默认镜头
						cameraControlEvent:FireClient(actualPlayer2, "restore")
						print(string.format("✅ 玩家 %s 镜头已恢复为默认状态", actualPlayer2.Name))
					end
				end
			end
		end
	end

	-- 解决思路4: 清理旧的selectionState引用，避免旧对局数据继续影响下一轮
	-- 重新获取tableId（因为可能在上面的if块中获取失败）
	local tableId = _G.TableManager and _G.TableManager.detectPlayerTable(player)
	if tableId then
		DrinkSelectionManager.resetGame(tableId)
	end

end

-- 简化的获胜玩家重置逻辑（重构：配合新的服务端主导死亡架构）
function DrinkSelectionManager.resetWinnerToWaitingStateDelayed(winner, loser)
	if not winner then return end


	-- 等待两个条件：
	-- 条件1: 失败者死亡流程完成
	-- 条件2: 胜利动作播放完成（1.2s镜头延迟 + 3s动作 + 缓冲）
	spawn(function()
		local maxWaitTime = 10  -- 最多等待10秒
		local checkInterval = 0.5  -- 每0.5秒检查一次
		local elapsedTime = 0

		local deathCompleted = false
		local animationCompleted = false
		local ANIMATION_TOTAL_TIME = 4.7  -- 1.2s镜头延迟 + 3s动作 + 0.5s缓冲

		-- 轮询等待两个条件都满足
		while elapsedTime < maxWaitTime do
			wait(checkInterval)
			elapsedTime = elapsedTime + checkInterval

			-- 验证玩家仍然有效
			if not winner or not winner.Parent then
				warn("获胜玩家在等待期间离开了游戏")
				return
			end

			-- 检查条件1：失败者是否完成死亡流程
			if not deathCompleted then
				if _G.DeathEffectManager and _G.DeathEffectManager.getPlayerDeathState then
					local deathState = _G.DeathEffectManager.getPlayerDeathState(loser)
					if deathState == "none" then
						deathCompleted = true
					end
				else
					-- 没有DeathEffectManager,等待固定4秒
					if elapsedTime >= 4 then
						deathCompleted = true
					end
				end
			end

			-- 检查条件2：胜利动作是否播放完成
			if not animationCompleted then
				if elapsedTime >= ANIMATION_TOTAL_TIME then
					animationCompleted = true
				end
			end

			-- 两个条件都满足，退出等待
			if deathCompleted and animationCompleted then
				break
			end
		end

		-- 如果超时但仍未完成,发出警告但继续
		if _G.DeathEffectManager and _G.DeathEffectManager.getPlayerDeathState then
			local finalDeathState = _G.DeathEffectManager.getPlayerDeathState(loser)
			if finalDeathState ~= "none" then
				warn("⚠️ 等待" .. elapsedTime .. "秒后失败玩家状态仍为: " .. finalDeathState .. "，但继续重置获胜玩家")
			end
		end

		-- 执行获胜玩家的状态重置
		DrinkSelectionManager.resetWinnerToWaitingState(winner)
	end)
end

-- 立即恢复BillboardGui显示
function DrinkSelectionManager.restoreBillboardGui()
	-- 通过TableManager获取当前桌子并恢复BillboardGui
	if _G.TableManager then
		local allTableInstances = _G.TableManager.getAllTableInstances()
		for tableId, gameInstance in pairs(allTableInstances) do
			if gameInstance and gameInstance.billboardGui then
				gameInstance.billboardGui.Enabled = true

				-- 更新玩家数显示
				if gameInstance.updatePlayerCount then
					gameInstance:updatePlayerCount()
				end
			end
		end
	else
		-- 备用方案：如果TableManager不可用，使用全局GameManager
		if _G.GameManager and _G.GameManager.resetToWaiting then
			-- 触发GameManager的重置，它会恢复BillboardGui
			local gamePhaseFlag = ReplicatedStorage:FindFirstChild("GamePhaseFlag")
			if gamePhaseFlag then
				gamePhaseFlag.Value = "waiting"
			end
		end
	end
end

-- 为获胜方立即设置准备状态镜头（等待完整重置）
function DrinkSelectionManager.setWinnerPrepareCamera(player)
	if not player then return end

	-- 🔑 Bug 1 修复：无论玩家是否在座位上，都优先使用桌面镜头
	-- 只有完全获取不到桌子数据时才回退到 restore

	-- 获取玩家所在桌子信息
	if _G.TableManager then
		local tableId = _G.TableManager.detectPlayerTable(player)
		if tableId then
			local gameInstance = _G.TableManager.getTableInstance(tableId)
			if gameInstance then
				-- 使用GameInstance的镜头控制方法，包含桌子位置信息
				local cameraData = {
					tableId = tableId,
					tablePosition = gameInstance.tablePart.Position
				}
				cameraControlEvent:FireClient(player, "enterPrepare", cameraData)
				print(string.format("✅ 已设置玩家 %s 镜头为桌面俯视（桌子: %s）", player.Name, tableId))
				return
			end
		end
	end

	-- 完全无法获取桌子数据时才回退到 restore
	warn(string.format("⚠️ 无法获取玩家 %s 的桌子数据，使用 restore 镜头", player.Name))
	cameraControlEvent:FireClient(player, "restore")
end

-- 为获胜玩家重置到对战准备状态（已弃用）
function DrinkSelectionManager.resetWinnerToPrepareState(player)
	if not player then return end


	-- 立即设置获胜玩家的镜头到准备状态
	if player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Sit then
		-- 玩家仍然在座位上，设置准备状态镜头
		-- 获取玩家所在桌子信息
		if _G.TableManager then
			local tableId = _G.TableManager.detectPlayerTable(player)
			if tableId then
				local gameInstance = _G.TableManager.getTableInstance(tableId)
				if gameInstance then
					-- 使用GameInstance的镜头控制方法，包含桌子位置信息
					local cameraData = {
						tableId = tableId,
						tablePosition = gameInstance.tablePart.Position
					}
					cameraControlEvent:FireClient(player, "enterPrepare", cameraData)
				else
					-- 回退方案：使用基本镜头控制
					cameraControlEvent:FireClient(player, "enterPrepare")
				end
			else
				-- 无法检测桌子，使用基本镜头控制
				cameraControlEvent:FireClient(player, "enterPrepare")
			end
		else
			-- TableManager不可用，使用基本镜头控制
			cameraControlEvent:FireClient(player, "enterPrepare")
		end
	else
		-- 玩家不在座位上，恢复默认镜头
		cameraControlEvent:FireClient(player, "restore")
	end

	-- 通过RemoteEvent请求GameManager启用Leave按钮
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local seatLockEvent = remoteEventsFolder:FindFirstChild("SeatLock")
	if seatLockEvent then
		-- 方法1：通过ReplicatedStorage传递信号
		local enableLeaveFlag = ReplicatedStorage:FindFirstChild("EnableLeaveFlag")
		if not enableLeaveFlag then
			enableLeaveFlag = Instance.new("StringValue")
			enableLeaveFlag.Name = "EnableLeaveFlag"
			enableLeaveFlag.Parent = ReplicatedStorage
		end
		enableLeaveFlag.Value = player.Name .. "_" .. tick() -- 使用时间戳确保唯一性

	end

end

-- 记录游戏结果到排行榜系统
function DrinkSelectionManager.recordGameResultToRanking(winner, loser)
	if not winner or not loser then
		warn("❌ 记录排行榜数据失败: 获胜者或失败者为空")
		return false
	end

	print("🎯 开始记录游戏结果: 获胜者=" .. winner.Name .. ", 失败者=" .. loser.Name)

	-- 🔧 关键修复：同步等待RankingDataManager加载，最多等待5秒
	local maxWaitTime = 5
	local waitStartTime = tick()
	local waitCompleted = false

	-- 如果RankingDataManager未加载，同步等待
	while not _G.RankingDataManager and (tick() - waitStartTime) < maxWaitTime do
		wait(0.1)
	end

	-- 检查RankingDataManager是否可用
	if not _G.RankingDataManager then
		warn("❌ RankingDataManager 加载超时，无法记录排行榜数据")

		-- 🔧 关键修复：即使RankingDataManager未加载，也要尝试通过备用方式记录
		-- 将数据存储到临时表中，等待后续处理
		if not _G.PendingGameResults then
			_G.PendingGameResults = {}
		end

		table.insert(_G.PendingGameResults, {
			winner = winner,
			loser = loser,
			timestamp = tick(),
			gameEndTime = os.time()
		})

		warn("⚠️ 游戏结果已存储到待处理队列，等待RankingDataManager可用")

		-- 启动后台重试任务
		spawn(function()
			local retryAttempts = 0
			while retryAttempts < 20 do -- 最多重试20次（100秒）
				wait(5)
				retryAttempts = retryAttempts + 1

				if _G.RankingDataManager and #_G.PendingGameResults > 0 then
					print("🔄 RankingDataManager现已可用，处理待处理的游戏结果...")

					local processedCount = 0
					local failedCount = 0

					-- 处理所有待处理的结果
					for i = #_G.PendingGameResults, 1, -1 do
						local result = _G.PendingGameResults[i]

						-- 检查结果是否太旧（超过5分钟的结果可能无效）
						if tick() - result.timestamp > 300 then
							table.remove(_G.PendingGameResults, i)
							warn("⚠️ 丢弃过期的游戏结果: " .. result.winner.Name .. " vs " .. result.loser.Name)
							continue
						end

						-- 验证玩家仍然有效
						if result.winner and result.winner.Parent and result.loser and result.loser.Parent then
							local success = DrinkSelectionManager.recordGameResultToRankingInternal(result.winner, result.loser)
							if success then
								table.remove(_G.PendingGameResults, i)
								processedCount = processedCount + 1
								print("✅ 成功处理待处理结果: " .. result.winner.Name .. " vs " .. result.loser.Name)
							else
								failedCount = failedCount + 1
							end
						else
							-- 玩家已离线，移除该结果
							table.remove(_G.PendingGameResults, i)
							warn("⚠️ 玩家已离线，移除游戏结果: " .. (result.winner and result.winner.Name or "未知") .. " vs " .. (result.loser and result.loser.Name or "未知"))
						end
					end

					if processedCount > 0 then
						print("🎉 成功处理 " .. processedCount .. " 个待处理的游戏结果")
					end
					if failedCount > 0 then
						warn("⚠️ 仍有 " .. failedCount .. " 个结果处理失败")
					end

					-- 如果队列为空，退出重试
					if #_G.PendingGameResults == 0 then
						break
					end
				end
			end
		end)

		return false
	end

	-- RankingDataManager可用，直接处理
	return DrinkSelectionManager.recordGameResultToRankingInternal(winner, loser)
end

-- 🔧 新增：内部记录函数，处理实际的排行榜记录逻辑
function DrinkSelectionManager.recordGameResultToRankingInternal(winner, loser)
	if not _G.RankingDataManager then
		return false
	end

	-- V1.6: 在记录失败者结果前，先保存其连胜数用于购买恢复功能
	local loserPendingStreak = 0
	if _G.RankingDataManager.getPlayerRankingData then
		local loserData = _G.RankingDataManager.getPlayerRankingData(loser)
		if loserData then
			loserPendingStreak = loserData.consecutiveWins

			-- 立即设置pendingStreak（在连胜被清零前）
			if loserPendingStreak >= 1 and _G.RankingDataManager.setPendingStreak then
				local success = _G.RankingDataManager.setPendingStreak(loser, loserPendingStreak)
				if not success then
					warn("⚠️ 保存失败者 " .. loser.Name .. " 的待恢复连胜数失败")
				else
					print("💾 已保存失败者 " .. loser.Name .. " 的待恢复连胜数: " .. loserPendingStreak)
				end
			end
		end
	end

	-- 🔧 关键修复：增加重试机制，确保记录成功
	local maxRecordRetries = 3
	local winnerSuccess = false
	local loserSuccess = false

	-- 记录获胜者结果（带重试）
	for attempt = 1, maxRecordRetries do
		winnerSuccess = _G.RankingDataManager.recordGameResult(winner, true)
		if winnerSuccess then
			print("✅ 获胜者 " .. winner.Name .. " 数据记录成功 (尝试 " .. attempt .. ")")
			break
		else
			warn("⚠️ 获胜者 " .. winner.Name .. " 数据记录失败 (尝试 " .. attempt .. ")")
			if attempt < maxRecordRetries then
				wait(0.5) -- 短暂等待后重试
			end
		end
	end

	-- 记录失败者结果（带重试）
	for attempt = 1, maxRecordRetries do
		loserSuccess = _G.RankingDataManager.recordGameResult(loser, false)
		if loserSuccess then
			print("✅ 失败者 " .. loser.Name .. " 数据记录成功 (尝试 " .. attempt .. ")")
			break
		else
			warn("⚠️ 失败者 " .. loser.Name .. " 数据记录失败 (尝试 " .. attempt .. ")")
			if attempt < maxRecordRetries then
				wait(0.5) -- 短暂等待后重试
			end
		end
	end

	if winnerSuccess and loserSuccess then
		print("🎉 排行榜数据记录完全成功: " .. winner.Name .. " 胜 " .. loser.Name)

		-- V1.5: 更新玩家头顶连胜显示
		if _G.PlayerOverheadDisplayManager then
			_G.PlayerOverheadDisplayManager.onWinStreakChanged(winner)
			_G.PlayerOverheadDisplayManager.onWinStreakChanged(loser)
		end

		return true
	else
		warn("❌ 排行榜数据记录失败")
		if not winnerSuccess then
			warn("❌ 获胜者 " .. winner.Name .. " 数据记录失败")
		end
		if not loserSuccess then
			warn("❌ 失败者 " .. loser.Name .. " 数据记录失败")
		end
		return false
	end
end

-- 重置游戏
function DrinkSelectionManager.resetGame(tableId)
	-- 如果传递了tableId,只清理该桌子的状态
	if tableId then
		local selectionState = getSelectionState(tableId)
		if selectionState then
			selectionState.activePhase = false
			selectionState.player1 = nil
			selectionState.player2 = nil
			selectionState.currentPlayer = nil
			selectionState.waitingPlayer = nil
			selectionState.selectionOrder = {}
			selectionState.gameResult = nil
			selectionState.availableDrinks = {}
			selectionState.isProcessingSelection = false  -- 🔒 重置处理标志
		end

		-- 清理该桌子的DrinkSelection标志
		local drinkSelectionFlag = ReplicatedStorage:FindFirstChild("DrinkSelectionActive_" .. tableId)
		if drinkSelectionFlag then
			drinkSelectionFlag.Value = false
		end

		-- 清理该桌子的奶茶
		DrinkManager.clearDrinksForTable(tableId)

		-- 通知GameManager重置到等待状态
		local gamePhaseFlag = ReplicatedStorage:FindFirstChild("GamePhaseFlag")
		if not gamePhaseFlag then
			gamePhaseFlag = Instance.new("StringValue")
			gamePhaseFlag.Name = "GamePhaseFlag"
			gamePhaseFlag.Parent = ReplicatedStorage
		end
		gamePhaseFlag.Value = "waiting"

		return
	end

	-- 如果没有传tableId,清理全局状态(向后兼容,已弃用)

	-- 清除ReplicatedStorage中的DrinkSelection标志
	local drinkSelectionFlag = ReplicatedStorage:FindFirstChild("DrinkSelectionActive")
	if drinkSelectionFlag then
		drinkSelectionFlag.Value = false
	end

	-- 通知GameManager重置到等待状态（恢复BillboardGui等）
	local gamePhaseFlag = ReplicatedStorage:FindFirstChild("GamePhaseFlag")
	if not gamePhaseFlag then
		gamePhaseFlag = Instance.new("StringValue")
		gamePhaseFlag.Name = "GamePhaseFlag"
		gamePhaseFlag.Parent = ReplicatedStorage
	end
	gamePhaseFlag.Value = "waiting"

	-- 🔧 修复：移除错误的"最后一道保险"逻辑
	-- 原逻辑会误清理其他正在游戏中的桌子的奶茶（判断条件反了）
	-- 正确的清理已在第1503行完成，TableManager的定期清理会处理遗留奶茶

end

-- 设置RemoteEvent处理
function DrinkSelectionManager.setupRemoteEvents()
	drinkSelectionEvent.OnServerEvent:Connect(function(player, action, data)
		if action == "selectDrink" then
			DrinkSelectionManager.onPlayerSelectDrink(player, data.drinkIndex)
		end
	end)

end

-- 初始化
function DrinkSelectionManager.initialize()
	DrinkSelectionManager.setupRemoteEvents()
end

-- 启动管理器
DrinkSelectionManager.initialize()

-- 导出到全局供其他脚本使用
_G.DrinkSelectionManager = DrinkSelectionManager

-- 检查选择阶段是否激活
function DrinkSelectionManager.isSelectionPhaseActive(tableId)
	-- 如果没有传tableId,检查是否有任何桌子在选择阶段(向后兼容)
	if not tableId then
		for tid, state in pairs(selectionStates) do
			if state.activePhase then
				return true
			end
		end
		return false
	end

	local selectionState = getSelectionState(tableId)
	return selectionState and selectionState.activePhase or false
end

-- 因玩家离开而结束选择阶段
function DrinkSelectionManager.endSelectionPhaseByPlayerLeave(winner, leavingPlayer, tableId)
	-- 如果没有传tableId,尝试从玩家检测
	if not tableId then
		tableId = getTableIdFromPlayer(leavingPlayer) or getTableIdFromPlayer(winner)
	end

	if not tableId then
		warn("endSelectionPhaseByPlayerLeave: 无法获取桌子ID")
		return
	end

	local selectionState = getSelectionState(tableId)
	if not selectionState or not selectionState.activePhase then
		return
	end

	-- V1.4: 停止选择阶段倒计时
	DrinkSelectionManager.stopSelectionTurnCountdown(tableId)

	-- 清理选择阶段状态
	selectionState.activePhase = false
	selectionState.gameResult = {
		winner = winner,
		loser = leavingPlayer,
		reason = "player_left"
	}
	-- 🔒 清除处理标志
	selectionState.isProcessingSelection = false

	-- 隐藏所有UI
	if selectionState.player1 and selectionState.player1.Parent then
		DrinkSelectionManager.hideSelectTips(selectionState.player1)
		DrinkSelectionManager.hideWaitingTips(selectionState.player1)
		DrinkSelectionManager.hidePropsUI(selectionState.player1)
	end
	if selectionState.player2 and selectionState.player2.Parent then
		DrinkSelectionManager.hideSelectTips(selectionState.player2)
		DrinkSelectionManager.hideWaitingTips(selectionState.player2)
		DrinkSelectionManager.hidePropsUI(selectionState.player2)
	end
	if winner and winner.Parent and winner ~= selectionState.player1 and winner ~= selectionState.player2 then
		DrinkSelectionManager.hideSelectTips(winner)
		DrinkSelectionManager.hideWaitingTips(winner)
		DrinkSelectionManager.hidePropsUI(winner)
	end

	-- 重置状态(传递tableId)
	DrinkSelectionManager.resetGame(tableId)
end

return DrinkSelectionManager
