-- 脚本名称: DrinkManager
-- 脚本作用: 管理奶茶的生成、摆放和状态（支持多桌）
-- 脚本类型: Script
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
-- 每个模型的单独旋转配置（使用角度值，不是弧度）
local DRINK_ORIENTATIONS = {
	-- 默认配置
	default = {
		rotationX = 0,      -- X轴旋转角度
		rotationY = 0,      -- Y轴旋转角度
		rotationZ = 0,      -- Z轴旋转角度
		heightOffset = 0    -- 高度偏移
	},
	-- 特定模型配置（填入你希望的最终Orientation角度）
	Default01 = {
		rotationX = 0,
		rotationY = 0,
		rotationZ = 90,     -- 如果需要Z轴90度
		heightOffset = 0
	},
	Default02 = {
		rotationX = 0,
		rotationY = 0,
		rotationZ = 90,     -- 如果需要Z轴90度
		heightOffset = 0
	},
	Sushi = {
		rotationX = 0,
		rotationY = 0,
		rotationZ = 0,      -- 填入Sushi需要的角度
		heightOffset = 0
	},
	Coffee = {
		rotationX = 0,
		rotationY = 0,
		rotationZ = 90,
		heightOffset = 0
	},
	Cola = {
		rotationX = 0,
		rotationY = 180,
		rotationZ = 90,
		heightOffset = 0
	},
	MangoTee = {
		rotationX = 0,
		rotationY = 90,
		rotationZ = 90,
		heightOffset = 0
	},
	Fries = {
		rotationX = 0,
		rotationY = 0,
		rotationZ = 0,
		heightOffset = 0
	},
	Watermelon = {
		rotationX = 0,
		rotationY = 0,
		rotationZ = 0,
		heightOffset = 0.2
	},
	Lobster = {
		rotationX = 0,
		rotationY = 180,
		rotationZ = 0,
		heightOffset = 0
	},
	Cake = {
		rotationX = 0,
		rotationY = 180,
		rotationZ = 0,
		heightOffset = 0
	},
	Doll = {
		rotationX = 0,
		rotationY = 180,
		rotationZ = 0,
		heightOffset = 0
	},
	Starlo = {
		rotationX = 0,
		rotationY = 180,
		rotationZ = 0,
		heightOffset = 0
	},
	Sprinkitty = {
		rotationX = 0,
		rotationY = 180,
		rotationZ = 0,
		heightOffset = 0
	}
	
}

-- 获取模型的旋转配置
local function getDrinkOrientation(modelName)
	return DRINK_ORIENTATIONS[modelName] or DRINK_ORIENTATIONS.default
end

-- 获取或创建桌子状态
function DrinkManager.getTableState(tableId)
	if not tableStates[tableId] then
		tableStates[tableId] = {
			activeDrinks = {},          -- 当前桌上的奶茶 {index = drinkModel}
			poisonedDrinks = {},        -- 被注入毒药的奶茶 {index = {poisoner1, poisoner2, ...}}
			drinkConnections = {}       -- 奶茶点击事件连接
		}
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

-- ============================================
-- V2.0 皮肤系统集成
-- ============================================

-- 从tableId获取对局玩家
function DrinkManager.getPlayersFromTable(tableId)
	if not _G.TableManager then
		warn("TableManager未加载")
		return nil, nil
	end

	local gameInstance = _G.TableManager.getTableInstance(tableId)
	if not gameInstance then
		warn("未找到桌子实例: " .. tableId)
		return nil, nil
	end

	return gameInstance.gameState.player1, gameInstance.gameState.player2
end

