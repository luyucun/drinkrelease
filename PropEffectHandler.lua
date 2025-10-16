-- 脚本名称: PropEffectHandler
-- 脚本作用: 处理道具使用效果和游戏逻辑集成
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- V2.0: 完整的多桌状态隔离重构

local PropEffectHandler = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引入其他管理器
local PropConfig = require(script.Parent.PropConfig)

-- 等待其他管理器加载
local DrinkSelectionManager = nil
local DrinkManager = nil

-- 延迟加载其他管理器
spawn(function()
	wait(2)
	DrinkSelectionManager = require(script.Parent.DrinkSelectionManager)
	DrinkManager = require(script.Parent.DrinkManager)
end)

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local propUseEvent = remoteEventsFolder:WaitForChild("PropUse")
local drinkSelectionEvent = remoteEventsFolder:WaitForChild("DrinkSelection")

-- ========== 多桌状态隔离核心重构 V2.0 ==========
-- 按桌子隔离的道具使用状态
local propUseStates = {}  -- {[tableId] = PropUseStateData}

-- 单个桌子的道具使用状态
local function createNewPropUseState()
	return {
		awaitingSelection = {},  -- {[player] = {propId, effectType}}
		usedPoisonClean = {},    -- {[player] = true}
	}
end

-- 获取或创建桌子的道具状态
local function getPropUseState(tableId)
	if not tableId then
		warn("getPropUseState: tableId为空")
		return nil
	end

	if not propUseStates[tableId] then
		print("🎲 创建桌子 " .. tableId .. " 的道具使用状态")
		propUseStates[tableId] = createNewPropUseState()
	end

	return propUseStates[tableId]
end

-- 通过玩家获取桌子ID
local function getTableIdFromPlayer(player)
	if not player then return nil end

	if _G.TableManager and _G.TableManager.detectPlayerTable then
		return _G.TableManager.detectPlayerTable(player)
	end

	return nil
end

-- 清理桌子状态(对局结束时调用)
function PropEffectHandler.resetTableState(tableId)
	if not tableId then
		warn("PropEffectHandler.resetTableState: tableId为空")
		return
	end

	print("🧹 清理桌子 " .. tableId .. " 的道具使用状态")

	-- 清理该桌子的道具使用记录
	if propUseStates[tableId] then
		propUseStates[tableId] = nil
	end
end
-- ========== 多桌状态隔离核心重构结束 ==========

-- 检查是否可以使用道具
function PropEffectHandler.canUseProp(player, propId)
	-- 获取玩家所在的桌子ID
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		return false, "不在桌子上"
	end

	-- 检查是否在选择奶茶阶段(传递tableId)
	if not DrinkSelectionManager or not DrinkSelectionManager.isSelectionPhaseActive then
		return false, "DrinkSelectionManager未加载"
	end

	-- 需要确保DrinkSelectionManager.isSelectionPhaseActive支持tableId参数
	-- 这将在DrinkSelectionManager中实现

	-- 检查是否是玩家的回合(传递tableId)
	local currentPlayer = DrinkSelectionManager.getCurrentPlayer and DrinkSelectionManager.getCurrentPlayer(tableId)
	if not currentPlayer or currentPlayer ~= player then
		return false, "不是该玩家的回合"
	end

	-- 检查道具数量
	if not _G.PropManager or not _G.PropManager.getPropQuantity then
		return false, "道具管理器未加载"
	end

	local quantity = _G.PropManager.getPropQuantity(player, propId)
	if quantity < 1 then
		return false, "道具数量不足"
	end

	return true, "可以使用"
end

