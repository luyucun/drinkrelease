-- 脚本名称: GameInstance
-- 脚本作用: 单张桌子的游戏实例，管理该桌子的完整游戏逻辑
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService

local GameInstance = {}
GameInstance.__index = GameInstance

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引入其他管理器模块
local DrinkManager = require(script.Parent.DrinkManager)
local PoisonSelectionManager = nil
local DrinkSelectionManager = nil

-- 安全地加载PoisonSelectionManager
local function loadPoisonSelectionManager()
	if not PoisonSelectionManager then
		local success, result = pcall(function()
			return require(script.Parent.PoisonSelectionManager)
		end)

		if success then
			PoisonSelectionManager = result
		else
			warn("GameInstance: PoisonSelectionManager 加载失败:", result)
		end
	end
	return PoisonSelectionManager
end

-- 安全地加载DrinkSelectionManager
local function loadDrinkSelectionManager()
	if not DrinkSelectionManager then
		local success, result = pcall(function()
			return require(script.Parent.DrinkSelectionManager)
		end)

		if success then
			DrinkSelectionManager = result
		else
			warn("GameInstance: DrinkSelectionManager 加载失败:", result)
		end
	end
	return DrinkSelectionManager
end

-- 创建新的游戏实例
function GameInstance.new(tableId, tableFolder)
	local self = setmetatable({}, GameInstance)

	-- 基本信息
	self.tableId = tableId
	self.tableFolder = tableFolder

	-- 🆕 教程模式标记
	self.isTutorial = _G.TutorialMode or false

	-- 获取桌子组件
	self.classicTable = tableFolder:WaitForChild("ClassicTable")
	self.classicChair1 = tableFolder:WaitForChild("ClassicChair1")
	self.classicChair2 = tableFolder:WaitForChild("ClassicChair2")

	-- 获取座位
	self.seat1 = self.classicChair1:WaitForChild("Seat")
	self.seat2 = self.classicChair2:WaitForChild("Seat")

	-- 获取UI组件
	self.tablePart = self.classicTable:WaitForChild("TablePart")
	self.billboardGui = self.tablePart:WaitForChild("BillboardGui")
	self.playerNumBg = self.billboardGui:WaitForChild("PlayerNumBg")
	self.numLabel = self.playerNumBg:WaitForChild("Num")

	-- 获取AirWall组件
	self.airWalls = {}

	-- 查找所有名为"AirWall"的Part
	for _, child in pairs(tableFolder:GetChildren()) do
		if child.Name == "AirWall" and child:IsA("Part") then
			table.insert(self.airWalls, child)
		end
	end

	-- 游戏状态
	self.gameState = {
		player1 = nil,
		player2 = nil,
		playersReady = 0,
		isCountingDown = false,
		countdownTime = 5,
		countdownCoroutine = nil,
		gamePhase = "waiting", -- \"waiting\", \"poison\", \"selection\", \"result\"
		poisonSelections = {}
	}

	-- 初始化
	self:initialize()

	return self
end

-- 初始化游戏实例
function GameInstance:initialize()
	-- 初始化UI显示
	self:updatePlayerCount()

	-- 确保BillboardGui启用
	self.billboardGui.Enabled = true

	-- 初始化AirWall为禁用状态（允许自由通行）
	self:disableAirWalls()

	-- 设置座位检测
	self:setupSeatDetection()
end

-- AirWall管理：启用碰撞（游戏开始时阻隔外部玩家）
function GameInstance:enableAirWalls()

	local enabledCount = 0
	for i, airWall in pairs(self.airWalls) do
		if airWall and airWall:IsA("Part") then
			-- 存储原始数据以便恢复
			local originalData = airWall:FindFirstChild("OriginalData")
			if not originalData then
				originalData = Instance.new("Folder")
				originalData.Name = "OriginalData"
				originalData.Parent = airWall

				local sizeValue = Instance.new("Vector3Value")
				sizeValue.Name = "Size"
				sizeValue.Value = airWall.Size
				sizeValue.Parent = originalData

				local positionValue = Instance.new("Vector3Value")
				positionValue.Name = "Position"
				positionValue.Value = airWall.Position
				positionValue.Parent = originalData

				local transparencyValue = Instance.new("NumberValue")
				transparencyValue.Name = "Transparency"
				transparencyValue.Value = airWall.Transparency
				transparencyValue.Parent = originalData

				local materialValue = Instance.new("StringValue")
				materialValue.Name = "Material"
				materialValue.Value = tostring(airWall.Material)
				materialValue.Parent = originalData

				local canTouchValue = Instance.new("BoolValue")
				canTouchValue.Name = "CanTouch"
				canTouchValue.Value = airWall.CanTouch
				canTouchValue.Parent = originalData
			end

			-- 新方案：高度分层 - 只在人物高度设置碰撞，桌面高度保持穿透
			local originalSize = airWall.Size
			local originalPosition = airWall.Position

			-- 1. 启用碰撞阻挡玩家移动
			airWall.CanCollide = true

			-- 2. 调整尺寸：保持X、Z不变，将Y高度调整为只覆盖玩家身高范围
			-- 假设玩家身高约6个单位，桌面高度约4个单位
			-- 我们让AirWall只覆盖0-5单位高度，桌面在4单位以上就不受影响
			local playerHeight = 5  -- 玩家身高范围
			local newSize = Vector3.new(originalSize.X, playerHeight, originalSize.Z)

			-- 3. 调整位置：让AirWall底部贴地，顶部不超过玩家身高
			local groundLevel = originalPosition.Y - originalSize.Y/2  -- 计算地面高度
			local newYPosition = groundLevel + playerHeight/2  -- 新的Y中心位置
			local newPosition = Vector3.new(originalPosition.X, newYPosition, originalPosition.Z)

			airWall.Size = newSize
			airWall.Position = newPosition

			-- 4. 设置完全透明，完全看不见
			airWall.Transparency = 1

			-- 5. 使用Glass材质，对射线检测影响最小
			airWall.Material = Enum.Material.Glass

			-- 6. 禁用Touch事件
			airWall.CanTouch = false

			-- 7. 不设置LocalTransparencyModifier，保持射线可达性

			enabledCount = enabledCount + 1
		else
			warn("  -> AirWall " .. i .. " 不是Part或不存在")
		end
	end

