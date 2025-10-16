-- 脚本名称: VictoryAudioClient
-- 脚本作用: 客户端胜利音效播放控制
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer/StarterPlayerScripts
-- 功能：
--   1. 监听服务端的VictoryAudio RemoteEvent
--   2. 播放/停止胜利音效（只有本地玩家听到）
--   3. 自动清理音效资源

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- 等待RemoteEvent
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local victoryAudioEvent = remoteEventsFolder:WaitForChild("VictoryAudio", 30)  -- 30秒超时

if not victoryAudioEvent then
	warn("⚠️ VictoryAudioClient: 未能加载 VictoryAudio RemoteEvent，音效功能将不可用")
	return
end

-- 音效配置
local VICTORY_SOUND_CONFIG = {
	SoundId = "rbxassetid://128188320751906",
	Volume = 0.5,
	PlaybackSpeed = 1.0,
	Looped = false
}

-- 当前播放的音效引用
local currentVictorySound = nil

-- 停止胜利音效（前置声明，供playVictorySound调用）
local stopVictorySound

-- 播放胜利音效
local function playVictorySound()
	-- 如果已经在播放，先停止
	if currentVictorySound then
		stopVictorySound()
	end

	-- 创建音效
	currentVictorySound = Instance.new("Sound")
	currentVictorySound.Name = "VictoryDanceSound"
	currentVictorySound.SoundId = VICTORY_SOUND_CONFIG.SoundId
	currentVictorySound.Volume = VICTORY_SOUND_CONFIG.Volume
	currentVictorySound.PlaybackSpeed = VICTORY_SOUND_CONFIG.PlaybackSpeed
	currentVictorySound.Looped = VICTORY_SOUND_CONFIG.Looped

	-- 附加到SoundService（只有本地玩家能听到）
	currentVictorySound.Parent = SoundService

	-- 播放音效
	currentVictorySound:Play()

	-- 监听播放结束事件（自动清理）
	currentVictorySound.Ended:Connect(function()
		if currentVictorySound then
			currentVictorySound:Destroy()
			currentVictorySound = nil
		end
	end)
end

-- 停止胜利音效
stopVictorySound = function()
	if currentVictorySound then
		currentVictorySound:Stop()
		currentVictorySound:Destroy()
		currentVictorySound = nil
	end
end

-- 监听服务端事件
victoryAudioEvent.OnClientEvent:Connect(function(action)
	if action == "play" then
		playVictorySound()
	elseif action == "stop" then
		stopVictorySound()
	else
		warn("VictoryAudioClient: 未知的音效控制指令: " .. tostring(action))
	end
end)

-- 玩家离开时清理
Players.PlayerRemoving:Connect(function(removingPlayer)
	if removingPlayer == player then
		stopVictorySound()
	end
end)
