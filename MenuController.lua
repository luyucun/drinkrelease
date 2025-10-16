-- 脚本名称: MenuController
-- 脚本作用: 客户端Menu界面显示/隐藏控制
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local MenuController = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- 等待RemoteEvent
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local menuControlEvent = remoteEventsFolder:WaitForChild("MenuControl", 10)  -- 等待最多10秒

-- 立即注册RemoteEvent监听器（同步执行，确保不会错过事件）
if menuControlEvent then
	menuControlEvent.OnClientEvent:Connect(function(action, data)
		if action == "setMenuVisibility" then
			MenuController.setMenuVisibility(data.visible)
		elseif action == "setSpecificMenuVisibility" then
			MenuController.setSpecificMenuVisibility(data)
		end
	end)
else
	warn("MenuController: MenuControl RemoteEvent未找到，创建备用监听器")
	-- 如果没找到，继续异步等待（备用方案）
	spawn(function()
		while not menuControlEvent do
			menuControlEvent = remoteEventsFolder:FindFirstChild("MenuControl")
			if not menuControlEvent then
				wait(0.1)
			end
		end

		-- 连接RemoteEvent
		menuControlEvent.OnClientEvent:Connect(function(action, data)
			if action == "setMenuVisibility" then
				MenuController.setMenuVisibility(data.visible)
			elseif action == "setSpecificMenuVisibility" then
				MenuController.setSpecificMenuVisibility(data)
			end
		end)
	end)
end

-- 设置Menu界面可见性
function MenuController.setMenuVisibility(visible)
	local playerGui = player:WaitForChild("PlayerGui")
	local menuGui = playerGui:FindFirstChild("Menu")

	if not menuGui then
		warn("MenuController: 未找到Menu ScreenGui")
		return
	end

	-- 查找目标按钮
	local imageButtonShop = menuGui:FindFirstChild("ImageButtonShop")
	local imageButtonSkin = menuGui:FindFirstChild("ImageButtonSkin")
	local imageButtonMoney = menuGui:FindFirstChild("ImageButtonMoney")  -- V2.0: 金币按钮
	local imageButtonWheel = menuGui:FindFirstChild("ImageButtonWheel")  -- V2.0: 转盘按钮
	local imageButtonEmote = menuGui:FindFirstChild("ImageButtonEmote")  -- V1.1: 庆祝动作按钮
	local newPlayerGiftButton = menuGui:FindFirstChild("NewPlayerGift")  -- V1.9: 新手礼包按钮

	-- 设置按钮可见性
	-- Shop/Wheel根据visible参数，Skin/Money/Emote始终显示

	if imageButtonShop then
		imageButtonShop.Visible = visible

		-- V1.8: 绑定商店按钮点击事件
		if visible then
			MenuController.bindShopButton(imageButtonShop)
		end
	else
		warn("MenuController: 未找到ImageButtonShop")
	end

	if imageButtonSkin then
		imageButtonSkin.Visible = true  -- V2.0: 皮肤按钮任何情况下都显示
	else
		warn("MenuController: 未找到ImageButtonSkin")
	end

	if imageButtonMoney then
		imageButtonMoney.Visible = true  -- V2.0: 金币按钮任何情况下都显示
	else
		warn("MenuController: 未找到ImageButtonMoney")
	end

	if imageButtonWheel then
		imageButtonWheel.Visible = visible  -- V2.0: 转盘按钮与Shop按钮使用相同逻辑

		-- V2.0: 绑定转盘按钮点击事件
		if visible then
			MenuController.bindWheelButton(imageButtonWheel)
		end
	else
		warn("MenuController: 未找到ImageButtonWheel")
	end

	-- V1.1: Emote按钮始终显示（像Skin和Money按钮一样）
	if imageButtonEmote then
		imageButtonEmote.Visible = true
		MenuController.bindEmoteButton(imageButtonEmote)
	else
		warn("MenuController: 未找到ImageButtonEmote")
	end

	-- V1.9: NewPlayerGift按钮不受全局Menu可见性影响，由NewPlayerGiftClient独立控制
	-- 这里不对其可见性做任何修改

end