end

-- AirWall管理：禁用碰撞（游戏结束时恢复自由通行）
function GameInstance:disableAirWalls()

	local disabledCount = 0
	for i, airWall in pairs(self.airWalls) do
		if airWall and airWall:IsA("Part") then
			-- 禁用碰撞
			airWall.CanCollide = false

			-- 恢复原始属性
			local originalData = airWall:FindFirstChild("OriginalData")
			if originalData then
				local sizeValue = originalData:FindFirstChild("Size")
				local positionValue = originalData:FindFirstChild("Position")
				local transparencyValue = originalData:FindFirstChild("Transparency")
				local materialValue = originalData:FindFirstChild("Material")
				local canTouchValue = originalData:FindFirstChild("CanTouch")

				if sizeValue then
					airWall.Size = sizeValue.Value
				end
				if positionValue then
					airWall.Position = positionValue.Value
				end
				if transparencyValue then
					airWall.Transparency = transparencyValue.Value
				end
				if materialValue then
					-- 将字符串转回Material枚举
					local materialName = materialValue.Value
					-- 处理弃用的材质
					if materialName == "Plastic" then
						-- 使用安全的材质设置
						local success = pcall(function()
							airWall.Material = Enum.Material.ForceField
						end)
						if not success then
							-- 如果ForceField也不可用，保持原有材质不变
						end
					elseif materialName and pcall(function() return Enum.Material[materialName] end) then
						local success = pcall(function()
							airWall.Material = Enum.Material[materialName]
						end)
						if not success then
						end
					else
						-- 使用安全的默认材质
						local success = pcall(function()
							airWall.Material = Enum.Material.ForceField
						end)
						if not success then
						end
					end
				end
				if canTouchValue then
					airWall.CanTouch = canTouchValue.Value
				end

				originalData:Destroy()
			else
				-- 如果没有原始数据，使用默认恢复
				airWall.CanTouch = true
				airWall.Transparency = 1
				-- 使用安全的默认材质设置
				local success = pcall(function()
					airWall.Material = Enum.Material.ForceField
				end)
				if not success then
				end
			end

			-- 重置其他属性
			airWall.LocalTransparencyModifier = 0

			disabledCount = disabledCount + 1
		else
			warn("  -> AirWall " .. i .. " 不是Part或不存在")
		end
	end

end

-- 获取AirWall状态（调试用）
function GameInstance:getAirWallStatus()
	local status = {
		total = #self.airWalls,
		enabled = 0,
		disabled = 0,
		details = {}
	}

	for i, airWall in pairs(self.airWalls) do
		if airWall and airWall:IsA("Part") then
			local detail = {
				index = i,
				name = airWall.Name,
				canCollide = airWall.CanCollide
			}

			if airWall.CanCollide then
				status.enabled = status.enabled + 1
			else
				status.disabled = status.disabled + 1
			end

			table.insert(status.details, detail)
		end
	end

	return status
end

-- 更新玩家数量显示
function GameInstance:updatePlayerCount()
	local count = self.gameState.playersReady
	self.numLabel.Text = count .. "/2"

	-- 根据玩家数量改变字体颜色
	-- 0/2: 白色，1/2: 红色，2/2: 绿色
	if count == 0 then
		self.numLabel.TextColor3 = Color3.fromRGB(255, 255, 255)  -- 白色
	elseif count == 1 then
		self.numLabel.TextColor3 = Color3.fromRGB(255, 170, 0)      -- 橙色
	elseif count == 2 then
		self.numLabel.TextColor3 = Color3.fromRGB(0, 255, 0)      -- 绿色
	end
end

