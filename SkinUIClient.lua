-- 脚本名称: SkinUIClient
-- 脚本作用: V2.0皮肤UI管理器,处理皮肤切换界面交互
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer → StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 等待UI加载
local skinGui = playerGui:WaitForChild("Skin", 10)
if not skinGui then
	warn("未找到StarterGui.Skin")
	return
end

local skinBg = skinGui:WaitForChild("SkinBg", 5)
if not skinBg then
	warn("未找到Skin.SkinBg")
	return
end

local scrollingFrame = skinBg:WaitForChild("ScrollingFrame", 5)
local skinTemplate = scrollingFrame and scrollingFrame:FindFirstChild("SkinTemplate")
local closeBtn = skinBg:FindFirstChild("CloseBtn")

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
local skinDataSyncEvent = remoteEventsFolder and remoteEventsFolder:WaitForChild("SkinDataSync", 5)
local skinEquipEvent = remoteEventsFolder and remoteEventsFolder:WaitForChild("SkinEquip", 5)
local skinPurchaseEvent = remoteEventsFolder and remoteEventsFolder:WaitForChild("SkinPurchase", 5)

-- 本地数据缓存
local ownedSkins = {}
local equippedSkin = nil

-- 从 ReplicatedStorage 加载 SkinConfig
local SKIN_CONFIG = {}
local function loadSkinConfig()
	local SkinConfigModule = ReplicatedStorage:FindFirstChild("SkinConfig")
	if SkinConfigModule then
		local success, result = pcall(function()
			local SkinConfig = require(SkinConfigModule)
			return SkinConfig.SKIN_CONFIG
		end)
		if success then
			SKIN_CONFIG = result
			-- 配置加载成功
		else
			warn("[SkinUIClient] 加载SkinConfig失败: " .. tostring(result))
		end
	else
		warn("[SkinUIClient] SkinConfig不在ReplicatedStorage中，使用本地备用配置")
	end
end

-- 尝试加载配置
loadSkinConfig()

-- 如果加载失败，使用备用配置
if next(SKIN_CONFIG) == nil then
	warn("[SkinUIClient] 使用本地备用配置")
	SKIN_CONFIG = {
		[1001] = {id = 1001, name = "Coffee", iconAssetId = "rbxassetid://1055218774"},
		[1002] = {id = 1002, name = "Cola", iconAssetId = "rbxassetid://1055218774"},
		[1003] = {id = 1003, name = "MangoTee", iconAssetId = "rbxassetid://1055218774"},
		[1004] = {id = 1004, name = "Fries", iconAssetId = "rbxassetid://1055218774"},
		[1005] = {id = 1005, name = "Sushi", iconAssetId = "rbxassetid://1055218774"},
		[1006] = {id = 1006, name = "Watermelon", iconAssetId = "rbxassetid://1055218774"},
		[1007] = {id = 1007, name = "Lobster", iconAssetId = "rbxassetid://1055218774"}
	}
end

local SkinUIClient = {}

-- ============================================
-- UI控制
-- ============================================

-- 打开皮肤弹框
function SkinUIClient.openSkinUI()
	if not skinBg then
		return
	end

	-- 如果界面已经打开,直接返回,避免重复刷新
	if skinBg.Visible then
		return
	end

	-- 刷新皮肤列表
	SkinUIClient.refreshSkinList()

	-- 显示弹框
	skinBg.Visible = true
end

-- 关闭皮肤弹框
function SkinUIClient.closeSkinUI()
	if not skinBg then
		return
	end

	skinBg.Visible = false
end

-- ============================================
-- 皮肤列表生成
-- ============================================

-- 清空皮肤列表
local function clearSkinList()
	if not scrollingFrame then
		return
	end

	local removeCount = 0
	for _, child in pairs(scrollingFrame:GetChildren()) do
		-- 删除以"Skin_"开头的皮肤卡片 (可能是Frame或ImageLabel)
		if child.Name:match("^Skin_%d+$") then
			child:Destroy()
			removeCount = removeCount + 1
		end
	end
end

