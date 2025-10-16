-- 脚本名称: WheelService
-- 脚本作用: 转盘系统核心服务，处理转盘逻辑、奖励计算和分发
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local WheelService = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 等待配置和数据管理器加载
local WheelConfig = nil
local WheelDataManager = nil

-- 转盘状态跟踪
local playerSpinStates = {} -- {[player] = {isSpinning = false, spinStartTime = 0}}

-- 转盘锁，防止同时转盘
local spinLocks = {}

-- RemoteEvents (延迟初始化)
local wheelSpinEvent = nil
local wheelDataSyncEvent = nil

-- ============================================
-- 依赖加载和初始化
-- ============================================

-- 加载依赖配置
local function loadDependencies()
	-- 加载WheelConfig
	if not WheelConfig then
		local success, result = pcall(function()
			return require(ReplicatedStorage:WaitForChild("WheelConfig", 10))
		end)

		if success then
			WheelConfig = result
		else
			warn("❌ WheelService: WheelConfig加载失败: " .. tostring(result))
			return false
		end
	end

	-- 等待WheelDataManager
	if not WheelDataManager then
		local timeout = 0
		while not _G.WheelDataManager and timeout < 30 do
			task.wait(0.5)
			timeout = timeout + 0.5
		end

		if _G.WheelDataManager then
			WheelDataManager = _G.WheelDataManager
		else
			warn("❌ WheelService: WheelDataManager连接超时")
			return false
		end
	end

	-- 🔧 新增：检查SkinDataManager依赖（用于皮肤排除功能）
	if not _G.SkinDataManager then
		warn("⚠️ WheelService: SkinDataManager未加载，皮肤排除功能可能不可用")
		-- 不返回false，因为这不是致命错误，转盘仍可正常工作
	end

	return true
end

-- 初始化RemoteEvents
local function initializeRemoteEvents()
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEventsFolder then
		warn("❌ WheelService: RemoteEvents文件夹不存在")
		return false
	end

	wheelSpinEvent = remoteEventsFolder:WaitForChild("WheelSpin", 5)
	wheelDataSyncEvent = remoteEventsFolder:WaitForChild("WheelDataSync", 5)

	if not wheelSpinEvent or not wheelDataSyncEvent then
		warn("❌ WheelService: 转盘RemoteEvents不存在")
		return false
	end

	return true
end

-- ============================================
-- 奖励处理逻辑
-- ============================================

-- 分发奖励
local function distributeReward(player, rewardType, value)
	local success = false
	local message = ""

	if rewardType == WheelConfig.REWARD_TYPES.COINS then
		-- 金币奖励
		if _G.CoinManager and _G.CoinManager.addCoins then
			-- 🔧 关键修复：使用pcall保护Manager调用
			local callSuccess, addSuccess = pcall(function()
				return _G.CoinManager.addCoins(player, value, "转盘奖励")
			end)

			if callSuccess and addSuccess then
				success = true
				message = "获得金币+" .. value
			else
				warn("WheelService: 金币发放失败 - " .. tostring(addSuccess))
				message = "系统错误：金币发放失败"
			end
		else
			warn("WheelService: CoinManager未加载，无法发放金币奖励")
			message = "系统错误：金币发放失败"
		end

	elseif rewardType == WheelConfig.REWARD_TYPES.TURN_SKIP then
		-- 跳过道具奖励 (PropId = 2)
		if _G.PropManager and _G.PropManager.addProp then
			-- 🔧 关键修复：使用pcall保护Manager调用
			local callSuccess, addSuccess = pcall(function()
				return _G.PropManager.addProp(player, 2, value, "转盘奖励")
			end)

			if callSuccess and addSuccess then
				success = true
				message = "获得跳过道具+" .. value
			else
				warn("WheelService: 跳过道具发放失败 - " .. tostring(addSuccess))
				message = "系统错误：道具发放失败"
			end
		else
			warn("WheelService: PropManager未加载，无法发放跳过道具")
			message = "系统错误：道具发放失败"
		end

	elseif rewardType == WheelConfig.REWARD_TYPES.POISON_DETECT then
		-- 验证道具奖励 (PropId = 1)
		if _G.PropManager and _G.PropManager.addProp then
			-- 🔧 关键修复：使用pcall保护Manager调用
			local callSuccess, addSuccess = pcall(function()
				return _G.PropManager.addProp(player, 1, value, "转盘奖励")
			end)

			if callSuccess and addSuccess then
				success = true
				message = "获得验证道具+" .. value
			else
				warn("WheelService: 验证道具发放失败 - " .. tostring(addSuccess))
				message = "系统错误：道具发放失败"
			end
		else
			warn("WheelService: PropManager未加载，无法发放验证道具")
			message = "系统错误：道具发放失败"
		end

	elseif rewardType == WheelConfig.REWARD_TYPES.SKIN then
		-- 🔧 皮肤奖励 - 理论上新逻辑已排除已拥有皮肤，但保留容错机制
		if _G.SkinDataManager and _G.SkinDataManager.grantSkin then
			-- 🔧 关键修复：使用pcall保护Manager调用
			local callSuccess, grantSuccess, grantMessage = pcall(function()
				return _G.SkinDataManager.grantSkin(player, value, "wheel_reward")
			end)

			if callSuccess and grantSuccess then
				success = true
				if grantMessage == "already_owned" then
					-- 📝 容错：如果仍然出现已拥有皮肤（不应该发生），转换为金币奖励
					local skinInfo = _G.SkinConfig and _G.SkinConfig.getSkinInfo and _G.SkinConfig.getSkinInfo(value)
					local compensationCoins = skinInfo and skinInfo.price or 100
					if _G.CoinManager and _G.CoinManager.addCoins then
						pcall(function()
							_G.CoinManager.addCoins(player, compensationCoins, "重复皮肤补偿")
						end)
					end
					message = "皮肤已拥有，获得补偿金币+" .. compensationCoins
					warn("🎰 WheelService: 意外获得已拥有皮肤 " .. value .. "，已补偿金币 - 玩家: " .. player.Name)
				else
					-- 获得新皮肤
					local skinInfo = _G.SkinConfig and _G.SkinConfig.getSkinInfo and _G.SkinConfig.getSkinInfo(value)
					local skinName = skinInfo and skinInfo.name or ("皮肤ID:" .. value)
					message = "获得皮肤: " .. skinName
				end
			else
				warn("WheelService: 皮肤发放失败 - " .. tostring(grantMessage))
				message = "系统错误：皮肤发放失败"
			end
		else
			warn("WheelService: SkinDataManager未加载，无法发放皮肤奖励")
			message = "系统错误：皮肤发放失败"
		end

	else
		warn("WheelService: 未知奖励类型 - " .. tostring(rewardType))
		message = "系统错误：未知奖励类型"
	end

	return success, message