-- 玩家坐下处理
function GameInstance:onPlayerSat(seat, player)

	-- 🆕 NPC代理识别
	local isNPC = false
	if _G.TutorialBotService then
		isNPC = _G.TutorialBotService:isBot(player)
	end

	-- 通知TableManager更新玩家映射（真实玩家才需要）
	if _G.TableManager and not isNPC then
		_G.TableManager.assignPlayerToTable(player, self.tableId)
	end

	-- 只有在等待阶段才允许玩家进入准备状态
	if self.gameState.gamePhase ~= "waiting" then
		return
	end

	if seat == self.seat1 and not self.gameState.player1 then
		self.gameState.player1 = player
		self.gameState.playersReady = self.gameState.playersReady + 1

		-- 立即启用Leave按钮（只有真实玩家才需要）
		if not isNPC then
			self:enableLeaveButton(player)
		end

		-- 🔧 修改：玩家单独坐下时不锁定镜头，保持镜头自由
		-- 镜头锁定延迟到倒计时阶段进行

		-- 补发菜单指令：确保玩家看到正确的菜单状态（只显示shop按钮）
		-- Skin和Emote按钮始终显示，不受游戏状态影响
		-- （只有真实玩家才需要菜单）
		if not isNPC then
			self:setMenuVisibility(player, true)
			self:setSpecificMenuVisibility(player, {
				shop = true,
				death = false
			})
		end

	elseif seat == self.seat2 and not self.gameState.player2 then
		self.gameState.player2 = player
		self.gameState.playersReady = self.gameState.playersReady + 1

		-- 立即启用Leave按钮（只有真实玩家才需要）
		if not isNPC then
			self:enableLeaveButton(player)
		end

		-- 🔧 修改：玩家单独坐下时不锁定镜头，保持镜头自由
		-- 镜头锁定延迟到倒计时阶段进行

		-- 补发菜单指令：确保玩家看到正确的菜单状态（只显示shop按钮）
		-- Skin和Emote按钮始终显示，不受游戏状态影响
		-- （只有真实玩家才需要菜单）
		if not isNPC then
			self:setMenuVisibility(player, true)
			self:setSpecificMenuVisibility(player, {
				shop = true,
				death = false
			})
		end
	end

	self:updatePlayerCount()

	-- 检查是否可以开始倒计时
	if self.gameState.gamePhase == "waiting" and self.gameState.playersReady == 2 and not self.gameState.isCountingDown then
		self:startCountdown()
	end
end

-- 玩家离开座位处理
function GameInstance:onPlayerLeft(seat, player)

	-- 🆕 NPC代理识别
	local isNPC = false
	if _G.TutorialBotService then
		isNPC = _G.TutorialBotService:isBot(player)
	end

	-- 通知TableManager移除玩家映射（真实玩家才需要）
	if _G.TableManager and not isNPC then
		_G.TableManager.removePlayerFromTable(player)
	end

	-- 无论当前阶段如何，都要立即把离座玩家从 gameState 中剔除
	local wasInGame = false
	if seat == self.seat1 and self.gameState.player1 == player then
		wasInGame = true

		-- 如果正在倒计时，先隐藏离开玩家的倒计时UI
		if self.gameState.isCountingDown then
			self:hideCountdownUI(player)
		end

		-- 立即清理状态
		self.gameState.player1 = nil
		self.gameState.playersReady = math.max(self.gameState.playersReady - 1, 0)

		-- 无论什么阶段，都要恢复镜头和禁用Leave按钮（只有真实玩家才需要）
		if not isNPC then
			self:disableLeaveButton(player)
			self:sendCameraControl(player, "restore")
		end

		-- ✨ 新增：倒计时中有人离开时，为剩余玩家恢复镜头自由状态
		if self.gameState.isCountingDown and self.gameState.player2 then
			-- 剩余玩家的镜头恢复为自由状态（就像单人坐下时一样）
			self:sendCameraControl(self.gameState.player2, "restore")
		end

		-- 离席时补发菜单指令：确保离席玩家立刻恢复到"仅显示Shop"的菜单状态
		-- Skin和Emote按钮始终显示，不受游戏状态影响
		-- （只有真实玩家才需要菜单）
		if not isNPC then
			self:setMenuVisibility(player, true)
			self:setSpecificMenuVisibility(player, {
				shop = true,
				death = false
			})
		end

	elseif seat == self.seat2 and self.gameState.player2 == player then
		wasInGame = true

		-- 如果正在倒计时，先隐藏离开玩家的倒计时UI
		if self.gameState.isCountingDown then
			self:hideCountdownUI(player)
		end

		-- 立即清理状态
		self.gameState.player2 = nil
		self.gameState.playersReady = math.max(self.gameState.playersReady - 1, 0)

		-- 无论什么阶段，都要恢复镜头和禁用Leave按钮（只有真实玩家才需要）
		if not isNPC then
			self:disableLeaveButton(player)
			self:sendCameraControl(player, "restore")
		end

		-- ✨ 新增：倒计时中有人离开时，为剩余玩家恢复镜头自由状态
		if self.gameState.isCountingDown and self.gameState.player1 then
			-- 剩余玩家的镜头恢复为自由状态（就像单人坐下时一样）
			self:sendCameraControl(self.gameState.player1, "restore")
		end

		-- 离席时补发菜单指令：确保离席玩家立刻恢复到"仅显示Shop"的菜单状态
		-- Skin和Emote按钮始终显示，不受游戏状态影响
		-- （只有真实玩家才需要菜单）
		if not isNPC then
			self:setMenuVisibility(player, true)
			self:setSpecificMenuVisibility(player, {
				shop = true,
				death = false
			})
		end
	end

	-- 如果玩家确实在游戏中，更新显示
	if wasInGame then
		self:updatePlayerCount()
		-- 注意：不在这里调用refreshSeatState()，因为会干扰handlePlayerLeaveWin的逻辑
		-- refreshSeatState()会在resetToWaiting()中被正确调用
	end

	-- 如果正在倒计时且有人离开，取消倒计时
	if self.gameState.isCountingDown and self.gameState.playersReady < 2 then
		self:cancelCountdown()
	end

	-- 如果游戏正在进行中且有玩家离开，直接调用获胜判定
	-- 不再依赖 playersReady < 2 条件，因为状态已经被清理
	if self.gameState.gamePhase ~= "waiting" and wasInGame then
		self:handlePlayerLeaveWin(player)
	end
