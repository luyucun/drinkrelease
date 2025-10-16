-- 脚本名称: VictoryAnimationManager V1.3
-- 脚本作用: 重构版胜利动画管理器，严格按照V1.3需求实现
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService
-- V1.3需求：
--   1. 接触当前所坐的座位的坐下状态，变成站起来
--   2. 将玩家的移动和跳跃都设定为0，然后玩家开始播放庆祝动作（延迟等玩家站起来后等0.5秒再开始播放庆祝动作）
--   3. 庆祝动作播放结束后，恢复玩家的移动和跳跃为默认值
--   4. 仅执行以上逻辑即可，不要再去做其他的各种限制和赋予玩家效果的操作

local VictoryAnimationManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

-- 胜利音效RemoteEvent
local victoryAudioEvent = remoteEventsFolder:FindFirstChild("VictoryAudio")
if not victoryAudioEvent then
    victoryAudioEvent = Instance.new("RemoteEvent")
    victoryAudioEvent.Name = "VictoryAudio"
    victoryAudioEvent.Parent = remoteEventsFolder
end

-- 配置参数 - 简化版
local CONFIG = {
    DEFAULT_ANIMATION_ID = "rbxassetid://113375965758912",  -- 默认胜利动作
    ANIMATION_DURATION = 3.0,                              -- 动作播放时长（秒）
    DELAY_BEFORE_ANIMATION = 0.5,                          -- 站起来后延迟时间（秒）
    PRIORITY = Enum.AnimationPriority.Action4,             -- 动画优先级
    FADE_TIME = 0.1,                                       -- 淡入淡出时间

    -- 默认移动参数
    DEFAULT_WALK_SPEED = 16,
    DEFAULT_JUMP_POWER = 50,
    DEFAULT_JUMP_HEIGHT = 7.2
}

-- 播放状态追踪（防止重复播放）
local playingPlayers = {}  -- {[player] = {animationTrack, originalState}}

-- V1.1: 引入EmoteConfig用于获取动作配置
local EmoteConfig = nil

-- 获取玩家装备的庆祝动作ID
local function getPlayerEmoteAnimationId(player)
    if not player then
        return CONFIG.DEFAULT_ANIMATION_ID
    end

    -- 延迟加载EmoteConfig
    if not EmoteConfig then
        local success, module = pcall(function()
            return require(ReplicatedStorage:WaitForChild("EmoteConfig", 5))
        end)
        if success then
            EmoteConfig = module
        else
            warn("VictoryAnimationManager: 无法加载EmoteConfig，使用默认动作")
            return CONFIG.DEFAULT_ANIMATION_ID
        end
    end

    -- 尝试从EmoteDataManager获取装备的动作ID
    local equippedEmoteId = 1001  -- 默认动作ID

    if _G.EmoteDataManager and _G.EmoteDataManager.getEquippedEmote then
        equippedEmoteId = _G.EmoteDataManager.getEquippedEmote(player)
    else
        warn("VictoryAnimationManager: EmoteDataManager未加载，使用默认动作")
    end

    -- 获取动作配置
    local emoteInfo = EmoteConfig.getEmoteInfo(equippedEmoteId)
    if emoteInfo and emoteInfo.animationId then
        local animationId = emoteInfo.animationId

        -- 验证动画ID格式
        if type(animationId) ~= "string" then
            warn("VictoryAnimationManager: 动画ID类型无效，使用默认动作")
            return CONFIG.DEFAULT_ANIMATION_ID
        end

        -- 检查是否包含错误信息
        if animationId:find("<error:") or animationId:find("unknown AssetId") then
            warn("VictoryAnimationManager: 动画ID包含错误信息，使用默认动作")
            return CONFIG.DEFAULT_ANIMATION_ID
        end

        -- 检查标准rbxassetid格式
        if not animationId:match("^rbxassetid://%d+$") then
            warn("VictoryAnimationManager: 动画ID格式无效，使用默认动作")
            return CONFIG.DEFAULT_ANIMATION_ID
        end

        return animationId
    end

    -- 获取失败，返回默认动作
    return CONFIG.DEFAULT_ANIMATION_ID
end

