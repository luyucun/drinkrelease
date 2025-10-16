-- 脚本名称: MultiModelRotatorClient
-- 脚本作用: 自动检测文件夹下所有模型并让它们旋转
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer → StarterPlayerScripts

local RunService = game:GetService("RunService")

-- ⚙️ 配置区域
local FOLDER_PATH = "Workspace.SkinTemplate"  -- 👈 监控的文件夹路径
local ROTATION_SPEED = 36  -- 旋转速度（度/秒）
local ROTATION_AXIS = "Y"  -- 旋转轴
local AUTO_DETECT_NEW_MODELS = true  -- 是否自动检测新添加的模型

-- 类型定义
type RotationSystem = {
	base: Part,
	connection: RBXScriptConnection,
	angle: number,
	model: Model | BasePart
}

-- 存储所有旋转系统
local rotationSystems: {[string]: RotationSystem} = {}

-- 等待文件夹加载
local function waitForFolder(): Instance?
	local pathParts = {}
	for part in FOLDER_PATH:gmatch("[^.]+") do
		table.insert(pathParts, part)
	end

	local current: Instance = game
	for _, pathPart in ipairs(pathParts) do
		current = current:WaitForChild(pathPart, 30)
		if not current then
			warn("❌ 未找到文件夹路径: " .. FOLDER_PATH)
			return nil
		end
	end

	return current
end

local targetFolder = waitForFolder()

if not targetFolder then
	warn("❌ 文件夹加载失败")
	return
end

-- 等待模型内容加载
local function waitForModelContent(model: Instance, timeout: number): boolean
	local startTime = tick()

	while (tick() - startTime) < timeout do
		local childCount = #model:GetChildren()
		if childCount > 0 then
			return true
		end
		task.wait(0.1)
	end

	return false
end

-- 为单个模型创建旋转系统
local function setupRotationForModel(model: Model | BasePart)
	local modelName = model.Name

	-- 检查是否已经设置过
	if rotationSystems[modelName] then
		return
	end

	-- 等待模型内容加载
	if not waitForModelContent(model, 5) then
		return
	end

	-- 获取模型中心点
	local pivot: CFrame
	if model:IsA("Model") then
		pivot = model:GetPivot()
	else
		pivot = model.CFrame
	end

	-- 创建旋转基座（只使用位置，重置旋转方向）
	local rotatingBase = Instance.new("Part")
	rotatingBase.Name = "RotatingBase_" .. modelName
	rotatingBase.Size = Vector3.new(0.1, 0.1, 0.1)
	rotatingBase.Transparency = 1
	rotatingBase.CanCollide = false
	rotatingBase.Anchored = true
	-- 🔧 只使用Pivot的位置，方向重置为世界坐标系方向
	rotatingBase.CFrame = CFrame.new(pivot.Position)
	rotatingBase.Parent = workspace

	-- 焊接所有Part
	local partsCount = 0
	local function weldParts(obj: Instance)
		if obj:IsA("BasePart") then
			obj.Anchored = false

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rotatingBase
			weld.Part1 = obj
			weld.Parent = rotatingBase

			partsCount = partsCount + 1
		end

		-- 递归处理子对象
		for _, child in pairs(obj:GetChildren()) do
			weldParts(child)
		end
	end

	if model:IsA("Model") then
		for _, child in pairs(model:GetChildren()) do
			weldParts(child)
		end
	else
		weldParts(model)
	end

	if partsCount == 0 then
		rotatingBase:Destroy()
		return
	end

	-- 创建旋转函数
	local rotationAngle = 0
	local function rotateModel(deltaTime: number)
		local angleIncrement = math.rad(ROTATION_SPEED * deltaTime)
		rotationAngle = rotationAngle + angleIncrement

		local basePosition = rotatingBase.CFrame.Position

		local rotationCFrame: CFrame
		if ROTATION_AXIS == "Y" then
			rotationCFrame = CFrame.new(basePosition) * CFrame.Angles(0, rotationAngle, 0)
		elseif ROTATION_AXIS == "X" then
			rotationCFrame = CFrame.new(basePosition) * CFrame.Angles(rotationAngle, 0, 0)
		elseif ROTATION_AXIS == "Z" then
			rotationCFrame = CFrame.new(basePosition) * CFrame.Angles(0, 0, rotationAngle)
		else
			rotationCFrame = CFrame.new(basePosition) * CFrame.Angles(0, rotationAngle, 0)
		end

		rotatingBase.CFrame = rotationCFrame
	end

	-- 连接到RenderStepped
	local connection = RunService.RenderStepped:Connect(rotateModel)

	-- 存储旋转系统
	rotationSystems[modelName] = {
		base = rotatingBase,
		connection = connection,
		angle = rotationAngle,
		model = model
	}

	-- 监听模型删除
	local cleanupConnection: RBXScriptConnection
	cleanupConnection = model.AncestryChanged:Connect(function()
		if not model.Parent then
			-- 模型被删除，清理旋转系统
			local system = rotationSystems[modelName]
			if system then
				system.connection:Disconnect()
				system.base:Destroy()
				rotationSystems[modelName] = nil
			end

			-- 断开自身连接
			cleanupConnection:Disconnect()
		end
	end)
end

-- 扫描并设置所有现有模型
local function scanAndSetupAllModels()
	for _, child in pairs(targetFolder:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			setupRotationForModel(child)
		end
	end
end

-- 监听新模型添加
if AUTO_DETECT_NEW_MODELS then
	targetFolder.ChildAdded:Connect(function(child: Instance)
		-- 延迟一下，确保模型完全加载
		task.wait(0.5)

		if child:IsA("Model") or child:IsA("BasePart") then
			setupRotationForModel(child)
		end
	end)
end

-- 初始扫描
scanAndSetupAllModels()

-- 清理函数（玩家离开时）
game.Players.LocalPlayer.AncestryChanged:Connect(function()
	for _, system in pairs(rotationSystems) do
		system.connection:Disconnect()
		system.base:Destroy()
	end

	table.clear(rotationSystems)
end)
