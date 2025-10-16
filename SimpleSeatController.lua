-- 脚本名称: SimpleSeatController V1.3
-- 脚本作用: 简化的座位控制器，严格按照V1.3需求实现
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts
-- V1.3需求：
--   1. 玩家靠近座椅后，自动坐到椅子上，此时视为占了一个椅子的位置
--   2. 移除复杂的游戏状态逻辑和强制锁定机制
--   3. 与LeaveButtonManager配合，不冲突地处理座位状态
--   4. 简化为基础的座位检测和状态追踪

local SimpleSeatController = {}
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- 座位状态追踪
local seatState = {
    currentSeat = nil,          -- 当前所在座位
    isInGameSeat = false,       -- 是否在游戏座位上
    isLocked = false,           -- 是否锁定（禁止跳跃离开）
    originalJumpPower = 50,     -- 原始跳跃力
    originalJumpHeight = 7.2,   -- 原始跳跃高度
    heartbeatConnection = nil,  -- 座位维持连接
}

-- ====================================
-- 座位锁定管理
-- ====================================

-- 锁定座位（禁用跳跃，强制保持坐着）
local function lockSeat(seat)
    if seatState.isLocked or not seat then
        return
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    -- 保存原始跳跃参数
    seatState.originalJumpPower = humanoid.JumpPower > 0 and humanoid.JumpPower or 50
    seatState.originalJumpHeight = humanoid.JumpHeight > 0 and humanoid.JumpHeight or 7.2

    -- 设置锁定状态
    seatState.isLocked = true

    -- 禁用跳跃
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0

    -- 持续监控确保玩家保持坐着
    seatState.heartbeatConnection = RunService.Heartbeat:Connect(function()
        local currentCharacter = player.Character
        local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")

        if currentHumanoid and seatState.isLocked then
            -- 如果玩家试图站起来，强制坐下
            if not currentHumanoid.Sit then
                currentHumanoid.Sit = true
            end

            -- 确保跳跃持续被禁用
            if currentHumanoid.JumpPower ~= 0 then
                currentHumanoid.JumpPower = 0
            end
            if currentHumanoid.JumpHeight ~= 0 then
                currentHumanoid.JumpHeight = 0
            end
        end
    end)
end

-- 解锁座位（恢复跳跃，允许离开）
local function unlockSeat()
    if not seatState.isLocked then
        return
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if humanoid then
        -- 恢复跳跃参数
        humanoid.JumpPower = seatState.originalJumpPower
        humanoid.JumpHeight = seatState.originalJumpHeight

        -- 强制离开座位
        humanoid.Sit = false
    end

    -- 清理heartbeat连接
    if seatState.heartbeatConnection then
        seatState.heartbeatConnection:Disconnect()
        seatState.heartbeatConnection = nil
    end

    -- 重置锁定状态
    seatState.isLocked = false
end

-- Leave按钮点击处理
function SimpleSeatController.onLeaveButtonPressed()
    if seatState.isLocked and seatState.currentSeat then
        -- 解锁并离开座位
        unlockSeat()
        return true
    else
        return false
    end
end

-- ====================================
-- 核心功能：座位检测
-- ====================================

-- 判断是否是游戏座位
function SimpleSeatController.isGameSeat(seat)
    if not seat or not seat.Parent then
        return false
    end

    local parent = seat.Parent

    -- 检查椅子名称模式
    if parent.Name == "ClassicChair1" or parent.Name == "ClassicChair2" then
        -- 检查是否在游戏组中
        local grandParent = parent.Parent
        return grandParent and grandParent.Name:find("2player_group")
    end

    return false
end

-- 获取玩家当前的座位状态
function SimpleSeatController.getPlayerSeatInfo()
    local character = player.Character
    if not character then
        return {
            isInSeat = false,
            isInGameSeat = false,
            seat = nil
        }
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return {
            isInSeat = false,
            isInGameSeat = false,
            seat = nil
        }
    end

    local seat = humanoid.SeatPart
    local isInSeat = humanoid.Sit and seat ~= nil
    local isInGameSeat = isInSeat and SimpleSeatController.isGameSeat(seat)

    return {
        isInSeat = isInSeat,
        isInGameSeat = isInGameSeat,
        seat = seat
    }
end

-- ====================================
-- 事件处理
-- ====================================

