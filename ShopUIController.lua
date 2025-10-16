-- 脚本名称: ShopUIController
-- 脚本作用: 客户端商店UI控制器，处理商店界面显示和交互
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local ShopUIController = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local shopEvent = remoteEventsFolder:WaitForChild("ShopEvent", 30)  -- 30秒超时
local coinUpdateEvent = remoteEventsFolder:WaitForChild("CoinUpdate", 30)  -- 30秒超时

if not shopEvent then
	warn("⚠️ ShopUIController: 未能加载 ShopEvent，商店功能将不可用")
	return
end

if not coinUpdateEvent then
	warn("⚠️ ShopUIController: 未能加载 CoinUpdate，金币显示可能异常")
	-- 继续运行，因为这不是致命错误
end

-- UI状态
local shopState = {
	isOpen = false,
	isLoading = false,
	products = {},
	purchaseInProgress = {},  -- 跟踪正在购买的商品，防止重复点击
	purchaseTimeouts = {}     -- 🔧 修复：跟踪购买超时定时器
}

-- UI元素引用
local shopUI = {
	shop = nil,           -- Shop ScreenGui
	shopBg = nil,         -- ShopBg Frame
	closeBtn = nil,       -- CloseBtn
	scrollFrame = nil,    -- ScrollingFrame
	goodsTemplate = nil   -- GoodsTemplate
}

-- 初始化UI引用
function ShopUIController.initializeUI()
	local playerGui = player:WaitForChild("PlayerGui")

	-- 等待Shop GUI
	shopUI.shop = playerGui:WaitForChild("Shop", 10)
	if not shopUI.shop then
		warn("ShopUIController: Shop GUI未找到")
		return false
	end

	shopUI.shopBg = shopUI.shop:WaitForChild("ShopBg", 5)
	if not shopUI.shopBg then
		warn("ShopUIController: ShopBg未找到")
		return false
	end

	shopUI.closeBtn = shopUI.shopBg:WaitForChild("CloseBtn", 5)
	if not shopUI.closeBtn then
		warn("ShopUIController: CloseBtn未找到")
		return false
	end

	shopUI.scrollFrame = shopUI.shopBg:WaitForChild("ScrollingFrame", 5)
	if not shopUI.scrollFrame then
		warn("ShopUIController: ScrollingFrame未找到")
		return false
	end

	shopUI.goodsTemplate = shopUI.scrollFrame:WaitForChild("GoodsTemplate", 5)
	if not shopUI.goodsTemplate then
		warn("ShopUIController: GoodsTemplate未找到")
		return false
	end

	-- 确保模板默认隐藏
	shopUI.goodsTemplate.Visible = false

	-- 确保商店默认关闭
	shopUI.shopBg.Visible = false

	return true
end

-- 切换商店显示状态
function ShopUIController.toggle(forceOpen)

	-- 检查UI是否已初始化
	if not shopUI.shopBg then
		warn("ShopUIController.toggle: UI未初始化，尝试重新初始化")
		local success = ShopUIController.initializeUI()
		if not success then
			warn("ShopUIController.toggle: UI初始化失败")
			return
		end
	end

	if shopState.isLoading then
		return
	end

	local shouldOpen = forceOpen or not shopState.isOpen

	if shouldOpen then
		ShopUIController.openShop()
	else
		ShopUIController.closeShop()
	end
end

-- 打开商店
function ShopUIController.openShop()
	if shopState.isOpen then return end
	shopState.isOpen = true
	shopState.isLoading = true

	-- 显示商店界面
	shopUI.shopBg.Visible = true

	-- 请求商品目录
	shopEvent:FireServer("requestCatalog")

	-- 播放打开动画
	ShopUIController.playOpenAnimation()
end

-- 关闭商店
function ShopUIController.closeShop()
	if not shopState.isOpen then return end
	shopState.isOpen = false

	-- 播放关闭动画
	ShopUIController.playCloseAnimation(function()
		shopUI.shopBg.Visible = false
	end)
end

-- 播放打开动画
function ShopUIController.playOpenAnimation()
	-- 从小到正常大小的缩放动画
	shopUI.shopBg.Size = UDim2.new(0, 0, 0, 0)
	shopUI.shopBg.Position = UDim2.new(0.5, 0, 0.5, 0)
	shopUI.shopBg.AnchorPoint = Vector2.new(0.5, 0.5)

	local animInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local openTween = TweenService:Create(shopUI.shopBg, animInfo, {
		Size = UDim2.new(0.8, 0, 0.8, 0)
	})

	openTween:Play()
end

-- 播放关闭动画
function ShopUIController.playCloseAnimation(callback)
	local animInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local closeTween = TweenService:Create(shopUI.shopBg, animInfo, {
		Size = UDim2.new(0, 0, 0, 0)
	})

	closeTween:Play()
	closeTween.Completed:Connect(function()
		if callback then callback() end
	end)
end