-- 创建单个皮肤卡片
local function createSkinCard(skinId)
	if not skinTemplate then
		warn("SkinTemplate模板不存在")
		return
	end

	local skinInfo = SKIN_CONFIG[skinId]
	if not skinInfo then
		return
	end

	-- 复制模板
	local card = skinTemplate:Clone()
	card.Name = "Skin_" .. skinId
	card.Visible = true

	-- 设置Icon
	local icon = card:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = skinInfo.iconAssetId
	end

	-- 设置Name
	local nameLabel = card:FindFirstChild("Name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = skinInfo.name
	end

	-- 设置装备指示器(Right)
	local rightIndicator = card:FindFirstChild("Right")
	if rightIndicator and rightIndicator:IsA("ImageLabel") then
		rightIndicator.Visible = (equippedSkin == skinId)
	end

	-- 添加点击事件 - 统一使用透明按钮覆盖
	-- 先检查是否已存在点击按钮,避免重复创建
	local clickButton = card:FindFirstChild("ClickButton")
	if not clickButton then
		clickButton = Instance.new("TextButton")
		clickButton.Name = "ClickButton"
		clickButton.Size = UDim2.new(1, 0, 1, 0)
		clickButton.Position = UDim2.new(0, 0, 0, 0)
		clickButton.BackgroundTransparency = 1
		clickButton.Text = ""
		clickButton.ZIndex = 100  -- 提高ZIndex确保在最上层
		clickButton.Parent = card

		-- 只在创建时绑定一次事件
		clickButton.MouseButton1Click:Connect(function()
			SkinUIClient.onSkinCardClick(skinId)
		end)
	end

	card.Parent = scrollingFrame
	print(string.format("[SkinUIClient] ✅ 卡片已添加到ScrollingFrame: %s (父级: %s)",
		card.Name,
		card.Parent and card.Parent.Name or "nil"))
	return card
end

-- 刷新皮肤列表
function SkinUIClient.refreshSkinList()
	if not scrollingFrame then
		return
	end

	print(string.format("[SkinUIClient] 刷新皮肤列表: 拥有%d个皮肤", #ownedSkins))

	-- 清空现有列表
	clearSkinList()

	-- 如果没有拥有的皮肤,显示空状态
	if #ownedSkins == 0 then
		return
	end

	-- 按ID排序
	local sortedSkins = {}
	for _, skinId in ipairs(ownedSkins) do
		table.insert(sortedSkins, skinId)
	end
	table.sort(sortedSkins)

	-- 生成皮肤卡片
	for _, skinId in ipairs(sortedSkins) do
		print(string.format("[SkinUIClient] 创建皮肤卡片: ID=%d", skinId))
		createSkinCard(skinId)
	end

	-- 更新ScrollingFrame的CanvasSize
	-- 从SkinTemplate读取实际高度
	local cardHeight = 100  -- 默认值
	local spacing = 10

	if skinTemplate then
		local templateSize = skinTemplate.Size
		if templateSize then
			cardHeight = templateSize.Y.Offset  -- 使用实际高度
		end
	end

	-- 如果ScrollingFrame有UIListLayout,让它自动计算
	local uiListLayout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if uiListLayout then
		-- UIListLayout会自动计算CanvasSize,不需要手动设置
	else
		-- 手动计算CanvasSize
		local cardCount = #sortedSkins
		scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, cardCount * (cardHeight + spacing))
	end
end

-- ============================================
-- 皮肤切换逻辑
-- ============================================

-- 处理皮肤卡片点击
function SkinUIClient.onSkinCardClick(skinId)
	-- 如果已经装备,不需要切换
	if equippedSkin == skinId then
		return
	end

	-- 发送切换请求到服务端
	if skinEquipEvent then
		skinEquipEvent:FireServer("equip", {skinId = skinId})
	end
end

-- 更新装备指示器
local function updateEquippedIndicator(newEquippedSkin)
	if not scrollingFrame then
		return
	end

	-- 更新本地缓存
	equippedSkin = newEquippedSkin

	-- 遍历所有皮肤卡片,更新Right显示
	for _, child in pairs(scrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child.Name:match("^Skin_") then
			local skinId = tonumber(child.Name:match("%d+"))
			local rightIndicator = child:FindFirstChild("Right")
			if rightIndicator and rightIndicator:IsA("ImageLabel") then
				rightIndicator.Visible = (equippedSkin == skinId)
			end
		end
	end
end

-- ============================================
-- 服务端通信
-- ============================================

-- 监听数据同步事件
if skinDataSyncEvent then
	skinDataSyncEvent.OnClientEvent:Connect(function(action, data)
		if action == "sync" and data then
			-- 更新本地数据
			ownedSkins = data.ownedSkins or {}
			equippedSkin = data.equippedSkin

			-- 如果皮肤弹框是打开的,刷新列表
			if skinBg and skinBg.Visible then
				SkinUIClient.refreshSkinList()
			end
		end
	end)
end

-- 监听装备成功事件
if skinEquipEvent then
	skinEquipEvent.OnClientEvent:Connect(function(action, data)
		if action == "equipSuccess" and data then
			-- 更新装备指示器
			updateEquippedIndicator(data.equippedSkin)
		elseif action == "equipFailed" and data then
			-- 装备失败处理
			if data.reason == "in_game" then
				-- 对局中不允许切换
				local StarterGui = game:GetService("StarterGui")
				StarterGui:SetCore("SendNotification", {
					Title = "Skin Switch",
					Text = "Cannot switch skin during a match",
					Duration = 3
				})
			end
		end
	end)
end

-- 监听购买成功事件(实时刷新UI)
if skinPurchaseEvent then
	skinPurchaseEvent.OnClientEvent:Connect(function(action, data)
		if action == "purchaseSuccess" and data then
			-- 更新本地数据
			ownedSkins = data.ownedSkins or {}
			equippedSkin = data.equippedSkin

			-- 如果皮肤弹框是打开的,刷新列表
			if skinBg and skinBg.Visible then
				SkinUIClient.refreshSkinList()
			end
		end
	end)
end

-- ============================================
-- 初始化
-- ============================================

-- 监听关闭按钮
if closeBtn then
	closeBtn.MouseButton1Click:Connect(function()
		SkinUIClient.closeSkinUI()
	end)
end

-- 注册为全局对象,供MenuClient调用
_G.SkinUIClient = SkinUIClient

return SkinUIClient
