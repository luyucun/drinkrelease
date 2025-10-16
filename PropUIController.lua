-- 脚本名称: PropUIController
-- 脚本作用: 客户端道具UI显示和交互控制
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local PropUIController = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- 等待RemoteEvents
local function waitForRemoteEvents()
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 60) -- 增加到60秒
	if not remoteEventsFolder then
		warn("PropUIController: 60秒内未找到RemoteEvents文件夹")
		return nil
	end

	local propUpdateEvent = remoteEventsFolder:WaitForChild("PropUpdate", 30)
	local propUseEvent = remoteEventsFolder:WaitForChild("PropUse", 30)
	local propPurchaseEvent = remoteEventsFolder:WaitForChild("PropPurchase", 30)

	if not propUpdateEvent or not propUseEvent or not propPurchaseEvent then
		warn("PropUIController: 未能找到所需的PropRemoteEvents")
		return nil
	end

	return propUpdateEvent, propUseEvent, propPurchaseEvent
end

local propUpdateEvent, propUseEvent, propPurchaseEvent = waitForRemoteEvents()
if not propUpdateEvent then
	warn("PropUIController: RemoteEvents初始化失败，脚本将不会正常工作")
	return
end

-- UI状态
local uiState = {
	isVisible = false,
	propData = {
		[1] = 0, -- 毒药验证
		[2] = 0, -- 跳过选择
		[3] = 0  -- 清除毒药
	},
	propElements = {} -- 存储UI元素引用
}

-- 道具配置（与服务端同步）
local PROP_CONFIG = {
	[1] = {
		name = "Poison Detector",
		description = "Detect if a drink contains poison"
	},
	[2] = {
		name = "Turn Skip",
		description = "Skip your turn without drinking"
	},
	[3] = {
		name = "Poison Cleaner",
		description = "Remove opponent's poison from a drink"
	}
}

-- 获取道具UI引用
local function getPropUI()
	local playerGui = player:WaitForChild("PlayerGui")

	-- 等待Props GUI从StarterGui复制到PlayerGui
	local propsGui = playerGui:WaitForChild("Props", 10)
	if not propsGui then
		warn("未找到Props GUI，请检查StarterGui中是否存在Props ScreenGui")
		return nil
	end

	return propsGui
end

-- 获取道具框架引用
local function getPropFrames()
	local propsGui = getPropUI()
	if not propsGui then return nil end

	local listBg = propsGui:WaitForChild("ListBg", 5)
	if not listBg then
		warn("未找到Props GUI中的ListBg Frame")
		return nil
	end

	local propFrames = {}
	for i = 1, 3 do
		local propFrame = listBg:FindFirstChild("Prop0" .. i)
		if propFrame then
			propFrames[i] = propFrame
		else
			warn("未找到道具框架: Prop0" .. i)
		end
	end

	return propFrames
end

-- 初始化UI元素引用
function PropUIController.initializeUIElements()
	local propFrames = getPropFrames()
	if not propFrames then
		warn("初始化道具UI元素失败")
		return false
	end

	uiState.propElements = {}

	for propId = 1, 3 do
		local propFrame = propFrames[propId]
		if propFrame then
			uiState.propElements[propId] = {
				frame = propFrame,
				icon = propFrame:FindFirstChild("Icon"),
				propName = propFrame:FindFirstChild("PropName"),
				propNum = propFrame:FindFirstChild("PropNum"),
				useButton = propFrame:FindFirstChild("UseButton")
			}

			-- 设置道具名称
			if uiState.propElements[propId].propName then
				uiState.propElements[propId].propName.Text = PROP_CONFIG[propId].name
			end

		end
	end

	return true
end

-- 更新道具数量显示
function PropUIController.updatePropDisplay(propId, quantity)
	if not uiState.propElements[propId] then
		warn("PropUIController.updatePropDisplay: 道具 " .. propId .. " 的UI元素不存在")
		return
	end

	local elements = uiState.propElements[propId]

	-- 更新数量显示
	if elements.propNum then
		elements.propNum.Text = tostring(quantity)
	else
		warn("PropUIController.updatePropDisplay: 道具 " .. propId .. " 的 propNum 元素不存在")
	end

	-- 按钮永远显示USE
	if elements.useButton then
		elements.useButton.Text = "USE"
		if quantity > 0 then
			elements.useButton.BackgroundColor3 = Color3.new(0, 0.7, 0) -- 绿色，有道具
		else
			elements.useButton.BackgroundColor3 = Color3.new(0.7, 0.7, 0) -- 黄色，无道具（点击购买）
		end
	else
		warn("PropUIController.updatePropDisplay: 道具 " .. propId .. " 的 useButton 元素不存在")
	end
end

