-- 脚本名称: NewPlayerEntry
-- 脚本作用: 新手教程场景启动脚本，初始化NPC和管理新手对局流程
-- 脚本类型: Script
-- 放置位置: Newplayer场景的ServerScriptService

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game.Workspace

-- 🔧 V1.6修复: 添加超时机制的安全require，如果模块不存在则返回nil
local function safeRequire(moduleName, timeout)
	timeout = timeout or 5
	local startTime = tick()

	while not script.Parent:FindFirstChild(moduleName) and (tick() - startTime) < timeout do
		wait(0.1)
	end

	local module = script.Parent:FindFirstChild(moduleName)
	if module then
		local success, result = pcall(function()
			return require(module)
		end)
		if success then
			return result
		else
			warn("[NewPlayerEntry] 加载模块失败: " .. moduleName .. " - " .. tostring(result))
			return nil
		end
	else
		warn("[NewPlayerEntry] 模块不存在: " .. moduleName)
		return nil
	end
end

-- 引入管理器模块（使用安全加载）
local TutorialBotService = safeRequire("TutorialBotService")
local TutorialGuideManager = safeRequire("TutorialGuideManager")
local TutorialAnalyticsService = safeRequire("TutorialAnalyticsService")
local PortalTransportManager = safeRequire("PortalTransportManager")
local TutorialEnvironmentManager = safeRequire("TutorialEnvironmentManager")
local PlayerDataService = safeRequire("PlayerDataService")

-- 检查关键模块是否加载成功
if not TutorialBotService then
	error("[NewPlayerEntry] 关键模块TutorialBotService未找到，无法启动教程场景")
end

if not PlayerDataService then
	error("[NewPlayerEntry] 关键模块PlayerDataService未找到，无法启动教程场景")
end

print("[NewPlayerEntry] ✓ 所有必需模块已加载")

-- 标记此场景为教程模式
_G.TutorialMode = true
_G.TutorialCompleted = {}  -- 记录完成的玩家
_G.TutorialEnvironmentManager = TutorialEnvironmentManager  -- 🔧 V1.6: 导出到全局，供其他模块使用
_G.PortalTransportManager = PortalTransportManager  -- 🔧 V1.6: 导出Portal管理器到全局

-- ============================================
-- 场景初始化配置
-- ============================================

local TUTORIAL_CONFIG = {
	NPC_NAME = "NPC",
	CHAIR1_NAME = "ClassicChair1",
	CHAIR2_NAME = "ClassicChair2",
	TABLE_NAME = "2player_group1",
	MAX_PLAYERS = 1,  -- 新手场景最多1个真实玩家
	MAIN_PLACE_ID = 138909711165251  -- 常规场景ID
}

-- ============================================
-- 场景初始化
-- ============================================

-- 等待2Player文件夹加载
local twoPlayerFolder = Workspace:WaitForChild("2Player")
local tableFolder = twoPlayerFolder:WaitForChild(TUTORIAL_CONFIG.TABLE_NAME)
local npcModel = Workspace:WaitForChild(TUTORIAL_CONFIG.NPC_NAME)

print("[NewPlayerEntry] ✓ 场景加载完成，正在初始化")

-- 初始化Portal
local mainPlaceId = TUTORIAL_CONFIG.MAIN_PLACE_ID
if _G.MainPlaceId then
	mainPlaceId = _G.MainPlaceId
end
PortalTransportManager:initializePortal(mainPlaceId)
PortalTransportManager:setMainPlaceId(mainPlaceId)

print("[NewPlayerEntry] ✓ Portal已初始化")

-- 初始化NPC机器人
local botTableId = TUTORIAL_CONFIG.TABLE_NAME
TutorialBotService:initializeBot(npcModel, botTableId)

print("[NewPlayerEntry] ✓ NPC机器人已初始化")

-- ============================================
-- NPC坐下逻辑
-- ============================================

