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

-- 计算镜头CFrame（支持表旋转）
-- 参数说明：
--   tableData: 包含 {position: Vector3, cframe: CFrame} 或仅 {position: Vector3}（后向兼容）
--   config: 配置参数 {height, angle, distance}
function CameraController.calculateCameraCFrame(tableData, config)
	-- 处理向后兼容性：如果传入的是Vector3，转换为新格式
	local tablePosition
	local tableCFrame

	if typeof(tableData) == "Vector3" then
		-- 旧式调用（仅传入Position）
		tablePosition = tableData
		tableCFrame = CFrame.new(tablePosition)
	elseif typeof(tableData) == "table" then
		-- 新式调用（传入{position, cframe}或仅{position}）
		tablePosition = tableData.position or tableData.tablePosition
		tableCFrame = tableData.cframe or tableData.tableCFrame or CFrame.new(tablePosition)
	else
		-- 未知格式，使用默认
		tablePosition = Vector3.new(0, 0, 0)
		tableCFrame = CFrame.new(tablePosition)
	end

	-- 使用表的本地坐标系计算偏移
	-- config中的offset是相对于表的局部坐标
	local offsetX = config.offsetX or 0
	local offsetY = config.height or config.offsetY or 0
	local offsetZ = config.distance or config.offsetZ or 0

	-- 计算世界坐标中的偏移
	-- 注意：LookVector 是表看向的方向，所以要用 -LookVector 获得表的"背后"
	-- distance 参数应该偏移到表的背后（相对于表的朝向）
	-- 技巧：如果某个桌子的正向相反，可在配置中设置 distance 为负数以调整
	local offset = tableCFrame.RightVector * offsetX
	           + tableCFrame.UpVector * offsetY
	           - tableCFrame.LookVector * offsetZ

	-- 镜头位置 = 表中心 + 旋转后的偏移
	local cameraPosition = tablePosition + offset

	-- 镜头看向表的中心
	local targetPosition = tablePosition

	-- 创建CFrame，让镜头看向桌子中心
	local cframe = CFrame.lookAt(cameraPosition, targetPosition)

	-- 应用俯视角度（向上倾斜）
	local angleRadians = math.rad(config.angle or 5)
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
function CameraController.enterPreparePhase(tableData)
	CameraController.saveOriginalCamera()

	local targetCFrame = CameraController.calculateCameraCFrame(
		tableData,
		CAMERA_CONFIG.preparePhase
	)

	CameraController.moveCameraTo(targetCFrame)
end

-- 进入毒药注入阶段镜头
function CameraController.enterPoisonPhase(tableData)
	local targetCFrame = CameraController.calculateCameraCFrame(
		tableData,
		CAMERA_CONFIG.poisonPhase
	)

	CameraController.moveCameraTo(targetCFrame)
end

-- 进入选择奶茶阶段镜头
function CameraController.enterSelectPhase(tableData)
	local targetCFrame = CameraController.calculateCameraCFrame(
		tableData,
		CAMERA_CONFIG.selectPhase
	)

	CameraController.moveCameraTo(targetCFrame)
end

-- 镜头聚焦到指定NPC或玩家
-- 支持新参数格式：targetPlayer, duration, npcData (可选)
-- npcData 可以包含 {character: Model, position: Vector3}
function CameraController.focusOnPlayer(targetPlayer, duration, npcData)
	-- 🔧 修复V1.6: 支持NPC模型（非Player实例）
	local character = nil
	local humanoidRootPart = nil

	-- 如果是真实玩家
	if targetPlayer and targetPlayer.Character then
		character = targetPlayer.Character
		humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	-- 如果是NPC数据（表）
	elseif npcData and npcData.character then
		character = npcData.character
		humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	end

	if not humanoidRootPart then return end

	-- 获取表数据用于判断玩家位置
	-- 优先使用传入的tableData，否则尝试从服务端获取或本地查询
	local tableCFrame
	local tablePosition

	if npcData and npcData.cframe then
		tableCFrame = npcData.cframe
		tablePosition = npcData.position or npcData.cframe.Position
	else
		-- 尝试从本地获取表的CFrame
		tableCFrame = CameraController.getTableCFrame()
		if not tableCFrame then
			-- 降级处理：只获取位置
			tablePosition = CameraController.getTablePosition()
			if not tablePosition then
				warn("无法获取桌子信息，使用默认镜头设置")
				return
			end
			tableCFrame = CFrame.new(tablePosition)
		else
			tablePosition = tableCFrame.Position
		end
	end

	local playerPosition = humanoidRootPart.Position

	-- 🔑 改进：使用表的本地坐标系判断左/右
	-- 把玩家位置转换到表的本地坐标系
	local playerLocalPos = tableCFrame:PointToObjectSpace(playerPosition)
	local isPlayerOnLeft = playerLocalPos.X < 0

	-- 根据玩家位置调整镜头位置（使用表的本地坐标系）
	local cameraOffsetLocal
	if isPlayerOnLeft then
		-- 左边玩家：镜头位于玩家右前方偏上
		-- 相对表的本地坐标：右轴正方向、上轴正方向、表背后方向的组合
		-- 使用 -LookVector 是因为 LookVector 指向表看向的方向，表的"前方"是 -LookVector
		cameraOffsetLocal = tableCFrame.RightVector * 5 + tableCFrame.UpVector * 4 - tableCFrame.LookVector * 3
	else
		-- 右边玩家：镜头位于玩家左前方偏上
		-- 相对表的本地坐标：右轴负方向、上轴正方向、表背后方向的组合
		cameraOffsetLocal = tableCFrame.RightVector * (-5) + tableCFrame.UpVector * 4 - tableCFrame.LookVector * 3
	end

	local cameraPosition = playerPosition + cameraOffsetLocal
	-- 镜头目标点：玩家胸部到头部之间的位置，确保看到脸部
	local lookAtTarget = playerPosition + Vector3.new(0, 2, 0)
	local targetCFrame = CFrame.lookAt(cameraPosition, lookAtTarget)

	CameraController.moveCameraTo(targetCFrame, duration or 2)