-- 处理商品目录响应
function ShopUIController.handleCatalogResponse(data)
	if not data or not data.products then
		warn("ShopUIController: 商品目录数据无效")
		shopState.isLoading = false
		return
	end

	shopState.products = data.products
	shopState.isLoading = false

	-- 渲染商品列表
	ShopUIController.renderProducts()
end

-- 渲染商品列表
function ShopUIController.renderProducts()

	-- 清理现有商品
	ShopUIController.clearProducts()

	-- 为每个商品创建UI
	for i, product in ipairs(shopState.products) do
		ShopUIController.createProductUI(product, i)
	end
end

-- 清理现有商品UI
function ShopUIController.clearProducts()
	for _, child in ipairs(shopUI.scrollFrame:GetChildren()) do
		if child.Name ~= "GoodsTemplate" and child:IsA("Frame") then
			child:Destroy()
		end
	end
end

-- 创建单个商品UI
function ShopUIController.createProductUI(product, index)
	-- 克隆模板
	local productFrame = shopUI.goodsTemplate:Clone()
	productFrame.Name = "Product_" .. product.id
	productFrame.Visible = true
	productFrame.Parent = shopUI.scrollFrame

	-- 设置位置（网格布局）
	local columns = 2
	local row = math.floor((index - 1) / columns)
	local col = (index - 1) % columns

	productFrame.Position = UDim2.new(
		col * 0.5, col * 10,  -- X: 50%宽度 + 10像素间距
		0, row * 120 + row * 10  -- Y: 120像素高度 + 10像素间距
	)

	-- 填充商品信息
	local icon = productFrame:FindFirstChild("Icon")
	local nameLabel = productFrame:FindFirstChild("Name")
	local buyButton = productFrame:FindFirstChild("Buy")

	if icon then
		icon.Image = product.iconAssetId
	end

	if nameLabel then
		nameLabel.Text = product.name
	end

	if buyButton then
		-- 设置按钮文本和图标
		local buttonText = buyButton:FindFirstChild("Text")
		local buttonIcon = buyButton:FindFirstChild("Icon")

		if buttonText then
			-- 格式化价格显示 - 直接显示数字，不加货币符号
			buttonText.Text = tostring(product.price)
		end

		if buttonIcon then
			buttonIcon.Image = product.currencyIconAssetId
		end

		-- 绑定购买事件
		buyButton.MouseButton1Click:Connect(function()
			ShopUIController.handlePurchaseClick(product)
		end)
	end

end

-- 处理购买点击
function ShopUIController.handlePurchaseClick(product)
	-- 检查是否正在购买中
	if shopState.purchaseInProgress[product.id] then
		return
	end

	-- 标记为购买中
	shopState.purchaseInProgress[product.id] = true

	-- 禁用按钮并显示加载状态
	ShopUIController.setPurchaseButtonState(product.id, false, "Loading...")

	-- 🔧 修复：设置超时定时器（30秒后自动重置按钮）
	-- 处理用户取消购买或购买窗口长时间未响应的情况
	if shopState.purchaseTimeouts[product.id] then
		-- 清理旧的超时定时器
		task.cancel(shopState.purchaseTimeouts[product.id])
	end

	shopState.purchaseTimeouts[product.id] = task.delay(30, function()
		-- 30秒后如果还在购买中状态，自动重置
		if shopState.purchaseInProgress[product.id] then
			print("⏱️ ShopUIController: 购买超时，自动重置按钮 - 商品ID: " .. product.id)
			ShopUIController.resetPurchaseButtonState(product)
		end
	end)

	-- 发送购买请求
	shopEvent:FireServer("purchase", {
		productId = product.id
	})
end

-- 设置购买按钮状态
function ShopUIController.setPurchaseButtonState(productId, enabled, text)
	local productFrame = shopUI.scrollFrame:FindFirstChild("Product_" .. productId)
	if not productFrame then return end

	local buyButton = productFrame:FindFirstChild("Buy")
	if not buyButton then return end

	local buttonText = buyButton:FindFirstChild("Text")
	if buttonText and text then
		buttonText.Text = text
	end

	-- 设置按钮可交互性
	buyButton.Interactable = enabled

	-- 视觉反馈
	if enabled then
		buyButton.BackgroundTransparency = 0
	else
		buyButton.BackgroundTransparency = 0.5
	end
end

-- 恢复购买按钮状态
function ShopUIController.resetPurchaseButtonState(product)
	-- 🔧 修复：清理超时定时器
	if shopState.purchaseTimeouts[product.id] then
		task.cancel(shopState.purchaseTimeouts[product.id])
		shopState.purchaseTimeouts[product.id] = nil
	end

	-- 清除购买进行中标志
	shopState.purchaseInProgress[product.id] = nil

	-- 恢复纯数字价格显示
	local text = tostring(product.price)

	ShopUIController.setPurchaseButtonState(product.id, true, text)
end

-- 处理购买成功
function ShopUIController.handlePurchaseSuccess(data)

	-- 查找对应商品
	local product = nil
	for _, p in ipairs(shopState.products) do
		if p.id == data.productId then
			product = p
			break
		end
	end

	if product then
		ShopUIController.resetPurchaseButtonState(product)
	end

	-- 显示成功提示
	ShopUIController.showPurchaseResult("Purchase Success", "获得: " .. (data.productName or "商品"), Color3.new(0, 1, 0))