end

-- 发送镜头控制指令（带桌子特定数据）
function GameInstance:sendCameraControl(player, action, data)
	-- 验证player参数
	if not player then return end
	-- 🔧 修复：检查是否是真实的 Roblox Player 对象，排除 NPC（NPC 是普通 table）
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if not player.Parent then return end  -- 检查玩家是否仍在游戏中

	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local cameraControlEvent = remoteEventsFolder:WaitForChild("CameraControl")

	-- 创建全新的、干净的数据表（不使用外来的data参数以避免序列化问题）
	local tableCFrame = self.tablePart.CFrame
	-- 提取CFrame的12个数值组件：位置(x,y,z) + 旋转矩阵(3x3)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = tableCFrame:GetComponents()

	-- 🔧 修复：创建全新的表，只包含可序列化的基础数据类型
	local cameraData = {
		tableId = self.tableId,
		tablePosition = {
			x = self.tablePart.Position.x,
			y = self.tablePart.Position.y,
			z = self.tablePart.Position.z
		},
		tableData = {
			position = {
				x = self.tablePart.Position.x,
				y = self.tablePart.Position.y,
				z = self.tablePart.Position.z
			},
			-- 将12个数值分别存储为可序列化的格式
			cframeValues = {x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22}
		}
	}

	cameraControlEvent:FireClient(player, action, cameraData)
end

-- 控制Menu界面显示/隐藏
function GameInstance:setMenuVisibility(player, visible)
	if not player then return end
	-- 🔧 修复：检查是否是真实的 Roblox Player 对象，排除 NPC
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if not player.Parent then return end  -- 检查玩家是否仍在游戏中

	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local menuControlEvent = remoteEventsFolder:FindFirstChild("MenuControl")

	if not menuControlEvent then
		-- 如果RemoteEvent不存在，创建它
		menuControlEvent = Instance.new("RemoteEvent")
		menuControlEvent.Name = "MenuControl"
		menuControlEvent.Parent = remoteEventsFolder
	end

	menuControlEvent:FireClient(player, "setMenuVisibility", {visible = visible})
end

-- 控制特定Menu按钮显示/隐藏
function GameInstance:setSpecificMenuVisibility(player, config)
	if not player then return end
	-- 🔧 修复：检查是否是真实的 Roblox Player 对象，排除 NPC
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if not player.Parent then return end  -- 检查玩家是否仍在游戏中

	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local menuControlEvent = remoteEventsFolder:FindFirstChild("MenuControl")

	if not menuControlEvent then
		-- 如果RemoteEvent不存在，创建它
		menuControlEvent = Instance.new("RemoteEvent")
		menuControlEvent.Name = "MenuControl"
		menuControlEvent.Parent = remoteEventsFolder
	end

	menuControlEvent:FireClient(player, "setSpecificMenuVisibility", config)
end

-- 隐藏两个玩家的Menu界面（进入对局时）
function GameInstance:hideMenuForBothPlayers()
	if self.gameState.player1 then
		self:setMenuVisibility(self.gameState.player1, false)
	end
	if self.gameState.player2 then
		self:setMenuVisibility(self.gameState.player2, false)
	end
end

-- 显示两个玩家的Menu界面（对局结束时）
function GameInstance:showMenuForBothPlayers()
	if self.gameState.player1 then
		self:setMenuVisibility(self.gameState.player1, true)
	end
	if self.gameState.player2 then
		self:setMenuVisibility(self.gameState.player2, true)
	end
end

-- 启用Leave按钮
function GameInstance:enableLeaveButton(player)
	if not player then return end
	-- 🔧 修复：检查是否是真实的 Roblox Player 对象，排除 NPC
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	-- 检查玩家是否仍在游戏中
	if not player.Parent then return end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	local leaveGui = playerGui:FindFirstChild("Leave")
	if leaveGui then
		leaveGui.Enabled = true

		-- 🔑 关键修复：Leave按钮的连接已在客户端LocalScript中管理
		-- 不需要在服务端重复创建连接，避免多次绑定导致重复触发
		-- 只需启用GUI即可，客户端会处理按钮点击事件
	end
end

-- 禁用Leave按钮
function GameInstance:disableLeaveButton(player)
	if not player then return end
	-- 🔧 修复：检查是否是真实的 Roblox Player 对象，排除 NPC
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	-- 检查玩家是否仍在游戏中
	if not player.Parent then return end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	local leaveGui = playerGui:FindFirstChild("Leave")
	if leaveGui then
		leaveGui.Enabled = false
	end
end

-- 玩家手动离开座位
function GameInstance:playerLeaveManually(player)
	if not player then return end
	-- 🔧 修复：检查是否是真实的 Roblox Player 对象，排除 NPC
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if not player.Parent then return end  -- 检查玩家是否仍在游戏中

	-- 通知客户端解除座位锁定
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
	local seatLockEvent = remoteEventsFolder:WaitForChild("SeatLock")
	seatLockEvent:FireClient(player, "unlock")

	-- 等待一帧确保锁定解除
	wait(0.1)

	-- 🔧 关键修复：增加角色和Humanoid的安全检查
	if player.Character and player.Character.Parent then
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.Sit = false
		else
			warn("玩家 " .. player.Name .. " 的角色没有Humanoid组件")
		end
	else
		warn("玩家 " .. player.Name .. " 的角色不存在或已被移除")
	end