end

-- 获取桌子的CFrame（包含位置和旋转）
function CameraController.getTableCFrame(tableId)
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
		-- 返回完整的CFrame（包含位置和旋转）
		return tablePart.CFrame
	end

	warn("CameraController: 桌子 " .. tableId .. " 无法找到ClassicTable下的TablePart")
	return nil
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
			-- 从data中获取表信息
			local tableId = data and data.tableId
			local tableData = data and data.tableData

			-- 构建tableData：优先使用服务端提供的完整数据
			if not tableData then
				tableData = {}
			end

			-- 🔧 修复：从cframeValues重建CFrame对象
			if tableData.cframeValues then
				-- cframeValues是一个table，包含CFrame的所有组件
				-- 格式：{x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22}
				if #tableData.cframeValues >= 12 then
					tableData.cframe = CFrame.new(
						tableData.cframeValues[1], tableData.cframeValues[2], tableData.cframeValues[3],
						tableData.cframeValues[4], tableData.cframeValues[5], tableData.cframeValues[6],
						tableData.cframeValues[7], tableData.cframeValues[8], tableData.cframeValues[9],
						tableData.cframeValues[10], tableData.cframeValues[11], tableData.cframeValues[12]
					)
					-- position可能以{x,y,z}格式发送，需要转换为Vector3
					if tableData.position and type(tableData.position) == "table" then
						tableData.position = Vector3.new(tableData.position.x, tableData.position.y, tableData.position.z)
					end
				end
			end

			-- 如果没有tableCFrame，尝试本地获取
			if not tableData.cframe or not tableData.cframe.Position then
				-- 从本地查询表的CFrame
				local localTableCFrame = CameraController.getTableCFrame(tableId)
				if localTableCFrame then
					tableData.cframe = localTableCFrame
					tableData.position = localTableCFrame.Position
				else
					-- 降级：仅使用Position
					local pos = data.tablePosition
					if pos and type(pos) == "table" then
						tableData.position = Vector3.new(pos.x, pos.y, pos.z)
					else
						tableData.position = pos
					end
					if not tableData.position then
						warn("CameraController: 无法获取表数据，镜头控制失效")
						return
					end
				end
			end

			if action == "enterPrepare" then
				CameraController.enterPreparePhase(tableData)
			elseif action == "enterPoison" then
				CameraController.enterPoisonPhase(tableData)
			elseif action == "enterSelect" then
				CameraController.enterSelectPhase(tableData)
			elseif action == "focusPlayer" then
				if data and data.player then
					CameraController.focusOnPlayer(data.player, data.duration, tableData)
				end
			elseif action == "focusOnSelection" then
				CameraController.enterSelectPhase(tableData)
			elseif action == "watchOther" then
				CameraController.enterSelectPhase(tableData)
			elseif action == "focusOnDrinking" then
				-- 🔧 修复V1.6: 支持NPC镜头定位
				-- 首先尝试作为真实玩家查找
				if data and data.targetPlayer then
					local targetPlayer = Players:FindFirstChild(data.targetPlayer)
					if targetPlayer then
						CameraController.focusOnPlayer(targetPlayer, 3, tableData)
					else
						-- 如果找不到真实玩家，尝试作为NPC模型处理
						-- NPC模型会通过 npcCharacterModel 传递
						if data.npcCharacterModel then
							CameraController.focusOnPlayer(nil, 3, {character = data.npcCharacterModel})
						else
							warn("CameraController: 未找到目标玩家或NPC: " .. tostring(data.targetPlayer))
						end
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