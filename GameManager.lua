-- 脚本名称: GameManager
-- 脚本作用: 管理单个对战组的游戏逻辑，检测座位和控制UI
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local GameManager = {}
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local cameraControlEvent = remoteEventsFolder:WaitForChild("CameraControl")
local seatLockEvent = remoteEventsFolder:WaitForChild("SeatLock")

-- 引入DrinkManager和PoisonSelectionManager
local DrinkManager = require(script.Parent.DrinkManager)
local PoisonSelectionManager = require(script.Parent.PoisonSelectionManager)
local DrinkSelectionManager = require(script.Parent.DrinkSelectionManager)

-- 获取对战组引用
local workspace = game.Workspace
local twoPlayerFolder = workspace:WaitForChild("2Player")
local battleGroup = twoPlayerFolder:WaitForChild("2player_group1")

-- 获取组件引用
local classicTable = battleGroup:WaitForChild("ClassicTable")
local classicChair1 = battleGroup:WaitForChild("ClassicChair1")
local classicChair2 = battleGroup:WaitForChild("ClassicChair2")

-- 获取座位引用
local seat1 = classicChair1:WaitForChild("Seat")
local seat2 = classicChair2:WaitForChild("Seat")

-- 获取UI引用
local tablePart = classicTable:WaitForChild("TablePart")
local billboardGui = tablePart:WaitForChild("BillboardGui")
local playerNumBg = billboardGui:WaitForChild("PlayerNumBg")
local numLabel = playerNumBg:WaitForChild("Num")

-- 游戏状态变量
local gameState = {
	player1 = nil,
	player2 = nil,
	playersReady = 0,
	isCountingDown = false,
	countdownTime = 5,
	countdownCoroutine = nil,
	gamePhase = "waiting", -- "waiting", "poison", "selection", "result"
	poisonSelections = {},  -- 存储玩家的毒药选择
	-- 🔧 新增：状态锁定机制，防止并发状态修改
	stateLock = false
}

-- 🔧 新增：获取状态锁
local function acquireStateLock()
	if gameState.stateLock then
		return false
	end
	gameState.stateLock = true
	return true
end

-- 🔧 新增：释放状态锁
local function releaseStateLock()
	gameState.stateLock = false
end

-- 🔧 新增：安全的状态更新函数
local function updateGameState(updates)
	if not acquireStateLock() then
		warn("GameManager: 状态正在被其他操作修改，跳过本次更新")
		return false
	end

	-- 使用pcall保护状态更新
	local success = pcall(function()
		for key, value in pairs(updates) do
			if gameState[key] ~= nil then  -- 只更新存在的字段
				gameState[key] = value
			else
				warn("GameManager: 尝试更新不存在的状态字段: " .. tostring(key))
			end
		end
	end)

	releaseStateLock()
	return success
end

-- 更新玩家数量显示
function GameManager.updatePlayerCount()
	local count = gameState.playersReady
	numLabel.Text = count .. "/2 Player"
end

-- 开始倒计时
function GameManager.startCountdown()
	if gameState.isCountingDown then return end

	gameState.isCountingDown = true
	gameState.countdownTime = 5


	-- 启用Leave按钮UI
	GameManager.enableLeaveButton(gameState.player1)
	GameManager.enableLeaveButton(gameState.player2)

	-- 开始倒计时协程
	gameState.countdownCoroutine = coroutine.create(function()
		while gameState.countdownTime > 0 and gameState.isCountingDown do
			-- 更新倒计时UI
			GameManager.updateCountdownUI(gameState.player1, gameState.countdownTime)
			GameManager.updateCountdownUI(gameState.player2, gameState.countdownTime)


			wait(1)
			gameState.countdownTime = gameState.countdownTime - 1
		end

		if gameState.isCountingDown and gameState.countdownTime <= 0 then
			GameManager.startGame()
		end
	end)

	coroutine.resume(gameState.countdownCoroutine)
end

-- 取消倒计时
function GameManager.cancelCountdown()
	if not gameState.isCountingDown then return end

	gameState.isCountingDown = false

	-- 获取当前在座位上的所有玩家（包括可能已经离开gameState的玩家）
	local playersInSeats = {}

	-- 检查座位1
	if seat1.Occupant then
		local player1 = Players:GetPlayerFromCharacter(seat1.Occupant.Parent)
		if player1 then
			table.insert(playersInSeats, player1)
		end
	end

	-- 检查座位2
	if seat2.Occupant then
		local player2 = Players:GetPlayerFromCharacter(seat2.Occupant.Parent)
		if player2 then
			table.insert(playersInSeats, player2)
		end
	end

	-- 为仍在座位上的玩家保持Leave按钮启用状态
	for _, player in ipairs(playersInSeats) do
		GameManager.enableLeaveButton(player)
	end

	-- 对所有在线玩家隐藏倒计时UI（确保离开的玩家也能隐藏UI）
	for _, player in pairs(Players:GetPlayers()) do
		GameManager.hideCountdownUI(player)
	end

