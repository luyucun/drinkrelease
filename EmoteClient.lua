-- 脚本名称: EmoteClient
-- 脚本作用: 客户端跳舞动作UI控制，处理界面显示、动作切换
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer.StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 引入配置
local EmoteConfig = require(ReplicatedStorage:WaitForChild("EmoteConfig"))

-- UI引用
local emoteGui = nil
local emoteBg = nil
local scrollingFrame = nil
local emoteTemplate = nil
local closeButton = nil

-- 数据缓存
local ownedEmotes = {}
local equippedEmote = 1001

-- RemoteEvents
local remoteEventsFolder = nil
local emoteDataSyncEvent = nil
local emoteEquipEvent = nil

-- UI卡片缓存
local emoteCards = {}

-- ============================================
-- 前向声明（Forward Declarations）
-- ============================================

-- 🔧 修复：前向声明解决函数相互引用的蓝色波浪线问题
local refreshEmoteUI
local updateEquipIndicators
local equipEmote
local showEmoteUI
local hideEmoteUI

-- ============================================
-- RemoteEvents初始化
-- ============================================

local function initializeRemoteEvents()
	remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEventsFolder then
		warn("EmoteClient: RemoteEvents文件夹不存在")
		return false
	end

	emoteDataSyncEvent = remoteEventsFolder:WaitForChild("EmoteDataSync", 10)
	if not emoteDataSyncEvent then
		warn("EmoteClient: EmoteDataSync RemoteEvent不存在")
		return false
	end

	emoteEquipEvent = remoteEventsFolder:WaitForChild("EmoteEquip", 10)
	if not emoteEquipEvent then
		warn("EmoteClient: EmoteEquip RemoteEvent不存在")
		return false
	end

	return true
end

-- ============================================
-- UI初始化
-- ============================================

local function initializeUI()
	-- 等待EmoteGui
	emoteGui = playerGui:WaitForChild("Emote", 10)
	if not emoteGui then
		warn("EmoteClient: 未找到StarterGui.Emote")
		return false
	end

	-- 获取UI元素
	emoteBg = emoteGui:WaitForChild("EmoteBg", 10)
	if not emoteBg then
		warn("EmoteClient: 未找到EmoteBg")
		return false
	end

	scrollingFrame = emoteBg:WaitForChild("ScrollingFrame", 10)
	if not scrollingFrame then
		warn("EmoteClient: 未找到ScrollingFrame")
		return false
	end

	emoteTemplate = scrollingFrame:WaitForChild("EmoteTemplate", 10)
	if not emoteTemplate then
		warn("EmoteClient: 未找到EmoteTemplate")
		return false
	end

	closeButton = emoteBg:WaitForChild("CloseBtn", 10)
	if not closeButton then
		warn("EmoteClient: 未找到CloseBtn")
		return false
	end

	-- 确保模板不可见
	emoteTemplate.Visible = false

	-- 默认隐藏界面
	emoteBg.Visible = false

	return true
end

-- ============================================
-- UI显示与隐藏
-- ============================================

-- 显示庆祝动作界面
showEmoteUI = function()
	if emoteBg then
		emoteBg.Visible = true
		-- 刷新UI显示
		refreshEmoteUI()
	end
end

-- 隐藏庆祝动作界面
hideEmoteUI = function()
	if emoteBg then
		emoteBg.Visible = false
	end
end

-- ============================================
-- 数据同步
-- ============================================

-- 处理服务器数据同步
local function handleDataSync(action, data)
	if action == "syncData" then
		if not data then
			warn("EmoteClient: 收到空数据")
			return
		end

		-- 更新本地缓存
		ownedEmotes = data.ownedEmotes or {1001}
		equippedEmote = data.equippedEmote or 1001

		-- 刷新UI（如果界面打开）
		if emoteBg and emoteBg.Visible then
			refreshEmoteUI()
		else
			-- 如果界面关闭，只更新装备标识（针对已缓存的卡片）
			updateEquipIndicators()
		end
	end
end

-- 请求数据同步
local function requestDataSync()
	if emoteDataSyncEvent then
		emoteDataSyncEvent:FireServer("requestSync")
	end
end

-- ============================================
-- UI生成与刷新
-- ============================================

-- 清理所有动作卡片
local function clearAllEmoteCards()
	for _, card in pairs(emoteCards) do
		if card and card.Parent then
			card:Destroy()
		end
	end
	emoteCards = {}
end

-- 🔧 修复：将 updateEquipIndicators 前置声明，供 handleDataSync 调用
-- 更新装备标识显示
updateEquipIndicators = function()
	for emoteId, card in pairs(emoteCards) do
		local rightMark = card:FindFirstChild("Right")
		if rightMark then
			rightMark.Visible = (emoteId == equippedEmote)
		end
	end
end

