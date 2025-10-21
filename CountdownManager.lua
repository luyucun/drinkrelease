-- 脚本名称: CountdownManager
-- 脚本作用: V1.4倒计时功能核心管理器，支持多桌子独立倒计时
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService
-- 版本: V1.4

local CountdownManager = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 倒计时配置
local COUNTDOWN_CONFIG = {
    POISON_PHASE_DURATION = 15,     -- 阶段3：毒药注入 15秒
    SELECTION_PHASE_DURATION = 15,  -- 阶段4：奶茶选择 15秒
    WARNING_TIME = 5,               -- 最后5秒红色警告
    UPDATE_INTERVAL = 0.1,          -- 100ms更新频率
    COUNTDOWN_PRECISION = 0.01      -- 倒计时精度（10ms）
}

-- 倒计时类型枚举
local COUNTDOWN_TYPES = {
    POISON_PHASE = "poison_phase",      -- 毒药注入阶段（共享倒计时）
    SELECTION_PHASE = "selection_phase"  -- 奶茶选择阶段（轮流倒计时）
}

-- 多桌子倒计时状态管理
local countdownStates = {} -- {[tableId] = CountdownState}

-- 单个桌子的倒计时状态数据结构
local function createNewCountdownState()
    return {
        active = false,
        countdownType = nil,
        duration = 0,
        remainingTime = 0,
        startTime = 0,
        players = {},               -- 参与倒计时的玩家列表
        currentPlayer = nil,        -- 当前轮到的玩家（selection阶段）
        isWarningPhase = false,     -- 是否进入警告阶段（最后5秒）
        onTimeoutCallback = nil,    -- 倒计时结束回调
        onUpdateCallback = nil,     -- 倒计时更新回调
        onWarningCallback = nil,    -- 进入警告阶段回调
        customData = {},            -- 自定义数据
        updateConnection = nil      -- RunService连接
    }
end

-- 获取或创建桌子的倒计时状态
local function getCountdownState(tableId)
    if not tableId then
        warn("CountdownManager.getCountdownState: tableId为空")
        return nil
    end

    if not countdownStates[tableId] then
        countdownStates[tableId] = createNewCountdownState()
    end

    return countdownStates[tableId]
end

-- 通过玩家获取桌子ID
local function getTableIdFromPlayer(player)
    if not player then return nil end

    -- 方法1: 使用TableManager检测
    if _G.TableManager and _G.TableManager.detectPlayerTable then
        local tableId = _G.TableManager.detectPlayerTable(player)
        if tableId then return tableId end
    end

    -- 方法2: 遍历所有倒计时状态查找
    for tableId, state in pairs(countdownStates) do
        for _, statePlayer in ipairs(state.players) do
            if statePlayer == player then
                return tableId
            end
        end
    end

    return nil
end

-- 清理桌子倒计时状态
function CountdownManager.cleanupTableState(tableId)
    if countdownStates[tableId] then
        -- 清理RunService连接
        local state = countdownStates[tableId]
        if state.updateConnection then
            state.updateConnection:Disconnect()
            state.updateConnection = nil
        end

        countdownStates[tableId] = nil
    end
end

-- 启动倒计时
function CountdownManager.startCountdown(tableId, countdownType, duration, players, options)
    if not tableId then
        warn("CountdownManager.startCountdown: tableId为空")
        return false
    end

    -- 验证倒计时类型是否有效（检查是否是COUNTDOWN_TYPES中的值）
    local isValidType = false
    for _, validType in pairs(COUNTDOWN_TYPES) do
        if countdownType == validType then
            isValidType = true
            break
        end
    end

    if not countdownType or not isValidType then
        warn("CountdownManager.startCountdown: 无效的倒计时类型: " .. tostring(countdownType))
        return false
    end

    if not duration or duration <= 0 then
        warn("CountdownManager.startCountdown: 无效的倒计时时长: " .. tostring(duration))
        return false
    end

    if not players or #players == 0 then
        warn("CountdownManager.startCountdown: 玩家列表为空")
        return false
    end

    local state = getCountdownState(tableId)
    if not state then
        warn("CountdownManager.startCountdown: 无法创建桌子 " .. tableId .. " 的倒计时状态")
        return false
    end

    -- 如果已经有倒计时在运行，先停止
    if state.active then
        CountdownManager.stopCountdown(tableId)
    end

    -- 设置倒计时状态
    state.active = true
    state.countdownType = countdownType
    state.duration = duration
    state.remainingTime = duration
    state.startTime = tick()
    state.players = players
    state.currentPlayer = options and options.currentPlayer or nil
    state.isWarningPhase = false
    state.customData = options and options.customData or {}

    -- 设置回调函数
    if options then
        state.onTimeoutCallback = options.onTimeout
        state.onUpdateCallback = options.onUpdate
        state.onWarningCallback = options.onWarning
    end


    -- 启动倒计时更新循环
    state.updateConnection = RunService.Heartbeat:Connect(function()
        CountdownManager.updateCountdown(tableId)
    end)

    -- 立即发送初始状态给客户端
    CountdownManager.sendCountdownUpdate(tableId)

    return true
