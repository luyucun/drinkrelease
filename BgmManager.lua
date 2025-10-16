-- 脚本名称: BgmManager
-- 脚本作用: V1.2 BGM音乐管理器
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService
-- 功能：
--   1. 管理游戏BGM播放状态
--   2. 响应客户端静音请求
--   3. 为每个玩家维护独立的静音状态

local BgmManager = {}
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

-- BGM配置
local BGM_CONFIG = {
	SOUND_NAME = "bgm",           -- SoundService中BGM的名称
	DEFAULT_VOLUME = 0.5,         -- 默认音量
	FADE_DURATION = 0.2           -- 淡入淡出时长(秒)
}

-- 玩家状态管理
local playerMuteStates = {}  -- {[player] = boolean} 玩家静音状态
local bgmSound = nil         -- BGM音频对象引用

-- ============================================
-- BGM音频管理
-- ============================================

-- 查找并初始化BGM音频对象
local function initializeBgmSound()
	bgmSound = SoundService:FindFirstChild(BGM_CONFIG.SOUND_NAME)

	if bgmSound then
		-- 确保BGM是Sound对象
		if bgmSound:IsA("Sound") then
			-- 设置默认属性
			bgmSound.Volume = BGM_CONFIG.DEFAULT_VOLUME
			bgmSound.Looped = true

			-- 如果没有播放，开始播放
			if not bgmSound.IsPlaying then
				bgmSound:Play()
			end
		else
			warn("⚠️ BgmManager: '" .. BGM_CONFIG.SOUND_NAME .. "' 不是Sound对象")
			bgmSound = nil
		end
	else
		warn("⚠️ BgmManager: 未在SoundService中找到 '" .. BGM_CONFIG.SOUND_NAME .. "' 音频")
	end

	return bgmSound ~= nil
end

-- 更新BGM音量（根据静音状态）
local function updateBgmVolume()
	if not bgmSound then return end

	-- 计算应该播放BGM的玩家数量
	local activePlayers = 0
	local totalPlayers = 0

	for player, isMuted in pairs(playerMuteStates) do
		if player.Parent then  -- 玩家仍在线
			totalPlayers = totalPlayers + 1
			if not isMuted then
				activePlayers = activePlayers + 1
			end
		end
	end

	-- 如果有任何玩家未静音，播放BGM；否则静音
	local targetVolume = (activePlayers > 0) and BGM_CONFIG.DEFAULT_VOLUME or 0

	-- 应用音量（可以添加淡入淡出效果）
	bgmSound.Volume = targetVolume
end

-- ============================================
-- 公开API
-- ============================================

-- 设置玩家的静音状态
function BgmManager.setMuted(player, isMuted)
	if not player or not player.Parent then
		warn("BgmManager.setMuted: 无效的玩家对象")
		return false
	end

	-- 确保isMuted是布尔值
	isMuted = isMuted and true or false

	-- 更新状态
	local oldState = playerMuteStates[player]
	playerMuteStates[player] = isMuted

	-- 发送音量控制到客户端
	if oldState ~= isMuted then
		-- 通过RemoteEvent通知客户端更新本地音量
		local remoteEventsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents")
		if remoteEventsFolder then
			local bgmControlEvent = remoteEventsFolder:FindFirstChild("BgmControl")
			if bgmControlEvent then
				bgmControlEvent:FireClient(player, "setLocalVolume", isMuted and 0 or BGM_CONFIG.DEFAULT_VOLUME)
			end
		end
	end

	return true
end

-- 查询玩家的静音状态
function BgmManager.isMuted(player)
	if not player then
		return false
	end

	return playerMuteStates[player] or false
end

-- 获取BGM播放状态
function BgmManager.getBgmStatus()
	if not bgmSound then
		return {
			available = false,
			playing = false,
			volume = 0
		}
	end

	return {
		available = true,
		playing = bgmSound.IsPlaying,
		volume = bgmSound.Volume,
		soundId = bgmSound.SoundId
	}
end

-- 手动刷新BGM状态（用于调试）
function BgmManager.refreshBgm()
	return initializeBgmSound()
end

-- ============================================
-- 玩家生命周期
-- ============================================

-- 玩家加入处理
function BgmManager.onPlayerAdded(player)
	-- 初始化玩家为未静音状态
	playerMuteStates[player] = false
end

-- 玩家离开处理
function BgmManager.onPlayerRemoving(player)
	-- 移除玩家状态
	playerMuteStates[player] = nil
end

-- ============================================
-- 初始化
-- ============================================

-- 初始化BGM管理器
function BgmManager.initialize()
	-- 初始化BGM音频
	local bgmInitialized = initializeBgmSound()

	if bgmInitialized then
		-- 监听玩家事件
		Players.PlayerAdded:Connect(BgmManager.onPlayerAdded)
		Players.PlayerRemoving:Connect(BgmManager.onPlayerRemoving)

		-- 处理已在线玩家
		for _, player in pairs(Players:GetPlayers()) do
			BgmManager.onPlayerAdded(player)
		end

		-- 设置全局变量
		_G.BgmManager = BgmManager
	else
		warn("❌ BgmManager: BGM初始化失败，静音功能将不可用")
	end

	return bgmInitialized
end

return BgmManager