-- 获取玩家的皮肤模型
function DrinkManager.getPlayerSkinModel(player, tableId, index)
	if not player then
		warn("玩家参数为空")
		-- 回退到默认模型
		if index % 2 == 1 then
			return default01Model
		else
			return default02Model
		end
	end

	-- 从SkinDataManager获取装备的皮肤ID
	local equippedSkinId = nil
	if _G.SkinDataManager and _G.SkinDataManager.getEquippedSkin then
		equippedSkinId = _G.SkinDataManager.getEquippedSkin(player)
	end

	-- 如果玩家未装备皮肤(nil),使用默认皮肤
	if not equippedSkinId then
		-- 判断玩家是player1还是player2
		local player1, player2 = DrinkManager.getPlayersFromTable(tableId)
		if player1 and player == player1 then
			return default01Model
		elseif player2 and player == player2 then
			return default02Model
		else
			-- 无法判断,回退到index判断
			if index % 2 == 1 then
				return default01Model
			else
				return default02Model
			end
		end
	end

	-- 根据皮肤ID加载模型
	if not _G.SkinConfig then
		warn("SkinConfig未加载")
		-- 回退到默认模型
		if index % 2 == 1 then
			return default01Model
		else
			return default02Model
		end
	end

	local skinInfo = _G.SkinConfig.getSkinInfo(equippedSkinId)
	if not skinInfo then
		warn("皮肤配置不存在: " .. equippedSkinId)
		-- 回退到默认模型
		if index % 2 == 1 then
			return default01Model
		else
			return default02Model
		end
	end

	local skinModel = drinkModelFolder:FindFirstChild(skinInfo.modelName)
	if not skinModel then
		warn(string.format("[DrinkManager] 皮肤模型不存在: %s (玩家: %s, 皮肤ID: %d)",
			skinInfo.modelName, player.Name, equippedSkinId))
		warn(string.format("[DrinkManager] DrinkModel文件夹中的模型: %s",
			table.concat((function()
				local names = {}
				for _, child in pairs(drinkModelFolder:GetChildren()) do
					table.insert(names, child.Name)
				end
				return names
			end)(), ", ")))
		-- 回退到默认模型
		if index % 2 == 1 then
			return default01Model
		else
			return default02Model
		end
	end

	return skinModel
end

-- 生成单个奶茶（支持指定桌子）
function DrinkManager.createSingleDrink(tableId, classicTable, index, attachment)
	local drinkState = DrinkManager.getTableState(tableId)

	-- V2.0: 根据玩家装备的皮肤选择模型
	local player1, player2 = DrinkManager.getPlayersFromTable(tableId)
	local targetPlayer = nil
	if index % 2 == 1 then
		-- 奇数位置：玩家A
		targetPlayer = player1
	else
		-- 偶数位置：玩家B
		targetPlayer = player2
	end

	-- 获取玩家的皮肤模型(如果未装备或加载失败,会自动回退到默认模型)
	local sourceModel = DrinkManager.getPlayerSkinModel(targetPlayer, tableId, index)

	local drinkModel = DrinkManager.deepCloneModel(sourceModel)

	if not drinkModel then
		warn("桌子 " .. tableId .. " 奶茶模型克隆失败: " .. index)
		return nil
	end

	-- 设置奶茶名称和父级
	drinkModel.Name = "Drink_" .. string.format("%02d", index)
	drinkModel.Parent = classicTable

	-- 获取该模型的旋转配置
	local orientation = getDrinkOrientation(sourceModel.Name)

	-- 计算奶茶位置和朝向
	-- 直接使用attachment的位置，但使用配置中的绝对旋转角度
	local position = attachment.WorldPosition + Vector3.new(0, orientation.heightOffset, 0)
	local finalRotation = CFrame.Angles(
		math.rad(orientation.rotationX),  -- 将角度转换为弧度
		math.rad(orientation.rotationY),
		math.rad(orientation.rotationZ)
	)
	local finalCFrame = CFrame.new(position) * finalRotation

	-- 设置模型位置
	if drinkModel.PrimaryPart then
		drinkModel:SetPrimaryPartCFrame(finalCFrame)
	else
		-- 如果没有PrimaryPart,尝试自动设置一个并使用MoveTo
		local firstPart = drinkModel:FindFirstChildOfClass("Part")
		if not firstPart then
			firstPart = drinkModel:FindFirstChildOfClass("MeshPart")
		end

		if firstPart then
			-- 自动设置PrimaryPart
			drinkModel.PrimaryPart = firstPart

			-- 使用SetPrimaryPartCFrame来正确定位整个模型
			drinkModel:SetPrimaryPartCFrame(finalCFrame)
		else
			warn(string.format("[DrinkManager] ❌ 模型%s既没有PrimaryPart,也没有Part/MeshPart!",
				drinkModel.Name))
		end
	end

	-- 设置奶茶点击检测
	DrinkManager.setupDrinkClickDetection(tableId, drinkModel, index)

	-- 设置奶茶编号显示
	DrinkManager.setupDrinkNumberDisplay(drinkModel, index)

	return drinkModel