end

-- 停止倒计时
function CountdownManager.stopCountdown(tableId)
    if not tableId then
        warn("CountdownManager.stopCountdown: tableId为空")
        return
    end

    local state = getCountdownState(tableId)
    if not state or not state.active then
        return
    end


    -- 断开更新连接
    if state.updateConnection then
        state.updateConnection:Disconnect()
        state.updateConnection = nil
    end

    -- 重置状态
    state.active = false
    state.remainingTime = 0
    state.isWarningPhase = false

    -- 通知客户端倒计时停止
    CountdownManager.sendCountdownStop(tableId)
end

-- 更新倒计时
function CountdownManager.updateCountdown(tableId)
    local state = getCountdownState(tableId)
    if not state or not state.active then
        return
    end

    local currentTime = tick()
    local elapsedTime = currentTime - state.startTime
    state.remainingTime = math.max(0, state.duration - elapsedTime)

    -- 检查是否进入警告阶段
    if not state.isWarningPhase and state.remainingTime <= COUNTDOWN_CONFIG.WARNING_TIME then
        state.isWarningPhase = true
        if state.onWarningCallback then
            state.onWarningCallback(tableId, state.remainingTime)
        end
    end

    -- 发送更新给客户端
    CountdownManager.sendCountdownUpdate(tableId)

    -- 调用更新回调
    if state.onUpdateCallback then
        state.onUpdateCallback(tableId, state.remainingTime)
    end

    -- 检查是否倒计时结束
    if state.remainingTime <= 0 then

        -- 保存回调函数（因为stopCountdown会清理状态）
        local timeoutCallback = state.onTimeoutCallback

        -- 停止倒计时
        CountdownManager.stopCountdown(tableId)

        -- 调用超时回调
        if timeoutCallback then
            timeoutCallback(tableId)
        end
    end
end

-- 发送倒计时更新给客户端
function CountdownManager.sendCountdownUpdate(tableId)
    local state = getCountdownState(tableId)
    if not state or not state.active then
        return
    end

    -- 计算时间显示格式 XX (秒)
    local seconds = math.floor(state.remainingTime)
    local timeString = string.format("%02d", seconds)

    -- 计算进度条比例 (1.0 = 开始, 0.0 = 结束)
    local progressRatio = state.remainingTime / state.duration

    local updateData = {
        tableId = tableId,
        countdownType = state.countdownType,
        remainingTime = state.remainingTime,
        timeString = timeString,
        progressRatio = progressRatio,
        isWarningPhase = state.isWarningPhase,
        currentPlayer = state.currentPlayer and state.currentPlayer.Name or nil,
        customData = state.customData
    }

    -- 发送给参与的玩家
    for _, player in ipairs(state.players) do
        if player and player.Parent then
            CountdownManager.fireCountdownEvent(player, "updateCountdown", updateData)
        end
    end
end

-- 发送倒计时停止给客户端
function CountdownManager.sendCountdownStop(tableId)
    local state = getCountdownState(tableId)
    if not state then
        return
    end

    local stopData = {
        tableId = tableId,
        countdownType = state.countdownType
    }

    -- 发送给参与的玩家
    for _, player in ipairs(state.players) do
        if player and player.Parent then
            CountdownManager.fireCountdownEvent(player, "stopCountdown", stopData)
        end
    end
end