-- 设置特定按钮的可见性
function MenuController.setSpecificMenuVisibility(config)
	local playerGui = player:WaitForChild("PlayerGui")
	local menuGui = playerGui:FindFirstChild("Menu")

	if not menuGui then
		warn("MenuController: 未找到Menu ScreenGui")
		return
	end

	-- 查找目标按钮
	local imageButtonShop = menuGui:FindFirstChild("ImageButtonShop")
	local imageButtonSkin = menuGui:FindFirstChild("ImageButtonSkin")
	local imageButtonMoney = menuGui:FindFirstChild("ImageButtonMoney")  -- V2.0: 金币按钮
	local imageButtonWheel = menuGui:FindFirstChild("ImageButtonWheel")  -- V2.0: 转盘按钮
	local imageButtonEmote = menuGui:FindFirstChild("ImageButtonEmote")  -- V1.1: 庆祝动作按钮
	local newPlayerGiftButton = menuGui:FindFirstChild("NewPlayerGift")  -- V1.9: 新手礼包按钮

	-- 设置按钮可见性

	if imageButtonShop and config.shop ~= nil then
		imageButtonShop.Visible = config.shop

		-- V1.8: 绑定商店按钮点击事件
		if config.shop then
			MenuController.bindShopButton(imageButtonShop)
		end
	end

	-- V2.0: Skin按钮始终显示（像Emote和Money按钮一样）
	if imageButtonSkin then
		imageButtonSkin.Visible = true
		MenuController.bindSkinButton(imageButtonSkin)
	end

	-- V2.0: Money按钮始终显示，不受config控制
	if imageButtonMoney then
		imageButtonMoney.Visible = true
	end

	-- V2.0: Wheel按钮的可见性控制
	if imageButtonWheel and config.wheel ~= nil then
		imageButtonWheel.Visible = config.wheel

		-- V2.0: 绑定转盘按钮点击事件
		if config.wheel then
			MenuController.bindWheelButton(imageButtonWheel)
		end
	elseif imageButtonWheel then
		-- 如果config中没有指定wheel，默认显示
		imageButtonWheel.Visible = true
		MenuController.bindWheelButton(imageButtonWheel)
	end

	-- V1.1: Emote按钮始终显示（像Skin和Money按钮一样）
	if imageButtonEmote then
		imageButtonEmote.Visible = true
		MenuController.bindEmoteButton(imageButtonEmote)
	end

	-- V1.9: NewPlayerGift按钮的可见性控制
	-- 由于策划案要求此按钮在对局中保持显示，这里接受config中的newPlayerGift参数
	-- 但实际的显示/隐藏逻辑主要由NewPlayerGiftClient根据购买状态控制
	if newPlayerGiftButton and config.newPlayerGift ~= nil then
		-- 只在config明确指定时才修改可见性
		-- 这允许GameInstance在对局开始时保持按钮可见
		newPlayerGiftButton.Visible = config.newPlayerGift

		-- V2.0: 绑定新手礼包按钮点击事件
		if config.newPlayerGift then
			MenuController.bindNewPlayerGiftButton(newPlayerGiftButton)
		end
	end

end

-- V1.8: 绑定商店按钮点击事件
function MenuController.bindShopButton(imageButtonShop)
	-- 移除旧的连接（如果存在）
	if MenuController.shopButtonConnection then
		MenuController.shopButtonConnection:Disconnect()
	end

	-- 绑定新的点击事件
	MenuController.shopButtonConnection = imageButtonShop.MouseButton1Click:Connect(function()
		MenuController.openShop()
	end)

end

-- V1.8: 打开商店
function MenuController.openShop()
	-- 通过ShopUIController打开商店
	if _G.ShopUIController then
		_G.ShopUIController.toggle(true)
	else
		-- 备用方案：直接操作UI
		local playerGui = player:WaitForChild("PlayerGui")
		local shopGui = playerGui:FindFirstChild("Shop")

		if shopGui then
			local shopBg = shopGui:FindFirstChild("ShopBg")
			if shopBg then
				shopBg.Visible = true
			end
		else
			warn("MenuController: 未找到Shop UI")
		end
	end
end

-- V2.0: 绑定皮肤按钮点击事件
function MenuController.bindSkinButton(imageButtonSkin)
	-- 移除旧的连接（如果存在）
	if MenuController.skinButtonConnection then
		MenuController.skinButtonConnection:Disconnect()
	end

	-- 绑定新的点击事件
	MenuController.skinButtonConnection = imageButtonSkin.MouseButton1Click:Connect(function()
		MenuController.openSkin()
	end)
end

-- V2.0: 打开皮肤界面
function MenuController.openSkin()
	if _G.SkinUIClient and _G.SkinUIClient.openSkinUI then
		_G.SkinUIClient.openSkinUI()
	else
		warn("MenuController: SkinUIClient未加载")
	end
