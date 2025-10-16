-- 脚本名称: LeaveButtonClient V1.3
-- 脚本作用: 客户端Leave按钮点击处理器
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts
-- 功能：监听Leave按钮点击，通过RemoteEvent发送给服务端处理

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- 等待RemoteEvents和GUI
local function initialize()
    -- 等待RemoteEvents文件夹
    local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
    if not remoteEventsFolder then
        warn("❌ LeaveButtonClient: RemoteEvents文件夹不存在")
        return
    end

    -- 等待或创建LeaveButtonControl RemoteEvent
    local leaveButtonControlEvent = remoteEventsFolder:FindFirstChild("LeaveButtonControl")
    if not leaveButtonControlEvent then
        -- 如果不存在，先尝试等待服务端创建
        leaveButtonControlEvent = remoteEventsFolder:WaitForChild("LeaveButtonControl", 15)

        if not leaveButtonControlEvent then
            warn("❌ LeaveButtonClient: LeaveButtonControl RemoteEvent不存在")
            return
        end
    end

    -- 等待玩家GUI
    local playerGui = player:WaitForChild("PlayerGui")

    -- 设置Leave按钮监听
    local function setupLeaveButton()
        -- 等待Leave GUI
        local leaveGui = playerGui:WaitForChild("Leave", 10)
        if not leaveGui then
            warn("❌ LeaveButtonClient: Leave GUI不存在")
            return
        end

        local leaveBtnBg = leaveGui:WaitForChild("LeaveBtnBg", 5)
        if not leaveBtnBg then
            warn("❌ LeaveButtonClient: LeaveBtnBg不存在")
            return
        end

        local leaveBtn = leaveBtnBg:WaitForChild("LeaveBtn", 5)
        if not leaveBtn then
            warn("❌ LeaveButtonClient: LeaveBtn不存在")
            return
        end

        -- 连接Leave按钮点击事件
        leaveBtn.MouseButton1Click:Connect(function()
            -- 发送点击事件到服务端
            pcall(function()
                leaveButtonControlEvent:FireServer("buttonClicked")
            end)
        end)
    end

    -- 设置按钮可见性控制
    local function setupVisibilityControl()
        leaveButtonControlEvent.OnClientEvent:Connect(function(action, data)
            if action == "setVisible" then
                local visible = data

                -- 等待Leave GUI（如果还没加载）
                local leaveGui = playerGui:FindFirstChild("Leave")
                if leaveGui then
                    leaveGui.Enabled = visible
                end
            end
        end)
    end

    -- 角色重生处理
    local function onCharacterAdded(character)
        -- 角色重生时重新设置按钮
        task.wait(2) -- 等待GUI重新加载
        setupLeaveButton()
    end

    -- 立即设置
    setupLeaveButton()
    setupVisibilityControl()

    -- 监听角色重生
    if player.Character then
        onCharacterAdded(player.Character)
    end
    player.CharacterAdded:Connect(onCharacterAdded)
end

-- 延迟初始化，确保所有系统加载完成
task.spawn(function()
    task.wait(1)
    initialize()
end)