end

-- 启用Leave按钮
function GameManager.enableLeaveButton(player)
	if not player then return end

	-- 🔧 关键修复：完全使用自定义Leave系统，不创建额外GUI
	print("✅ Leave按钮管理已移交给CustomLeaveController")
	-- CustomLeaveController会自动处理您的自定义Leave按钮显示和隐藏
	-- 路径：StarterGui - Leave - LeaveBtnBg - LeaveBtn
end

-- 禁用Leave按钮
function GameManager.disableLeaveButton(player)
	if not player then return end

	-- 🔧 关键修复：禁用功能也移交给CustomLeaveController自动处理
	print("✅ Leave按钮禁用已移交给CustomLeaveController")
	-- CustomLeaveController会根据座位状态自动隐藏按钮
end

-- 更新倒计时UI
function GameManager.updateCountdownUI(player, timeLeft)
	if not player then return end

	local playerGui = player:WaitForChild("PlayerGui")
	local countDownTips = playerGui:FindFirstChild("CountDownTips")
	if countDownTips then
		countDownTips.Enabled = true

		local textBg = countDownTips:FindFirstChild("TextBg")
		if textBg then
			local tips = textBg:FindFirstChild("Tips")
			if tips then
				tips.Text = "Starting in: " .. timeLeft .. "S"
			end
		end
	end
end

-- 隐藏倒计时UI
function GameManager.hideCountdownUI(player)
	if not player then return end

	local playerGui = player:WaitForChild("PlayerGui")
	local countDownTips = playerGui:FindFirstChild("CountDownTips")
	if countDownTips then
		countDownTips.Enabled = false
	end
end

-- 玩家手动离开座位
function GameManager.playerLeaveManually(player)
	-- 🔧 直接设置玩家离座，不使用复杂的适配器
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		player.Character.Humanoid.Sit = false
		print("🔓 GameManager: 玩家 " .. player.Name .. " 手动离开座位")
	end
end

-- 开始游戏
function GameManager.startGame()

	-- 隐藏BillboardGui
	billboardGui.Enabled = false

	-- 隐藏倒计时UI
	GameManager.hideCountdownUI(gameState.player1)
	GameManager.hideCountdownUI(gameState.player2)

	-- 游戏开始后禁用Leave按钮
	GameManager.disableLeaveButton(gameState.player1)
	GameManager.disableLeaveButton(gameState.player2)

	-- 注意：奶茶生成现在由GameInstance负责，这里不再重复调用

	-- 注意：毒药注入阶段现在也由GameInstance负责
end

-- 开始毒药注入阶段（已弃用 - 现在由GameInstance负责）
function GameManager.startPoisonPhase()
	-- 此函数已弃用，毒药选择阶段现在由各个桌子的GameInstance独立管理

	-- 以下代码已注释掉，功能转移到GameInstance
	-- gameState.gamePhase = "poison"
	-- cameraControlEvent:FireClient(gameState.player1, "enterPoison")
	-- cameraControlEvent:FireClient(gameState.player2, "enterPoison")
	-- PoisonSelectionManager.startPoisonPhase(gameState.player1, gameState.player2)
end

-- 开始选择奶茶阶段
function GameManager.startSelectionPhase()

	-- 更新游戏状态
	gameState.gamePhase = "selection"

	-- 切换镜头回到选择视角
	cameraControlEvent:FireClient(gameState.player1, "enterSelect")
	cameraControlEvent:FireClient(gameState.player2, "enterSelect")

	-- 启动轮流选择系统
	DrinkSelectionManager.startSelectionPhase(gameState.player1, gameState.player2)

end

-- 重置到等待状态
function GameManager.resetToWaiting()

	-- 🔧 关键修复：使用安全的状态更新
	local success = updateGameState({
		gamePhase = "waiting",
		isCountingDown = false,
		poisonSelections = {}
	})

	if not success then
		warn("GameManager: 重置到等待状态失败，尝试强制重置")
		-- 强制重置（紧急情况下）
		gameState.gamePhase = "waiting"
		gameState.isCountingDown = false
		gameState.poisonSelections = {}
	end

	-- 清理桌子上的奶茶模型
	DrinkManager.clearAllDrinks()

	-- 重新检测当前座位占用情况，而不是简单清空
	GameManager.refreshSeatState()

	-- 显示BillboardGui
	billboardGui.Enabled = true

	-- 更新玩家数量显示
	GameManager.updatePlayerCount()