-- 处理玩家坐下事件
local function onPlayerSeated(humanoid, active, seat)
    if active and seat then
        -- 玩家坐下
        local isGameSeat = SimpleSeatController.isGameSeat(seat)

        seatState.currentSeat = seat
        seatState.isInGameSeat = isGameSeat

        if isGameSeat then
            -- 立即锁定座位，禁用跳跃
            task.wait(0.1) -- 等待坐下稳定
            lockSeat(seat)

            -- V1.3: 通知LeaveButtonManager更新按钮状态
            if _G.LeaveButtonManager and _G.LeaveButtonManager.onPlayerSeated then
                _G.LeaveButtonManager.onPlayerSeated(player)
            end
        end
    else
        -- 玩家离开座位
        local wasInGameSeat = seatState.isInGameSeat

        -- 如果是锁定状态下离开，解锁座位
        if seatState.isLocked then
            unlockSeat()
        end

        seatState.currentSeat = nil
        seatState.isInGameSeat = false

        if wasInGameSeat then
            -- V1.3: 通知LeaveButtonManager更新按钮状态
            if _G.LeaveButtonManager and _G.LeaveButtonManager.onPlayerLeftSeat then
                _G.LeaveButtonManager.onPlayerLeftSeat(player)
            end
        end
    end
end

-- ====================================
-- 座位检测系统设置
-- ====================================

local function setupSeatDetection()
    local function onCharacterAdded(character)
        -- 角色重生时清理所有状态
        if seatState.heartbeatConnection then
            seatState.heartbeatConnection:Disconnect()
            seatState.heartbeatConnection = nil
        end

        seatState.currentSeat = nil
        seatState.isInGameSeat = false
        seatState.isLocked = false

        local humanoid = character:WaitForChild("Humanoid")

        -- 监听座位状态变化
        humanoid.Seated:Connect(function(active, seat)
            onPlayerSeated(humanoid, active, seat)
        end)

        -- 监听角色死亡
        humanoid.Died:Connect(function()
            -- 死亡时清理状态
            if seatState.heartbeatConnection then
                seatState.heartbeatConnection:Disconnect()
                seatState.heartbeatConnection = nil
            end

            seatState.currentSeat = nil
            seatState.isInGameSeat = false
            seatState.isLocked = false
        end)
    end

    -- 处理当前角色
    if player.Character then
        onCharacterAdded(player.Character)
    end

    -- 监听角色重生
    player.CharacterAdded:Connect(onCharacterAdded)
end

-- ====================================
-- RemoteEvent通信（简化版）
-- ====================================

local function setupRemoteEvents()
    local replicatedStorage = game:GetService("ReplicatedStorage")

    -- 等待RemoteEvents文件夹
    local remoteEventsFolder = replicatedStorage:WaitForChild("RemoteEvents", 10)
    if not remoteEventsFolder then
        warn("SimpleSeatController V1.3: RemoteEvents文件夹不存在")
        return
    end

    -- 座位控制事件（如果需要服务器端控制）
    local seatControlEvent = remoteEventsFolder:FindFirstChild("SeatControl")
    if seatControlEvent then
        seatControlEvent.OnClientEvent:Connect(function(action, data)
            if action == "querySeatStatus" then
                -- 服务器查询座位状态
                local seatInfo = SimpleSeatController.getPlayerSeatInfo()
                seatControlEvent:FireServer("seatStatusResponse", seatInfo)
            elseif action == "forceLeaveSeat" then
                -- 服务器强制离开座位
                local character = player.Character
                if character then
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        humanoid.Sit = false
                    end
                end
            elseif action == "handleLeaveButton" then
                -- 🔧 新增：处理Leave按钮点击
                SimpleSeatController.onLeaveButtonPressed()
            end
        end)
    end
end

-- ====================================
-- 状态查询接口
-- ====================================

-- 获取当前座位状态（供其他系统调用）
function SimpleSeatController.getCurrentSeatState()
    return {
        currentSeat = seatState.currentSeat,
        isInGameSeat = seatState.isInGameSeat,
        seatInfo = SimpleSeatController.getPlayerSeatInfo()
    }
end

-- 检查玩家是否在游戏座位上（供其他系统调用）
function SimpleSeatController.isPlayerInGameSeat()
    return seatState.isInGameSeat
end

-- 获取玩家当前座位（供其他系统调用）
function SimpleSeatController.getCurrentSeat()
    return seatState.currentSeat
end

-- ====================================
-- 调试接口
-- ====================================

function SimpleSeatController.debugInfo()
    local seatInfo = SimpleSeatController.getPlayerSeatInfo()
    return {
        -- 内部状态
        internalCurrentSeat = seatState.currentSeat and seatState.currentSeat.Name or "nil",
        internalIsInGameSeat = seatState.isInGameSeat,

        -- 实时状态
        realTimeIsInSeat = seatInfo.isInSeat,
        realTimeIsInGameSeat = seatInfo.isInGameSeat,
        realTimeSeat = seatInfo.seat and seatInfo.seat.Name or "nil",

        -- 角色状态
        hasCharacter = player.Character ~= nil,
        hasHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid") ~= nil
    }
end

-- ====================================
-- 初始化
-- ====================================

function SimpleSeatController.initialize()
    -- 设置座位检测
    setupSeatDetection()

    -- 设置RemoteEvent通信
    setupRemoteEvents()

    -- 设置全局引用
    _G.SimpleSeatController = SimpleSeatController
end

-- 自动初始化
task.spawn(function()
    SimpleSeatController.initialize()
end)

return SimpleSeatController