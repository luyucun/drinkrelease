-- 脚本名称: TypewriterEffect
-- 脚本作用: 为文本提供打字机显示效果
-- 脚本类型: ModuleScript
-- 放置位置: ReplicatedStorage

local TypewriterEffect = {}

-- 活跃的打字机效果协程（用于取消）
local activeCoroutines = {}
local coroutineIdCounter = 0  -- 协程ID计数器

-- 打字机效果配置
local DEFAULT_CHAR_DELAY = 0.03  -- 每个字符的显示延迟（秒）
local DEFAULT_SOUND_ENABLED = false  -- 是否播放打字音效

-- 播放打字机效果
-- @param textLabel: TextLabel实例
-- @param fullText: 要显示的完整文本
-- @param charDelay: 每个字符的延迟时间（可选，默认0.03秒）
-- @param onComplete: 完成回调函数（可选）
function TypewriterEffect.play(textLabel, fullText, charDelay, onComplete)
	if not textLabel or not textLabel:IsA("TextLabel") and not textLabel:IsA("TextButton") then
		warn("TypewriterEffect.play: 无效的TextLabel")
		return
	end

	-- 取消该TextLabel上之前的打字机效果
	TypewriterEffect.cancel(textLabel)

	charDelay = charDelay or DEFAULT_CHAR_DELAY

	-- 清空当前文本
	textLabel.Text = ""

	-- 生成唯一的协程ID
	coroutineIdCounter = coroutineIdCounter + 1
	local currentId = coroutineIdCounter

	-- 创建打字机协程
	local co = coroutine.create(function()
		-- 逐字符显示
		for i = 1, #fullText do
			-- 检查协程是否被取消（通过ID比较）
			local activeId = activeCoroutines[textLabel]
			if not activeId or activeId ~= currentId then
				return
			end

			textLabel.Text = string.sub(fullText, 1, i)
			wait(charDelay)
		end

		-- 清理协程引用
		local activeId = activeCoroutines[textLabel]
		if activeId and activeId == currentId then
			activeCoroutines[textLabel] = nil
		end

		-- 调用完成回调
		if onComplete then
			onComplete()
		end
	end)

	-- 记录活跃协程的ID
	activeCoroutines[textLabel] = currentId

	-- 启动协程
	coroutine.resume(co)
end

-- 快速播放打字机效果（更快的速度）
function TypewriterEffect.playFast(textLabel, fullText, onComplete)
	TypewriterEffect.play(textLabel, fullText, 0.015, onComplete)
end

-- 慢速播放打字机效果（更慢的速度，用于重要提示）
function TypewriterEffect.playSlow(textLabel, fullText, onComplete)
	TypewriterEffect.play(textLabel, fullText, 0.05, onComplete)
end

-- 立即显示文本（跳过打字机效果）
function TypewriterEffect.skip(textLabel, fullText)
	if not textLabel then return end

	-- 取消当前效果
	TypewriterEffect.cancel(textLabel)

	-- 直接显示完整文本
	textLabel.Text = fullText
end

-- 取消指定TextLabel的打字机效果
function TypewriterEffect.cancel(textLabel)
	if activeCoroutines[textLabel] then
		activeCoroutines[textLabel] = nil
	end
end

-- 取消所有活跃的打字机效果
function TypewriterEffect.cancelAll()
	activeCoroutines = {}
end

return TypewriterEffect