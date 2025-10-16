-- 脚本名称: LeaveButtonManager V1.3
-- 脚本作用: 统一管理Leave按钮的显示和隐藏，严格按照V1.3需求实现
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService
-- V1.3需求：
--   1. 玩家靠近座椅后，自动坐到椅子上，此时视为占了一个椅子的位置，同时出现leave按钮
--   2. 玩家点击leave按钮可以离开座位
--   3. 进入对战流程后（包括注入毒药阶段和选择奶茶服下的阶段），需要隐藏leave按钮

local LeaveButtonManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Leave按钮控制RemoteEvent
local leaveButtonControlEvent = remoteEventsFolder:FindFirstChild("LeaveButtonControl")
if not leaveButtonControlEvent then
    leaveButtonControlEvent = Instance.new("RemoteEvent")
    leaveButtonControlEvent.Name = "LeaveButtonControl"
    leaveButtonControlEvent.Parent = remoteEventsFolder
end

-- 玩家Leave按钮状态追踪
local playerLeaveButtonState = {}  -- {[player] = {isVisible = boolean, shouldShow = boolean}}

-- ====================================
-- 核心功能：Leave按钮状态管理
-- ====================================

-- 检查玩家是否在游戏座位上
local function isPlayerInGameSeat(player)
    if not player or not player.Character then
        return false
    end

    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid or not humanoid.SeatPart then
        return false
    end

    local seat = humanoid.SeatPart
    local parent = seat.Parent

    if not parent then
        return false
    end

    -- 检查椅子名称模式
    if parent.Name == "ClassicChair1" or parent.Name == "ClassicChair2" then
        -- 检查是否在游戏组中
        local grandParent = parent.Parent
        return grandParent and grandParent.Name:find("2player_group")
    end

    return false
end

-- 检查当前游戏阶段
local function getCurrentGamePhase(player)
    -- 通过TableManager检测玩家所在桌子的游戏阶段
    if _G.TableManager and _G.TableManager.detectPlayerTable then
        local tableId = _G.TableManager.detectPlayerTable(player)
        if tableId then
            local gameInstance = _G.TableManager.getTableInstance(tableId)
            if gameInstance then
                return gameInstance.gameState.gamePhase
            end
        end
    end

    -- 备用方案：检查全局游戏阶段标志
    local gamePhaseFlag = ReplicatedStorage:FindFirstChild("GamePhaseFlag")
    if gamePhaseFlag and gamePhaseFlag.Value then
        return gamePhaseFlag.Value
    end

    return "waiting"  -- 默认为等待阶段
end

-- 计算玩家是否应该显示Leave按钮
local function shouldShowLeaveButton(player)
    local isInSeat = isPlayerInGameSeat(player)
    local gamePhase = getCurrentGamePhase(player)

    -- V1.3逻辑：在座位上 AND 游戏处于等待阶段
    local shouldShow = isInSeat and gamePhase == "waiting"

    return shouldShow
end

-- 更新单个玩家的Leave按钮状态
function LeaveButtonManager.updatePlayerLeaveButton(player)
    if not player or not player.Parent then
        return
    end

    local shouldShow = shouldShowLeaveButton(player)
    local currentState = playerLeaveButtonState[player]

    -- 初始化状态
    if not currentState then
        playerLeaveButtonState[player] = {
            isVisible = false,
            shouldShow = shouldShow
        }
        currentState = playerLeaveButtonState[player]
    end

    -- 如果状态发生变化，更新
    if currentState.shouldShow ~= shouldShow then
        currentState.shouldShow = shouldShow
        LeaveButtonManager.setPlayerLeaveButtonVisible(player, shouldShow)
    end
end

-- 设置玩家Leave按钮的可见性
function LeaveButtonManager.setPlayerLeaveButtonVisible(player, visible)
    if not player or not player.Parent then
        return
    end

    local currentState = playerLeaveButtonState[player]
    if not currentState then
        playerLeaveButtonState[player] = {
            isVisible = visible,
            shouldShow = visible
        }
        currentState = playerLeaveButtonState[player]
    end

    -- 如果状态没有变化，跳过
    if currentState.isVisible == visible then
        return
    end

    currentState.isVisible = visible

    -- 通过RemoteEvent通知客户端
    if leaveButtonControlEvent and player.Parent then
        pcall(function()
            leaveButtonControlEvent:FireClient(player, "setVisible", visible)
        end)
    end
end

-- 更新所有玩家的Leave按钮状态
function LeaveButtonManager.updateAllPlayersLeaveButton()
    for _, player in pairs(Players:GetPlayers()) do
        LeaveButtonManager.updatePlayerLeaveButton(player)
    end
end

-- 隐藏所有玩家的Leave按钮（对战开始时调用）
function LeaveButtonManager.hideAllLeaveButtons()
    for _, player in pairs(Players:GetPlayers()) do
        LeaveButtonManager.setPlayerLeaveButtonVisible(player, false)
    end
end

-- 根据游戏阶段更新所有Leave按钮
function LeaveButtonManager.onGamePhaseChanged(newPhase)
    if newPhase == "waiting" then
        -- 等待阶段：重新计算所有玩家的Leave按钮状态
        LeaveButtonManager.updateAllPlayersLeaveButton()
    else
        -- 非等待阶段：隐藏所有Leave按钮
        LeaveButtonManager.hideAllLeaveButtons()
    end