-- 创建单个动作卡片
local function createEmoteCard(emoteId, index)
	-- 获取动作信息
	local emoteInfo = EmoteConfig.getEmoteInfo(emoteId)
	if not emoteInfo then
		return nil
	end

	-- 克隆模板
	local card = emoteTemplate:Clone()
	card.Name = "EmoteCard_" .. emoteId
	card.Visible = true

	-- 设置图标
	local icon = card:FindFirstChild("Icon")
	if icon then
		icon.Image = emoteInfo.iconAssetId
	end

	-- 设置名称
	local nameLabel = card:FindFirstChild("Name")
	if nameLabel then
		nameLabel.Text = emoteInfo.name
	end

	-- 设置装备标识
	local rightMark = card:FindFirstChild("Right")
	if rightMark then
		rightMark.Visible = (emoteId == equippedEmote)
	end

	-- 设置按钮点击事件
	local button = card:FindFirstChild("Button")
	if not button then
		-- 如果没有Button，整个卡片作为按钮
		button = card
	end

	-- 添加点击事件
	if button:IsA("GuiButton") or button:IsA("TextButton") or button:IsA("ImageButton") then
		button.MouseButton1Click:Connect(function()
			-- 请求装备该动作
			equipEmote(emoteId)
		end)
	else
		-- 如果不是按钮，添加一个透明按钮覆盖层
		local overlayButton = Instance.new("TextButton")
		overlayButton.Name = "OverlayButton"
		overlayButton.Size = UDim2.new(1, 0, 1, 0)
		overlayButton.Position = UDim2.new(0, 0, 0, 0)
		overlayButton.BackgroundTransparency = 1
		overlayButton.Text = ""
		overlayButton.ZIndex = card.ZIndex + 10
		overlayButton.Parent = card

		overlayButton.MouseButton1Click:Connect(function()
			equipEmote(emoteId)
		end)
	end

	-- 设置布局顺序
	card.LayoutOrder = index

	-- 添加到ScrollingFrame
	card.Parent = scrollingFrame

	return card
end

-- 🔧 修复：将全局函数改为 local，避免与其他脚本冲突
-- 刷新整个UI
refreshEmoteUI = function()
	-- 清理旧卡片
	clearAllEmoteCards()

	-- 按ID排序拥有的动作
	table.sort(ownedEmotes)

	-- 为每个拥有的动作创建卡片
	for index, emoteId in ipairs(ownedEmotes) do
		local card = createEmoteCard(emoteId, index)
		if card then
			emoteCards[emoteId] = card
		end
	end
end

-- ============================================
-- 动作装备
-- ============================================

-- 🔧 修复：将全局函数改为 local，避免与其他脚本冲突
-- 装备动作
equipEmote = function(emoteId)
	if not emoteId then
		return
	end

	-- 检查是否已经装备
	if emoteId == equippedEmote then
		return
	end

	-- 检查是否拥有
	local hasEmote = false
	for _, id in ipairs(ownedEmotes) do
		if id == emoteId then
			hasEmote = true
			break
		end
	end

	if not hasEmote then
		warn("EmoteClient: 未拥有该动作")
		return
	end

	-- 发送装备请求到服务器
	if emoteEquipEvent then
		emoteEquipEvent:FireServer(emoteId)
	end
end

-- ============================================
-- 通知系统
-- ============================================

-- 🔧 修复：使用 StarterGui:SetCore 实现真实的右下角通知
local StarterGui = game:GetService("StarterGui")

-- 监听通知事件
local function setupNotificationListener()
	local showNotificationEvent = remoteEventsFolder:FindFirstChild("ShowNotification")
	if showNotificationEvent then
		showNotificationEvent.OnClientEvent:Connect(function(data)
			if not data or not data.message then
				return
			end

			-- 使用 Roblox 原生右下角通知系统
			local success, error = pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title = data.isSuccess and "✅ Success" or "❌ Failed",
					Text = data.message,
					Duration = data.duration or 3,
				})
			end)

			if not success then
				-- 如果 SetCore 失败（可能在启动时），回退到打印
				warn("EmoteClient: 通知显示失败: " .. tostring(error))
			end
		end)
	end
end

-- ============================================
-- 按钮事件
-- ============================================

local function setupButtonEvents()
	-- 关闭按钮
	if closeButton then
		closeButton.MouseButton1Click:Connect(function()
			hideEmoteUI()
		end)
	end
end

-- ============================================
-- 全局接口（供MenuController调用）
-- ============================================

-- 导出显示接口
_G.EmoteClient = {
	showUI = showEmoteUI,
	hideUI = hideEmoteUI,
	refreshUI = refreshEmoteUI
}

-- ============================================
-- 初始化
-- ============================================

local function initialize()
	-- 等待一下确保所有资源加载完成
	task.wait(1)

	-- 初始化RemoteEvents
	if not initializeRemoteEvents() then
		warn("EmoteClient: RemoteEvents初始化失败")
		return
	end

	-- 初始化UI
	if not initializeUI() then
		warn("EmoteClient: UI初始化失败")
		return
	end

	-- 设置按钮事件
	setupButtonEvents()

	-- 设置通知监听
	setupNotificationListener()

	-- 监听数据同步
	emoteDataSyncEvent.OnClientEvent:Connect(handleDataSync)

	-- 请求初始数据同步
	task.wait(0.5)
	requestDataSync()
end

-- 启动
initialize()
