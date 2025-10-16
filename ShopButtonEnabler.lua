-- 脚本名称: ShopButtonEnabler
-- 脚本作用: 确保商店按钮在游戏开始时就是可见和可点击的
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- 等待UI加载并设置商店按钮
local function setupShopButton()
	local playerGui = player:WaitForChild("PlayerGui")

	-- 等待Menu GUI
	local menuGui = playerGui:WaitForChild("Menu", 10)
	if not menuGui then
		warn("ShopButtonEnabler: Menu GUI未找到")
		return
	end

	-- 等待商店按钮
	local imageButtonShop = menuGui:WaitForChild("ImageButtonShop", 10)
	if not imageButtonShop then
		warn("ShopButtonEnabler: ImageButtonShop未找到")
		return
	end

	-- 确保按钮可见
	imageButtonShop.Visible = true

	-- 直接绑定点击事件（备用方案）
	imageButtonShop.MouseButton1Click:Connect(function()

		-- 尝试通过ShopUIController打开
		if _G.ShopUIController and _G.ShopUIController.toggle then
			_G.ShopUIController.toggle(true)
		else
			-- 直接操作UI
			local shopGui = playerGui:FindFirstChild("Shop")
			if shopGui then
				local shopBg = shopGui:FindFirstChild("ShopBg")
				if shopBg then
					shopBg.Visible = true
				else
					warn("ShopButtonEnabler: ShopBg未找到")
				end
			else
				warn("ShopButtonEnabler: Shop GUI未找到")
			end
		end
	end)

end

-- 启动设置
spawn(function()
	wait(2) -- 等待其他脚本加载
	setupShopButton()
end)