end

-- 开始倒计时
function GameInstance:startCountdown()
	if self.gameState.isCountingDown then return end

	self.gameState.isCountingDown = true
	self.gameState.countdownTime = 3

	-- 启用AirWall阻隔外部玩家干扰
	self:enableAirWalls()

	-- ✨ 新增：在倒计时开始时锁定镜头到准备阶段
	-- 此时两个玩家都已坐好，现在锁定镜头对准桌子
	self:sendCameraControl(self.gameState.player1, "enterPrepare")
	self:sendCameraControl(self.gameState.player2, "enterPrepare")

	-- 隐藏Menu界面（进入对局状态）
	self:hideMenuForBothPlayers()

	-- 启用Leave按钮UI
	self:enableLeaveButton(self.gameState.player1)
	self:enableLeaveButton(self.gameState.player2)

	-- 开始倒计时协程
	self.gameState.countdownCoroutine = coroutine.create(function()
		while self.gameState.countdownTime > 0 and self.gameState.isCountingDown do
			-- 更新倒计时UI
			self:updateCountdownUI(self.gameState.player1, self.gameState.countdownTime)
			self:updateCountdownUI(self.gameState.player2, self.gameState.countdownTime)

			wait(1)
			self.gameState.countdownTime = self.gameState.countdownTime - 1
		end

		if self.gameState.isCountingDown and self.gameState.countdownTime <= 0 then
			self:startGame()
		end
	end)

	coroutine.resume(self.gameState.countdownCoroutine)
end

-- 取消倒计时
function GameInstance:cancelCountdown()
	if not self.gameState.isCountingDown then return end

	self.gameState.isCountingDown = false

	-- 禁用AirWall，恢复自由通行
	self:disableAirWalls()

	-- 显示Menu界面（退出对局状态）
	self:showMenuForBothPlayers()

	-- ✨ 新增：取消倒计时时，为剩余在座位上的玩家恢复镜头自由状态
	-- 这样玩家在取消倒计时后会恢复到单人坐下时的镜头自由状态
	if self.gameState.player1 then
		self:sendCameraControl(self.gameState.player1, "restore")
	end
	if self.gameState.player2 then
		self:sendCameraControl(self.gameState.player2, "restore")
	end

	-- 倒计时中断后重置留席玩家：为仍在座位上的玩家显式设置只保留Shop按钮
	-- Skin和Emote按钮始终显示，不受游戏状态影响
	if self.gameState.player1 then
		self:setSpecificMenuVisibility(self.gameState.player1, {
			shop = true,
			death = false
		})
	end
	if self.gameState.player2 then
		self:setSpecificMenuVisibility(self.gameState.player2, {
			shop = true,
			death = false
		})
	end

	-- 为仍在座位上的玩家保持Leave按钮启用状态
	if self.seat1.Occupant then
		-- 🔧 关键修复：增加座位占用者的安全检查
		local character1 = self.seat1.Occupant.Parent
		if character1 then
			local player1 = Players:GetPlayerFromCharacter(character1)
			if player1 and player1.Parent then  -- 检查玩家是否仍在游戏中
				self:enableLeaveButton(player1)
			end
		end
	end

	if self.seat2.Occupant then
		-- 🔧 关键修复：增加座位占用者的安全检查
		local character2 = self.seat2.Occupant.Parent
		if character2 then
			local player2 = Players:GetPlayerFromCharacter(character2)
			if player2 and player2.Parent then  -- 检查玩家是否仍在游戏中
				self:enableLeaveButton(player2)
			end
		end
	end

	-- 隐藏倒计时UI（为所有可能的玩家）
	-- 先尝试为记录的玩家隐藏
	if self.gameState.player1 then
		self:hideCountdownUI(self.gameState.player1)
	end
	if self.gameState.player2 then
		self:hideCountdownUI(self.gameState.player2)
	end

	-- 同时为当前座位上的玩家隐藏（防止状态不一致）
	if self.seat1.Occupant then
		-- 🔧 关键修复：增加座位占用者的安全检查
		local character1 = self.seat1.Occupant.Parent
		if character1 then
			local player1 = Players:GetPlayerFromCharacter(character1)
			if player1 and player1.Parent then  -- 检查玩家是否仍在游戏中
				self:hideCountdownUI(player1)
			end
		end
	end

	if self.seat2.Occupant then
		-- 🔧 关键修复：增加座位占用者的安全检查
		local character2 = self.seat2.Occupant.Parent
		if character2 then
			local player2 = Players:GetPlayerFromCharacter(character2)
			if player2 and player2.Parent then  -- 检查玩家是否仍在游戏中
				self:hideCountdownUI(player2)
			end
		end
	end
end

-- 更新倒计时UI
function GameInstance:updateCountdownUI(player, timeLeft)
	if not player then return end
	-- 🔧 修复：检查是否是真实的 Roblox Player 对象，排除 NPC
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	-- 检查玩家是否仍在游戏中
	if not player.Parent then return end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	local countDownTips = playerGui:FindFirstChild("CountDownTips")
	if countDownTips then
		countDownTips.Enabled = true
		local textBg = countDownTips:FindFirstChild("TextBg")
		if textBg then
			local tips = textBg:FindFirstChild("Tips")
			if tips then
				tips.Text = "Starting in: " .. timeLeft .. "S"
			end
		end
	end