end

-- ====================================
-- 事件处理
-- ====================================

-- 处理玩家坐下事件
function LeaveButtonManager.onPlayerSeated(player)
    task.wait(0.1)  -- 等待座位状态稳定
    LeaveButtonManager.updatePlayerLeaveButton(player)
end

-- 处理玩家离开座位事件
function LeaveButtonManager.onPlayerLeftSeat(player)
    LeaveButtonManager.setPlayerLeaveButtonVisible(player, false)
end

-- 处理玩家离开游戏
function LeaveButtonManager.onPlayerRemoving(player)
    if playerLeaveButtonState[player] then
        playerLeaveButtonState[player] = nil
    end
end

-- ====================================
-- RemoteEvent处理
-- ====================================

-- 处理客户端Leave按钮点击
local function handleLeaveButtonClick(player)
    -- 验证玩家确实在座位上
    local isInSeat = isPlayerInGameSeat(player)

    if not isInSeat then
        return
    end

    -- 🔧 关键修复：通过RemoteEvent通知客户端SimpleSeatController处理Leave
    -- 因为座位锁定逻辑在客户端，需要客户端来解锁
    local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if remoteEventsFolder then
        local seatControlEvent = remoteEventsFolder:FindFirstChild("SeatControl")
        if not seatControlEvent then
            seatControlEvent = Instance.new("RemoteEvent")
            seatControlEvent.Name = "SeatControl"
            seatControlEvent.Parent = remoteEventsFolder
        end

        -- 通知客户端处理Leave按钮点击
        pcall(function()
            seatControlEvent:FireClient(player, "handleLeaveButton")
        end)
    end
end

-- 设置RemoteEvent处理
local function setupRemoteEvents()
    leaveButtonControlEvent.OnServerEvent:Connect(function(player, action, ...)
        if action == "buttonClicked" then
            handleLeaveButtonClick(player)
        end
    end)
end

-- ====================================
-- 游戏阶段监听
-- ====================================

-- 监听游戏阶段变化
local function setupGamePhaseMonitoring()
    local gamePhaseFlag = ReplicatedStorage:FindFirstChild("GamePhaseFlag")
    if not gamePhaseFlag then
        gamePhaseFlag = Instance.new("StringValue")
        gamePhaseFlag.Name = "GamePhaseFlag"
        gamePhaseFlag.Parent = ReplicatedStorage
    end

    gamePhaseFlag.Changed:Connect(function(newValue)
        if newValue and newValue ~= "" then
            LeaveButtonManager.onGamePhaseChanged(newValue)
        end
    end)
end

-- ====================================
-- 座位检测系统集成
-- ====================================

-- 监听所有玩家的座位状态变化
local function setupSeatMonitoring()
    local function onCharacterAdded(character)
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        local humanoid = character:WaitForChild("Humanoid")

        -- 监听Seated事件
        humanoid.Seated:Connect(function(active, seat)
            if active and seat then
                -- 玩家坐下
                task.spawn(function()
                    LeaveButtonManager.onPlayerSeated(player)
                end)
            else
                -- 玩家离开座位
                task.spawn(function()
                    LeaveButtonManager.onPlayerLeftSeat(player)
                end)
            end
        end)
    end

    -- 处理现有玩家
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character then
            onCharacterAdded(player.Character)
        end

        player.CharacterAdded:Connect(onCharacterAdded)
    end

    -- 处理新加入的玩家
    Players.PlayerAdded:Connect(function(player)
        if player.Character then
            onCharacterAdded(player.Character)
        end

        player.CharacterAdded:Connect(onCharacterAdded)
    end)
end

-- ====================================
-- 调试和状态查询
-- ====================================

-- 获取所有玩家的Leave按钮状态
function LeaveButtonManager.getAllPlayerStates()
    local states = {}
    for player, state in pairs(playerLeaveButtonState) do
        states[player.Name] = {
            isVisible = state.isVisible,
            shouldShow = state.shouldShow,
            isInSeat = isPlayerInGameSeat(player),
            gamePhase = getCurrentGamePhase(player)
        }
    end
    return states
end

-- 获取单个玩家的Leave按钮状态
function LeaveButtonManager.getPlayerState(player)
    if not player or not playerLeaveButtonState[player] then
        return nil
    end

    local state = playerLeaveButtonState[player]
    return {
        isVisible = state.isVisible,
        shouldShow = state.shouldShow,
        isInSeat = isPlayerInGameSeat(player),
        gamePhase = getCurrentGamePhase(player)
    }
end

-- ====================================
-- 初始化
-- ====================================

function LeaveButtonManager.initialize()
    -- 设置RemoteEvent处理
    setupRemoteEvents()

    -- 设置游戏阶段监听
    setupGamePhaseMonitoring()

    -- 设置座位监听
    setupSeatMonitoring()

    -- 监听玩家离开
    Players.PlayerRemoving:Connect(LeaveButtonManager.onPlayerRemoving)

    -- 设置全局引用
    _G.LeaveButtonManager = LeaveButtonManager
end

-- 自动初始化
task.spawn(function()
    task.wait(1) -- 等待其他系统加载
    LeaveButtonManager.initialize()
end)

return LeaveButtonManager