-- 发送倒计时事件给客户端
function CountdownManager.fireCountdownEvent(player, action, data)
    -- 🔧 V1.6修复：检查是否是真实的Roblox Player对象（排除NPC）
    -- 避免向NPC（非Player实例）发送RemoteEvent导致的错误
    if typeof(player) ~= "Instance" or not player:IsA("Player") then
        -- NPC或无效对象，跳过发送
        return
    end

    local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if not remoteEventsFolder then
        warn("CountdownManager: RemoteEvents文件夹不存在")
        return
    end

    local countdownEvent = remoteEventsFolder:FindFirstChild("CountdownEvent")
    if not countdownEvent then
        -- 创建RemoteEvent
        countdownEvent = Instance.new("RemoteEvent")
        countdownEvent.Name = "CountdownEvent"
        countdownEvent.Parent = remoteEventsFolder
    end

    -- 发送给客户端
    pcall(function()
        countdownEvent:FireClient(player, action, data)
    end)
end

-- 获取倒计时状态
function CountdownManager.getCountdownInfo(tableId)
    if not tableId then
        return nil
    end

    local state = getCountdownState(tableId)
    if not state or not state.active then
        return nil
    end

    return {
        active = state.active,
        countdownType = state.countdownType,
        duration = state.duration,
        remainingTime = state.remainingTime,
        isWarningPhase = state.isWarningPhase,
        currentPlayer = state.currentPlayer,
        players = state.players
    }
end

-- 检查倒计时是否激活
function CountdownManager.isCountdownActive(tableId)
    if not tableId then
        return false
    end

    local state = getCountdownState(tableId)
    return state and state.active or false
end

-- 切换当前玩家（用于selection阶段轮流倒计时）
function CountdownManager.switchCurrentPlayer(tableId, newPlayer)
    if not tableId then
        warn("CountdownManager.switchCurrentPlayer: tableId为空")
        return false
    end

    local state = getCountdownState(tableId)
    if not state or not state.active then
        warn("CountdownManager.switchCurrentPlayer: 倒计时未激活")
        return false
    end

    if state.countdownType ~= COUNTDOWN_TYPES.SELECTION_PHASE then
        warn("CountdownManager.switchCurrentPlayer: 只有selection阶段支持切换玩家")
        return false
    end

    state.currentPlayer = newPlayer

    -- 立即发送更新
    CountdownManager.sendCountdownUpdate(tableId)
    return true
end

-- 重置倒计时（保持配置，重新开始计时）
function CountdownManager.resetCountdown(tableId, newDuration)
    if not tableId then
        warn("CountdownManager.resetCountdown: tableId为空")
        return false
    end

    local state = getCountdownState(tableId)
    if not state or not state.active then
        warn("CountdownManager.resetCountdown: 倒计时未激活")
        return false
    end

    -- 重置计时
    state.duration = newDuration or state.duration
    state.remainingTime = state.duration
    state.startTime = tick()
    state.isWarningPhase = false


    -- 立即发送更新
    CountdownManager.sendCountdownUpdate(tableId)
    return true
end

-- 获取预设配置
function CountdownManager.getConfig()
    return COUNTDOWN_CONFIG
end

function CountdownManager.getCountdownTypes()
    return COUNTDOWN_TYPES
end

-- 初始化
function CountdownManager.initialize()

    -- 立即创建CountdownEvent RemoteEvent
    local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if not remoteEventsFolder then
        remoteEventsFolder = Instance.new("Folder")
        remoteEventsFolder.Name = "RemoteEvents"
        remoteEventsFolder.Parent = ReplicatedStorage
    end

    local countdownEvent = remoteEventsFolder:FindFirstChild("CountdownEvent")
    if not countdownEvent then
        countdownEvent = Instance.new("RemoteEvent")
        countdownEvent.Name = "CountdownEvent"
        countdownEvent.Parent = remoteEventsFolder
    end

    -- 监听玩家离开事件，清理相关状态
    Players.PlayerRemoving:Connect(function(player)
        -- 从所有倒计时状态中移除该玩家
        for tableId, state in pairs(countdownStates) do
            for i = #state.players, 1, -1 do
                if state.players[i] == player then
                    table.remove(state.players, i)
                end
            end

            -- 如果是当前玩家，清除引用
            if state.currentPlayer == player then
                state.currentPlayer = nil
            end
        end
    end)
end

-- 启动管理器
CountdownManager.initialize()

-- 导出到全局供其他脚本使用
_G.CountdownManager = CountdownManager

return CountdownManager