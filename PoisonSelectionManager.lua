-- 脚本名称: PoisonSelectionManager
-- 脚本作用: 管理毒药注入选择机制，处理UI和确认逻辑
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- V2.0: 完整的多桌状态隔离重构

local PoisonSelectionManager = {}
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引入其他管理器（避免循环依赖，延迟加载）
local DrinkManager = nil
local DrinkSelectionManager = nil
local CountdownManager = nil

-- 延迟加载的 RemoteEvents
local remoteEventsFolder = nil
local poisonSelectionEvent = nil
local poisonIndicatorEvent = nil

-- 获取或初始化RemoteEvents
local function getRemoteEvents()
	if not remoteEventsFolder then
		remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
		if not remoteEventsFolder then
			warn("PoisonSelectionManager: RemoteEvents文件夹不存在")
			return false
		end
	end

	if not poisonSelectionEvent then
		poisonSelectionEvent = remoteEventsFolder:FindFirstChild("PoisonSelection")
		if not poisonSelectionEvent then
			warn("PoisonSelectionManager: PoisonSelection RemoteEvent不存在")
			return false
		end
	end

	if not poisonIndicatorEvent then
		poisonIndicatorEvent = remoteEventsFolder:FindFirstChild("PoisonIndicator")
		if not poisonIndicatorEvent then
			warn("PoisonSelectionManager: PoisonIndicator RemoteEvent不存在")
			return false
		end
	end

	return true
end

-- 初始化标志
local isInitialized = false

-- 确保初始化（延迟初始化）
local function ensureInitialized()
	if not isInitialized then
		-- 先获取RemoteEvents
		if getRemoteEvents() then
			PoisonSelectionManager.setupRemoteEvents()
			isInitialized = true
		else
			warn("PoisonSelectionManager 初始化失败：RemoteEvents不可用")
			return false
		end
	end
	return true
end

-- 道具ID配置 (V1.7: 更新为新的开发者商品ID)
local DEVELOPER_PRODUCT_ID = 3416569819

-- ========== 多桌状态隔离核心重构 ==========
-- 按桌子隔离的毒药选择状态
local poisonStates = {} -- {[tableId] = PoisonStateData}

-- 单个桌子的毒药状态数据结构
local function createNewPoisonState()
	return {
		activePhase = false,
		player1 = nil,
		player2 = nil,
		playerSelections = {},
		playerConfirmations = {},
		completedPlayers = {},
		playerPoisonList = {},
		extraPoisonTargets = {},
		startTime = 0,
	}
end

-- 获取或创建桌子的毒药状态
local function getPoisonState(tableId)
	if not tableId then
		warn("getPoisonState: tableId为空")
		return nil
	end

	if not poisonStates[tableId] then
		poisonStates[tableId] = createNewPoisonState()
	end

	return poisonStates[tableId]
end

-- 通过玩家获取桌子ID
local function getTableIdFromPlayer(player)
	if not player then return nil end

	-- 方法1: 使用TableManager检测
	if _G.TableManager and _G.TableManager.detectPlayerTable then
		local tableId = _G.TableManager.detectPlayerTable(player)
		if tableId then return tableId end
	end

	-- 方法2: 遍历所有毒药状态查找
	for tableId, state in pairs(poisonStates) do
		if state.player1 == player or state.player2 == player then
			return tableId
		end
	end

	return nil
end

-- 清理桌子状态(对局结束时调用)
function PoisonSelectionManager.cleanupTableState(tableId)
	if poisonStates[tableId] then
		poisonStates[tableId] = nil
	end
end
-- ========== 多桌状态隔离核心重构结束 ==========

-- ========== V1.4 倒计时功能 ==========
-- 启动毒药阶段倒计时
function PoisonSelectionManager.startPoisonPhaseCountdown(tableId, player1, player2)
	-- 延迟加载CountdownManager
	if not CountdownManager then
		CountdownManager = _G.CountdownManager
		if not CountdownManager then
			warn("PoisonSelectionManager: CountdownManager未加载")
			return false
		end
	end

	local config = CountdownManager.getConfig()
	local countdownTypes = CountdownManager.getCountdownTypes()

	-- 设置倒计时选项
	local options = {
		onTimeout = function(tableId)
			PoisonSelectionManager.onPoisonPhaseTimeout(tableId)
		end,
		onUpdate = function(tableId, remainingTime)
			PoisonSelectionManager.onPoisonPhaseUpdate(tableId, remainingTime)
		end,
		onWarning = function(tableId, remainingTime)
			PoisonSelectionManager.onPoisonPhaseWarning(tableId, remainingTime)
		end,
		customData = {
			phase = "poison_selection",
			uiPath = "ConfirmTips"
		}
	}

	-- 启动倒计时
	local success = CountdownManager.startCountdown(
		tableId,
		countdownTypes.POISON_PHASE,
		config.POISON_PHASE_DURATION,
		{player1, player2},
		options
	)

	if not success then
		warn("PoisonSelectionManager: 启动毒药阶段倒计时失败")
		return false
	end

	print("PoisonSelectionManager: 毒药阶段倒计时已启动 - 桌子: " .. tableId)
	return true