end

-- 处理购买失败
function ShopUIController.handlePurchaseFailed(data)
	local reason = data.reason or "购买失败"

	-- 恢复所有按钮状态
	for _, product in ipairs(shopState.products) do
		if shopState.purchaseInProgress[product.id] then
			ShopUIController.resetPurchaseButtonState(product)
		end
	end

	-- 显示失败原因
	local message = "购买失败"
	if reason == "insufficient_funds" then
		message = "金币不足"
		if data.required and data.current then
			message = message .. "\n需要: " .. data.required .. " 当前: " .. data.current
		end
	elseif reason == "请稍等片刻再试" then
		message = "请稍等片刻再试"
	elseif reason == "购买被取消或失败" then
		message = "购买被取消"
	else
		message = reason
	end

	ShopUIController.showPurchaseResult("Purchase Failed", message, Color3.new(1, 0, 0))
end

-- 显示购买结果飘字
function ShopUIController.showPurchaseResult(title, message, color)
	local playerGui = player:WaitForChild("PlayerGui")

	-- 创建飘字ScreenGui
	local floatingGui = Instance.new("ScreenGui")
	floatingGui.Name = "PurchaseFloatingText"
	floatingGui.Parent = playerGui

	-- 创建飘字文本
	local floatingText = Instance.new("TextLabel")
	floatingText.Size = UDim2.new(0, 300, 0, 50)
	floatingText.Position = UDim2.new(0.5, -150, 0.3, 0) -- 屏幕中上方
	floatingText.BackgroundTransparency = 1
	floatingText.Text = title  -- 直接显示文本
	floatingText.TextColor3 = color
	floatingText.TextScaled = true
	floatingText.Font = Enum.Font.SourceSansBold
	floatingText.TextStrokeTransparency = 0
	floatingText.TextStrokeColor3 = Color3.new(0, 0, 0)
	floatingText.Parent = floatingGui

	-- 飘字动画：从下往上飘，同时淡出
	local startPos = UDim2.new(0.5, -150, 0.4, 0)
	local endPos = UDim2.new(0.5, -150, 0.2, 0)

	floatingText.Position = startPos

	local moveTween = TweenService:Create(floatingText,
		TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = endPos}
	)

	local fadeTween = TweenService:Create(floatingText,
		TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{TextTransparency = 1, TextStrokeTransparency = 1}
	)

	moveTween:Play()
	fadeTween:Play()

	-- 2秒后删除
	fadeTween.Completed:Connect(function()
		floatingGui:Destroy()
	end)
end

-- 设置事件监听
function ShopUIController.setupEvents()
	-- 商店事件监听
	shopEvent.OnClientEvent:Connect(function(action, data)
		if action == "catalogResponse" then
			ShopUIController.handleCatalogResponse(data)
		elseif action == "purchaseSuccess" then
			ShopUIController.handlePurchaseSuccess(data)
		elseif action == "purchaseFailed" then
			ShopUIController.handlePurchaseFailed(data)
		end
	end)

	-- 🔧 修复：监听 Roblox 购买窗口关闭事件
	-- 当用户关闭购买窗口（包括取消购买）时，重置按钮状态
	MarketplaceService.PromptPurchaseFinished:Connect(function(userId, productId, isPurchased)
		-- 只处理本地玩家的购买
		if userId ~= player.UserId then return end

		print(string.format("🛒 PromptPurchaseFinished - ProductId: %d, Purchased: %s", productId, tostring(isPurchased)))

		-- 如果购买被取消（isPurchased = false），重置所有正在购买中的按钮
		if not isPurchased then
			-- 遍历所有正在购买中的商品
			for productIdKey, _ in pairs(shopState.purchaseInProgress) do
				-- 查找对应的商品
				for _, product in ipairs(shopState.products) do
					if product.id == productIdKey then
						print(string.format("🔄 重置按钮 - 商品ID: %d (购买被取消)", product.id))
						ShopUIController.resetPurchaseButtonState(product)
						break
					end
				end
			end
		end
		-- 如果购买成功（isPurchased = true），等待服务端的 purchaseSuccess 事件处理
	end)

	-- 关闭按钮事件
	shopUI.closeBtn.MouseButton1Click:Connect(function()
		ShopUIController.closeShop()
	end)

	-- ESC键关闭商店
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.Escape and shopState.isOpen then
			ShopUIController.closeShop()
		end
	end)

end

-- 初始化
function ShopUIController.initialize()

	-- 等待UI加载
	spawn(function()
		local success = ShopUIController.initializeUI()
		if success then
			ShopUIController.setupEvents()
		else
			warn("ShopUIController 初始化失败：UI组件缺失")
		end
	end)
end

-- 启动控制器
ShopUIController.initialize()

-- 导出供其他脚本使用
_G.ShopUIController = ShopUIController

return ShopUIController