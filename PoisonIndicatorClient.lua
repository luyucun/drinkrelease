-- 脚本名称: PoisonIndicatorClient
-- 脚本作用: 客户端毒药标识显示，为下毒者显示红色毒药标记
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local PoisonIndicatorClient = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- 等待RemoteEvents
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local poisonIndicatorEvent = remoteEventsFolder:WaitForChild("PoisonIndicator")

-- 毒药标识状态
local indicatorState = {
	poisonedDrinks = {},        -- 本玩家下毒的奶茶
	indicatorEffects = {}       -- 视觉效果实例
}

-- 接收毒药信息
function PoisonIndicatorClient.receivePoisonInfo(poisonedDrinks)
	indicatorState.poisonedDrinks = poisonedDrinks or {}


	-- 立即显示标识
	PoisonIndicatorClient.showPoisonIndicators()
end

-- 显示毒药标识
function PoisonIndicatorClient.showPoisonIndicators()
	local workspace = game.Workspace
	local twoPlayerFolder = workspace:WaitForChild("2Player")

	-- 自动检测玩家所在的桌子（支持多桌）
	local tableId = PoisonIndicatorClient.detectPlayerTable()
	local battleGroup = twoPlayerFolder:FindFirstChild(tableId or "2player_group1")

	if not battleGroup then
		warn("PoisonIndicatorClient: 未找到桌子 " .. (tableId or "2player_group1"))
		return
	end

	local classicTable = battleGroup:FindFirstChild("ClassicTable")
	if not classicTable then
		warn("PoisonIndicatorClient: 桌子 " .. (tableId or "2player_group1") .. " 未找到ClassicTable")
		return
	end

	-- 智能更新：只清除不在新列表中的标识，添加新的标识
	local newPoisonedDrinks = {}
	for _, drinkIndex in ipairs(indicatorState.poisonedDrinks) do
		newPoisonedDrinks[drinkIndex] = true
	end

	-- 清除不再需要的标识
	for drinkIndex, effect in pairs(indicatorState.indicatorEffects) do
		if not newPoisonedDrinks[drinkIndex] then
			PoisonIndicatorClient.removePoisonIndicator(drinkIndex)
		end
	end

	-- 添加新的标识
	for _, drinkIndex in ipairs(indicatorState.poisonedDrinks) do
		local drinkName = "Drink_" .. string.format("%02d", drinkIndex)
		local drinkModel = classicTable:FindFirstChild(drinkName)

		if drinkModel then
			PoisonIndicatorClient.addPoisonIndicator(drinkModel, drinkIndex)
		else
			warn("未找到奶茶模型: " .. drinkName)
		end
	end

end

-- 检测玩家所在的桌子（客户端版本）
function PoisonIndicatorClient.detectPlayerTable()
	local player = Players.LocalPlayer
	if not player.Character then return nil end

	local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return nil end

	local playerPosition = humanoidRootPart.Position
	local workspace = game.Workspace
	local twoPlayerFolder = workspace:FindFirstChild("2Player")

	if not twoPlayerFolder then return nil end

	local closestTableId = nil
	local closestDistance = math.huge

	-- 遍历所有桌子，找到最近的
	for _, child in pairs(twoPlayerFolder:GetChildren()) do
		if child.Name:match("^2player_group%d+$") then
			local classicTable = child:FindFirstChild("ClassicTable")
			if classicTable then
				local tablePart = classicTable:FindFirstChild("TablePart")
				if tablePart then
					local distance = (playerPosition - tablePart.Position).Magnitude
					if distance < closestDistance and distance < 20 then
						closestDistance = distance
						closestTableId = child.Name
					end
				end
			end
		end
	end

	return closestTableId
end