-- 发送消息给对方玩家（不包括使用者）
function PropEffectHandler.broadcastMessageToOpponent(message, user, tableId)
	if not tableId then
		tableId = getTableIdFromPlayer(user)
	end

	if not tableId then
		warn("无法检测桌子ID,无法发送消息")
		return
	end

	-- 获取对方玩家(使用带tableId参数的版本)
	local opponent = nil
	if _G.DrinkSelectionManager and _G.DrinkSelectionManager.getOpponent then
		opponent = _G.DrinkSelectionManager.getOpponent(user, tableId)
	end

	if opponent and opponent.Parent then
		-- 发送飘字提示到对方客户端
		if drinkSelectionEvent then
			drinkSelectionEvent:FireClient(opponent, "showFloatingMessage", {
				message = message,
				color = Color3.new(1, 1, 0), -- 黄色
				duration = 3
			})
		end
	else
		warn("无法找到对方玩家，无法发送消息")
	end
end

-- 毒药验证道具效果
function PropEffectHandler.handlePoisonDetect(player)
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		warn("玩家 " .. player.Name .. " 不在任何桌子上")
		return false
	end

	local propUseState = getPropUseState(tableId)
	if not propUseState then
		return false
	end

	-- 设置等待选择状态
	propUseState.awaitingSelection[player] = {
		propId = 1,
		effectType = PropConfig.EFFECT_TYPES.POISON_DETECT
	}

	-- 修改UI提示文本
	if drinkSelectionEvent then
		drinkSelectionEvent:FireClient(player, "updateSelectTips", {
			text = "Please select the drink to verify"
		})
	else
		warn("drinkSelectionEvent 未找到，无法更新UI文本")
	end

	return true
end

-- 跳过选择道具效果
function PropEffectHandler.handleTurnSkip(player)
	-- 获取玩家所在的桌子ID
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		warn("玩家 " .. player.Name .. " 不在任何桌子上")
		return false
	end

	-- 广播使用消息(只给对方玩家)
	PropEffectHandler.broadcastMessageToOpponent(player.Name .. " used Turn Skip", player, tableId)

	-- 获取DrinkSelectionManager
	local DrinkSelectionManager = _G.DrinkSelectionManager
	if not DrinkSelectionManager then
		warn("无法获取DrinkSelectionManager")
		return false
	end

	-- 隐藏SelectTips UI(只对该桌子玩家)
	local opponent = DrinkSelectionManager.getOpponent and DrinkSelectionManager.getOpponent(player, tableId)
	if drinkSelectionEvent then
		drinkSelectionEvent:FireClient(player, "hideSelectTips")
		if opponent and opponent.Parent then
			drinkSelectionEvent:FireClient(opponent, "hideSelectTips")
		end
	end

	-- 聚焦镜头到使用道具的玩家(只对该桌子玩家)
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local cameraControlEvent = remoteEventsFolder:FindFirstChild("CameraControl")

	if cameraControlEvent then
		-- 只通知该桌子的玩家
		cameraControlEvent:FireClient(player, "focusOnDrinking", {targetPlayer = player.Name})
		if opponent and opponent.Parent then
			cameraControlEvent:FireClient(opponent, "focusOnDrinking", {targetPlayer = player.Name})
		end
	else
		warn("CameraControl事件不存在")
	end

	-- 等待镜头动画完成
	wait(1)

	-- 显示蓝色Skip结果(只对该桌子玩家)
	if drinkSelectionEvent then
		drinkSelectionEvent:FireClient(player, "showResult", {
			targetPlayer = player.Name,
			result = "Skip",
			color = Color3.new(0, 0.5, 1), -- 蓝色
			drinkIndex = 0 -- 0表示没有选择奶茶
		})
		if opponent and opponent.Parent then
			drinkSelectionEvent:FireClient(opponent, "showResult", {
				targetPlayer = player.Name,
				result = "Skip",
				color = Color3.new(0, 0.5, 1),
				drinkIndex = 0
			})
		end
	end

	-- 等待结果显示
	wait(1.5)

	-- 切换到下一个玩家(传递tableId)
	if DrinkSelectionManager.switchToNextPlayer then
		DrinkSelectionManager.switchToNextPlayer(tableId)
	else
		warn("DrinkSelectionManager.switchToNextPlayer 函数不存在")
	end

	return true
