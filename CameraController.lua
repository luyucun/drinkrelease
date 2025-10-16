-- 脚本名称: CameraController
-- 脚本作用: 控制玩家镜头，管理不同游戏阶段的视角
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayerScripts

local CameraController = {}
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- 镜头状态
local cameraState = {
	originalCFrame = nil,
	isControlled = false,
	currentTween = nil
}

-- 镜头配置参数 (可调整)
local CAMERA_CONFIG = {
	-- 准备阶段镜头参数
	preparePhase = {
		height = 8,          -- 镜头高度
		angle = 5,          -- 俯视角度
		distance = 8         -- 距离桌子的距离
	},

	-- 注入毒药阶段镜头参数
	poisonPhase = {
		height = 5,
		angle = 5,
		distance = 5          -- 更近的距离
	},

	-- 选择奶茶阶段镜头参数
	selectPhase = {
		height = 6,
		angle = 5,
		distance = 6
	},

	-- 镜头动画时间
	tweenTime = 1.1
}

-- 保存原始镜头状态
function CameraController.saveOriginalCamera()
	if not cameraState.isControlled then
		cameraState.originalCFrame = camera.CFrame
	end
end

-- 恢复原始镜头状态
function CameraController.restoreOriginalCamera()
	if cameraState.originalCFrame then
		camera.CameraType = Enum.CameraType.Custom
		camera.CFrame = cameraState.originalCFrame
		cameraState.isControlled = false
	end
end

-- 计算镜头CFrame
function CameraController.calculateCameraCFrame(tablePosition, config)
	-- 计算镜头位置
	local cameraPosition = Vector3.new(
		tablePosition.X,
		tablePosition.Y + config.height,
		tablePosition.Z + config.distance
	)

	-- 计算看向桌子的方向
	local lookDirection = (tablePosition - cameraPosition).Unit

	-- 创建CFrame，让镜头看向桌子
	local cframe = CFrame.lookAt(cameraPosition, tablePosition)

	-- 应用俯视角度
	local angleRadians = math.rad(config.angle)
	cframe = cframe * CFrame.Angles(angleRadians, 0, 0)

	return cframe
end

-- 平滑移动镜头到指定位置
function CameraController.moveCameraTo(targetCFrame, duration)
	-- 停止当前动画
	if cameraState.currentTween then
		cameraState.currentTween:Cancel()
	end

	-- 设置镜头类型为脚本控制
	camera.CameraType = Enum.CameraType.Scriptable
	cameraState.isControlled = true

	-- 创建镜头移动动画
	local tweenInfo = TweenInfo.new(
		duration or CAMERA_CONFIG.tweenTime,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	)

	cameraState.currentTween = TweenService:Create(
		camera,
		tweenInfo,
		{CFrame = targetCFrame}
	)

	cameraState.currentTween:Play()

	return cameraState.currentTween
end

-- 进入准备阶段镜头
function CameraController.enterPreparePhase(tablePosition)
	CameraController.saveOriginalCamera()

	local targetCFrame = CameraController.calculateCameraCFrame(
		tablePosition,
		CAMERA_CONFIG.preparePhase
	)

	CameraController.moveCameraTo(targetCFrame)
end

-- 进入毒药注入阶段镜头
function CameraController.enterPoisonPhase(tablePosition)
	local targetCFrame = CameraController.calculateCameraCFrame(
		tablePosition,
		CAMERA_CONFIG.poisonPhase
	)

	CameraController.moveCameraTo(targetCFrame)
end

-- 进入选择奶茶阶段镜头
function CameraController.enterSelectPhase(tablePosition)
	local targetCFrame = CameraController.calculateCameraCFrame(
		tablePosition,
		CAMERA_CONFIG.selectPhase
	)

	CameraController.moveCameraTo(targetCFrame)
end

-- 镜头聚焦到指定玩家
function CameraController.focusOnPlayer(targetPlayer, duration)
	if not targetPlayer or not targetPlayer.Character then return end

	local character = targetPlayer.Character
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end

	-- 获取桌子位置用于判断玩家位置
	local tablePosition = CameraController.getTablePosition()
	if not tablePosition then
		warn("无法获取桌子位置，使用默认镜头设置")
		return
	end

	local playerPosition = humanoidRootPart.Position

	-- 判断玩家在桌子的左边还是右边
	local relativeX = playerPosition.X - tablePosition.X
	local isPlayerOnLeft = relativeX < 0

	-- 根据玩家位置调整镜头位置
	local cameraOffset
	if isPlayerOnLeft then
		-- 左边玩家：镜头位于玩家右前方偏上，角度稍微偏向玩家
		cameraOffset = Vector3.new(5, 4, 3)
	else
		-- 右边玩家：镜头位于玩家左前方偏上，角度稍微偏向玩家
		cameraOffset = Vector3.new(-5, 4, 3)
	end

	local cameraPosition = playerPosition + cameraOffset
	-- 镜头目标点：玩家胸部到头部之间的位置，确保看到脸部
	local lookAtTarget = playerPosition + Vector3.new(0, 2, 0)
	local targetCFrame = CFrame.lookAt(cameraPosition, lookAtTarget)

	CameraController.moveCameraTo(targetCFrame, duration or 2)