end

-- ============================================
-- 转盘核心逻辑
-- ============================================

-- 执行转盘旋转
function WheelService.performSpin(player)
	-- 验证依赖是否加载
	if not loadDependencies() then
		return false, "system_not_ready"
	end

	-- 检查转盘锁
	if spinLocks[player] then
		return false, "spin_in_progress"
	end

	-- 检查转盘次数
	local spinCount = WheelDataManager.getSpinCount(player)
	if spinCount <= 0 then
		return false, "no_spins_available"
	end

	-- 加锁
	spinLocks[player] = true

	-- 使用转盘次数
	local useSuccess = WheelDataManager.useSpinCount(player)
	if not useSuccess then
		spinLocks[player] = nil
		return false, "spin_count_deduction_failed"
	end

	-- 🔧 新功能：使用玩家特定的奖励计算，排除已拥有的皮肤
	local rewardPosition, rewardData = WheelConfig.getRandomRewardPositionForPlayer(player)

	-- 🔧 修复：验证返回的奖励数据有效性
	if not rewardPosition or not rewardData or not rewardData.type or not rewardData.value then
		warn("🎰 WheelService: 获得无效奖励数据，使用备用逻辑")
		spinLocks[player] = nil
		-- 返还转盘次数
		if WheelDataManager.addSpinCount then
			WheelDataManager.addSpinCount(player, 1, "系统错误补偿")
		end
		return false, "invalid_reward_data"
	end

	local rewardType = rewardData.type
	local rewardValue = rewardData.value

	-- 计算转盘旋转参数
	local fullRotations = WheelConfig.SETTINGS.FULL_ROTATIONS or 5
	local degreesPerPosition = WheelConfig.SETTINGS.DEGREES_PER_POSITION or 60
	local animationDuration = WheelConfig.SETTINGS.SPIN_ANIMATION_DURATION or 3

	-- 计算最终角度（多圈旋转 + 奖励位置）
	local finalAngle = fullRotations * 360 + (rewardPosition - 1) * degreesPerPosition

	-- 记录转盘状态
	playerSpinStates[player] = {
		isSpinning = true,
		spinStartTime = tick(),
		rewardType = rewardType,
		rewardValue = rewardValue,
		rewardPosition = rewardPosition,
		finalAngle = finalAngle,
		animationDuration = animationDuration,
		rewardDistributed = false  -- 🔧 添加奖励分发标记，防止重复分发
	}

	-- 延迟分发奖励（等待动画完成）
	task.spawn(function()
		task.wait(animationDuration + 0.5) -- 额外0.5秒缓冲

		-- 🔧 修复：检查奖励是否已经分发，防止重复分发
		if player.Parent and playerSpinStates[player] and playerSpinStates[player].isSpinning and not playerSpinStates[player].rewardDistributed then
			-- 标记奖励即将分发
			playerSpinStates[player].rewardDistributed = true

			-- 🔧 关键修复：分发奖励并检查结果，失败时返还转盘次数
			local success, message = distributeReward(player, rewardType, rewardValue)

			-- 🔧 关键修复：如果奖励发放失败，返还转盘次数
			if not success then
				warn("🎰 WheelService: 奖励发放失败，返还转盘次数 - 玩家: " .. player.Name)
				if WheelDataManager and WheelDataManager.addSpinCount then
					pcall(function()
						WheelDataManager.addSpinCount(player, 1, "奖励发放失败补偿")
					end)
				end
			end

			-- 通知客户端奖励结果
			if wheelSpinEvent and player.Parent then
				pcall(function()
					wheelSpinEvent:FireClient(player, "spinComplete", {
						success = success,
						rewardType = rewardType,
						rewardValue = rewardValue,
						rewardPosition = rewardPosition,
						message = message
					})
				end)
			end

			-- 清理状态
			playerSpinStates[player] = nil
		end

		-- 解锁
		spinLocks[player] = nil
	end)

	-- 立即返回转盘参数给客户端
	return true, {
		rewardPosition = rewardPosition,
		finalAngle = finalAngle,
		animationDuration = animationDuration,
		rewardType = rewardType,
		rewardValue = rewardValue
	}