end

-- V2.0: 绑定转盘按钮点击事件
function MenuController.bindWheelButton(imageButtonWheel)
	-- 移除旧的连接（如果存在）
	if MenuController.wheelButtonConnection then
		MenuController.wheelButtonConnection:Disconnect()
	end

	-- 绑定新的点击事件
	MenuController.wheelButtonConnection = imageButtonWheel.MouseButton1Click:Connect(function()
		MenuController.openWheel()
	end)
end

-- V2.0: 打开转盘界面
function MenuController.openWheel()
	if _G.WheelClient and _G.WheelClient.showWheelUI then
		_G.WheelClient.showWheelUI()
	else
		warn("MenuController: WheelClient未加载")
	end
end

-- V1.1: 绑定庆祝动作按钮点击事件
function MenuController.bindEmoteButton(imageButtonEmote)
	-- 移除旧的连接（如果存在）
	if MenuController.emoteButtonConnection then
		MenuController.emoteButtonConnection:Disconnect()
	end

	-- 绑定新的点击事件
	MenuController.emoteButtonConnection = imageButtonEmote.MouseButton1Click:Connect(function()
		MenuController.openEmote()
	end)
end

-- V1.1: 打开庆祝动作界面
function MenuController.openEmote()
	if _G.EmoteClient and _G.EmoteClient.showUI then
		_G.EmoteClient.showUI()
	else
		warn("MenuController: EmoteClient未加载")
	end
end

-- V2.0: 绑定新手礼包按钮点击事件
function MenuController.bindNewPlayerGiftButton(newPlayerGiftButton)
	-- 移除旧的连接（如果存在）
	if MenuController.giftButtonConnection then
		MenuController.giftButtonConnection:Disconnect()
	end

	-- 绑定新的点击事件
	MenuController.giftButtonConnection = newPlayerGiftButton.MouseButton1Click:Connect(function()
		MenuController.openNewPlayerGift()
	end)
end

-- V2.0: 打开新手礼包界面
function MenuController.openNewPlayerGift()
	local playerGui = player:WaitForChild("PlayerGui")
	local giftGui = playerGui:FindFirstChild("NewPlayerGift")
	if giftGui then
		local giftBg = giftGui:FindFirstChild("Bg")
		if giftBg then
			giftBg.Visible = true
		end
	else
		warn("MenuController: 未找到NewPlayerGift UI")
	end
end

-- 初始化
function MenuController.initialize()
	-- V2.0: 等待SkinUIClient、WheelClient和EmoteClient加载,然后绑定所有按钮
	task.spawn(function()
		local attempts = 0
		while (not _G.SkinUIClient or not _G.WheelClient or not _G.EmoteClient) and attempts < 20 do
			task.wait(0.5)
			attempts = attempts + 1
		end

		if not _G.SkinUIClient then
			warn("MenuController: SkinUIClient加载超时,皮肤按钮功能可能不可用")
		end

		if not _G.WheelClient then
			warn("MenuController: WheelClient加载超时,转盘按钮功能可能不可用")
		end

		if not _G.EmoteClient then
			warn("MenuController: EmoteClient加载超时,庆祝动作按钮功能可能不可用")
		end

		-- 初始化所有按钮绑定
		local playerGui = player:WaitForChild("PlayerGui")
		local menuGui = playerGui:FindFirstChild("Menu")

		if menuGui then
			local imageButtonSkin = menuGui:FindFirstChild("ImageButtonSkin")
			local imageButtonWheel = menuGui:FindFirstChild("ImageButtonWheel")
			local imageButtonEmote = menuGui:FindFirstChild("ImageButtonEmote")
			local newPlayerGiftButton = menuGui:FindFirstChild("NewPlayerGift")

			if imageButtonSkin then
				MenuController.bindSkinButton(imageButtonSkin)
			end

			if imageButtonWheel then
				MenuController.bindWheelButton(imageButtonWheel)
			end

			if imageButtonEmote then
				MenuController.bindEmoteButton(imageButtonEmote)
			end

			if newPlayerGiftButton then
				MenuController.bindNewPlayerGiftButton(newPlayerGiftButton)
			end
		end
	end)
end

-- 启动控制器
MenuController.initialize()

-- V1.8: 导出到全局供其他脚本使用
_G.MenuController = MenuController

return MenuController