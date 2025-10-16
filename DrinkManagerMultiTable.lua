-- 脚本名称: DrinkManagerMultiTable
-- 脚本作用: 管理奶茶的生成、摆放和状态（多桌版本）
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local DrinkManager = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- 等待DrinkModel文件夹
local drinkModelFolder = ReplicatedStorage:WaitForChild("DrinkModel")
local default01Model = drinkModelFolder:WaitForChild("Default01")
local default02Model = drinkModelFolder:WaitForChild("Default02")

-- 多桌奶茶管理状态
local tableStates = {} -- 每张桌子的状态: {tableId = {activeDrinks = {}, poisonedDrinks = {}, drinkConnections = {}}}

-- 奶茶朝向配置（可调整）
local DRINK_ORIENTATION = {
	rotationX = 0,              -- 前后倾斜
	rotationY = 0,              -- 左右旋转
	rotationZ = math.rad(90),   -- 侧倾
	heightOffset = 0            -- 高度微调
}

-- 获取或创建桌子状态
function DrinkManager.getTableState(tableId)
	if not tableStates[tableId] then
		tableStates[tableId] = {
			activeDrinks = {},          -- 当前桌上的奶茶 {index = drinkModel}
			poisonedDrinks = {},        -- 被注入毒药的奶茶 {index = {poisoner1, poisoner2, ...}}
			drinkConnections = {}       -- 奶茶点击事件连接
		}
		print("创建桌子 " .. tableId .. " 的奶茶状态")
	end
	return tableStates[tableId]
end

-- 深度克隆模型
function DrinkManager.deepCloneModel(sourceModel)
	local success, result = pcall(function()
		return sourceModel:Clone()
	end)

	if success and result then
		return result
	else
		warn("模型克隆失败: " .. tostring(result))
		return nil
	end
end

-- 生成单个奶茶（支持指定桌子）
function DrinkManager.createSingleDrink(tableId, classicTable, index, attachment)
	local drinkState = DrinkManager.getTableState(tableId)

	-- 从两种模型中随机选择一种
	local sourceModel = (math.random() > 0.5) and default01Model or default02Model
	local drinkModel = DrinkManager.deepCloneModel(sourceModel)

	if not drinkModel then
		warn("桌子 " .. tableId .. " 奶茶模型克隆失败: " .. index)
		return nil
	end

	-- 设置奶茶名称和父级
	drinkModel.Name = "Drink_" .. string.format("%02d", index)
	drinkModel.Parent = classicTable

	-- 计算奶茶位置和朝向
	local attachmentWorldCFrame = attachment.WorldCFrame
	local finalRotation = CFrame.Angles(
		DRINK_ORIENTATION.rotationX,
		DRINK_ORIENTATION.rotationY,
		DRINK_ORIENTATION.rotationZ
	)
	local heightVector = Vector3.new(0, DRINK_ORIENTATION.heightOffset, 0)
	local finalCFrame = attachmentWorldCFrame * finalRotation + heightVector

	-- 设置模型位置
	if drinkModel.PrimaryPart then
		drinkModel:SetPrimaryPartCFrame(finalCFrame)
	else
		local firstPart = drinkModel:FindFirstChildOfClass("Part")
		if firstPart then
			firstPart.CFrame = finalCFrame
		end
	end

	-- 设置奶茶点击检测
	DrinkManager.setupDrinkClickDetection(tableId, drinkModel, index)

	print("桌子 " .. tableId .. " 生成奶茶 " .. index .. " 在位置 " .. attachment.Name)
	return drinkModel
end

-- 设置奶茶点击检测（支持桌子ID）
function DrinkManager.setupDrinkClickDetection(tableId, drinkModel, index)
	local drinkState = DrinkManager.getTableState(tableId)
	local clickDetector = drinkModel:FindFirstChildOfClass("ClickDetector")

	if not clickDetector then
		local targetPart = nil
		local cup = drinkModel:FindFirstChild("Cup")
		if cup and cup:IsA("Part") then
			targetPart = cup
		else
			if drinkModel.PrimaryPart then
				targetPart = drinkModel.PrimaryPart
			else
				targetPart = drinkModel:FindFirstChildOfClass("Part")
			end
		end

		if targetPart then
			clickDetector = Instance.new("ClickDetector")
			clickDetector.MaxActivationDistance = 50
			clickDetector.Parent = targetPart
		else
			warn("桌子 " .. tableId .. " 奶茶 " .. index .. " 没有找到合适的Part来添加ClickDetector")
			return
		end
	end

	if clickDetector then
		local connection = clickDetector.MouseClick:Connect(function(player)
			DrinkManager.onDrinkClicked(player, tableId, index, drinkModel)
		end)

		drinkState.drinkConnections[index] = connection
	end