end

-- 检查玩家是否正在转盘
function WheelService.isPlayerSpinning(player)
	local state = playerSpinStates[player]
	return state and state.isSpinning or false
end

-- 获取玩家转盘状态
function WheelService.getPlayerSpinState(player)
	return playerSpinStates[player]
end

-- ============================================
-- RemoteEvent处理
-- ============================================

-- 处理客户端转盘请求
local function onSpinRequest(player, action, data)
	if action == "requestSpin" then
		local success, result = WheelService.performSpin(player)

		if success then
			-- 发送转盘开始事件到客户端
			wheelSpinEvent:FireClient(player, "spinStart", result)
		else
			-- 发送失败事件到客户端
			wheelSpinEvent:FireClient(player, "spinFailed", {
				reason = result
			})
		end

	elseif action == "forceComplete" then
		-- 🔧 需求修复：强制完成转盘（玩家关闭界面时）
		if playerSpinStates[player] and playerSpinStates[player].isSpinning and not playerSpinStates[player].rewardDistributed then
			-- 标记奖励即将分发
			playerSpinStates[player].rewardDistributed = true

			local rewardType = playerSpinStates[player].rewardType
			local rewardValue = playerSpinStates[player].rewardValue
			local rewardPosition = playerSpinStates[player].rewardPosition

			-- 🔧 关键修复：立即分发奖励并检查结果
			local success, message = distributeReward(player, rewardType, rewardValue)

			-- 🔧 关键修复：如果奖励发放失败，返还转盘次数
			if not success then
				warn("🎰 WheelService: 强制完成时奖励发放失败，返还转盘次数 - 玩家: " .. player.Name)
				if WheelDataManager and WheelDataManager.addSpinCount then
					pcall(function()
						WheelDataManager.addSpinCount(player, 1, "强制完成奖励失败补偿")
					end)
				end
			end

			-- 通知客户端强制完成结果
			pcall(function()
				wheelSpinEvent:FireClient(player, "spinComplete", {
					success = success,
					rewardType = rewardType,
					rewardValue = rewardValue,
					rewardPosition = rewardPosition,
					message = message
				})
			end)

			-- 清理状态
			playerSpinStates[player] = nil
			spinLocks[player] = nil
		end

	elseif action == "getSpinState" then
		-- 返回当前转盘状态
		local state = WheelService.getPlayerSpinState(player)
		wheelSpinEvent:FireClient(player, "spinState", {
			isSpinning = WheelService.isPlayerSpinning(player),
			state = state
		})
	end
end

-- ============================================
-- 清理和事件处理
-- ============================================

-- 玩家离开清理
local function onPlayerRemoving(player)
	-- 🔧 修复：如果玩家正在转盘中离开，立即结算奖励避免丢失
	if playerSpinStates[player] and playerSpinStates[player].isSpinning and not playerSpinStates[player].rewardDistributed then
		-- 标记奖励即将分发
		playerSpinStates[player].rewardDistributed = true

		local rewardType = playerSpinStates[player].rewardType
		local rewardValue = playerSpinStates[player].rewardValue

		-- 🔧 关键修复：立即分发奖励（玩家离线时不通知客户端）并检查结果
		local success, message = distributeReward(player, rewardType, rewardValue)

		-- 🔧 关键修复：如果奖励发放失败，返还转盘次数（离线补偿）
		if not success then
			warn("🎰 WheelService: 玩家离线时奖励发放失败，返还转盘次数 - 玩家: " .. player.Name)
			if WheelDataManager and WheelDataManager.addSpinCount then
				pcall(function()
					WheelDataManager.addSpinCount(player, 1, "离线奖励失败补偿")
				end)
			end
		end
	end

	playerSpinStates[player] = nil
	spinLocks[player] = nil
end

-- ============================================
-- 初始化和启动
-- ============================================

-- 初始化服务
function WheelService.initialize()
	-- 等待依赖加载
	task.spawn(function()
		task.wait(3) -- 等待其他系统初始化
		loadDependencies()
	end)

	-- 初始化RemoteEvents
	task.spawn(function()
		task.wait(4) -- 等待RemoteEvents创建
		if initializeRemoteEvents() then
			-- 设置事件监听
			wheelSpinEvent.OnServerEvent:Connect(onSpinRequest)
		end
	end)

	-- 监听玩家离开
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

-- 启动服务
WheelService.initialize()

-- 导出到全局
_G.WheelService = WheelService

return WheelService