-- 更新所有道具显示
function PropUIController.updateAllPropsDisplay()
	for propId = 1, 3 do
		-- V1.9: 兼容V2数据结构
		local quantity = 0
		if uiState.propData.props then
			-- V2结构：{ props = {[1]=x, [2]=y, [3]=z}, hasReceivedNewPlayerGift = false, version = 2 }
			quantity = uiState.propData.props[propId] or 0
		else
			-- V1结构（兼容旧数据）：{ [1]=x, [2]=y, [3]=z }
			quantity = uiState.propData[propId] or 0
		end
		PropUIController.updatePropDisplay(propId, quantity)
	end
end

-- 显示道具界面
function PropUIController.showPropsUI()
	local propsGui = getPropUI()
	if not propsGui then return end

	propsGui.Enabled = true
	uiState.isVisible = true

	-- 更新显示
	PropUIController.updateAllPropsDisplay()

end

-- 隐藏道具界面
function PropUIController.hidePropsUI()
	local propsGui = getPropUI()
	if not propsGui then return end

	propsGui.Enabled = false
	uiState.isVisible = false

end

-- 处理道具使用按钮点击
function PropUIController.onPropButtonClick(propId)
	-- V1.9: 兼容V2数据结构
	local quantity = 0
	if uiState.propData.props then
		-- V2结构
		quantity = uiState.propData.props[propId] or 0
	else
		-- V1结构（兼容旧数据）
		quantity = uiState.propData[propId] or 0
	end

	if quantity > 0 then
		-- 有道具，检查是否可以使用

		-- 发送使用请求到服务器，服务器会检查是否轮到该玩家
		propUseEvent:FireServer("useProp", {propId = propId})
	else
		-- 没有道具，调用开发者商品购买
		propPurchaseEvent:FireServer("buyDeveloperProduct", {propId = propId})
	end
end

-- 设置按钮点击事件
function PropUIController.setupButtonEvents()
	for propId = 1, 3 do
		if uiState.propElements[propId] and uiState.propElements[propId].useButton then
			local button = uiState.propElements[propId].useButton

			button.MouseButton1Click:Connect(function()
				PropUIController.onPropButtonClick(propId)
			end)

		end
	end
end

-- 显示提示消息
function PropUIController.showMessage(message, color)
	-- 这里可以实现飘字效果或其他提示方式

	-- 简单的聊天提示（可以后续改为更好的UI提示）
	local chatService = game:GetService("StarterGui")
	chatService:SetCore("ChatMakeSystemMessage", {
		Text = message;
		Color = color or Color3.new(1, 1, 0); -- 默认黄色
		Font = Enum.Font.SourceSansBold;
		FontSize = Enum.FontSize.Size18;
	})
end

-- 处理服务端事件
function PropUIController.setupRemoteEvents()
	-- 道具数据更新
	propUpdateEvent.OnClientEvent:Connect(function(action, data)

		if action == "syncData" and data.propData then
			uiState.propData = data.propData
			PropUIController.updateAllPropsDisplay()
		elseif action == "showPropsUI" then
			PropUIController.showPropsUI()
		elseif action == "hidePropsUI" then
			PropUIController.hidePropsUI()
		else
		end
	end)

	-- 道具购买结果
	propPurchaseEvent.OnClientEvent:Connect(function(action, data)
		if action == "success" then
			PropUIController.showMessage("成功购买: " .. data.propName, Color3.new(0, 1, 0))
		elseif action == "failed" then
			PropUIController.showMessage("购买失败: " .. data.reason, Color3.new(1, 0, 0))
		end
	end)

	-- 道具使用结果
	propUseEvent.OnClientEvent:Connect(function(action, data)
		if action == "failed" then
			PropUIController.showMessage(data.reason, Color3.new(1, 1, 0))
		elseif action == "success" then
			PropUIController.showMessage("使用道具: " .. data.propName, Color3.new(0, 1, 0))
		end
	end)

end

-- 检查UI是否存在
function PropUIController.checkUIExists()
	local propsGui = getPropUI()
	if not propsGui then
		warn("Props GUI未找到，请检查StarterGui中是否存在Props ScreenGui")
		return false
	end

	local propFrames = getPropFrames()
	if not propFrames then
		warn("道具框架未找到，请检查Props GUI结构")
		return false
	end

	return true
end

-- 初始化道具UI控制器
function PropUIController.initialize()

	-- 等待玩家角色完全加载
	if not player.Character then
		player.CharacterAdded:Wait()
	end

	-- 额外等待确保UI完全复制
	wait(3)

	-- 检查UI是否存在
	if not PropUIController.checkUIExists() then
		warn("道具UI初始化失败，请检查StarterGui设置")
		return
	end

	-- 初始化UI元素
	if not PropUIController.initializeUIElements() then
		warn("道具UI元素初始化失败")
		return
	end

	-- 设置按钮事件
	PropUIController.setupButtonEvents()

	-- 设置远程事件监听
	PropUIController.setupRemoteEvents()

end

-- 启动控制器
PropUIController.initialize()

-- 导出到全局供其他脚本使用
_G.PropUIController = PropUIController

return PropUIController