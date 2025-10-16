-- 脚本名称: Bgm
-- 脚本作用: V1.2 更新版 - BGM播放脚本
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- 功能：初始化BGM播放（现已集成到BgmManager系统）

local SoundService = game:GetService("SoundService")

-- 查找BGM音频
local backgroundMusic = SoundService:FindFirstChild("bgm")

if backgroundMusic then
	-- 确保BGM属性正确
	if backgroundMusic:IsA("Sound") then
		backgroundMusic.Looped = true
		backgroundMusic.Volume = 0.5  -- 默认音量

		-- 开始播放
		if not backgroundMusic.IsPlaying then
			backgroundMusic:Play()
		end
	else
		warn("⚠️ Bgm: 'bgm'不是Sound对象")
	end
else
	warn("⚠️ Bgm: 未在SoundService中找到'bgm'音频")
	warn("   请在SoundService中添加名为'bgm'的Sound对象")
end

-- 注意：此脚本现在与BgmManager协同工作
-- BgmManager将接管音量控制和静音功能