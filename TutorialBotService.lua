-- 脚本名称: TutorialBotService
-- 脚本作用: 管理新手教程中的NPC机器人代理，模拟真实玩家行为
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local TutorialBotService = {}
local Players = game:GetService("Players")

-- 机器人状态数据
local botInstance = {
	-- 机器人伪玩家对象
	playerProxy = nil,
	-- 机器人Character模型
	character = nil,
	-- 机器人是否已初始化
	isInitialized = false,
	-- 机器人所在的表ID
	tableId = nil,
	-- 机器人的选择决策状态
	decisionState = {
		lastPoisonChoice = nil,
		lastDrinkChoice = nil
	}
}

-- ============================================
-- 机器人代理对象构造
-- ============================================

local function createBotPlayerProxy(npcCharacter)
	-- 🔧 V1.6修复: 创建更完整的伪Player表对象，模拟真实玩家结构
	local proxy = {
		-- 基础属性
		Name = "NPC_Bot",
		UserId = 99999999,  -- 固定ID，便于识别
		Parent = game:GetService("Players"),  -- 伪装为Players服务中的对象
		DisplayName = "NPC_Bot",

		-- Character相关
		Character = npcCharacter,

		-- 🔧 新增：Player标准属性
		AccountAge = 0,
		MembershipType = Enum.MembershipType.None,

		-- 玩家GUI（创建更完善的容器，机器人不需要UI但需要兼容性）
		PlayerGui = Instance.new("Folder"),

		-- 🔧 新增：方法支持增强
		IsA = function(self, className)
			return className == "Player" or className == "Instance"
		end,

		-- 🔧 增强：用于兼容性检查
		FindFirstChild = function(self, name)
			if name == "Character" then return npcCharacter end
			if name == "PlayerGui" then
				-- 返回具有UI系统所需方法的容器
				return {
					Enabled = true,
					FindFirstChild = function() return nil end,
					WaitForChild = function() return nil end
				}
			end
			return nil
		end,

		-- 🔧 新增：WaitForChild支持
		WaitForChild = function(self, childName, timeout)
			return self:FindFirstChild(childName)
		end,

		-- 🔧 新增：确保所有Player检查都通过
		GetPropertyChangedSignal = function(self, propertyName)
			-- 返回一个简单的信号对象，避免连接错误
			return {
				Connect = function() return {} end,
				Wait = function() return end
			}
		end
	}

	return proxy
end

-- ============================================
-- 初始化机器人
-- ============================================

function TutorialBotService:initializeBot(npcCharacter, tableId)
	if self:isInitialized() then
		warn("TutorialBotService: 机器人已初始化，跳过重复初始化")
		return false
	end

	if not npcCharacter or not npcCharacter.Parent then
		warn("TutorialBotService: NPC模型不存在或已被销毁")
		return false
	end

	-- 创建伪玩家代理
	botInstance.playerProxy = createBotPlayerProxy(npcCharacter)
	botInstance.character = npcCharacter
	botInstance.tableId = tableId
	botInstance.isInitialized = true

	print("[TutorialBotService] ✓ 机器人已初始化，TableId: " .. tostring(tableId))

	return true
end

-- ============================================
-- 检查机器人状态
-- ============================================

function TutorialBotService:isInitialized()
	return botInstance.isInitialized
end

function TutorialBotService:getPlayerProxy()
	return botInstance.playerProxy
end

function TutorialBotService:getCharacter()
	return botInstance.character
end

function TutorialBotService:getTableId()
	return botInstance.tableId
end

-- ============================================
-- 识别机器人
-- ============================================

function TutorialBotService:isBot(player)
	if not player then return false end

	-- 通过UserId识别
	if player.UserId == 99999999 then
		return true
	end

	-- 通过代理对象识别
	if botInstance.playerProxy and player == botInstance.playerProxy then
		return true
	end

	return false
end

function TutorialBotService:isBotCharacter(character)
	if not character then return false end
	return character == botInstance.character
end

-- ============================================
-- 机器人决策逻辑
-- ============================================

-- 获取随机延迟（2-4秒）
local function getRandomDelay()
	return math.random(200, 400) / 100  -- 返回 2.00 到 4.00 秒
end

-- 获取机器人的毒药选择
function TutorialBotService:getBotPoisonChoice(availableIndices)
	-- 🔧 V1.6: 毒药选择阶段，所有奶茶都可用（1-24）
	-- 即使不传availableIndices，也使用完整的1-24范围
	if not availableIndices or #availableIndices == 0 then
		-- 毒药选择阶段通常允许从1-24中任选一个
		return math.random(1, 24)
	end

	local choice = availableIndices[math.random(1, #availableIndices)]
	botInstance.decisionState.lastPoisonChoice = choice

	return choice
end

-- 获取机器人的奶茶选择
function TutorialBotService:getBotDrinkChoice(availableIndices)
	-- 🔧 V1.6: 奶茶选择阶段，从可用的奶茶中选择
	if not availableIndices or #availableIndices == 0 then
		-- 如果没有提供可用列表，使用完整范围（理论上不应发生）
		warn("[TutorialBotService] 获取奶茶选择时没有可用列表，使用随机选择")
		return math.random(1, 24)
	end

	-- 从可用列表中随机选择一个奶茶
	local choice = availableIndices[math.random(1, #availableIndices)]
	botInstance.decisionState.lastDrinkChoice = choice

	return choice
end

-- ============================================
-- 机器人行为调度
-- ============================================

-- 调度机器人在毒药阶段的决策
function TutorialBotService:scheduleBotPoisonDecision(onDecisionCallback)
	local delay = getRandomDelay()

	task.delay(delay, function()
		if not self:isInitialized() then
			warn("TutorialBotService: 机器人未初始化，跳过毒药决策")
			return
		end

		-- 机器人随机选择一个毒药
		local choice = self:getBotPoisonChoice()

		-- 通知决策回调
		if onDecisionCallback then
			onDecisionCallback(choice)
		end
	end)
end

-- 调度机器人在饮料选择阶段的决策
function TutorialBotService:scheduleBotDrinkDecision(onDecisionCallback, availableDrinks)
	local delay = getRandomDelay()

	task.delay(delay, function()
		if not self:isInitialized() then
			warn("TutorialBotService: 机器人未初始化，跳过饮料决策")
			return
		end

		-- 🔧 V1.6: 传递可用饮料列表给决策函数
		local choice = self:getBotDrinkChoice(availableDrinks)

		-- 通知决策回调
		if onDecisionCallback then
			onDecisionCallback(choice)
		end
	end)
end

-- ============================================
-- 清理机器人资源
-- ============================================

function TutorialBotService:cleanup()
	if botInstance.playerProxy and botInstance.playerProxy.PlayerGui then
		pcall(function()
			botInstance.playerProxy.PlayerGui:Destroy()
		end)
	end

	botInstance.playerProxy = nil
	botInstance.character = nil
	botInstance.tableId = nil
	botInstance.isInitialized = false

	print("[TutorialBotService] ✓ 机器人资源已清理")
end

-- ============================================
-- 获取机器人信息（调试用）
-- ============================================

function TutorialBotService:getBotInfo()
	return {
		isInitialized = self:isInitialized(),
		tableId = botInstance.tableId,
		lastPoisonChoice = botInstance.decisionState.lastPoisonChoice,
		lastDrinkChoice = botInstance.decisionState.lastDrinkChoice,
		characterExists = botInstance.character ~= nil and botInstance.character.Parent ~= nil
	}
end

-- 🔧 CRITICAL FIX: Export to global for cross-script access
_G.TutorialBotService = TutorialBotService

return TutorialBotService