end

-- 隐藏倒计时UI
function GameInstance:hideCountdownUI(player)
	if not player then return end
	-- 🔧 修复：检查是否是真实的 Roblox Player 对象，排除 NPC
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	-- 检查玩家是否仍在游戏中
	if not player.Parent then return end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	local countDownTips = playerGui:FindFirstChild("CountDownTips")
	if countDownTips then
		countDownTips.Enabled = false
	end
end

-- 开始游戏
function GameInstance:startGame()

	-- 立即设置游戏阶段为游戏中，防止在等待期间玩家离开被误判为waiting状态
	self.gameState.gamePhase = "starting"

	-- 隐藏BillboardGui
	self.billboardGui.Enabled = false

	-- 隐藏倒计时UI
	self:hideCountdownUI(self.gameState.player1)
	self:hideCountdownUI(self.gameState.player2)

	-- 游戏开始后禁用Leave按钮
	self:disableLeaveButton(self.gameState.player1)
	self:disableLeaveButton(self.gameState.player2)

	-- 生成奶茶模型
	DrinkManager.spawnDrinksForTable(self.tableId, self.tableFolder)

	-- 等待生成完成后进入毒药注入阶段
	wait(1.5)

	-- 检查游戏是否还在进行中（可能在等待期间有玩家离开）
	if self.gameState.gamePhase == "starting" then
		self:startPoisonPhase()
	end
end

-- 开始毒药注入阶段
function GameInstance:startPoisonPhase()
	self.gameState.gamePhase = "poison"

	-- 切换镜头到毒药注入视角
	self:sendCameraControl(self.gameState.player1, "enterPoison")
	self:sendCameraControl(self.gameState.player2, "enterPoison")

	-- V1.7: 更新房间好友信息
	if _G.FriendsService and not _G.TutorialMode then
		local players = {}
		if self.gameState.player1 then table.insert(players, self.gameState.player1) end
		if self.gameState.player2 then table.insert(players, self.gameState.player2) end
		_G.FriendsService:updateRoomFriends(self.tableId, players)
	end

	-- 安全地加载并调用PoisonSelectionManager
	local poisonManager = loadPoisonSelectionManager()
	if poisonManager and poisonManager.startPoisonPhase then
		local success, result = pcall(function()
			return poisonManager.startPoisonPhase(
				self.gameState.player1,
				self.gameState.player2
			)
		end)

		if success then
			-- 毒药选择阶段启动成功
		else
			warn("毒药选择阶段启动失败:", result)
		end
	else
		warn("无法启动毒药选择阶段 - PoisonSelectionManager不可用")
		-- 可以在这里添加fallback逻辑
	end
end

-- 检查玩家是否在此桌子的座位上
function GameInstance:isPlayerInSeats(player)
	-- 🔧 关键修复：增加空指针检查
	if not player or not player.Parent then return false end
	if not player.Character then return false end

	local humanoid = player.Character:FindFirstChild("Humanoid")
	if not humanoid then return false end

	-- 🔧 关键修复：增加座位占用者的安全检查
	local seat1Occupied = self.seat1.Occupant and self.seat1.Occupant.Parent == player.Character
	local seat2Occupied = self.seat2.Occupant and self.seat2.Occupant.Parent == player.Character

	return seat1Occupied or seat2Occupied
end

-- 获取状态信息（供TableManager调试使用）
function GameInstance:getStatus()
	local airWallStatus = self:getAirWallStatus()
	return {
		tableId = self.tableId,
		phase = self.gameState.gamePhase,
		playerCount = self.gameState.playersReady,
		player1Name = self.gameState.player1 and self.gameState.player1.Name or nil,
		player2Name = self.gameState.player2 and self.gameState.player2.Name or nil,
		isCountingDown = self.gameState.isCountingDown,
		airWalls = {
			total = airWallStatus.total,
			enabled = airWallStatus.enabled,
			disabled = airWallStatus.disabled
		}
	}
end

-- 处理玩家离开服务器
function GameInstance:onPlayerRemoving(player)
	if self.gameState.player1 == player or self.gameState.player2 == player then
		-- 统一使用 handlePlayerLeaveWin 处理，无论什么阶段
		-- 如果是 waiting 阶段，handlePlayerLeaveWin 会直接 return
		-- 如果不是 waiting 阶段，会正确处理获胜逻辑

		if self.gameState.gamePhase ~= "waiting" then
			-- 非等待阶段：直接调用获胜处理
			self:handlePlayerLeaveWin(player)
		else
			-- 等待阶段：手动清理状态
			if self.gameState.player1 == player then
				self.gameState.player1 = nil
				self.gameState.playersReady = math.max(self.gameState.playersReady - 1, 0)
			elseif self.gameState.player2 == player then
				self.gameState.player2 = nil
				self.gameState.playersReady = math.max(self.gameState.playersReady - 1, 0)
			end

			self:updatePlayerCount()

			if self.gameState.isCountingDown then
				self:cancelCountdown()
			end

			-- 刷新座位状态以确保一致性
			self:refreshSeatState()
		end
	end
end

