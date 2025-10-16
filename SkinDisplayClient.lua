-- 脚本名称: SkinDisplayClient
-- 脚本作用: V2.0皮肤展示模型客户端脚本,初始化BillboardGui显示
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer → StarterPlayerScripts

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- 等待SkinConfig加载(从ServerScriptService复制到ReplicatedStorage)
local function waitForSkinConfig()
	local attempts = 0
	while attempts < 30 do
		local config = ReplicatedStorage:FindFirstChild("SkinConfig")
		if config then
			return require(config)
		end
		task.wait(0.5)
		attempts = attempts + 1
	end
	warn("❌ SkinConfig加载超时")
	return nil
end

-- 如果SkinConfig不在ReplicatedStorage中,创建一个简化版本
local SkinConfig = waitForSkinConfig()

-- 如果无法加载SkinConfig,使用本地配置表
if not SkinConfig then
	SkinConfig = {
		SKIN_CONFIG = {
			[1001] = {id = 1001, name = "Coffee", price = 100, displayModelName = "CoffeeShow"},
			[1002] = {id = 1002, name = "Cola", price = 200, displayModelName = "ColaShow"},
			[1003] = {id = 1003, name = "MangoTee", price = 200, displayModelName = "MangoTeeShow"},
			[1004] = {id = 1004, name = "Fries", price = 300, displayModelName = "FriesShow"},
			[1005] = {id = 1005, name = "Sushi", price = 500, displayModelName = "SushiShow"},
			[1006] = {id = 1006, name = "Watermelon", price = 1000, displayModelName = "WatermelonShow"},
			[1007] = {id = 1007, name = "Lobster", price = 2000, displayModelName = "LobsterShow"}
		},
		getSkinByDisplayModelName = function(displayModelName)
			for _, skinInfo in pairs(SkinConfig.SKIN_CONFIG) do
				if skinInfo.displayModelName == displayModelName then
					return skinInfo
				end
			end
			return nil
		end
	}
end

local SkinDisplayClient = {}

-- ============================================
-- BillboardGui初始化
-- ============================================

-- 为单个展示模型设置BillboardGui
local function setupDisplayModelInfo(displayModel)
	-- 根据展示模型名称查找皮肤配置
	local skinInfo = SkinConfig.getSkinByDisplayModelName(displayModel.Name)
	if not skinInfo then
		return
	end

	-- 查找NumPart
	local numPart = displayModel:FindFirstChild("NumPart")
	if not numPart then
		return  -- 静默跳过，展示模型可选配置
	end

	-- 查找BillboardGui
	local billboardGui = numPart:FindFirstChild("BillboardGui")
	if not billboardGui then
		return  -- 静默跳过，BillboardGui可选配置
	end

	-- 设置Name
	local nameLabel = billboardGui:FindFirstChild("Name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = skinInfo.name
	end

	-- 设置Price
	local priceLabel = billboardGui:FindFirstChild("Price")
	if priceLabel and priceLabel:IsA("TextLabel") then
		priceLabel.Text = "$" .. skinInfo.price
	end
end

-- 扫描并设置所有展示模型
function SkinDisplayClient.setupAllDisplayModels()
	local skinTemplate = Workspace:WaitForChild("SkinTemplate", 10)
	if not skinTemplate then
		warn("未找到Workspace.SkinTemplate文件夹")
		return
	end

	-- 等待模型加载
	task.wait(1)

	-- 遍历所有展示模型
	for _, displayModel in pairs(skinTemplate:GetChildren()) do
		if displayModel:IsA("Model") or displayModel:IsA("BasePart") then
			setupDisplayModelInfo(displayModel)
		end
	end
end

-- ============================================
-- 购买反馈通知
-- ============================================

-- 显示购买成功通知
local function showPurchaseSuccessNotification()
	local StarterGui = game:GetService("StarterGui")
	StarterGui:SetCore("SendNotification", {
		Title = "Skin Purchase",
		Text = "Purchase Successful!",
		Duration = 3
	})
end

-- 显示已拥有通知
local function showAlreadyOwnedNotification()
	local StarterGui = game:GetService("StarterGui")
	StarterGui:SetCore("SendNotification", {
		Title = "Skin Purchase",
		Text = "you have already owned this skin",
		Duration = 3
	})
end

-- 监听购买事件
local function listenToPurchaseEvents()
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEventsFolder then
		return
	end

	local purchaseEvent = remoteEventsFolder:WaitForChild("SkinPurchase", 10)
	if not purchaseEvent then
		return
	end

	purchaseEvent.OnClientEvent:Connect(function(action, data)
		if action == "notifySuccess" then
			showPurchaseSuccessNotification()
		elseif action == "notifyAlreadyOwned" then
			showAlreadyOwnedNotification()
		end
	end)
end

-- ============================================
-- 初始化
-- ============================================

-- 启动时初始化
task.spawn(function()
	-- 等待游戏完全加载
	task.wait(2)

	-- 设置所有展示模型的BillboardGui
	SkinDisplayClient.setupAllDisplayModels()

	-- 监听购买事件
	listenToPurchaseEvents()
end)

return SkinDisplayClient