end

-- 刷新座位状态（检测当前实际占用情况）
function GameManager.refreshSeatState()
	local actualPlayer1 = nil
	local actualPlayer2 = nil
	local actualCount = 0

	-- 检查座位1
	if seat1.Occupant then
		local player1 = Players:GetPlayerFromCharacter(seat1.Occupant.Parent)
		if player1 then
			actualPlayer1 = player1
			actualCount = actualCount + 1
		end
	end

	-- 检查座位2
	if seat2.Occupant then
		local player2 = Players:GetPlayerFromCharacter(seat2.Occupant.Parent)
		if player2 then
			actualPlayer2 = player2
			actualCount = actualCount + 1
		end
	end

	-- 🔧 关键修复：使用安全的状态更新
	local success = updateGameState({
		player1 = actualPlayer1,
		player2 = actualPlayer2,
		playersReady = actualCount
	})

	if not success then
		warn("GameManager: 座位状态刷新失败，使用直接赋值")
		-- 紧急情况下的直接赋值
		gameState.player1 = actualPlayer1
		gameState.player2 = actualPlayer2
		gameState.playersReady = actualCount
	end

	-- 重要：为重新检测到的玩家设置正确的准备状态（只在waiting阶段）
	if gameState.gamePhase == "waiting" then
		if actualPlayer1 then
			GameManager.enableLeaveButton(actualPlayer1)
			cameraControlEvent:FireClient(actualPlayer1, "enterPrepare")
		end

		if actualPlayer2 then
			GameManager.enableLeaveButton(actualPlayer2)
			cameraControlEvent:FireClient(actualPlayer2, "enterPrepare")
		end
	end
end

-- 玩家坐下处理
function GameManager.onPlayerSat(seat, player)

	-- 只有在等待阶段才允许玩家进入准备状态
	if gameState.gamePhase ~= "waiting" then
		return
	end

	-- 🔧 关键修复：使用安全的状态更新
	local updates = {}
	local shouldUpdateCount = false

	if seat == seat1 and not gameState.player1 then
		updates.player1 = player
		shouldUpdateCount = true

		-- 立即启用Leave按钮
		GameManager.enableLeaveButton(player)

		-- 切换到准备阶段镜头
		cameraControlEvent:FireClient(player, "enterPrepare")

	elseif seat == seat2 and not gameState.player2 then
		updates.player2 = player
		shouldUpdateCount = true

		-- 立即启用Leave按钮
		GameManager.enableLeaveButton(player)

		-- 切换到准备阶段镜头
		cameraControlEvent:FireClient(player, "enterPrepare")
	end

	-- 如果有状态更新，统一执行
	if shouldUpdateCount then
		updates.playersReady = gameState.playersReady + 1

		local success = updateGameState(updates)
		if success then
			GameManager.updatePlayerCount()

			-- 检查是否可以开始倒计时（只有在waiting阶段）
			if gameState.gamePhase == "waiting" and gameState.playersReady == 2 and not gameState.isCountingDown then
				GameManager.startCountdown()
			end
		else
			warn("GameManager: 玩家坐下状态更新失败")
		end
	end
end

-- 玩家离开座位处理
function GameManager.onPlayerLeft(seat, player)

	-- 🔧 关键修复：统一状态检查逻辑，不依赖外部标志
	-- 检查是否在非waiting阶段（不应该清理状态）
	local shouldSkipStateReset = (gameState.gamePhase ~= "waiting")

	-- 🔧 关键修复：使用安全的状态更新
	local updates = {}
	local shouldUpdateCount = false

	if seat == seat1 and gameState.player1 == player then
		if not shouldSkipStateReset then
			updates.player1 = nil
			shouldUpdateCount = true
		end

		-- 重要：无论什么阶段，只要玩家离开座位，就应该恢复镜头和禁用Leave按钮
		GameManager.disableLeaveButton(player)
		cameraControlEvent:FireClient(player, "restore")

	elseif seat == seat2 and gameState.player2 == player then
		if not shouldSkipStateReset then
			updates.player2 = nil
			shouldUpdateCount = true
		end

		-- 重要：无论什么阶段，只要玩家离开座位，就应该恢复镜头和禁用Leave按钮
		GameManager.disableLeaveButton(player)
		cameraControlEvent:FireClient(player, "restore")
	end

	-- 如果需要更新状态，统一执行
	if shouldUpdateCount then
		updates.playersReady = math.max(gameState.playersReady - 1, 0)

		local success = updateGameState(updates)
		if success then
			GameManager.updatePlayerCount()
		else
			warn("GameManager: 玩家离开状态更新失败")
		end
	end

	-- 如果正在倒计时且有人离开，取消倒计时
	if gameState.isCountingDown and gameState.playersReady < 2 then
		GameManager.cancelCountdown()
	end

	-- 如果游戏正在进行中（不是waiting阶段）且有玩家离开，判定另一个玩家获胜
	if gameState.gamePhase ~= "waiting" and gameState.playersReady < 2 then
		GameManager.handlePlayerLeaveWin(player)
	end