end

-- 奶茶点击事件处理（支持桌子ID）
function DrinkManager.onDrinkClicked(player, tableId, drinkIndex, drinkModel)
	print("桌子 " .. tableId .. ": 玩家 " .. player.Name .. " 点击了奶茶 " .. drinkIndex)

	-- 通过TableManager获取对应桌子的游戏实例
	if _G.TableManager then
		local gameInstance = _G.TableManager.getTableInstance(tableId)
		if gameInstance then
			-- 转发给对应的管理器处理
			-- 这里需要各个管理器支持桌子ID参数
			local DrinkSelectionManager = require(script.Parent.DrinkSelectionManager)
			local PoisonSelectionManager = require(script.Parent.PoisonSelectionManager)

			-- 检查游戏阶段
			local gameStatus = gameInstance:getStatus()

			if gameStatus.phase == "selection" and DrinkSelectionManager.onPlayerSelectDrink then
				DrinkSelectionManager.onPlayerSelectDrink(player, tableId, drinkIndex)
			elseif gameStatus.phase == "poison" and PoisonSelectionManager.onPlayerSelectDrink then
				PoisonSelectionManager.onPlayerSelectDrink(player, tableId, drinkIndex)
			else
				print("桌子 " .. tableId .. " 当前阶段 " .. gameStatus.phase .. " 不处理奶茶点击")
			end
		end
	end
end

-- 为指定桌子生成所有奶茶
function DrinkManager.spawnDrinksForTable(tableId, tableFolder)
	print("桌子 " .. tableId .. " 开始生成所有奶茶...")

	local classicTable = tableFolder:FindFirstChild("ClassicTable")
	if not classicTable then
		warn("桌子 " .. tableId .. " 未找到ClassicTable")
		return false
	end

	-- 清除现有奶茶
	DrinkManager.clearDrinksForTable(tableId)

	local drinkState = DrinkManager.getTableState(tableId)

	-- 生成24杯奶茶
	for i = 1, 24 do
		local attachmentName = "Attachment" .. string.format("%02d", i)
		local attachment = classicTable:FindFirstChild(attachmentName)

		if attachment then
			local drinkModel = DrinkManager.createSingleDrink(tableId, classicTable, i, attachment)
			if drinkModel then
				drinkState.activeDrinks[i] = drinkModel
			end

			-- 添加小延迟，让生成动画更自然
			wait(0.1)
		else
			warn("桌子 " .. tableId .. " 未找到 " .. attachmentName)
		end
	end

	print("桌子 " .. tableId .. " 所有奶茶生成完成！")
	return true
end

-- 清除指定桌子的所有奶茶
function DrinkManager.clearDrinksForTable(tableId)
	local drinkState = DrinkManager.getTableState(tableId)

	print("清除桌子 " .. tableId .. " 的现有奶茶...")

	-- 清除奶茶模型
	for index, drinkModel in pairs(drinkState.activeDrinks) do
		if drinkModel and drinkModel.Parent then
			drinkModel:Destroy()
		end
	end

	-- 清除点击事件连接
	for index, connection in pairs(drinkState.drinkConnections) do
		if connection then
			connection:Disconnect()
		end
	end

	-- 重置状态
	drinkState.activeDrinks = {}
	drinkState.drinkConnections = {}
	drinkState.poisonedDrinks = {}

	print("桌子 " .. tableId .. " 奶茶清理完成")
end

-- 为奶茶注入毒药（支持桌子ID）
function DrinkManager.poisonDrinkForTable(tableId, drinkIndex, poisoner)
	local drinkState = DrinkManager.getTableState(tableId)

	if not drinkState.poisonedDrinks[drinkIndex] then
		drinkState.poisonedDrinks[drinkIndex] = {}
	end

	table.insert(drinkState.poisonedDrinks[drinkIndex], poisoner)
	print("桌子 " .. tableId .. " 奶茶 " .. drinkIndex .. " 被 " .. poisoner.Name .. " 注入毒药")