-- 添加毒药标识
function PoisonIndicatorClient.addPoisonIndicator(drinkModel, drinkIndex)
	-- 检查是否已经设置过标识，避免重复操作
	if indicatorState.indicatorEffects[drinkIndex] then
		-- 已经设置过，检查字体颜色是否正确
		local effect = indicatorState.indicatorEffects[drinkIndex]
		if effect.numPart then
			local billboardGui = effect.numPart:FindFirstChild("BillboardGui")
			if billboardGui then
				local numLabel = billboardGui:FindFirstChild("Num")
				if numLabel and numLabel.TextColor3 ~= Color3.new(1, 0, 0) then
					numLabel.TextColor3 = Color3.new(1, 0, 0) -- 确保为红色
				end
			end
		end
		return
	end

	-- 只设置红色字体，移除SelectionBox边框和粒子效果
	local numPart = drinkModel:FindFirstChild("NumPart")
	if numPart then
		local billboardGui = numPart:FindFirstChild("BillboardGui")
		if billboardGui then
			local numLabel = billboardGui:FindFirstChild("Num")
			if numLabel then
				numLabel.TextColor3 = Color3.new(1, 0, 0) -- 设置为红色
			end
		end
	end

	-- 存储标识状态（用于后续清理）
	indicatorState.indicatorEffects[drinkIndex] = {
		drinkModel = drinkModel,
		numPart = numPart
	}
end

-- 移除单个奶茶的毒药标识
function PoisonIndicatorClient.removePoisonIndicator(drinkIndex)
	local effect = indicatorState.indicatorEffects[drinkIndex]
	if effect then
		-- 恢复字体颜色为默认白色
		if effect.numPart then
			local billboardGui = effect.numPart:FindFirstChild("BillboardGui")
			if billboardGui then
				local numLabel = billboardGui:FindFirstChild("Num")
				if numLabel then
					numLabel.TextColor3 = Color3.new(1, 1, 1) -- 恢复为白色
				end
			end
		end

		indicatorState.indicatorEffects[drinkIndex] = nil
	end
end

-- 清除所有标识
function PoisonIndicatorClient.clearIndicators()
	for drinkIndex, effect in pairs(indicatorState.indicatorEffects) do
		PoisonIndicatorClient.removePoisonIndicator(drinkIndex)
	end

	indicatorState.indicatorEffects = {}
end

-- 当奶茶被移除时清理标识
function PoisonIndicatorClient.onDrinkRemoved(drinkIndex)
	PoisonIndicatorClient.removePoisonIndicator(drinkIndex)
end

-- 监听奶茶移除事件
function PoisonIndicatorClient.setupDrinkRemovalListener()
	local workspace = game.Workspace
	local twoPlayerFolder = workspace:WaitForChild("2Player")
	local battleGroup = twoPlayerFolder:WaitForChild("2player_group1")
	local classicTable = battleGroup:WaitForChild("ClassicTable")

	classicTable.ChildRemoved:Connect(function(child)
		if child.Name:find("Drink_") then
			local drinkIndex = tonumber(child.Name:match("%d+"))
			if drinkIndex then
				PoisonIndicatorClient.onDrinkRemoved(drinkIndex)
			end
		end
	end)
end

-- 设置RemoteEvent处理
function PoisonIndicatorClient.setupRemoteEvents()
	poisonIndicatorEvent.OnClientEvent:Connect(function(action, data)
		if action == "showPoisonIndicators" then
			PoisonIndicatorClient.receivePoisonInfo(data.poisonedDrinks)
		elseif action == "clearIndicators" then
			PoisonIndicatorClient.clearIndicators()
		elseif action == "removeDrinkIndicator" then
			if data and data.drinkIndex then
				PoisonIndicatorClient.removePoisonIndicator(data.drinkIndex)
			end
		end
	end)

end

-- 初始化
function PoisonIndicatorClient.initialize()
	PoisonIndicatorClient.setupRemoteEvents()
	PoisonIndicatorClient.setupDrinkRemovalListener()
end

-- 启动客户端控制器
PoisonIndicatorClient.initialize()

return PoisonIndicatorClient