end

-- 毒药阶段倒计时超时处理
function PoisonSelectionManager.onPoisonPhaseTimeout(tableId)
	print("PoisonSelectionManager: 毒药阶段倒计时超时 - 桌子: " .. tableId)

	local poisonState = getPoisonState(tableId)
	if not poisonState or not poisonState.activePhase then
		return
	end

	-- 为未完成选择的玩家自动选择
	local playersToAutoSelect = {}

	if not poisonState.completedPlayers[poisonState.player1] then
		table.insert(playersToAutoSelect, poisonState.player1)
	end

	if not poisonState.completedPlayers[poisonState.player2] then
		table.insert(playersToAutoSelect, poisonState.player2)
	end

	-- 先隐藏所有玩家的选择UI
	PoisonSelectionManager.hideSelectionUI(poisonState.player1)
	PoisonSelectionManager.hideSelectionUI(poisonState.player2)

	-- 执行自动选择
	for _, player in ipairs(playersToAutoSelect) do
		PoisonSelectionManager.autoSelectForPlayer(tableId, player)
	end
end

-- 为玩家自动选择毒药
function PoisonSelectionManager.autoSelectForPlayer(tableId, player)
	print("PoisonSelectionManager: 自动选择毒药 - 玩家: " .. player.Name .. ", 桌子: " .. tableId)

	-- 获取该桌子的状态
	local poisonState = getPoisonState(tableId)
	if not poisonState then
		warn("无法获取桌子 " .. tableId .. " 的毒药状态")
		return
	end

	-- 🔧 修复：改进随机选择算法，确保不同玩家选择不同的奶茶
	local usedIndexes = {}

	-- 收集已经被选择的奶茶索引
	for otherPlayer, selectedIndex in pairs(poisonState.playerSelections) do
		if otherPlayer ~= player and selectedIndex then
			usedIndexes[selectedIndex] = true
		end
	end

	-- 创建可选择的奶茶列表（排除已被选择的）
	local availableIndexes = {}
	for i = 1, 24 do
		if not usedIndexes[i] then
			table.insert(availableIndexes, i)
		end
	end

	-- 如果没有可选择的（理论上不应该发生），则使用全部范围
	if #availableIndexes == 0 then
		for i = 1, 24 do
			table.insert(availableIndexes, i)
		end
		warn("PoisonSelectionManager: 所有奶茶都被选择，使用全部范围")
	end

	-- 添加玩家特定的随机种子偏移，确保不同玩家有不同的随机结果
	-- 🔧 修复：将tableId转换为数字进行计算
	local tableIdNumber = tonumber(tableId) or 0
	local playerSeed = player.UserId + tick() * 1000 + tableIdNumber
	math.randomseed(playerSeed)

	-- 从可选择的列表中随机选择一个
	local randomChoice = math.random(1, #availableIndexes)
	local randomDrinkIndex = availableIndexes[randomChoice]

	-- 记录玩家选择
	poisonState.playerSelections[player] = randomDrinkIndex

	-- 直接执行"No"选择的流程（不购买道具，直接注入毒药）
	PoisonSelectionManager.startPoisonInjectionEffect(player, randomDrinkIndex, tableId)

	print("PoisonSelectionManager: 已为玩家 " .. player.Name .. " 自动选择奶茶 " .. randomDrinkIndex .. " (可选: " .. #availableIndexes .. "个)")
end

-- 毒药阶段倒计时更新
function PoisonSelectionManager.onPoisonPhaseUpdate(tableId, remainingTime)
	-- 可以在这里添加实时更新逻辑
	-- 目前由CountdownManager自动发送给客户端
end

-- 毒药阶段进入警告阶段
function PoisonSelectionManager.onPoisonPhaseWarning(tableId, remainingTime)
	print("PoisonSelectionManager: 毒药阶段进入警告阶段 - 桌子: " .. tableId .. ", 剩余: " .. string.format("%.1f", remainingTime) .. "秒")
	-- 警告阶段的处理（如字体变红）由客户端CountdownClient处理
end

-- 停止毒药阶段倒计时
function PoisonSelectionManager.stopPoisonPhaseCountdown(tableId)
	if CountdownManager and CountdownManager.stopCountdown then
		CountdownManager.stopCountdown(tableId)
		print("PoisonSelectionManager: 毒药阶段倒计时已停止 - 桌子: " .. tableId)
	end
end

-- 检查是否应该提前结束倒计时
function PoisonSelectionManager.checkEarlyFinish(tableId)
	local poisonState = getPoisonState(tableId)
	if not poisonState then
		return false
	end

	-- 检查是否双方都完成了选择
	local completedCount = 0
	if poisonState.completedPlayers[poisonState.player1] then
		completedCount = completedCount + 1
	end
	if poisonState.completedPlayers[poisonState.player2] then
		completedCount = completedCount + 1
	end

	if completedCount >= 2 then
		-- 双方都完成，停止倒计时并进入下一阶段
		PoisonSelectionManager.stopPoisonPhaseCountdown(tableId)
		return true
	end

	return false
end
-- ========== V1.4 倒计时功能结束 ==========

-- 开始毒药选择阶段
function PoisonSelectionManager.startPoisonPhase(player1, player2)
	if not ensureInitialized() then
		warn("PoisonSelectionManager.startPoisonPhase: 初始化失败")
		return false
	end

	-- 检测桌子ID (两个玩家应该在同一张桌子)
	local tableId = getTableIdFromPlayer(player1) or getTableIdFromPlayer(player2)
	if not tableId then
		warn("无法检测玩家所在的桌子ID")
		return false
	end

	-- 获取该桌子的状态
	local poisonState = getPoisonState(tableId)
	if not poisonState then
		warn("无法创建桌子 " .. tableId .. " 的毒药状态")
		return false
	end

	-- 重置状态
	poisonState.activePhase = true
	poisonState.player1 = player1
	poisonState.player2 = player2
	poisonState.playerSelections = {}
	poisonState.playerConfirmations = {}
	poisonState.completedPlayers = {}
	poisonState.playerPoisonList = {}
	poisonState.extraPoisonTargets = {}
	poisonState.startTime = tick()

	-- 重置道具使用状态（针对该桌子）
	if _G.PropEffectHandler and _G.PropEffectHandler.resetTableState then
		_G.PropEffectHandler.resetTableState(tableId)
	end

	-- V1.4: 启动毒药阶段倒计时
	PoisonSelectionManager.startPoisonPhaseCountdown(tableId, player1, player2)

	-- 为两个玩家显示选择UI(只发给这两个玩家)
	PoisonSelectionManager.showSelectionUI(player1)
	PoisonSelectionManager.showSelectionUI(player2)

	return true
end

-- 显示选择UI
function PoisonSelectionManager.showSelectionUI(player)
	if not player then return end

	-- 通过RemoteEvent通知客户端显示UI
	poisonSelectionEvent:FireClient(player, "showSelectionUI")
end

-- 隐藏选择UI
function PoisonSelectionManager.hideSelectionUI(player)
	if not player then return end

	-- 通过RemoteEvent通知客户端隐藏UI
	poisonSelectionEvent:FireClient(player, "hideSelectionUI")
end

-- 玩家选择奶茶
function PoisonSelectionManager.onPlayerSelectDrink(player, drinkIndex)
	if not ensureInitialized() then
		warn("PoisonSelectionManager.onPlayerSelectDrink: 初始化失败")
		return
	end

	-- 获取玩家所在的桌子ID
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		warn("玩家 " .. player.Name .. " 不在任何桌子上")
		return
	end

	local poisonState = getPoisonState(tableId)
	if not poisonState or not poisonState.activePhase then
		warn("桌子 " .. tableId .. " 毒药选择阶段未激活")
		return
	end

	if poisonState.completedPlayers[player] then
		warn("玩家 " .. player.Name .. " 已完成选择")
		return
	end


	-- 记录玩家当前选择（覆盖之前的选择）
	poisonState.playerSelections[player] = drinkIndex

	-- 显示毒药预览（只显示当前选择的奶茶为红色）
	poisonIndicatorEvent:FireClient(player, "showPoisonIndicators", {
		poisonedDrinks = {drinkIndex}
	})

	-- 显示确认弹框（仅用于道具购买选择）
	PoisonSelectionManager.showConfirmationDialog(player, drinkIndex)
end

-- 显示确认弹框
function PoisonSelectionManager.showConfirmationDialog(player, drinkIndex)
	if not player then return end

	-- 通过RemoteEvent通知客户端显示确认弹框
	poisonSelectionEvent:FireClient(player, "showConfirmation", {drinkIndex = drinkIndex})
end

-- 玩家确认选择
function PoisonSelectionManager.onPlayerConfirm(player, confirmed)
	if not ensureInitialized() then
		warn("PoisonSelectionManager.onPlayerConfirm: 初始化失败")
		return
	end

	-- 获取玩家所在的桌子ID
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		warn("玩家 " .. player.Name .. " 不在任何桌子上")
		return
	end

	local poisonState = getPoisonState(tableId)
	if not poisonState or not poisonState.activePhase then
		return
	end

	-- 检查玩家是否已经完成选择，防止重复处理
	if poisonState.completedPlayers[player] then
		return
	end

	local drinkIndex = poisonState.playerSelections[player]
	if not drinkIndex then
		warn("玩家 " .. player.Name .. " 没有选择奶茶")
		return
	end


	if confirmed then
		-- 显示道具购买选项
		PoisonSelectionManager.offerDeveloperProduct(player, drinkIndex, tableId)
	else
		-- 开始V1.4毒药注入视觉效果
		PoisonSelectionManager.startPoisonInjectionEffect(player, drinkIndex, tableId)
	end
end

-- V1.4: 开始毒药注入视觉效果
function PoisonSelectionManager.startPoisonInjectionEffect(player, drinkIndex, tableId)

	-- 获取该桌子的状态
	local poisonState = getPoisonState(tableId)
	if not poisonState then
		warn("无法获取桌子 " .. (tableId or "未知") .. " 的毒药状态")
		return
	end

	-- 立即标记玩家完成选择
	poisonState.playerConfirmations[player] = false
	poisonState.completedPlayers[player] = true

	-- 隐藏确认弹框
	poisonSelectionEvent:FireClient(player, "hideConfirmation")

	-- 立即检查并显示等待状态
	PoisonSelectionManager.checkAndShowWaitingState(player, tableId)

	-- 通知客户端开始视觉效果（只对注入毒药的玩家显示）
	poisonSelectionEvent:FireClient(player, "startPoisonEffect", {
		drinkIndex = drinkIndex
	})

	-- 等待2秒让效果播放完成
	spawn(function()
		wait(2)

		-- 效果播放完成，继续正常的毒药注入流程
		PoisonSelectionManager.completePoisonInjection(player, drinkIndex, tableId)
	end)
end

-- V1.4: 完成毒药注入流程（在视觉效果播放后）
function PoisonSelectionManager.completePoisonInjection(player, drinkIndex, tableId)

	-- 现在才真正注入毒药到选中的奶茶（使用正确的tableId）
	if not DrinkManager then
		DrinkManager = require(script.Parent.DrinkManager)
	end

	-- 使用tableId注入毒药
	if tableId then
		DrinkManager.poisonDrinkForTable(tableId, drinkIndex, player)
	else
		-- 备用方案：使用默认接口
		warn("无法检测玩家 " .. player.Name .. " 的桌子ID，使用默认方法")
		DrinkManager.poisonDrink(drinkIndex, player)
	end

	-- 获取该桌子的状态
	local poisonState = getPoisonState(tableId)
	if not poisonState then
		warn("无法获取桌子 " .. (tableId or "未知") .. " 的毒药状态")
		return
	end

	-- 维护玩家的毒药列表
	if not poisonState.playerPoisonList then
		poisonState.playerPoisonList = {}
	end
	if not poisonState.playerPoisonList[player] then
		poisonState.playerPoisonList[player] = {}
	end
	table.insert(poisonState.playerPoisonList[player], drinkIndex)

	-- 更新毒药标识显示（现在显示真正注入的毒药）
	poisonIndicatorEvent:FireClient(player, "showPoisonIndicators", {
		poisonedDrinks = poisonState.playerPoisonList[player]
	})

	-- 检查是否所有玩家都完成选择
	PoisonSelectionManager.checkAllPlayersCompleted(tableId)
end

-- 提供开发者道具购买
function PoisonSelectionManager.offerDeveloperProduct(player, drinkIndex, tableId)

	-- 提示购买道具
	MarketplaceService:PromptProductPurchase(player, DEVELOPER_PRODUCT_ID)

	-- 🔧 修复：移除不可靠的PromptProductPurchaseFinished监听
	-- 购买处理现在由UnifiedPurchaseManager通过ProcessReceipt统一处理
	-- 临时存储购买上下文，等待UnifiedPurchaseManager回调
	if not _G.PoisonSelectionPurchaseContext then
		_G.PoisonSelectionPurchaseContext = {}
	end
	_G.PoisonSelectionPurchaseContext[player] = {
		drinkIndex = drinkIndex,
		tableId = tableId,
		timestamp = tick()
	}

	-- 🔧 修复：改进超时处理，不再直接清理上下文
	-- 而是标记为过期，让回调函数决定如何处理
	task.spawn(function()
		task.wait(15)
		if _G.PoisonSelectionPurchaseContext and _G.PoisonSelectionPurchaseContext[player] then
			local context = _G.PoisonSelectionPurchaseContext[player]
			if context.timestamp and (tick() - context.timestamp > 15) then
				-- 🔧 修复：修正时间检查逻辑，等待15秒后检查是否已过期15秒
				-- 避免竞态条件：如果已经等待了15秒，那么检查是否真的超过15秒
				context.expired = true
				print("⏰ 购买上下文过期标记: 玩家 " .. player.Name)
				-- 注意：不再自动调用continueNormalFlow，让ProcessReceipt统一处理
			end
		end
	end)
end

-- V1.7: 处理额外毒药购买
function PoisonSelectionManager.handleExtraPoisonPurchase(player, originalDrinkIndex, tableId)

	-- 隐藏确认弹框
	poisonSelectionEvent:FireClient(player, "hideConfirmation")

	-- 获取所有可选的奶茶（1-24，排除玩家已选择的）
	local availableDrinks = {}
	for i = 1, 24 do
		if i ~= originalDrinkIndex then
			table.insert(availableDrinks, i)
		end
	end

	-- 随机选择一个额外的奶茶进行毒药注入
	if #availableDrinks > 0 then
		local randomIndex = math.random(1, #availableDrinks)
		local randomDrinkIndex = availableDrinks[randomIndex]


		-- 获取该桌子的状态
		local poisonState = getPoisonState(tableId)
		if poisonState then
			-- 记录购买状态
			poisonState.extraPoisonTargets[player] = {
				originalTarget = originalDrinkIndex,
				randomTarget = randomDrinkIndex
			}
		end

		-- 注入两个毒药：原始选择 + 随机选择
		PoisonSelectionManager.injectBothPoisons(player, originalDrinkIndex, randomDrinkIndex, tableId)
	else
		warn("没有可用的额外毒药目标，仅注入原始选择")
		-- 备用：仅注入原始选择
		PoisonSelectionManager.injectSinglePoison(player, originalDrinkIndex, tableId)
	end
end

-- V1.7: 注入两个毒药（原始选择 + 随机选择）
function PoisonSelectionManager.injectBothPoisons(player, originalDrinkIndex, randomDrinkIndex, tableId)

	-- 初始化DrinkManager
	if not DrinkManager then
		DrinkManager = require(script.Parent.DrinkManager)
	end

	-- 注入原始选择的毒药
	if tableId then
		DrinkManager.poisonDrinkForTable(tableId, originalDrinkIndex, player)
	else
		warn("无法检测玩家 " .. player.Name .. " 的桌子ID，使用默认方法（原始选择）")
		DrinkManager.poisonDrink(originalDrinkIndex, player)
	end

	-- 注入随机选择的毒药
	if tableId then
		DrinkManager.poisonDrinkForTable(tableId, randomDrinkIndex, player)
	else
		warn("无法检测玩家 " .. player.Name .. " 的桌子ID，使用默认方法（随机选择）")
		DrinkManager.poisonDrink(randomDrinkIndex, player)
	end

	-- 获取该桌子的状态
	local poisonState = getPoisonState(tableId)
	if not poisonState then
		warn("无法获取桌子 " .. (tableId or "未知") .. " 的毒药状态")
		return
	end

	-- 维护玩家的毒药列表
	if not poisonState.playerPoisonList then
		poisonState.playerPoisonList = {}
	end
	if not poisonState.playerPoisonList[player] then
		poisonState.playerPoisonList[player] = {}
	end
	table.insert(poisonState.playerPoisonList[player], originalDrinkIndex)
	table.insert(poisonState.playerPoisonList[player], randomDrinkIndex)

	-- 显示毒药注入视觉效果（只有购买者能看到）
	PoisonSelectionManager.showDualPoisonEffects(player, originalDrinkIndex, randomDrinkIndex, poisonState)

	-- 完成选择流程
	PoisonSelectionManager.completePurchaseSelection(player, tableId)
end

-- V1.7: 注入单个毒药（备用方案）
function PoisonSelectionManager.injectSinglePoison(player, drinkIndex, tableId)

	-- 初始化DrinkManager
	if not DrinkManager then
		DrinkManager = require(script.Parent.DrinkManager)
	end

	-- 注入毒药
	if tableId then
		DrinkManager.poisonDrinkForTable(tableId, drinkIndex, player)
	else
		warn("无法检测玩家 " .. player.Name .. " 的桌子ID，使用默认方法")
		DrinkManager.poisonDrink(drinkIndex, player)
	end

	-- 获取该桌子的状态
	local poisonState = getPoisonState(tableId)
	if not poisonState then
		warn("无法获取桌子 " .. (tableId or "未知") .. " 的毒药状态")
		return
	end

	-- 维护玩家的毒药列表
	if not poisonState.playerPoisonList then
		poisonState.playerPoisonList = {}
	end
	if not poisonState.playerPoisonList[player] then
		poisonState.playerPoisonList[player] = {}
	end
	table.insert(poisonState.playerPoisonList[player], drinkIndex)

	-- 显示毒药注入视觉效果
	PoisonSelectionManager.showSinglePoisonEffect(player, drinkIndex, poisonState)

	-- 完成选择流程
	PoisonSelectionManager.completePurchaseSelection(player, tableId)
end

-- V1.7: 显示双毒药视觉效果（只有购买者能看到）
function PoisonSelectionManager.showDualPoisonEffects(player, originalDrinkIndex, randomDrinkIndex, poisonState)
	-- 同时显示两个奶茶的毒药注入效果
	poisonSelectionEvent:FireClient(player, "startPoisonEffect", {
		drinkIndex = originalDrinkIndex
	})

	poisonSelectionEvent:FireClient(player, "startPoisonEffect", {
		drinkIndex = randomDrinkIndex
	})

	-- 更新毒药标识显示（现在显示真正注入的两个毒药，都是红色，只有购买者能看到）
	poisonIndicatorEvent:FireClient(player, "showPoisonIndicators", {
		poisonedDrinks = {originalDrinkIndex, randomDrinkIndex}
	})
end

-- V1.7: 显示单毒药视觉效果
function PoisonSelectionManager.showSinglePoisonEffect(player, drinkIndex, poisonState)
	poisonSelectionEvent:FireClient(player, "startPoisonEffect", {
		drinkIndex = drinkIndex
	})

	-- 更新毒药标识显示
	poisonIndicatorEvent:FireClient(player, "showPoisonIndicators", {
		poisonedDrinks = {drinkIndex}
	})
end

-- V1.4: 统一的等待对手检查函数
function PoisonSelectionManager.checkAndShowWaitingState(player, tableId)
	local poisonState = getPoisonState(tableId)
	if not poisonState then
		return
	end

	-- 检查对手是否完成选择
	local otherPlayer = (player == poisonState.player1) and poisonState.player2 or poisonState.player1
	if otherPlayer and not poisonState.completedPlayers[otherPlayer] then
		-- 显示"Waiting for opponent"
		poisonSelectionEvent:FireClient(player, "showWaitingForOpponent")
	end
end

-- V1.7: 完成购买选择流程
function PoisonSelectionManager.completePurchaseSelection(player, tableId)
	-- 获取该桌子的状态
	local poisonState = getPoisonState(tableId)
	if not poisonState then
		warn("无法获取桌子 " .. (tableId or "未知") .. " 的毒药状态")
		return
	end

	-- 记录最终选择
	poisonState.playerConfirmations[player] = true
	poisonState.completedPlayers[player] = true

	-- 立即检查并显示等待状态
	PoisonSelectionManager.checkAndShowWaitingState(player, tableId)

	-- 等待2秒让视觉效果播放完成
	spawn(function()
		wait(2)

		-- 隐藏所有相关UI
		poisonSelectionEvent:FireClient(player, "hideAll")

		-- 检查是否所有玩家都完成选择
		PoisonSelectionManager.checkAllPlayersCompleted(tableId)
	end)
end

-- 继续正常流程
function PoisonSelectionManager.continueNormalFlow(player, drinkIndex, tableId)

	-- 现在才真正注入毒药到选中的奶茶（购买失败也要注入毒药，使用正确的tableId）
	if not DrinkManager then
		DrinkManager = require(script.Parent.DrinkManager)
	end

	-- 使用tableId注入毒药
	if tableId then
		DrinkManager.poisonDrinkForTable(tableId, drinkIndex, player)
	else
		-- 备用方案：使用默认接口
		warn("无法检测玩家 " .. player.Name .. " 的桌子ID，使用默认方法")
		DrinkManager.poisonDrink(drinkIndex, player)
	end

	-- 获取该桌子的状态
	local poisonState = getPoisonState(tableId)
	if not poisonState then
		warn("无法获取桌子 " .. (tableId or "未知") .. " 的毒药状态")
		return
	end

	-- 维护玩家的毒药列表
	if not poisonState.playerPoisonList then
		poisonState.playerPoisonList = {}
	end
	if not poisonState.playerPoisonList[player] then
		poisonState.playerPoisonList[player] = {}
	end
	table.insert(poisonState.playerPoisonList[player], drinkIndex)

	-- 更新毒药标识显示（现在显示真正注入的毒药）
	poisonIndicatorEvent:FireClient(player, "showPoisonIndicators", {
		poisonedDrinks = poisonState.playerPoisonList[player]
	})

	-- 记录最终选择
	poisonState.playerConfirmations[player] = true
	poisonState.completedPlayers[player] = true

	-- 立即检查并显示等待状态
	PoisonSelectionManager.checkAndShowWaitingState(player, tableId)

	-- 隐藏确认弹框和选择UI
	poisonSelectionEvent:FireClient(player, "hideAll")

	-- 检查是否所有玩家都完成选择
	PoisonSelectionManager.checkAllPlayersCompleted(tableId)
end

-- 检查所有玩家是否完成选择(关键修复!)
function PoisonSelectionManager.checkAllPlayersCompleted(tableId)
	if not tableId then
		warn("checkAllPlayersCompleted: tableId为空")
		return
	end

	local poisonState = getPoisonState(tableId)
	if not poisonState then
		return
	end

	local completedCount = 0

	-- 只计算该桌子的两个玩家
	if poisonState.completedPlayers[poisonState.player1] then
		completedCount = completedCount + 1
	end
	if poisonState.completedPlayers[poisonState.player2] then
		completedCount = completedCount + 1
	end

	-- V1.4: 检查是否提前结束倒计时
	if completedCount >= 2 then
		-- 双方都完成，停止倒计时
		PoisonSelectionManager.stopPoisonPhaseCountdown(tableId)
		-- 立即进入下一阶段
		PoisonSelectionManager.finishPoisonPhase(tableId)
	end
end

-- 完成毒药选择阶段
function PoisonSelectionManager.finishPoisonPhase(tableId)
	if not tableId then
		warn("finishPoisonPhase: tableId为空")
		return
	end

	local poisonState = getPoisonState(tableId)
	if not poisonState then
		return
	end


	poisonState.activePhase = false

	-- 显示道具界面给双方玩家（只给该桌子玩家）
	PoisonSelectionManager.showPropsUIForPlayers(poisonState.player1, poisonState.player2)

	-- 直接调用DrinkSelectionManager开始轮流选择
	if not DrinkSelectionManager then
		DrinkSelectionManager = require(script.Parent.DrinkSelectionManager)
	end
	DrinkSelectionManager.startSelectionPhase(poisonState.player1, poisonState.player2)
end

-- 为玩家显示道具UI(只对该桌子的玩家)
function PoisonSelectionManager.showPropsUIForPlayers(player1, player2)
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local propUpdateEvent = remoteEventsFolder:FindFirstChild("PropUpdate")

	if propUpdateEvent then
		if player1 and player1.Parent then
			propUpdateEvent:FireClient(player1, "showPropsUI")
		end
		if player2 and player2.Parent then
			propUpdateEvent:FireClient(player2, "showPropsUI")
		end
	else
		warn("未找到PropUpdate RemoteEvent")
	end
end

-- 设置RemoteEvent处理
function PoisonSelectionManager.setupRemoteEvents()
	poisonSelectionEvent.OnServerEvent:Connect(function(player, action, data)
		if action == "selectDrink" then
			PoisonSelectionManager.onPlayerSelectDrink(player, data.drinkIndex)
		elseif action == "confirm" then
			PoisonSelectionManager.onPlayerConfirm(player, data.confirmed)
		end
	end)
end

-- 玩家离开时清理
local function onPlayerRemoving(player)
	-- 🔧 关键修复：清理玩家的购买上下文，防止内存泄漏
	PoisonSelectionManager.cleanupPlayerPurchaseContext(player)
end

-- 初始化
function PoisonSelectionManager.initialize()
	PoisonSelectionManager.setupRemoteEvents()

	-- 🔧 关键修复：监听玩家离开事件
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

-- 检查毒药阶段是否激活(兼容旧代码)
function PoisonSelectionManager.isPoisonPhaseActive(tableId)
	if not tableId then
		-- 兼容旧代码:如果没有tableId,检查是否有任何桌子在毒药阶段
		for _, state in pairs(poisonStates) do
			if state.activePhase then
				return true
			end
		end
		return false
	end

	local poisonState = getPoisonState(tableId)
	return poisonState and poisonState.activePhase or false
end

-- 因玩家离开而结束毒药阶段
function PoisonSelectionManager.endPoisonPhaseByPlayerLeave(winner, leavingPlayer, tableId)
	-- 如果没有传递tableId,尝试从玩家检测
	if not tableId then
		tableId = getTableIdFromPlayer(leavingPlayer) or getTableIdFromPlayer(winner)
	end

	if not tableId then
		warn("无法检测桌子ID,无法结束毒药阶段")
		return
	end

	local poisonState = getPoisonState(tableId)
	if not poisonState or not poisonState.activePhase then
		return
	end

	-- V1.4: 停止倒计时
	PoisonSelectionManager.stopPoisonPhaseCountdown(tableId)

	-- 先缓存当前玩家引用
	local player1 = poisonState.player1
	local player2 = poisonState.player2

	-- 🔧 修复：清理离开玩家的购买上下文
	if leavingPlayer then
		PoisonSelectionManager.cleanupPlayerPurchaseContext(leavingPlayer)
	end

	-- 隐藏所有UI(只对该桌子玩家)
	local playersToHide = {}
	if player1 and player1.Parent then table.insert(playersToHide, player1) end
	if player2 and player2.Parent then table.insert(playersToHide, player2) end
	if winner and winner.Parent and winner ~= player1 and winner ~= player2 then
		table.insert(playersToHide, winner)
	end

	for _, player in ipairs(playersToHide) do
		-- 隐藏选择UI
		PoisonSelectionManager.hideSelectionUI(player)
		-- 发送hideAll指令
		if poisonSelectionEvent then
			poisonSelectionEvent:FireClient(player, "hideAll")
		end
	end

	-- 清理该桌子的毒药阶段状态
	poisonState.activePhase = false
	poisonState.player1 = nil
	poisonState.player2 = nil
	poisonState.playerSelections = {}
	poisonState.playerConfirmations = {}
	poisonState.completedPlayers = {}
end

-- 🔧 供UnifiedPurchaseManager调用的购买成功处理接口
function PoisonSelectionManager.onDeveloperProductPurchaseSuccess(player, productId)
	-- 🔧 修复：移除冗余的商品ID验证
	-- UnifiedPurchaseManager已经在调用前验证了商品ID，此处再次验证是冗余的
	-- 这个冗余验证可能导致正确的商品返回false，进而导致NotProcessedYet

	print("☠️ PoisonSelectionManager: 处理额外毒药购买成功 - " .. player.Name .. " (ProductId: " .. productId .. ")")

	-- 🔧 修复：优雅降级处理，即使没有购买上下文也能安全处理
	local context = nil
	if _G.PoisonSelectionPurchaseContext and _G.PoisonSelectionPurchaseContext[player] then
		context = _G.PoisonSelectionPurchaseContext[player]
		-- 立即清理上下文，防止重复处理
		_G.PoisonSelectionPurchaseContext[player] = nil

		if context.expired then
			print("⏰ 购买上下文已过期，但仍尝试使用其数据")
		else
			print("✅ 找到购买上下文，使用正常流程")
		end
	else
		warn("⚠️ PoisonSelectionManager: 未找到购买上下文，使用降级处理")
	end

	-- 方案A：有上下文时使用正常流程（即使过期也尝试使用）
	if context and context.drinkIndex and context.tableId then
		print("🎯 使用上下文信息: drinkIndex=" .. context.drinkIndex .. ", tableId=" .. context.tableId)

		-- 验证上下文信息的有效性
		local tableId = context.tableId
		local poisonState = getPoisonState(tableId)

		-- 即使上下文过期，如果玩家仍在毒药选择阶段且数据有效，就执行正常流程
		if poisonState and poisonState.activePhase and (poisonState.player1 == player or poisonState.player2 == player) then
			PoisonSelectionManager.handleExtraPoisonPurchase(player, context.drinkIndex, tableId)
			return true
		else
			print("⚠️ 上下文数据无效或玩家不在毒药选择阶段，继续降级处理")
		end
	end

	-- 方案B：无上下文或上下文无效时的降级处理
	print("🆘 执行降级处理：检查玩家是否在毒药选择阶段")

	-- 尝试检测玩家当前所在的桌子和状态
	local tableId = getTableIdFromPlayer(player)
	if tableId then
		local poisonState = getPoisonState(tableId)
		if poisonState and poisonState.activePhase then
			-- 玩家确实在毒药选择阶段
			local currentSelection = poisonState.playerSelections[player]
			if currentSelection then
				print("🔄 降级处理成功: 使用当前选择 drinkIndex=" .. currentSelection .. ", tableId=" .. tableId)
				PoisonSelectionManager.handleExtraPoisonPurchase(player, currentSelection, tableId)
				return true
			end
		end
	end

	-- 方案C：完全无法确定状态时的最终降级
	print("💰 最终降级处理：发放等价补偿")

	-- 🔧 关键修复：补偿必须成功，否则返回NotProcessedYet让Roblox重试
	local compensationSuccess = false

	-- 发放等价的游戏内货币补偿
	-- 额外毒药商品的价值相当于能获得双倍毒药效果，按中等价值设定补偿
	if _G.CoinManager and _G.CoinManager.addCoins then
		local compensationCoins = 50 -- 保守的补偿金币数量
		local success = _G.CoinManager.addCoins(player, compensationCoins, "额外毒药购买补偿")
		if success then
			print("💎 补偿成功: 玩家 " .. player.Name .. " 获得 " .. compensationCoins .. " 金币补偿")
			compensationSuccess = true

			-- 通知玩家
			local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if remoteEventsFolder then
				local poisonSelectionEvent = remoteEventsFolder:FindFirstChild("PoisonSelection")
				if poisonSelectionEvent and player.Parent then
					-- 使用pcall防止RemoteEvent调用失败
					local eventSuccess, eventError = pcall(function()
						poisonSelectionEvent:FireClient(player, "purchaseCompensation", {
							reason = "购买上下文丢失，已发放等价补偿",
							compensation = compensationCoins .. " 金币"
						})
					end)
					if not eventSuccess then
						warn("RemoteEvent通知失败: " .. tostring(eventError))
					end
				end
			end
		else
			warn("❌ 金币补偿发放失败")
		end
	else
		warn("❌ CoinManager不可用，无法发放金币补偿")
	end

	-- 如果金币补偿失败，尝试道具补偿
	if not compensationSuccess then
		print("🎁 尝试备用补偿：发放道具")
		if _G.PropManager and _G.PropManager.addProp then
			-- 发放一个验证道具作为补偿
			local success = _G.PropManager.addProp(player, 1, 1, "额外毒药购买道具补偿")
			if success then
				print("🔧 备用补偿成功: 玩家 " .. player.Name .. " 获得1个验证道具")
				compensationSuccess = true
			else
				warn("❌ 道具补偿也失败")
			end
		else
			warn("❌ PropManager不可用，无法发放道具补偿")
		end
	end

	-- 🔧 关键修复：如果所有补偿都失败，必须返回false让Roblox重试
	if not compensationSuccess then
		warn("🚨 所有补偿方案都失败，返回false要求Roblox重试")
		-- 记录到日志供后续人工处理
		print("📋 需要重试的购买记录: 玩家=" .. player.Name .. ", 商品ID=" .. productId .. ", 时间=" .. os.date())
		return false  -- 让Roblox重试，不要标记为PurchaseGranted
	end

	-- 只有补偿成功时才返回true
	return true
end

-- 🔧 新增：清理玩家购买上下文的函数（供玩家离开时调用）
function PoisonSelectionManager.cleanupPlayerPurchaseContext(player)
	if _G.PoisonSelectionPurchaseContext and _G.PoisonSelectionPurchaseContext[player] then
		_G.PoisonSelectionPurchaseContext[player] = nil
	end
end

-- 导出到全局供其他脚本使用
_G.PoisonSelectionManager = PoisonSelectionManager

return PoisonSelectionManager
