-- 脚本名称: CountdownClient
-- 脚本作用: V1.4倒计时功能客户端UI控制器
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts
-- 版本: V1.4

local CountdownClient = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local countdownEvent = nil

-- 延迟获取CountdownEvent，避免无限等待
local function getCountdownEvent()
    if not countdownEvent then
        countdownEvent = remoteEventsFolder:FindFirstChild("CountdownEvent")
        if not countdownEvent then
            -- 如果不存在，创建一个临时的（服务端会创建正式的）
            warn("CountdownClient: CountdownEvent不存在，等待服务端创建...")
            return nil
        end
    end
    return countdownEvent
end

-- 倒计时状态
local countdownState = {
    active = false,
    countdownType = nil,
    currentUI = nil,
    progressBar = nil,
    timeLabel = nil,
    progressTween = nil
}

-- UI路径映射
local UI_PATHS = {
    poison_phase = {
        container = "Confirm.ConfirmTips",
        progressBg = "ProgressBg",
        progressBar = "ProgressBar",
        timeLabel = "Time"
    },
    selection_phase = {
        container = "Confirm.SelectTips",
        progressBg = "ProgressBg",
        progressBar = "ProgressBar",
        timeLabel = "Time"
    }
}

-- 获取UI元素
local function getUIElements(countdownType)
    local playerGui = player:WaitForChild("PlayerGui")

    local uiPath = UI_PATHS[countdownType]
    if not uiPath then
        warn("CountdownClient: 未知的倒计时类型: " .. tostring(countdownType))
        return nil
    end

    -- 解析UI路径
    local containerPath = uiPath.container:split(".")
    local container = playerGui

    for _, pathPart in ipairs(containerPath) do
        container = container:FindFirstChild(pathPart)
        if not container then
            warn("CountdownClient: 找不到UI容器路径: " .. uiPath.container)
            return nil
        end
    end

    -- 获取进度条背景
    local progressBg = container:FindFirstChild(uiPath.progressBg)
    if not progressBg then
        warn("CountdownClient: 找不到进度条背景: " .. uiPath.progressBg)
        return nil
    end

    -- 获取进度条
    local progressBar = progressBg:FindFirstChild(uiPath.progressBar)
    if not progressBar then
        warn("CountdownClient: 找不到进度条: " .. uiPath.progressBar)
        return nil
    end

    -- 获取时间标签
    local timeLabel = container:FindFirstChild(uiPath.timeLabel)
    if not timeLabel then
        warn("CountdownClient: 找不到时间标签: " .. uiPath.timeLabel)
        return nil
    end

    return {
        container = container,
        progressBg = progressBg,
        progressBar = progressBar,
        timeLabel = timeLabel
    }
end

-- 启动倒计时显示
function CountdownClient.startCountdown(data)
    if not data then
        warn("CountdownClient.startCountdown: 数据为空")
        return
    end

    local countdownType = data.countdownType
    if not countdownType then
        warn("CountdownClient.startCountdown: 倒计时类型为空")
        return
    end


    -- 停止当前倒计时（如果有）
    CountdownClient.stopCountdown()

    -- 获取UI元素
    local uiElements = getUIElements(countdownType)
    if not uiElements then
        return
    end

    -- 设置状态
    countdownState.active = true
    countdownState.countdownType = countdownType
    countdownState.currentUI = uiElements
    countdownState.progressBar = uiElements.progressBar
    countdownState.timeLabel = uiElements.timeLabel

    -- 显示UI元素
    uiElements.progressBg.Visible = true
    uiElements.timeLabel.Visible = true

    -- 初始化进度条
    uiElements.progressBar.Size = UDim2.new(0, 0, 1, 0) -- 开始时长度为0

    -- 初始化时间显示
    uiElements.timeLabel.Text = "15"
    uiElements.timeLabel.TextColor3 = Color3.new(1, 1, 1) -- 默认白色

end

-- 更新倒计时显示
function CountdownClient.updateCountdown(data)
    if not countdownState.active or not countdownState.currentUI then
        return
    end

    if not data then
        warn("CountdownClient.updateCountdown: 数据为空")
        return
    end

    local timeString = data.timeString or "00"
    local progressRatio = data.progressRatio or 0
    local isWarningPhase = data.isWarningPhase or false

    -- 更新时间显示
    if countdownState.timeLabel then
        countdownState.timeLabel.Text = timeString

        -- 警告阶段变红色
        if isWarningPhase then
            countdownState.timeLabel.TextColor3 = Color3.new(1, 0, 0) -- 红色
        else
            countdownState.timeLabel.TextColor3 = Color3.new(1, 1, 1) -- 白色
        end
    end

    -- 更新进度条 (progressRatio: 1.0=开始, 0.0=结束)
    if countdownState.progressBar then
        -- 停止之前的动画
        if countdownState.progressTween then
            countdownState.progressTween:Cancel()
        end

        -- 计算进度条长度 (从左到右填充，所以是 1 - progressRatio)
        local fillRatio = 1 - progressRatio

        -- 创建平滑的进度条动画
        countdownState.progressTween = TweenService:Create(
            countdownState.progressBar,
            TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
            {Size = UDim2.new(fillRatio, 0, 1, 0)}
        )
        countdownState.progressTween:Play()
    end
end

-- 停止倒计时显示
function CountdownClient.stopCountdown(data)
    if not countdownState.active then
        return
    end


    -- 停止动画
    if countdownState.progressTween then
        countdownState.progressTween:Cancel()
        countdownState.progressTween = nil
    end

    -- 隐藏UI元素
    if countdownState.currentUI then
        if countdownState.currentUI.progressBg then
            countdownState.currentUI.progressBg.Visible = false
        end
        if countdownState.currentUI.timeLabel then
            countdownState.currentUI.timeLabel.Visible = false
        end
    end

    -- 重置状态
    countdownState.active = false
    countdownState.countdownType = nil
    countdownState.currentUI = nil
    countdownState.progressBar = nil
    countdownState.timeLabel = nil
end

-- 处理倒计时完成
function CountdownClient.onCountdownComplete(data)

    -- 自动停止显示
    CountdownClient.stopCountdown(data)
end

-- 设置RemoteEvent处理
function CountdownClient.setupRemoteEvents()
    -- 使用延迟连接，等待CountdownEvent可用
    local function tryConnect()
        local event = getCountdownEvent()
        if event then
            event.OnClientEvent:Connect(function(action, data)
                if action == "updateCountdown" then
                    -- 如果是第一次更新，先启动倒计时
                    if not countdownState.active and data and data.countdownType then
                        CountdownClient.startCountdown(data)
                    end
                    CountdownClient.updateCountdown(data)
                elseif action == "stopCountdown" then
                    CountdownClient.stopCountdown(data)
                elseif action == "countdownComplete" then
                    CountdownClient.onCountdownComplete(data)
                end
            end)
            return true
        end
        return false
    end

    -- 立即尝试连接
    if not tryConnect() then
        -- 如果失败，等待CountdownEvent创建
        local connection
        connection = remoteEventsFolder.ChildAdded:Connect(function(child)
            if child.Name == "CountdownEvent" and child:IsA("RemoteEvent") then
                connection:Disconnect()
                wait(0.1) -- 短暂等待确保服务端完全设置好
                tryConnect()
            end
        end)
    end
end

-- 初始化
function CountdownClient.initialize()
    CountdownClient.setupRemoteEvents()
end

-- 启动客户端控制器
CountdownClient.initialize()

return CountdownClient