end

-- 处理玩家离开导致的获胜
function GameManager.handlePlayerLeaveWin(leavingPlayer)
	-- 检查ReplicatedStorage中的DrinkSelection标志
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local drinkSelectionFlag = ReplicatedStorage:FindFirstChild("DrinkSelectionActive")

	if drinkSelectionFlag and drinkSelectionFlag.Value then
		return
	end

	-- 检查游戏是否已经在结果阶段或等待阶段
	if gameState.gamePhase == "result" or gameState.gamePhase == "waiting" then
		return
	end

	-- 🔧 关键修复：检查是否有胜利动画正在播放，避免重复记录
	-- 胜利动画播放时会强制玩家站起来，这不应该被视为"离开"
	if _G.VictoryAnimationManager and _G.VictoryAnimationManager.isPlayingAnimation then
		if _G.VictoryAnimationManager.isPlayingAnimation(leavingPlayer) then
			print("🎭 跳过胜利动画中的玩家离开事件: " .. leavingPlayer.Name)
			return
		end
		-- 检查对手是否在播放胜利动画
		local opponent = (gameState.player1 == leavingPlayer) and gameState.player2 or gameState.player1
		if opponent and _G.VictoryAnimationManager.isPlayingAnimation(opponent) then
			print("🎭 跳过胜利动画期间的座位变化事件: " .. leavingPlayer.Name)
			return
		end
	end

	local winner = nil

	-- 确定获胜者
	if gameState.player1 and gameState.player1 ~= leavingPlayer then
		winner = gameState.player1
	elseif gameState.player2 and gameState.player2 ~= leavingPlayer then
		winner = gameState.player2
	end

	if winner then

		-- ✅ 恢复排行榜记录功能：玩家离开时也需要记录胜负
		GameManager.recordLeaveWinToRanking(winner, leavingPlayer)

		-- 设置游戏阶段为结果阶段，防止重复判定
		gameState.gamePhase = "result"

		-- 通知获胜者
		local drinkSelectionEvent = remoteEventsFolder:FindFirstChild("DrinkSelection")
		if drinkSelectionEvent then
			drinkSelectionEvent:FireClient(winner, "gameWin", {
				reason = "opponent_left",
				opponent = leavingPlayer.Name
			})
		end

		-- 立即重置游戏，无需等待（玩家离开情况下）
		GameManager.resetToWaiting()
	end
end

-- 记录离开导致的获胜到排行榜系统
function GameManager.recordLeaveWinToRanking(winner, leavingPlayer)

	if not winner or not leavingPlayer then
		warn("记录排行榜数据失败: 获胜者或离开者为空")
		return
	end


	-- 检查RankingDataManager是否可用
	if not _G.RankingDataManager then
		warn("RankingDataManager 未加载，尝试等待加载...")
		-- 尝试等待一段时间再调用
		spawn(function()
			local attempts = 0
			while not _G.RankingDataManager and attempts < 10 do
				wait(0.5)
				attempts = attempts + 1
			end

			if _G.RankingDataManager then
				_G.RankingDataManager.recordGameResult(winner, true)         -- 获胜者
				_G.RankingDataManager.recordGameResult(leavingPlayer, false)  -- 离开者(失败)
			else
				warn("RankingDataManager 加载失败，无法记录排行榜数据")
			end
		end)
		return
	end

	-- 记录获胜者和离开者的数据
	local winnerSuccess = _G.RankingDataManager.recordGameResult(winner, true)
	local loserSuccess = _G.RankingDataManager.recordGameResult(leavingPlayer, false)

	if winnerSuccess and loserSuccess then
	else
		warn("离开获胜排行榜数据记录失败")
		if not winnerSuccess then
			warn("获胜者 " .. winner.Name .. " 数据记录失败")
		end
		if not loserSuccess then
			warn("离开者 " .. leavingPlayer.Name .. " 数据记录失败")
		end
	end