end

-- 获取桌子位置的函数（支持多桌）
function CameraController.getTablePosition(tableId)
	local workspace = game.Workspace

	local twoPlayerFolder = workspace:FindFirstChild("2Player")
	if not twoPlayerFolder then
		warn("CameraController: 未找到Workspace.2Player文件夹")
		return nil
	end

	-- 如果没有指定tableId，尝试根据玩家位置检测
	if not tableId then
		tableId = CameraController.detectPlayerTable()
		if not tableId then
			warn("CameraController: 无法检测玩家所在桌子，使用默认桌子")
			tableId = "2player_group1"
		end
	end

	local battleGroup = twoPlayerFolder:FindFirstChild(tableId)
	if not battleGroup then
		warn("CameraController: 未找到桌子: " .. tableId)
		return nil
	end

	local classicTable = battleGroup:FindFirstChild("ClassicTable")
	if not classicTable then
		warn("CameraController: 桌子 " .. tableId .. " 未找到ClassicTable")
		return nil
	end

	local tablePart = classicTable:FindFirstChild("TablePart")
	if tablePart and tablePart:IsA("Part") then
		return tablePart.Position
	end

	warn("CameraController: 桌子 " .. tableId .. " 无法找到ClassicTable下的TablePart")
	return nil
end

-- 检测玩家所在的桌子
function CameraController.detectPlayerTable()
	if not player.Character then
		return nil
	end

	local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return nil
	end

	-- 客户端无法直接访问_G.TableManager，使用距离检测作为备用方案
	local playerPosition = humanoidRootPart.Position
	local workspace = game.Workspace
	local twoPlayerFolder = workspace:FindFirstChild("2Player")

	if not twoPlayerFolder then
		return nil
	end

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
					if distance < closestDistance and distance < 20 then -- 20是最大检测距离
						closestDistance = distance
						closestTableId = child.Name
					end
				end
			end
		end
	end

	if closestTableId then
		return closestTableId
	end

	return nil
end

-- 初始化镜头控制器
function CameraController.initialize()
end

-- 远程事件处理（接收服务器的镜头控制指令）
local function setupRemoteEvents()
	local replicatedStorage = game:GetService("ReplicatedStorage")

	-- 等待RemoteEvents文件夹
	local remoteEventsFolder = replicatedStorage:WaitForChild("RemoteEvents", 60) -- 增加到60秒
	if not remoteEventsFolder then
		warn("CameraController: 60秒内未找到RemoteEvents文件夹")
		return
	end

	-- 镜头控制事件
	local cameraControlEvent = remoteEventsFolder:WaitForChild("CameraControl", 30)
	if cameraControlEvent then
		cameraControlEvent.OnClientEvent:Connect(function(action, data)
			-- 从data中获取桌子信息（优先使用服务端提供的信息）
			local tableId = data and data.tableId
			local tablePosition = data and data.tablePosition

			-- 如果服务端提供了桌子位置，直接使用
			if tablePosition then
				-- 使用服务端提供的桌子位置
			else
				-- 否则尝试获取桌子位置
				tablePosition = CameraController.getTablePosition(tableId)
				if not tablePosition then
					warn("CameraController: 无法获取桌子位置，镜头控制失效")
					return
				end
			end

			if action == "enterPrepare" then
				CameraController.enterPreparePhase(tablePosition)
			elseif action == "enterPoison" then
				CameraController.enterPoisonPhase(tablePosition)
			elseif action == "enterSelect" then
				CameraController.enterSelectPhase(tablePosition)
			elseif action == "focusPlayer" then
				if data and data.player then
					CameraController.focusOnPlayer(data.player, data.duration)
				end
			elseif action == "focusOnSelection" then
				CameraController.enterSelectPhase(tablePosition)
			elseif action == "watchOther" then
				CameraController.enterSelectPhase(tablePosition)
			elseif action == "focusOnDrinking" then
				if data and data.targetPlayer then
					local targetPlayer = Players:FindFirstChild(data.targetPlayer)
					if targetPlayer then
						CameraController.focusOnPlayer(targetPlayer, 3)
					else
						warn("CameraController: 未找到目标玩家: " .. tostring(data.targetPlayer))
					end
				else
					warn("CameraController: focusOnDrinking缺少目标玩家数据")
				end
			elseif action == "restore" then
				CameraController.restoreOriginalCamera()
			else
				warn("CameraController: 未知的镜头控制指令: " .. tostring(action))
			end
		end)
	else
		warn("CameraController: 未找到CameraControl事件")
	end
end

-- 启动镜头控制器
CameraController.initialize()
setupRemoteEvents()

return CameraController