-- V1.3核心实现：播放胜利动作
function VictoryAnimationManager.playVictoryAnimation(player, options)
    -- 参数验证
    if not player or not player.Parent or not player.Character then
        warn("VictoryAnimationManager: 玩家参数无效")
        return false
    end

    -- 防止重复播放
    if playingPlayers[player] then
        warn("VictoryAnimationManager: 玩家 " .. player.Name .. " 已在播放动作")
        return false
    end

    local character = player.Character
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

    if not humanoid or not animator then
        warn("VictoryAnimationManager: 玩家 " .. player.Name .. " 缺少Humanoid或Animator")
        return false
    end

    print("🎭 开始为玩家 " .. player.Name .. " 播放胜利动作")

    -- 标记正在播放
    playingPlayers[player] = {}

    -- === V1.3步骤1：接触当前所坐的座位的坐下状态，变成站起来 ===
    print("📍 步骤1：强制玩家站起来")
    humanoid.Sit = false

    -- 等待玩家站起来（SeatPart会由引擎自动设置为nil）
    task.wait(0.1)

    -- === V1.3步骤2：延迟0.5秒，然后禁用移动并播放动作 ===
    task.spawn(function()
        -- 等待0.5秒让玩家站起来
        print("⏱️ 步骤2：等待0.5秒...")
        task.wait(CONFIG.DELAY_BEFORE_ANIMATION)

        -- 再次验证玩家状态（延迟期间可能离线）
        if not player or not player.Parent or not player.Character then
            warn("VictoryAnimationManager: 延迟期间玩家离线")
            playingPlayers[player] = nil
            return
        end

        -- 重新获取引用（角色可能重生）
        local currentCharacter = player.Character
        local currentHumanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
        local currentAnimator = currentHumanoid and currentHumanoid:FindFirstChildOfClass("Animator")

        if not currentHumanoid or not currentAnimator then
            warn("VictoryAnimationManager: 延迟后玩家缺少Humanoid或Animator")
            playingPlayers[player] = nil
            return
        end

        print("🚫 步骤2：禁用移动和跳跃")

        -- 保存原始移动参数
        local originalState = {
            walkSpeed = currentHumanoid.WalkSpeed > 0 and currentHumanoid.WalkSpeed or CONFIG.DEFAULT_WALK_SPEED,
            jumpPower = currentHumanoid.JumpPower > 0 and currentHumanoid.JumpPower or CONFIG.DEFAULT_JUMP_POWER,
            jumpHeight = currentHumanoid.JumpHeight > 0 and currentHumanoid.JumpHeight or CONFIG.DEFAULT_JUMP_HEIGHT
        }

        -- 禁用移动和跳跃
        currentHumanoid.WalkSpeed = 0
        currentHumanoid.JumpPower = 0
        currentHumanoid.JumpHeight = 0

        print("💾 已保存原始移动参数: WalkSpeed=" .. originalState.walkSpeed ..
              ", JumpPower=" .. originalState.jumpPower ..
              ", JumpHeight=" .. originalState.jumpHeight)

        -- 加载并播放动画
        local animationId = getPlayerEmoteAnimationId(player)
        local success, animationTrack = pcall(function()
            local animation = Instance.new("Animation")
            animation.AnimationId = animationId

            local track = currentAnimator:LoadAnimation(animation)
            animation:Destroy()  -- 立即销毁Animation对象

            track.Priority = CONFIG.PRIORITY
            track.Looped = false

            return track
        end)

        if not success or not animationTrack then
            warn("VictoryAnimationManager: 动画加载失败，恢复移动")
            -- 恢复移动参数
            currentHumanoid.WalkSpeed = originalState.walkSpeed
            currentHumanoid.JumpPower = originalState.jumpPower
            currentHumanoid.JumpHeight = originalState.jumpHeight
            playingPlayers[player] = nil
            return
        end

        -- 保存状态到全局
        playingPlayers[player] = {
            animationTrack = animationTrack,
            originalState = originalState,
            humanoid = currentHumanoid
        }

        print("🎬 开始播放胜利动画")

        -- 播放动画
        animationTrack:Play(CONFIG.FADE_TIME)

        -- 播放胜利音效（只有获胜玩家自己能听到）
        if victoryAudioEvent and player.Parent then
            pcall(function()
                victoryAudioEvent:FireClient(player, "play")
            end)
        end

        -- === V1.3步骤3：动作播放结束后，恢复玩家的移动和跳跃为默认值 ===
        task.delay(CONFIG.ANIMATION_DURATION, function()
            -- 验证玩家仍然有效
            if not player or not player.Parent then
                print("⚠️ 动作结束时玩家已离线")
                return
            end

            local playerData = playingPlayers[player]
            if not playerData then
                print("⚠️ 动作结束时未找到玩家数据")
                return
            end

            print("✅ 步骤3：恢复移动参数")

            -- 停止动画
            if playerData.animationTrack then
                pcall(function()
                    playerData.animationTrack:Stop(CONFIG.FADE_TIME)
                    playerData.animationTrack:Destroy()
                end)
            end

            -- 停止胜利音效
            if victoryAudioEvent and player.Parent then
                pcall(function()
                    victoryAudioEvent:FireClient(player, "stop")
                end)
            end

            -- 恢复移动参数
            if playerData.humanoid and playerData.humanoid.Parent then
                local humanoid = playerData.humanoid
                local originalState = playerData.originalState

                humanoid.WalkSpeed = originalState.walkSpeed
                humanoid.JumpPower = originalState.jumpPower
                humanoid.JumpHeight = originalState.jumpHeight

                print("🔄 已恢复移动参数: WalkSpeed=" .. originalState.walkSpeed ..
                      ", JumpPower=" .. originalState.jumpPower ..
                      ", JumpHeight=" .. originalState.jumpHeight)
            else
                warn("⚠️ 动作结束时Humanoid已无效")
            end

            -- 清除播放标记
            playingPlayers[player] = nil
            print("🎉 玩家 " .. player.Name .. " 胜利动作播放完成")
        end)
    end)

    return true