end

-- 清除对方毒药道具效果
function PropEffectHandler.handlePoisonClean(player)
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		warn("玩家 " .. player.Name .. " 不在任何桌子上")
		return false
	end

	local propUseState = getPropUseState(tableId)
	if not propUseState then
		return false
	end

	-- 获取对方玩家
	local opponent = nil
	if _G.DrinkSelectionManager and _G.DrinkSelectionManager.getOpponent then
		opponent = _G.DrinkSelectionManager.getOpponent(player, tableId)
	end

	if not opponent then
		warn("无法获取对手玩家")
		return false
	end

	-- 立即标记该玩家为已使用（防止重复使用）
	propUseState.usedPoisonClean[player] = true

	-- 获取对方下毒的奶茶列表（使用正确的桌子ID）
	local opponentPoisonedDrinks = {}
	if DrinkManager then
		for drinkIndex = 1, 24 do
			local poisonInfo = DrinkManager.getDrinkPoisonInfoForTable(tableId, drinkIndex)

			if #poisonInfo > 0 then
				for _, poisoner in ipairs(poisonInfo) do
					if poisoner == opponent then
						table.insert(opponentPoisonedDrinks, drinkIndex)
						break
					end
				end
			end
		end
	end

	if #opponentPoisonedDrinks == 0 then
		return false
	end

	-- 广播使用消息给对方玩家
	PropEffectHandler.broadcastMessageToOpponent(player.Name .. " used Poison Cleaner", player, tableId)

	-- 清除对方的所有毒药并显示UI效果
	for _, drinkIndex in ipairs(opponentPoisonedDrinks) do
		-- 先显示红色Num（只有使用者能看到）
		if drinkSelectionEvent then
			drinkSelectionEvent:FireClient(player, "showPoisonCleanEffect", {
				drinkIndex = drinkIndex,
				phase = "red", -- 红色阶段
				duration = 2,
				tableId = tableId  -- 传递桌子ID给客户端
			})
		end

		-- 2秒后显示绿色并实际清除毒药
		spawn(function()
			wait(2)

			-- 显示绿色Num（只有使用者能看到）
			if drinkSelectionEvent then
				drinkSelectionEvent:FireClient(player, "showPoisonCleanEffect", {
					drinkIndex = drinkIndex,
					phase = "green", -- 绿色阶段
					duration = 1,
					tableId = tableId  -- 传递桌子ID给客户端
				})
			end

			-- 实际清除毒药数据
			if DrinkManager then
				local success = DrinkManager.clearAllPoisonFromDrinkForTable(tableId, drinkIndex)

				if success then
					-- 验证清除结果
					local remainingPoisons = DrinkManager.getDrinkPoisonInfoForTable(tableId, drinkIndex)

					if #remainingPoisons > 0 then
						warn("警告：奶茶 " .. drinkIndex .. " 清除后仍有毒药！")
					end
				else
					warn("清除奶茶 " .. drinkIndex .. " 中所有毒药失败")
					-- 备用方法：移除对方毒药
					DrinkManager.removePoisonFromDrinkForTable(tableId, drinkIndex, opponent)
				end
			end
		end)
	end

	return true
end