-- 处理玩家离开导致的获胜
function GameInstance:handlePlayerLeaveWin(leavingPlayer)
	if self.gameState.gamePhase == "result" or self.gameState.gamePhase == "waiting" then
		return
	end

	local winner = nil
	if self.gameState.player1 and self.gameState.player1 ~= leavingPlayer then
		winner = self.gameState.player1
	elseif self.gameState.player2 and self.gameState.player2 ~= leavingPlayer then
		winner = self.gameState.player2
	end

	if winner then
		-- 防御性菜单设置：立即为获胜者设置只显示shop按钮
		-- Skin和Emote按钮始终显示，不受游戏状态影响
		-- 即使后续状态被意外清掉，胜者也会第一时间收到"只留商店"指令
		if winner and winner.Parent then
			self:setSpecificMenuVisibility(winner, {
				shop = true,
				death = false
			})
		end

		-- 立即清理离开玩家的引用，防止后续代码尝试向离开的玩家发送消息
		if self.gameState.player1 == leavingPlayer then
			self.gameState.player1 = nil
			self.gameState.playersReady = self.gameState.playersReady - 1
		elseif self.gameState.player2 == leavingPlayer then
			self.gameState.player2 = nil
			self.gameState.playersReady = self.gameState.playersReady - 1
		end

		-- 根据当前游戏阶段，通知对应的管理器结束游戏
		if self.gameState.gamePhase == "starting" then
			-- 奶茶生成阶段玩家离开：立即清理奶茶并重置
			DrinkManager.clearDrinksForTable(self.tableId)

			-- 通知获胜玩家游戏结束
			local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
			local drinkSelectionEvent = remoteEventsFolder:FindFirstChild("DrinkSelection")
			if drinkSelectionEvent and winner and typeof(winner) == "Instance" and winner:IsA("Player") and winner.Parent then
				drinkSelectionEvent:FireClient(winner, "gameWin", {
					reason = "opponent_left",
					opponent = leavingPlayer.Name
				})
			end

			-- 恢复获胜玩家的镜头状态
			if winner and winner.Parent then
				-- 如果获胜玩家仍在座位上，切换到准备状态镜头
				if self:isPlayerInSeats(winner) then
					self:sendCameraControl(winner, "enterPrepare")
				else
					-- 如果不在座位上，恢复默认镜头
					self:sendCameraControl(winner, "restore")
				end
			end

		elseif self.gameState.gamePhase == "poison" then
			-- 通知PoisonSelectionManager结束毒药阶段
			if _G.PoisonSelectionManager and _G.PoisonSelectionManager.endPoisonPhaseByPlayerLeave then
				_G.PoisonSelectionManager.endPoisonPhaseByPlayerLeave(winner, leavingPlayer)
			end
		elseif self.gameState.gamePhase == "selection" then
			-- 通知DrinkSelectionManager结束选择阶段
			if _G.DrinkSelectionManager and _G.DrinkSelectionManager.endSelectionPhaseByPlayerLeave then
				_G.DrinkSelectionManager.endSelectionPhaseByPlayerLeave(winner, leavingPlayer)
			end
		end

		-- 🔧 关键修复：移除重复的排行榜记录逻辑
		-- 排行榜数据已经由DrinkSelectionManager正确记录，避免重复记录导致胜负颠倒
		-- DrinkSelectionManager.recordGameResultToRanking() 在第946行已处理
		--
		-- 注释掉的原因：
		-- 1. VictoryAnimationManager强制获胜者站起来（humanoid.Sit = false）
		-- 2. 这触发了座位离开事件，调用handlePlayerLeaveWin
		-- 3. 在这里记录排行榜会导致第二次记录，且winner/leavingPlayer角色颠倒
		-- 4. 第二次记录：winner变成了因为动画站起来的玩家，leavingPlayer变成了真正的获胜者
		--
		-- if _G.RankingDataManager then
		--	_G.RankingDataManager.recordGameResult(winner, true)
		--	_G.RankingDataManager.recordGameResult(leavingPlayer, false)
		--
		--	-- V1.5: 更新玩家头顶连胜显示
		--	if _G.PlayerOverheadDisplayManager then
		--		_G.PlayerOverheadDisplayManager.onWinStreakChanged(winner)
		--		_G.PlayerOverheadDisplayManager.onWinStreakChanged(leavingPlayer)
		--	end
		-- end

		self.gameState.gamePhase = "result"

		-- 立即重置游戏，无需等待（玩家离开情况下）
		-- refreshSeatState会自动为仍在座位上的获胜玩家设置准备状态
		self:resetToWaiting()
	else
		-- 没有获胜者的情况（两个玩家都离开）：立即重置游戏
		-- 立即清理离开玩家的引用
		if self.gameState.player1 == leavingPlayer then
			self.gameState.player1 = nil
			self.gameState.playersReady = self.gameState.playersReady - 1
		elseif self.gameState.player2 == leavingPlayer then
			self.gameState.player2 = nil
			self.gameState.playersReady = self.gameState.playersReady - 1
		end

		self.gameState.gamePhase = "result"
		-- 立即重置，不需要等待
		self:resetToWaiting()
	end
end