end

-- 强制停止玩家的动作播放（紧急情况使用）
function VictoryAnimationManager.forceStopAnimation(player)
    if not player then
        return
    end

    local playerData = playingPlayers[player]
    if not playerData then
        return  -- 没有在播放动作
    end

    print("🛑 强制停止玩家 " .. player.Name .. " 的胜利动作")

    -- 停止动画
    if playerData.animationTrack then
        pcall(function()
            playerData.animationTrack:Stop(0)  -- 立即停止
            playerData.animationTrack:Destroy()
        end)
    end

    -- 停止音效
    if victoryAudioEvent and player and player.Parent then
        pcall(function()
            victoryAudioEvent:FireClient(player, "stop")
        end)
    end

    -- 恢复移动参数
    if playerData.humanoid and playerData.humanoid.Parent and playerData.originalState then
        local humanoid = playerData.humanoid
        local originalState = playerData.originalState

        humanoid.WalkSpeed = originalState.walkSpeed
        humanoid.JumpPower = originalState.jumpPower
        humanoid.JumpHeight = originalState.jumpHeight
    elseif player.Character then
        -- 使用默认值恢复
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = CONFIG.DEFAULT_WALK_SPEED
            humanoid.JumpPower = CONFIG.DEFAULT_JUMP_POWER
            humanoid.JumpHeight = CONFIG.DEFAULT_JUMP_HEIGHT
        end
    end

    -- 清除播放标记
    playingPlayers[player] = nil
end

-- 检查玩家是否正在播放动作
function VictoryAnimationManager.isPlayingAnimation(player)
    return playingPlayers[player] ~= nil
end

-- 获取正在播放动作的玩家列表
function VictoryAnimationManager.getPlayingPlayers()
    local players = {}
    for player, _ in pairs(playingPlayers) do
        table.insert(players, player)
    end
    return players
end

-- 初始化
function VictoryAnimationManager.initialize()
    -- 监听玩家离开，清理播放状态
    game:GetService("Players").PlayerRemoving:Connect(function(player)
        if playingPlayers[player] then
            print("⚠️ 玩家 " .. player.Name .. " 离线时正在播放动作，执行清理")
            VictoryAnimationManager.forceStopAnimation(player)
        end
    end)

    -- 设置全局引用
    _G.VictoryAnimationManager = VictoryAnimationManager

    print("✅ VictoryAnimationManager V1.3 初始化完成")
end

return VictoryAnimationManager