end

-- 设置奶茶编号显示
function DrinkManager.setupDrinkNumberDisplay(drinkModel, index)
	-- 按照正确路径查找：模型 -> NumPart -> BillboardGui -> Num
	local numPart = drinkModel:FindFirstChild("NumPart")
	if not numPart then
		warn("桌子奶茶 " .. index .. " 未找到NumPart")
		return
	end

	local billboardGui = numPart:FindFirstChild("BillboardGui")
	if not billboardGui then
		warn("桌子奶茶 " .. index .. " 的NumPart下未找到BillboardGui")
		return
	end

	local numLabel = billboardGui:FindFirstChild("Num")
	if not numLabel or not numLabel:IsA("TextLabel") then
		warn("桌子奶茶 " .. index .. " 的BillboardGui下未找到Num TextLabel")
		return
	end

	-- 设置编号并确保只有一个文本显示
	numLabel.Text = tostring(index)

	-- 确保文本属性正确，避免重叠显示
	numLabel.BackgroundTransparency = 1 -- 确保背景透明
	numLabel.TextStrokeTransparency = 0 -- 如果有描边，确保描边显示
	numLabel.ZIndex = 10 -- 确保在最上层显示

end

-- 设置奶茶点击检测（支持桌子ID）
function DrinkManager.setupDrinkClickDetection(tableId, drinkModel, index)
	local drinkState = DrinkManager.getTableState(tableId)

	-- 方案: 为模型中的每个Part都添加ClickDetector
	local clickDetectors = {}
	local hasClickDetector = false

	-- 遍历模型中的所有Part并添加ClickDetector
	for _, child in pairs(drinkModel:GetDescendants()) do
		if child:IsA("BasePart") then  -- 包括Part, MeshPart, UnionOperation等
			-- 跳过已有ClickDetector的Part
			local existingDetector = child:FindFirstChildOfClass("ClickDetector")
			if not existingDetector then
				-- 为这个Part创建ClickDetector
				local clickDetector = Instance.new("ClickDetector")
				clickDetector.MaxActivationDistance = 50
				clickDetector.Parent = child

				-- 连接点击事件
				local connection = clickDetector.MouseClick:Connect(function(player)
					DrinkManager.onDrinkClicked(player, tableId, index, drinkModel)
				end)

				table.insert(clickDetectors, connection)
				hasClickDetector = true

			else
				-- 如果已有ClickDetector，也连接事件
				local connection = existingDetector.MouseClick:Connect(function(player)
					DrinkManager.onDrinkClicked(player, tableId, index, drinkModel)
				end)
				table.insert(clickDetectors, connection)
				hasClickDetector = true
			end
		end
	end

	-- 如果没有找到任何Part，报告错误
	if not hasClickDetector then
		warn(string.format("[DrinkManager] 桌子 %s 奶茶 %d 没有找到任何Part来添加ClickDetector",
			tableId, index))
	end

	-- 存储所有连接（用于后续清理）
	drinkState.drinkConnections[index] = clickDetectors
end