local function setupNPCSeating()

	local chair1 = tableFolder:FindFirstChild(TUTORIAL_CONFIG.CHAIR1_NAME)
	if not chair1 then
		warn("[NewPlayerEntry] 找不到ClassicChair1")
		return false
	end

	local seat1 = chair1:FindFirstChild("Seat")
	if not seat1 or not seat1:IsA("Seat") then
		warn("[NewPlayerEntry] ClassicChair1下找不到Seat")
		return false
	end

	-- 检查NPC模型结构
	local humanoid = npcModel:FindFirstChild("Humanoid")
	if not humanoid then
		warn("[NewPlayerEntry] NPC模型没有Humanoid")
		return false
	end

	local rootPart = npcModel:FindFirstChild("HumanoidRootPart") or npcModel:FindFirstChild("Torso")
	if not rootPart then
		warn("[NewPlayerEntry] NPC模型没有HumanoidRootPart或Torso")
		return false
	end

	-- 🔧 修复：确保座位未被禁用且可用
	if seat1.Disabled then
		seat1.Disabled = false
	end


	-- 1. 确保NPC在站立状态
	humanoid.Sit = false

	-- 2. 将NPC移动到座位正前方（使用座位的CFrame，不猜测高度）
	local seatCFrame = seat1.CFrame

	-- 🔧 修复：座位正前方1.5个单位（Z轴负方向），保持座位的高度
	-- 这样NPC会站在座位前方，高度与座位一致
	local approachCFrame = seatCFrame * CFrame.new(0, 0, -1.5)

	-- 直接使用计算出的CFrame，但调整方向让NPC面向座位
	rootPart.CFrame = approachCFrame * CFrame.Angles(0, math.pi, 0)

	-- 3. 等待物理引擎稳定
	wait(0.3)


	-- 方法1：使用Seat:Sit()
	seat1:Sit(humanoid)

	-- 方法2：同时设置Humanoid.Sit（确保双重触发）
	wait(0.1)
	humanoid.Sit = true

	-- 5. 等待坐下动画播放
	wait(0.5)

	-- 验证是否成功坐下
	if seat1.Occupant == humanoid and humanoid.Sit then
		return true
	else
		warn("[NewPlayerEntry] ⚠️ NPC坐下失败")
		warn("  座位占用者: " .. tostring(seat1.Occupant))
		warn("  Humanoid.Sit: " .. tostring(humanoid.Sit))

		-- 🔧 最后的备用方案：完全对齐座位CFrame

		-- 直接将NPC的RootPart对齐到座位的CFrame
		-- 座位会自动调整角色到正确的坐姿位置
		rootPart.CFrame = seat1.CFrame

		-- 设置坐下状态
		humanoid.Sit = true
		seat1.Occupant = humanoid

		wait(0.3)

		if seat1.Occupant == humanoid then
			return true
		else
			warn("[NewPlayerEntry] ❌ 所有坐下方案都失败")
			return false
		end
	end
end

-- 🔧 修复：延迟执行NPC坐下，确保场景完全加载
wait(1)  -- 给场景1秒时间完全加载
setupNPCSeating()

-- ============================================
-- 玩家加入处理
-- ============================================

local function onPlayerAdded(player)

	-- 埋点1：玩家进入Newplayer
	TutorialAnalyticsService:trackPlayerEnterNewplayer(player)

	-- 等待玩家角色加载
	local character = player.Character or player.CharacterAdded:Wait()

	-- 获取Chair2（玩家应该坐的椅子）
	local chair2 = tableFolder:FindFirstChild(TUTORIAL_CONFIG.CHAIR2_NAME)
	if not chair2 then
		warn("[NewPlayerEntry] 找不到ClassicChair2")
		return
	end

	-- 创建引导箭头
	TutorialGuideManager:showGuidingArrow(player, chair2:FindFirstChild("Seat"))
end

-- 玩家离开处理
local function onPlayerRemoving(player)

	-- 清理引导箭头
	TutorialGuideManager:cleanupOnPlayerLeaving(player)

	-- 清理埋点缓存
	TutorialAnalyticsService:cleanupPlayerTrack(player)

	-- 🔧 CRITICAL FIX: 清理内存中的教程完成标记，防止内存泄漏
	if _G.TutorialCompleted and _G.TutorialCompleted[player.UserId] then
		_G.TutorialCompleted[player.UserId] = nil
	end
end

-- 监听玩家加入和离开
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- 处理已在线的玩家
for _, player in pairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- ============================================
-- GameInstance初始化
-- ============================================

-- 等待GameInstance创建（由TableManager创建）
local function waitForGameInstance()
	local maxAttempts = 30
	local attempts = 0

	while attempts < maxAttempts do
		if _G.TableManager then
			local gameInstance = _G.TableManager.getTableInstance(botTableId)
			if gameInstance then
				-- 标记为教程模式
				gameInstance.isTutorial = true

				-- 🔧 V1.6: 初始化教程环境管理器，缓存Chair2 Seat
				if TutorialEnvironmentManager then
					local chair2 = tableFolder:FindFirstChild(TUTORIAL_CONFIG.CHAIR2_NAME)
					if chair2 then
						TutorialEnvironmentManager:initializeTutorialSeat(chair2)
					else
						warn("[NewPlayerEntry] 无法找到Chair2，无法初始化座位缓存")
					end
				end

				return gameInstance
			end
		end

		attempts = attempts + 1
		wait(0.5)
	end

	warn("[NewPlayerEntry] 等待GameInstance超时")
	return nil
end

