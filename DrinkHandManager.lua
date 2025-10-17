-- 脚本名称: DrinkHandManager
-- 脚本作用: 管理玩家手中持有的奶茶模型，处理奶茶的挂载和移除
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService
-- V1.5新增: 喝饮料动作时的手持道具管理

local DrinkHandManager = {}
local DrinkManager = require(script.Parent.DrinkManager)

-- 保存玩家手中奶茶的状态
local playerHandDrinks = {} -- {[player] = {model = drinkModel, originalInfo = {...}}}

-- 获取玩家左手骨骼部位
local function getLeftHand(character)
	if not character then return nil end

	-- Roblox R15角色的左手部位
	local leftHand = character:FindFirstChild("LeftHand")
	if leftHand then
		return leftHand
	end

	-- 备用: R6角色检查
	local leftArm = character:FindFirstChild("Left Arm")
	if leftArm then
		return leftArm
	end

	warn("DrinkHandManager: 无法找到角色的左手")
	return nil
end

-- 获取或创建焊接关节
local function createWeld(part0, part1, c0, c1)
	-- 🔧 修复2：使用Motor6D确保物理同步，比WeldConstraint更可靠
	local weld = Instance.new("Motor6D")
	weld.Part0 = part0
	weld.Part1 = part1

	-- 设置相对位置和旋转（C0是Part0的相对位置，C1是Part1的相对位置）
	weld.C0 = c0 or CFrame.new()
	weld.C1 = c1 or CFrame.new()

	weld.Parent = part1

	return weld
end

-- 计算奶茶在手中的位置和旋转
-- 需要根据实际测试调整这些参数
local function calculateDrinkHandCFrame()
	-- 返回相对于左手的CFrame
	local offset = Vector3.new(0.5, -0.5, 0.3) -- X向右, Y向下, Z向前
	local rotation = CFrame.Angles(
		math.rad(90),   -- X轴旋转90度（使杯子竖起来）
		math.rad(0),    -- Y轴旋转
		math.rad(0)     -- Z轴旋转
	)

	return CFrame.new(offset) * rotation
end

-- 隐藏奶茶的数字显示标签
local function hideDrinkNumberLabel(drinkModel)
	if not drinkModel then return end

	local numPart = drinkModel:FindFirstChild("NumPart")
	if not numPart then
		-- warn("DrinkHandManager: 奶茶模型中找不到NumPart")
		return
	end

	local billboardGui = numPart:FindFirstChild("BillboardGui")
	if billboardGui then
		billboardGui.Enabled = false
		print(string.format("[DrinkHandManager] 已隐藏奶茶的BillboardGui"))
	else
		warn("DrinkHandManager: NumPart中找不到BillboardGui")
	end
end

-- 显示奶茶的数字显示标签
local function showDrinkNumberLabel(drinkModel)
	if not drinkModel then return end

	local numPart = drinkModel:FindFirstChild("NumPart")
	if not numPart then
		return
	end

	local billboardGui = numPart:FindFirstChild("BillboardGui")
	if billboardGui then
		billboardGui.Enabled = true
		print(string.format("[DrinkHandManager] 已显示奶茶的BillboardGui"))
	end
end