-- 重置到等待状态
function GameInstance:resetToWaiting()

	self.gameState.gamePhase = "waiting"
	self.gameState.isCountingDown = false
	self.gameState.poisonSelections = {}

	-- 禁用AirWall，恢复自由通行
	self:disableAirWalls()

	-- V1.7: 清理房间好友缓存
	if _G.FriendsService then
		_G.FriendsService:clearRoomCache(self.tableId)
	end

	-- 为仍在座位上的玩家显示Menu界面（退出对局状态）
	-- 使用特定菜单配置：只显示shop按钮
	-- Skin和Emote按钮始终显示，不受游戏状态影响
	if self.gameState.player1 then
		self:setSpecificMenuVisibility(self.gameState.player1, {
			shop = true,
			death = false
		})
	end
	if self.gameState.player2 then
		self:setSpecificMenuVisibility(self.gameState.player2, {
			shop = true,
			death = false
		})
	end

	-- 清理桌子上的奶茶模型
	DrinkManager.clearDrinksForTable(self.tableId)

	-- 重新检测当前座位占用情况
	self:refreshSeatState()

	-- 显示BillboardGui
	self.billboardGui.Enabled = true

	-- 更新玩家数量显示
	self:updatePlayerCount()
end

-- 刷新座位状态
function GameInstance:refreshSeatState()
	local actualPlayer1 = nil
	local actualPlayer2 = nil
	local actualCount = 0

	if self.seat1.Occupant then
		-- 🔧 关键修复：增加座位占用者的安全检查
		local character1 = self.seat1.Occupant.Parent
		if character1 then
			-- 🔧 V1.6: 先尝试从Players服务获取玩家
			local player1 = Players:GetPlayerFromCharacter(character1)

			-- 🔧 V1.6: 如果不是真实玩家，检查是否为NPC
			if not player1 and _G.TutorialBotService then
				if _G.TutorialBotService:isBotCharacter(character1) then
					-- 使用NPC的伪Player对象
					player1 = _G.TutorialBotService:getPlayerProxy()
				end
			end

			if player1 and player1.Parent then  -- 检查玩家是否仍在游戏中
				actualPlayer1 = player1
				actualCount = actualCount + 1
			end
		end
	end

	if self.seat2.Occupant then
		-- 🔧 关键修复：增加座位占用者的安全检查
		local character2 = self.seat2.Occupant.Parent
		if character2 then
			-- 🔧 V1.6: 先尝试从Players服务获取玩家
			local player2 = Players:GetPlayerFromCharacter(character2)

			-- 🔧 V1.6: 如果不是真实玩家，检查是否为NPC
			if not player2 and _G.TutorialBotService then
				if _G.TutorialBotService:isBotCharacter(character2) then
					-- 使用NPC的伪Player对象
					player2 = _G.TutorialBotService:getPlayerProxy()
				end
			end

			if player2 and player2.Parent then  -- 检查玩家是否仍在游戏中
				actualPlayer2 = player2
				actualCount = actualCount + 1
			end
		end
	end

	self.gameState.player1 = actualPlayer1
	self.gameState.player2 = actualPlayer2
	self.gameState.playersReady = actualCount

	-- 为重新检测到的玩家设置准备状态
	if self.gameState.gamePhase == "waiting" then
		if actualPlayer1 then
			self:enableLeaveButton(actualPlayer1)
			-- 🔧 修改：等待阶段不锁定镜头，保持镜头自由
			-- 镜头锁定延迟到倒计时阶段进行
			-- 设置正确的菜单显示：只显示shop按钮
			-- Skin和Emote按钮始终显示，不受游戏状态影响
			self:setSpecificMenuVisibility(actualPlayer1, {
				shop = true,
				death = false
			})
		end
		if actualPlayer2 then
			self:enableLeaveButton(actualPlayer2)
			-- 🔧 修改：等待阶段不锁定镜头，保持镜头自由
			-- 镜头锁定延迟到倒计时阶段进行
			-- 设置正确的菜单显示：只显示shop按钮
			-- Skin和Emote按钮始终显示，不受游戏状态影响
			self:setSpecificMenuVisibility(actualPlayer2, {
				shop = true,
				death = false
			})
		end
	end
end

-- 设置座位检测
function GameInstance:setupSeatDetection()
	-- 检测座位1
	self.seat1:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = self.seat1.Occupant
		if occupant then
			-- 🔧 V1.6: 先尝试从Players服务获取玩家
			local player = Players:GetPlayerFromCharacter(occupant.Parent)

			-- 🔧 V1.6: 如果不是真实玩家，检查是否为NPC
			if not player and _G.TutorialBotService then
				local npcCharacter = occupant.Parent
				if _G.TutorialBotService:isBotCharacter(npcCharacter) then
					-- 使用NPC的伪Player对象
					player = _G.TutorialBotService:getPlayerProxy()
				end
			end

			if player then
				self:onPlayerSat(self.seat1, player)
			end
		else
			if self.gameState.player1 then
				self:onPlayerLeft(self.seat1, self.gameState.player1)
			end
		end
	end)

	-- 检测座位2
	self.seat2:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = self.seat2.Occupant
		if occupant then
			-- 🔧 V1.6: 先尝试从Players服务获取玩家
			local player = Players:GetPlayerFromCharacter(occupant.Parent)

			-- 🔧 V1.6: 如果不是真实玩家，检查是否为NPC
			if not player and _G.TutorialBotService then
				local npcCharacter = occupant.Parent
				if _G.TutorialBotService:isBotCharacter(npcCharacter) then
					-- 使用NPC的伪Player对象
					player = _G.TutorialBotService:getPlayerProxy()
				end
			end

			if player then
				self:onPlayerSat(self.seat2, player)
			end
		else
			if self.gameState.player2 then
				self:onPlayerLeft(self.seat2, self.gameState.player2)
			end
		end
	end)

end

return GameInstance