end

-- 检查奶茶是否有毒（支持桌子ID）
function DrinkManager.isDrinkPoisonedForTable(tableId, drinkIndex)
	local drinkState = DrinkManager.getTableState(tableId)
	return drinkState.poisonedDrinks[drinkIndex] and #drinkState.poisonedDrinks[drinkIndex] > 0
end

-- 获取奶茶的毒药信息（支持桌子ID）
function DrinkManager.getDrinkPoisonInfoForTable(tableId, drinkIndex)
	local drinkState = DrinkManager.getTableState(tableId)
	return drinkState.poisonedDrinks[drinkIndex] or {}
end

-- 移除指定奶茶（支持桌子ID）
function DrinkManager.removeDrinkForTable(tableId, drinkIndex)
	local drinkState = DrinkManager.getTableState(tableId)
	local drinkModel = drinkState.activeDrinks[drinkIndex]

	if drinkModel then
		-- 断开点击事件
		local connection = drinkState.drinkConnections[drinkIndex]
		if connection then
			connection:Disconnect()
			drinkState.drinkConnections[drinkIndex] = nil
		end

		-- 销毁模型
		drinkModel:Destroy()
		drinkState.activeDrinks[drinkIndex] = nil

		print("桌子 " .. tableId .. " 移除奶茶 " .. drinkIndex)
	end
end

-- 调试：打印指定桌子的毒药数据
function DrinkManager.debugPrintPoisonDataForTable(tableId)
	local drinkState = DrinkManager.getTableState(tableId)
	print("=== 桌子 " .. tableId .. " 毒药数据调试 ===")

	for drinkIndex, poisoners in pairs(drinkState.poisonedDrinks) do
		if #poisoners > 0 then
			local poisonerNames = {}
			for _, poisoner in ipairs(poisoners) do
				table.insert(poisonerNames, poisoner.Name)
			end
			print("奶茶 " .. drinkIndex .. " 被注毒，下毒者: " .. table.concat(poisonerNames, ", "))
		end
	end

	print("=== 桌子 " .. tableId .. " 毒药数据调试完成 ===")
end

-- 获取所有桌子状态（调试用）
function DrinkManager.getAllTableStates()
	return tableStates
end

-- === 兼容性函数（保持原有接口，但映射到默认桌子） ===

-- 注意：以下函数为了兼容现有代码，默认使用第一张检测到的桌子
local function getDefaultTableId()
	for tableId, _ in pairs(tableStates) do
		return tableId -- 返回第一张桌子
	end
	return "2player_group1" -- 如果没有桌子，返回默认值
end

function DrinkManager.spawnAllDrinks()
	local tableId = getDefaultTableId()
	local workspace = game.Workspace
	local twoPlayerFolder = workspace:FindFirstChild("2Player")
	if twoPlayerFolder then
		local tableFolder = twoPlayerFolder:FindFirstChild(tableId)
		if tableFolder then
			return DrinkManager.spawnDrinksForTable(tableId, tableFolder)
		end
	end
	warn("无法找到默认桌子进行奶茶生成")
	return false
end

function DrinkManager.clearAllDrinks()
	local tableId = getDefaultTableId()
	DrinkManager.clearDrinksForTable(tableId)
end

function DrinkManager.poisonDrink(drinkIndex, poisoner)
	local tableId = getDefaultTableId()
	DrinkManager.poisonDrinkForTable(tableId, drinkIndex, poisoner)
end

function DrinkManager.isDrinkPoisoned(drinkIndex)
	local tableId = getDefaultTableId()
	return DrinkManager.isDrinkPoisonedForTable(tableId, drinkIndex)
end

function DrinkManager.getDrinkPoisonInfo(drinkIndex)
	local tableId = getDefaultTableId()
	return DrinkManager.getDrinkPoisonInfoForTable(tableId, drinkIndex)
end

function DrinkManager.removeDrink(drinkIndex)
	local tableId = getDefaultTableId()
	DrinkManager.removeDrinkForTable(tableId, drinkIndex)
end

function DrinkManager.debugPrintAllPoisonData()
	local tableId = getDefaultTableId()
	DrinkManager.debugPrintPoisonDataForTable(tableId)
end

return DrinkManager