-- 将奶茶附着到玩家手中
-- 参数: player(玩家), drinkModel(奶茶模型), drinkIndex(奶茶编号用于记录), tableId(桌子ID用于获取原始旋转)
function DrinkHandManager.attachDrinkToHand(player, drinkModel, drinkIndex, tableId)
	if not player or not player.Character then
		warn("DrinkHandManager: 玩家或其角色无效")
		return false
	end

	if not drinkModel or not drinkModel.Parent then
		warn("DrinkHandManager: 奶茶模型无效")
		return false
	end

	print(string.format("[DrinkHandManager] 开始为玩家 %s 手中附着奶茶 %d", player.Name, drinkIndex or 0))

	local character = player.Character
	local leftHand = getLeftHand(character)

	if not leftHand then
		warn("DrinkHandManager: 无法获取玩家 " .. player.Name .. " 的左手")
		return false
	end

	-- 检查玩家是否已经持有奶茶
	if playerHandDrinks[player] then
		warn("DrinkHandManager: 玩家 " .. player.Name .. " 已经持有奶茶，先移除旧的")
		DrinkHandManager.removeDrinkFromHand(player)
	end

	-- 隐藏奶茶的数字显示标签
	hideDrinkNumberLabel(drinkModel)

	-- 计算手中奶茶的相对位置
	local handCFrame = calculateDrinkHandCFrame()

	-- 获取奶茶模型的主要部分（通常是PrimaryPart）
	local drinkPrimaryPart = drinkModel.PrimaryPart
	if not drinkPrimaryPart then
		-- 如果没有PrimaryPart，尝试找到第一个Part
		local parts = drinkModel:FindFirstChildOfClass("Part")
		or drinkModel:FindFirstChildOfClass("MeshPart")
		if parts then
			drinkPrimaryPart = parts
		else
			warn("DrinkHandManager: 奶茶模型中找不到任何Part")
			return false
		end
	end

	-- 🔧 修复4：获取奶茶在桌子上的原始旋转，在手里保持相同角度
	-- 从DrinkModel获取原始模型的旋转
	local drinkState = DrinkManager.getTableState(tableId)
	local originalDrinkOnTable = drinkState.activeDrinks[drinkIndex]

	local originalRotation = CFrame.new()  -- 默认无旋转
	if originalDrinkOnTable and originalDrinkOnTable.PrimaryPart then
		-- 获取桌子上奶茶的旋转（不包括位置）
		originalRotation = originalDrinkOnTable.PrimaryPart.CFrame - originalDrinkOnTable.PrimaryPart.CFrame.Position
	end

	-- 🔧 关键修复3：解除所有部件的锚固，并将它们焊接到PrimaryPart上
	-- 这样既能让PrimaryPart被焊接到手上，又能保持模型结构完整
	local allParts = {}
	for _, part in pairs(drinkModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = false  -- 解除所有部件的锚固
			if part ~= drinkPrimaryPart then
				table.insert(allParts, part)
			end
		end
	end

	-- 将所有部件焊接到PrimaryPart上，保持模型结构
	for _, part in pairs(allParts) do
		local weldBetweenParts = Instance.new("Motor6D")
		weldBetweenParts.Part0 = drinkPrimaryPart
		weldBetweenParts.Part1 = part
		weldBetweenParts.C0 = drinkPrimaryPart.CFrame:Inverse() * part.CFrame
		weldBetweenParts.C1 = part.CFrame:Inverse() * part.CFrame
		weldBetweenParts.Parent = part
	end

	-- 设置奶茶在手中的位置
	if drinkModel:IsA("Model") and drinkModel.PrimaryPart then
		-- 使用SetPrimaryPartCFrame设置位置
		local targetCFrame = leftHand.CFrame * handCFrame
		drinkModel:SetPrimaryPartCFrame(targetCFrame)
	end

	-- 🔧 修复2：计算正确的焊接偏移，使奶茶正确跟随手的运动
	-- C1应该是奶茶PrimaryPart相对于自己位置的偏移（通常为单位矩阵）
	local c1 = drinkPrimaryPart.CFrame:Inverse() * drinkModel.PrimaryPart.CFrame

	-- 🔧 修复4：计算c0时使用桌子上的原始旋转，保持相同的角度
	-- 获取左手的位置，加上偏移后的位置，再加上原始旋转
	local offsetPosition = Vector3.new(0, 0, 0)  -- 完全重合手和模型
	local additionalRotation = CFrame.Angles(math.rad(0), math.rad(90), math.rad(0))  -- Y轴+90度
	local targetCFrame = leftHand.CFrame * CFrame.new(offsetPosition) * originalRotation * additionalRotation
	local c0 = leftHand.CFrame:Inverse() * targetCFrame

	-- 创建焊接连接（传入正确的C0和C1参数）
	local weld = createWeld(leftHand, drinkPrimaryPart, c0, c1)

	-- 保存状态
	playerHandDrinks[player] = {
		model = drinkModel,
		primaryPart = drinkPrimaryPart,
		weld = weld,
		drinkIndex = drinkIndex,
		originalPhysicsState = {}
	}

	print(string.format("[DrinkHandManager] ✅ 成功为玩家 %s 附着奶茶 %d 到左手", player.Name, drinkIndex or 0))
	return true
end

-- 从玩家手中移除奶茶
-- 参数: player(玩家)
function DrinkHandManager.removeDrinkFromHand(player)
	if not player then
		warn("DrinkHandManager: 玩家参数无效")
		return false
	end

	local handDrinkData = playerHandDrinks[player]
	if not handDrinkData then
		-- 玩家手中没有奶茶
		return false
	end

	print(string.format("[DrinkHandManager] 开始移除玩家 %s 手中的奶茶", player.Name))

	local drinkModel = handDrinkData.model
	local weld = handDrinkData.weld

	-- 移除焊接连接
	if weld and weld.Parent then
		pcall(function()
			weld:Destroy()
		end)
	end

	-- 显示奶茶的数字标签
	if drinkModel and drinkModel.Parent then
		showDrinkNumberLabel(drinkModel)
	end

	-- 清除状态
	playerHandDrinks[player] = nil

	print(string.format("[DrinkHandManager] ✅ 成功移除玩家 %s 手中的奶茶", player.Name))
	return true
end

-- 销毁玩家手中的奶茶（包括模型本身）
function DrinkHandManager.destroyHandDrink(player)
	if not player then
		return false
	end

	local handDrinkData = playerHandDrinks[player]
	if not handDrinkData then
		return false
	end

	print(string.format("[DrinkHandManager] 销毁玩家 %s 手中的奶茶模型", player.Name))

	-- 先移除焊接
	DrinkHandManager.removeDrinkFromHand(player)

	-- 销毁模型
	if handDrinkData.model and handDrinkData.model.Parent then
		pcall(function()
			handDrinkData.model:Destroy()
		end)
	end

	return true
end

-- 检查玩家是否持有奶茶
function DrinkHandManager.hasHandDrink(player)
	if not player then
		return false
	end

	return playerHandDrinks[player] ~= nil
end

-- 获取玩家手中的奶茶信息
function DrinkHandManager.getHandDrinkInfo(player)
	if not player then
		return nil
	end

	local handDrinkData = playerHandDrinks[player]
	if not handDrinkData then
		return nil
	end

	return {
		model = handDrinkData.model,
		drinkIndex = handDrinkData.drinkIndex
	}
end

-- 清理玩家离线时的奶茶
function DrinkHandManager.cleanupPlayerHandDrink(player)
	if not player then
		return
	end

	if playerHandDrinks[player] then
		print(string.format("[DrinkHandManager] 清理离线玩家 %s 的手中奶茶", player.Name))

		-- 先销毁模型
		if playerHandDrinks[player].model then
			pcall(function()
				playerHandDrinks[player].model:Destroy()
			end)
		end

		-- 清除状态
		playerHandDrinks[player] = nil
	end
end

-- 初始化
function DrinkHandManager.initialize()
	-- 监听玩家离开，清理手中奶茶
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		DrinkHandManager.cleanupPlayerHandDrink(player)
	end)

	print("✅ DrinkHandManager 初始化完成")
end

-- 导出到全局
_G.DrinkHandManager = DrinkHandManager

-- 启动初始化
DrinkHandManager.initialize()

return DrinkHandManager