-- 奶茶点击事件处理（支持桌子ID）
function DrinkManager.onDrinkClicked(player, tableId, drinkIndex, drinkModel)

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
				DrinkSelectionManager.onPlayerSelectDrink(player, drinkIndex)
			elseif gameStatus.phase == "poison" and PoisonSelectionManager.onPlayerSelectDrink then
				PoisonSelectionManager.onPlayerSelectDrink(player, drinkIndex)
			else
			end
		else
			warn("无法获取桌子 " .. tableId .. " 的GameInstance")
		end
	else
		warn("TableManager不可用")
	end
end

-- 为指定桌子生成所有奶茶
function DrinkManager.spawnDrinksForTable(tableId, tableFolder)

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

	return true
end

-- 清除指定桌子的所有奶茶
function DrinkManager.clearDrinksForTable(tableId)
	local drinkState = DrinkManager.getTableState(tableId)

	-- 清除奶茶模型
	local clearedCount = 0
	for index, drinkModel in pairs(drinkState.activeDrinks) do
		if drinkModel and drinkModel.Parent then
			drinkModel:Destroy()
			clearedCount = clearedCount + 1
		end
	end

	-- 🔧 内存泄漏修复：增强连接清理逻辑
	local disconnectedCount = 0
	local failedCount = 0

	for index, connections in pairs(drinkState.drinkConnections) do
		if connections then
			-- 如果是数组，断开所有连接
			if type(connections) == "table" then
				for i, connection in pairs(connections) do
					if connection then
						local success, errorMsg = pcall(function()
							-- 更严格的类型检查：确保是RBXScriptConnection
							if type(connection) == "userdata" and connection.Disconnect and type(connection.Disconnect) == "function" then
								connection:Disconnect()
								return true
							else
								warn(string.format("连接对象类型异常 (桌子%s, 奶茶%d, 连接%s): %s",
									tableId, index, tostring(i), type(connection)))
								return false
							end
						end)
						if success then
							disconnectedCount = disconnectedCount + 1
						else
							failedCount = failedCount + 1
							warn(string.format("断开连接失败 (桌子%s, 奶茶%d, 连接%s): %s",
								tableId, index, tostring(i), tostring(errorMsg)))
						end
					end
				end
				-- 兼容旧版本的单个连接
			elseif type(connections) == "userdata" then
				local success, errorMsg = pcall(function()
					if connections.Disconnect and type(connections.Disconnect) == "function" then
						connections:Disconnect()
						return true
					else
						warn(string.format("单一连接对象类型异常 (桌子%s, 奶茶%d): %s",
							tableId, index, type(connections)))
						return false
					end
				end)
				if success then
					disconnectedCount = disconnectedCount + 1
				else
					failedCount = failedCount + 1
					warn(string.format("断开单一连接失败 (桌子%s, 奶茶%d): %s",
						tableId, index, tostring(errorMsg)))
				end
			end
		end
	end

	-- 重置状态
	drinkState.activeDrinks = {}
	drinkState.drinkConnections = {}
	drinkState.poisonedDrinks = {}

	-- 额外保险：直接搜索并清理可能遗留的奶茶模型
	local workspace = game.Workspace
	local twoPlayerFolder = workspace:FindFirstChild("2Player")
	if twoPlayerFolder then
		local tableFolder = twoPlayerFolder:FindFirstChild(tableId)
		if tableFolder then
			local classicTable = tableFolder:FindFirstChild("ClassicTable")
			if classicTable then
				-- 查找所有名称匹配 "Drink_XX" 格式的模型并删除
				local extraClearedCount = 0
				for _, child in pairs(classicTable:GetChildren()) do
					if child.Name:match("^Drink_%d%d$") then
						child:Destroy()
						extraClearedCount = extraClearedCount + 1
					end
				end
				-- 如果额外清理了任何奶茶，说明之前的清理可能有遗漏
				if extraClearedCount > 0 then
					warn("桌子 " .. tableId .. " 额外清理了 " .. extraClearedCount .. " 个遗留奶茶模型")
				end
			end
		end
	end

end