-- 启动一个异步任务来获取GameInstance
spawn(function()
	waitForGameInstance()
end)

-- ============================================
-- 关于玩家坐下的处理
-- ============================================

-- GameInstance中的onPlayerSat会自动处理玩家坐下事件
-- 我们只需要监听座位变化，在玩家坐下时销毁引导箭头

local function setupSeatMonitoring()
	local chair2 = tableFolder:FindFirstChild(TUTORIAL_CONFIG.CHAIR2_NAME)
	if not chair2 then return end

	local seat2 = chair2:FindFirstChild("Seat")
	if not seat2 then return end

	-- 监听座位占用者变化
	seat2:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat2.Occupant then
			local occupantHumanoid = seat2.Occupant
			if occupantHumanoid and occupantHumanoid.Parent then
				local character = occupantHumanoid.Parent
				local player = Players:GetPlayerFromCharacter(character)

				if player then
	
					-- 埋点2：玩家坐下
					TutorialAnalyticsService:trackPlayerSitDown(player)

					-- 销毁引导箭头
					TutorialGuideManager:hideGuidingArrow(player)

					end
			end
		end
	end)
end

setupSeatMonitoring()

-- ============================================
-- Portal交互处理
-- ============================================

local function setupPortalInteraction()
	-- 等待Portal初始化
	while not PortalTransportManager:getPortalStatus().initialized do
		wait(0.1)
	end

	local portalStatus = PortalTransportManager:getPortalStatus()
	if not portalStatus.portalExists then
		warn("[NewPlayerEntry] Portal不存在")
		return
	end

	-- 监听Portal的ClickDetector点击
	local portal = Workspace:FindFirstChild("Portal")
	if not portal then return end

	-- 辅助函数：处理Portal交互的公共逻辑
	local function handlePortalInteraction(player)

		-- 🔧 V1.6: 检查游戏是否已经完成
		local gameInstance = _G.TableManager and _G.TableManager.getTableInstance(botTableId) or nil
		local gameCompleted = false
		local gameResult = "unknown"

		if gameInstance and gameInstance.gameState then
			-- 检查游戏是否已达到结果阶段
			if gameInstance.gameState.gamePhase == "result" then
				gameCompleted = true
				gameResult = "completed"
			elseif gameInstance.gameState.gamePhase == "waiting" then
				-- 游戏还没开始，允许传送但不标记完成
				gameResult = "not_started"
			else
				-- 游戏尚未完成，提示玩家等待
					gameResult = "incomplete"
			end
		else
			-- 无法获取游戏状态，可能是GameInstance尚未初始化
				gameResult = "unknown"
		end

		-- 🔧 CRITICAL FIX: 统一内存和持久化状态逻辑
		-- 只有游戏真正完成时才标记为已完成教程
		if gameCompleted then
			-- 标记为已完成教程（内存和持久化都设置）
			_G.TutorialCompleted[player.UserId] = true
			PlayerDataService:setTutorialCompleted(player, true)

			-- 🔧 V1.6: 移除教程座位，强制玩家前往下一个场景
			if TutorialEnvironmentManager then
				TutorialEnvironmentManager:removeTutorialSeat()
			end
		else
			-- 不设置任何完成标记，保持newPlayerCompleted = false
		end

		-- 埋点3：Portal交互
		TutorialAnalyticsService:trackPortalInteraction(player, gameResult)

		-- 🔧 V1.6新增：清理Portal指引箭头（在传送前）
		if TutorialGuideManager then
			TutorialGuideManager:hidePortalArrow(player)
			end

		-- 触发传送
		task.delay(1, function()
			if player and player.Parent then
				PortalTransportManager:teleportToMainPlace(player)
			end
		end)
	end

	-- ClickDetector处理
	local clickDetector = nil
	for _, child in pairs(portal:GetDescendants()) do
		if child:IsA("ClickDetector") then
			clickDetector = child
			break
		end
	end

	if clickDetector then
		clickDetector.MouseClick:Connect(function(player)
				handlePortalInteraction(player)
		end)
	end

	-- 🔧 V1.6新增：ProximityPrompt处理（支持长按E键交互）
	-- 找到交互占位块上的ProximityPrompt，绑定Triggered事件
	local promptPart = portal:FindFirstChild("TutorialPromptPart")
	if promptPart then
		local prompt = promptPart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
					handlePortalInteraction(player)
			end)
			else
			warn("[NewPlayerEntry] ⚠️ 交互占位块上未找到ProximityPrompt")
		end
	else
		warn("[NewPlayerEntry] ⚠️ Portal上未找到交互占位块 TutorialPromptPart")
	end
end

setupPortalInteraction()

print("[NewPlayerEntry] ✓ 新手场景已完全初始化")