end

-- 座位状态检测
function GameManager.setupSeatDetection()
	-- 检测座位1
	seat1:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat1.Occupant
		if occupant then
			local player = Players:GetPlayerFromCharacter(occupant.Parent)
			if player then
				GameManager.onPlayerSat(seat1, player)
			end
		else
			-- 座位空了，处理玩家离开
			if gameState.player1 then
				GameManager.onPlayerLeft(seat1, gameState.player1)
			end
		end
	end)

	-- 检测座位2
	seat2:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat2.Occupant
		if occupant then
			local player = Players:GetPlayerFromCharacter(occupant.Parent)
			if player then
				GameManager.onPlayerSat(seat2, player)
			end
		else
			-- 座位空了，处理玩家离开
			if gameState.player2 then
				GameManager.onPlayerLeft(seat2, gameState.player2)
			end
		end
	end)

end

-- 初始化游戏管理器
function GameManager.initialize()

	-- 初始化UI显示
	GameManager.updatePlayerCount()

	-- 确保BillboardGui启用
	billboardGui.Enabled = true

	-- 设置座位检测
	GameManager.setupSeatDetection()

	-- 设置玩家离开服务器的监听
	GameManager.setupPlayerLeftHandling()

	-- 设置SeatLock RemoteEvent监听
	GameManager.setupSeatLockEvent()

end

-- 设置玩家离开服务器的处理
function GameManager.setupPlayerLeftHandling()
	Players.PlayerRemoving:Connect(function(player)

		-- 检查离开的玩家是否在游戏中
		if gameState.player1 == player or gameState.player2 == player then

			-- 直接处理为离开游戏的情况
			if gameState.gamePhase ~= "waiting" then
				GameManager.handlePlayerLeaveWin(player)
			else
				-- 如果在等待阶段，清理状态
				if gameState.player1 == player then
					gameState.player1 = nil
					gameState.playersReady = gameState.playersReady - 1
				elseif gameState.player2 == player then
					gameState.player2 = nil
					gameState.playersReady = gameState.playersReady - 1
				end

				GameManager.updatePlayerCount()

				-- 如果正在倒计时，取消倒计时
				if gameState.isCountingDown then
					GameManager.cancelCountdown()
				end
			end
		end
	end)

end

-- 设置SeatLock RemoteEvent处理
function GameManager.setupSeatLockEvent()
	-- 监听来自DrinkSelectionManager的请求
	seatLockEvent.OnServerEvent:Connect(function(player, action)
		if action == "enableLeave" then
			GameManager.enableLeaveButton(player)
		elseif action == "unlock" then
			-- 🔧 简化：直接设置玩家离座
			if player.Character and player.Character:FindFirstChild("Humanoid") then
				player.Character.Humanoid.Sit = false
				print(string.format("🔓 GameManager: 玩家 %s 解锁座位", player.Name))
			end
		end
	end)

	-- 监听ReplicatedStorage中的EnableLeaveFlag变化
	local enableLeaveFlag = ReplicatedStorage:FindFirstChild("EnableLeaveFlag")
	if not enableLeaveFlag then
		enableLeaveFlag = Instance.new("StringValue")
		enableLeaveFlag.Name = "EnableLeaveFlag"
		enableLeaveFlag.Parent = ReplicatedStorage
	end

	enableLeaveFlag.Changed:Connect(function(newValue)
		if newValue and newValue ~= "" then
			local playerName = newValue:match("([^_]+)_")
			if playerName then
				local player = Players:FindFirstChild(playerName)
				if player then
					GameManager.enableLeaveButton(player)
					-- 清空标志，防止重复触发
					enableLeaveFlag.Value = ""
				end
			end
		end
	end)

	-- 监听GamePhaseFlag变化
	local gamePhaseFlag = ReplicatedStorage:FindFirstChild("GamePhaseFlag")
	if not gamePhaseFlag then
		gamePhaseFlag = Instance.new("StringValue")
		gamePhaseFlag.Name = "GamePhaseFlag"
		gamePhaseFlag.Parent = ReplicatedStorage
	end

	gamePhaseFlag.Changed:Connect(function(newValue)
		if newValue and newValue ~= "" then
			gameState.gamePhase = newValue

			-- 如果阶段变化为waiting，调用重置函数
			if newValue == "waiting" then
				GameManager.resetToWaiting()
			end
		end
	end)

end

-- 启动管理器
GameManager.initialize()

-- 导出到全局供其他脚本使用
_G.GameManager = GameManager

return GameManager