-- 处理毒药验证的奶茶选择
function PropEffectHandler.handlePoisonDetectSelection(player, drinkIndex)
	-- 获取玩家当前所在的桌子ID
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		warn("玩家 " .. player.Name .. " 不在任何桌子上")
		return
	end

	-- 检查奶茶是否有毒
	local isPoisoned = false
	local poisonInfo = {}

	if DrinkManager then
		isPoisoned = DrinkManager.isDrinkPoisonedForTable(tableId, drinkIndex)
		poisonInfo = DrinkManager.getDrinkPoisonInfoForTable(tableId, drinkIndex)
	end

	-- 显示验证结果（只有使用者能看到）
	local resultColor = isPoisoned and Color3.new(1, 0, 0) or Color3.new(0, 1, 0) -- 红色有毒，绿色无毒

	if drinkSelectionEvent then
		drinkSelectionEvent:FireClient(player, "showPoisonVerifyResult", {
			drinkIndex = drinkIndex,
			isPoisoned = isPoisoned,
			color = resultColor,
			tableId = tableId  -- 传递桌子ID给客户端
		})
	end

	-- 现在广播使用消息给对方玩家
	PropEffectHandler.broadcastMessageToOpponent(player.Name .. " used Poison Detector", player, tableId)

	-- 恢复默认提示文本
	if drinkSelectionEvent then
		drinkSelectionEvent:FireClient(player, "updateSelectTips", {
			text = "Please choose a drink to drink"
		})
	end

	-- 清除等待状态
	local propUseState = getPropUseState(tableId)
	if propUseState then
		propUseState.awaitingSelection[player] = nil
	end
end

-- 执行道具效果（由PropManager调用，不处理道具消耗和验证）
function PropEffectHandler.executePropEffect(player, propId)
	-- 根据道具类型执行相应效果
	local effectType = PropConfig.getPropEffect(propId)
	local success = false

	if effectType == PropConfig.EFFECT_TYPES.POISON_DETECT then
		success = PropEffectHandler.handlePoisonDetect(player)
	elseif effectType == PropConfig.EFFECT_TYPES.TURN_SKIP then
		success = PropEffectHandler.handleTurnSkip(player)
	elseif effectType == PropConfig.EFFECT_TYPES.POISON_CLEAN then
		success = PropEffectHandler.handlePoisonClean(player)
	else
		warn("未知的道具效果类型: " .. tostring(effectType))
	end

	if success then
		-- Success was handled by the specific effect function
	else
		warn("玩家 " .. player.Name .. " 道具效果执行失败: " .. PropConfig.getPropName(propId))
	end

	return success
end

-- 处理奶茶选择（可能是道具验证选择）
function PropEffectHandler.handleDrinkSelection(player, drinkIndex)
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		return false
	end

	local propUseState = getPropUseState(tableId)
	if not propUseState then
		return false
	end

	-- 检查是否在等待毒药验证选择
	if propUseState.awaitingSelection[player] then
		local awaitingData = propUseState.awaitingSelection[player]

		if awaitingData.effectType == PropConfig.EFFECT_TYPES.POISON_DETECT then
			PropEffectHandler.handlePoisonDetectSelection(player, drinkIndex)
			return true -- 表示已处理，不需要继续正常的奶茶选择流程
		end
	end

	return false -- 继续正常的奶茶选择流程
end

-- 检查清除毒药道具的使用限制（在消耗道具前调用）
function PropEffectHandler.checkPoisonCleanUsage(player)
	local tableId = getTableIdFromPlayer(player)
	if not tableId then
		warn("玩家 " .. player.Name .. " 不在任何桌子上")
		return false, "系统错误"
	end

	local propUseState = getPropUseState(tableId)
	if not propUseState then
		return false, "系统错误"
	end

	-- 检查该玩家在该桌子是否已经使用过
	if propUseState.usedPoisonClean[player] then
		return false, "This prop can only be used once per game"
	end

	return true, "可以使用"
end

-- 设置事件监听
function PropEffectHandler.setupEvents()
	-- 注意：道具使用事件现在由PropManager统一处理
	-- PropManager会在验证后调用PropEffectHandler.executePropEffect
end

-- 初始化
function PropEffectHandler.initialize()
	PropEffectHandler.setupEvents()
end

-- 启动效果处理器
PropEffectHandler.initialize()

-- 导出到全局供其他脚本使用
_G.PropEffectHandler = PropEffectHandler

return PropEffectHandler