-- 为奶茶注入毒药（支持桌子ID）
function DrinkManager.poisonDrinkForTable(tableId, drinkIndex, poisoner)
	local drinkState = DrinkManager.getTableState(tableId)

	if not drinkState.poisonedDrinks[drinkIndex] then
		drinkState.poisonedDrinks[drinkIndex] = {}
	end

	table.insert(drinkState.poisonedDrinks[drinkIndex], poisoner)
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

-- 清除指定奶茶的所有毒药（支持桌子ID）
function DrinkManager.clearAllPoisonFromDrinkForTable(tableId, drinkIndex)
	local drinkState = DrinkManager.getTableState(tableId)

	if drinkState.poisonedDrinks[drinkIndex] then
		drinkState.poisonedDrinks[drinkIndex] = {}
		return true
	end

	return false
end

-- 从指定奶茶中移除特定玩家的毒药（支持桌子ID）
function DrinkManager.removePoisonFromDrinkForTable(tableId, drinkIndex, player)
	local drinkState = DrinkManager.getTableState(tableId)

	if drinkState.poisonedDrinks[drinkIndex] then
		for i = #drinkState.poisonedDrinks[drinkIndex], 1, -1 do
			if drinkState.poisonedDrinks[drinkIndex][i] == player then
				table.remove(drinkState.poisonedDrinks[drinkIndex], i)
				return true
			end
		end
	end

	return false
end

-- 移除指定奶茶（支持桌子ID）
function DrinkManager.removeDrinkForTable(tableId, drinkIndex)
	local drinkState = DrinkManager.getTableState(tableId)
	local drinkModel = drinkState.activeDrinks[drinkIndex]

	if drinkModel then
		-- 断开点击事件（现在是数组）
		local connections = drinkState.drinkConnections[drinkIndex]
		if connections then
			-- 如果是数组，断开所有连接
			if type(connections) == "table" then
				for _, connection in pairs(connections) do
					if connection and type(connection) == "userdata" then
						local success, errorMsg = pcall(function()
							if connection.Disconnect and type(connection.Disconnect) == "function" then
								connection:Disconnect()
							end
						end)
						if not success then
							warn(string.format("removeDrinkForTable断开连接失败 (桌子%s, 奶茶%d): %s",
								tableId, drinkIndex, tostring(errorMsg)))
						end
					end
				end
				-- 兼容旧版本的单个连接
			elseif type(connections) == "userdata" then
				local success, errorMsg = pcall(function()
					if connections.Disconnect and type(connections.Disconnect) == "function" then
						connections:Disconnect()
					end
				end)
				if not success then
					warn(string.format("removeDrinkForTable断开单一连接失败 (桌子%s, 奶茶%d): %s",
						tableId, drinkIndex, tostring(errorMsg)))
				end
			end
			drinkState.drinkConnections[drinkIndex] = nil
		end

		-- 销毁模型
		drinkModel:Destroy()
		drinkState.activeDrinks[drinkIndex] = nil

	end
end

-- 调试：打印指定桌子的毒药数据
function DrinkManager.debugPrintPoisonDataForTable(tableId)
	local drinkState = DrinkManager.getTableState(tableId)
	-- 调试函数保留但移除内部print语句
	for drinkIndex, poisoners in pairs(drinkState.poisonedDrinks) do
		if #poisoners > 0 then
			local poisonerNames = {}
			for _, poisoner in ipairs(poisoners) do
				table.insert(poisonerNames, poisoner.Name)
			end
		end
	end
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

-- 简化版函数（使用默认桌子ID）
function DrinkManager.clearAllPoisonFromDrink(drinkIndex)
	local tableId = getDefaultTableId()
	return DrinkManager.clearAllPoisonFromDrinkForTable(tableId, drinkIndex)
end

function DrinkManager.removePoisonFromDrink(drinkIndex, player)
	local tableId = getDefaultTableId()
	return DrinkManager.removePoisonFromDrinkForTable(tableId, drinkIndex, player)
end

return DrinkManager