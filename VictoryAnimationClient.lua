-- 脚本名称: VictoryAnimationClient
-- 脚本作用: 客户端胜利动画辅助控制器，确保动画期间移动完全禁用
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer.StarterPlayerScripts
-- 功能：
--   1. 接收服务器的移动禁用/恢复命令
--   2. 在客户端强制禁用移动和跳跃
--   3. 防止动画期间的输入干扰
--   4. 确保动画播放完整性

local VictoryAnimationClient = {}
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- 移动控制状态
local movementControlState = {
	isDisabled = false,
	originalWalkSpeed = 16,
	originalJumpPower = 50,
	originalJumpHeight = 7.2,
	heartbeatConnection = nil,
	inputConnections = {},
	character = nil,
	humanoid = nil
}

-- ============================================
-- 前向声明函数
-- ============================================

-- 前向声明，避免作用域问题
local disableMovement
local enableMovement
local setupInputBlocking
local clearInputBlocking

-- ============================================
-- 输入拦截系统
-- ============================================

-- 设置输入拦截
setupInputBlocking = function()
	clearInputBlocking() -- 先清理旧连接

	-- 拦截键盘输入
	local keyInputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not movementControlState.isDisabled then
			return
		end

		-- 拦截移动相关按键
		if input.KeyCode == Enum.KeyCode.W or
		   input.KeyCode == Enum.KeyCode.A or
		   input.KeyCode == Enum.KeyCode.S or
		   input.KeyCode == Enum.KeyCode.D or
		   input.KeyCode == Enum.KeyCode.Space or
		   input.KeyCode == Enum.KeyCode.Up or
		   input.KeyCode == Enum.KeyCode.Down or
		   input.KeyCode == Enum.KeyCode.Left or
		   input.KeyCode == Enum.KeyCode.Right then

			-- 注意：我们不能完全阻止输入，但可以立即重置移动状态
			-- 这样可以最大程度减少移动对动画的干扰
			local character = player.Character
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					-- 立即重置移动状态
					humanoid:Move(Vector3.new(0, 0, 0))
				end
			end
		end
	end)

	-- 拦截触摸移动（移动设备）
	local touchInputConnection = UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
		if not movementControlState.isDisabled then
			return
		end

		-- 移动设备上也需要限制触摸移动
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:Move(Vector3.new(0, 0, 0))
			end
		end
	end)

	-- 保存连接以便清理
	movementControlState.inputConnections = {
		keyInput = keyInputConnection,
		touchInput = touchInputConnection
	}
end

-- 清理输入拦截
clearInputBlocking = function()
	for _, connection in pairs(movementControlState.inputConnections) do
		if connection then
			connection:Disconnect()
		end
	end
	movementControlState.inputConnections = {}
end

-- ============================================
-- 移动控制核心函数
-- ============================================

-- 恢复玩家移动
enableMovement = function()
	print("🔄 VictoryAnimationClient: 开始恢复移动")

	if not movementControlState.isDisabled then
		print("   状态检查：移动未被禁用，无需恢复")
		return -- 没有禁用
	end

	-- 清理心跳连接
	if movementControlState.heartbeatConnection then
		movementControlState.heartbeatConnection:Disconnect()
		movementControlState.heartbeatConnection = nil
		print("   ✅ 已断开心跳连接")
	end

	-- 清理输入连接
	clearInputBlocking()
	print("   ✅ 已清理输入拦截")

	-- 恢复移动能力（如果角色仍然存在）
	local character = player.Character
	if character and character == movementControlState.character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid == movementControlState.humanoid then
			print(string.format("   当前移动参数: WalkSpeed=%.1f, JumpPower=%.1f, JumpHeight=%.1f",
				humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight))
			print(string.format("   当前Sit状态: %s", tostring(humanoid.Sit)))
			print(string.format("   恢复目标参数: WalkSpeed=%.1f, JumpPower=%.1f, JumpHeight=%.1f",
				movementControlState.originalWalkSpeed, movementControlState.originalJumpPower, movementControlState.originalJumpHeight))

			-- 🔑 关键修复：强制角色站立，确保不会保持坐着的姿势
			humanoid.Sit = false
			print("   🚶 强制角色站立，防止动画残留的坐姿")

			-- 🔧 关键修复：检查SeatLockController状态，智能恢复属性
			local seatLockActive = _G.SeatLockController and _G.SeatLockController.isLocked and _G.SeatLockController.isLocked()
			print(string.format("   SeatLock状态: %s", seatLockActive and "激活" or "未激活"))

			-- 🔧 使用防守性默认值，确保移动参数有效
			local walkSpeedToRestore = movementControlState.originalWalkSpeed
			if not walkSpeedToRestore or walkSpeedToRestore <= 0 then
				walkSpeedToRestore = 16
				warn("   ⚠️ 原始WalkSpeed无效，使用默认值16")
			end

			local jumpPowerToRestore = movementControlState.originalJumpPower
			if not jumpPowerToRestore or jumpPowerToRestore <= 0 then
				jumpPowerToRestore = 50
				warn("   ⚠️ 原始JumpPower无效，使用默认值50")
			end

			local jumpHeightToRestore = movementControlState.originalJumpHeight
			if not jumpHeightToRestore or jumpHeightToRestore <= 0 then
				jumpHeightToRestore = 7.2
				warn("   ⚠️ 原始JumpHeight无效，使用默认值7.2")
			end

			-- 恢复WalkSpeed（总是恢复）
			humanoid.WalkSpeed = walkSpeedToRestore
			print(string.format("   ✅ 已恢复WalkSpeed: %.1f", walkSpeedToRestore))

			-- 只有在SeatLock未激活时才恢复跳跃属性，否则让SeatLock保持控制
			if not seatLockActive then
				humanoid.JumpPower = jumpPowerToRestore
				humanoid.JumpHeight = jumpHeightToRestore
				print(string.format("   ✅ 已恢复JumpPower: %.1f, JumpHeight: %.1f", jumpPowerToRestore, jumpHeightToRestore))
			else
				print("   ⚠️ SeatLock激活中，保持跳跃禁用状态")
			end

			-- 🔑 关键修复：再次确认角色处于正确的站立状态
			task.wait(0.02)
			if humanoid.Sit then
				humanoid.Sit = false
				print("   🔄 二次确认：强制角色站立")
			end

			-- 验证设置是否生效
			task.wait(0.05)
			local actualWalkSpeed = humanoid.WalkSpeed
			local actualJumpPower = humanoid.JumpPower
			local actualJumpHeight = humanoid.JumpHeight

			print(string.format("   验证结果: WalkSpeed=%.1f, JumpPower=%.1f, JumpHeight=%.1f",
				actualWalkSpeed, actualJumpPower, actualJumpHeight))
			print(string.format("   最终Sit状态: %s", tostring(humanoid.Sit)))

			-- 🔑 关键修复：检查最终Sit状态，如果异常则强制修正
			if humanoid.Sit then
				warn("   ⚠️ 检测到异常的Sit状态，强制修正")

				-- 🚀 超级强制站立：多重方法确保成功
				-- 方法1: 直接设置Sit = false
				humanoid.Sit = false

				-- 方法2: 如果有SeatPart，强制断开连接
				if humanoid.SeatPart then
					humanoid.SeatPart = nil
					warn("   🔧 已强制断开SeatPart连接")
				end

				-- 方法3: 通过PlatformStand强制控制
				humanoid.PlatformStand = true
				task.wait(0.05)
				humanoid.PlatformStand = false

				-- 方法4: 移动角色离开可能的座位碰撞区域
				local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					local currentCF = rootPart.CFrame
					-- 向上移动0.5单位，离开座位碰撞区域
					rootPart.CFrame = currentCF + Vector3.new(0, 0.5, 0)
					warn("   🚀 已移动角色避免座位碰撞")
				end

				-- 等待一帧确保修正生效
				task.wait(0.1)
				print(string.format("   🔄 修正后Sit状态: %s", tostring(humanoid.Sit)))

				-- 🔧 如果还是无法修正，使用终极方案
				if humanoid.Sit then
					warn("   ❌ 常规方法无效，使用终极修正方案")
					-- 重置Humanoid状态
					humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
					task.wait(0.05)
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
					warn("   🚀 已重置Humanoid状态机")
				end
			end

			-- 检查WalkSpeed是否恢复成功
			if math.abs(actualWalkSpeed - walkSpeedToRestore) > 0.1 then
				warn(string.format("   ⚠️ WalkSpeed恢复异常: %.1f (期望: %.1f)，尝试重新设置", actualWalkSpeed, walkSpeedToRestore))
				humanoid.WalkSpeed = walkSpeedToRestore
				task.wait(0.05)
				if math.abs(humanoid.WalkSpeed - walkSpeedToRestore) > 0.1 then
					warn(string.format("   ❌ WalkSpeed重试后仍异常: %.1f (期望: %.1f)", humanoid.WalkSpeed, walkSpeedToRestore))
				else
					print("   ✅ WalkSpeed重试成功")
				end
			end

			-- 🔧 新增：检查JumpPower/JumpHeight是否被其他系统重置
			if not seatLockActive then -- 只在SeatLock未激活时检查
				if actualJumpPower ~= jumpPowerToRestore then
					warn(string.format("   ⚠️ JumpPower被重置: %.1f (期望: %.1f)，重新恢复", actualJumpPower, jumpPowerToRestore))
					humanoid.JumpPower = jumpPowerToRestore
				end
				if actualJumpHeight ~= jumpHeightToRestore then
					warn(string.format("   ⚠️ JumpHeight被重置: %.1f (期望: %.1f)，重新恢复", actualJumpHeight, jumpHeightToRestore))
					humanoid.JumpHeight = jumpHeightToRestore
				end
			end
		else
			warn("   ⚠️ 角色或Humanoid已改变，使用当前角色恢复默认值")
			-- 如果角色或Humanoid改变，使用当前角色恢复默认值
			local currentHumanoid = character:FindFirstChildOfClass("Humanoid")
			if currentHumanoid then
				-- 🔑 关键修复：确保站立状态
				currentHumanoid.Sit = false
				currentHumanoid.WalkSpeed = 16
				currentHumanoid.JumpPower = 50
				currentHumanoid.JumpHeight = 7.2
				print("   ✅ 已设置默认移动参数并强制站立")
			end
		end
	else
		warn("   ⚠️ 角色不存在或已改变")
	end

	-- 重置状态
	movementControlState.isDisabled = false
	movementControlState.character = nil
	movementControlState.humanoid = nil

	print("✅ VictoryAnimationClient: 移动恢复完成")
end

-- 禁用玩家移动（客户端强制）
disableMovement = function()
	print("🚫 VictoryAnimationClient: 开始禁用移动")

	if movementControlState.isDisabled then
		print("   状态检查：移动已被禁用")
		return -- 已经禁用
	end

	local character = player.Character
	if not character then
		warn("VictoryAnimationClient: 角色不存在，无法禁用移动")
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("VictoryAnimationClient: Humanoid不存在，无法禁用移动")
		return
	end

	-- 🔧 关键修复：智能保存原始值，防止保存0值
	local originalWalkSpeed = humanoid.WalkSpeed
	local originalJumpPower = humanoid.JumpPower
	local originalJumpHeight = humanoid.JumpHeight

	print(string.format("   当前移动参数: WalkSpeed=%.1f, JumpPower=%.1f, JumpHeight=%.1f",
		originalWalkSpeed, originalJumpPower, originalJumpHeight))

	-- 如果当前WalkSpeed为0（可能在座位上），使用默认值
	if originalWalkSpeed <= 0 then
		originalWalkSpeed = 16
		warn("   ⚠️ 检测到WalkSpeed为0，使用默认值16作为恢复目标")
	end

	if originalJumpPower <= 0 then
		originalJumpPower = 50
		warn("   ⚠️ 检测到JumpPower为0，使用默认值50作为恢复目标")
	end

	if originalJumpHeight <= 0 then
		originalJumpHeight = 7.2
		warn("   ⚠️ 检测到JumpHeight为0，使用默认值7.2作为恢复目标")
	end

	-- 保存修正后的原始值
	movementControlState.originalWalkSpeed = originalWalkSpeed
	movementControlState.originalJumpPower = originalJumpPower
	movementControlState.originalJumpHeight = originalJumpHeight
	movementControlState.character = character
	movementControlState.humanoid = humanoid
	movementControlState.isDisabled = true

	print(string.format("   保存恢复目标: WalkSpeed=%.1f, JumpPower=%.1f, JumpHeight=%.1f",
		originalWalkSpeed, originalJumpPower, originalJumpHeight))

	-- 立即禁用移动
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	print("   ✅ 已设置移动参数为0")

	-- 🔑 关键：持续监控并强制保持移动禁用状态
	movementControlState.heartbeatConnection = RunService.Heartbeat:Connect(function()
		if not movementControlState.isDisabled then
			return
		end

		-- 验证角色和Humanoid仍然有效
		local currentCharacter = player.Character
		if not currentCharacter or currentCharacter ~= movementControlState.character then
			-- 角色已改变，停止控制
			print("   ⚠️ 角色已改变，停止移动控制")
			enableMovement()
			return
		end

		local currentHumanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
		if not currentHumanoid or currentHumanoid ~= movementControlState.humanoid then
			-- Humanoid已改变，停止控制
			print("   ⚠️ Humanoid已改变，停止移动控制")
			enableMovement()
			return
		end

		-- 🔧 关键修复：检查SeatLockController状态，避免冲突
		-- 如果SeatLockController处于激活状态，只控制WalkSpeed，不干预Jump属性
		local seatLockActive = _G.SeatLockController and _G.SeatLockController.isLocked and _G.SeatLockController.isLocked()

		-- 强制保持移动禁用（防止其他脚本修改）
		if currentHumanoid.WalkSpeed ~= 0 then
			currentHumanoid.WalkSpeed = 0
		end

		-- 只有在SeatLock未激活时才控制跳跃属性，避免冲突
		if not seatLockActive then
			if currentHumanoid.JumpPower ~= 0 then
				currentHumanoid.JumpPower = 0
			end
			if currentHumanoid.JumpHeight ~= 0 then
				currentHumanoid.JumpHeight = 0
			end
		end

		-- 🔑 额外保护：防止玩家通过其他方式移动
		local rootPart = currentCharacter:FindFirstChild("HumanoidRootPart")
		if rootPart then
			-- 限制玩家通过外力移动（保持相对位置稳定）
			local currentVelocity = rootPart.AssemblyLinearVelocity
			if currentVelocity.Magnitude > 1 then -- 如果移动速度过大
				-- 减缓移动（不完全停止，避免影响动画播放）
				rootPart.AssemblyLinearVelocity = currentVelocity * 0.1
			end
		end
	end)

	-- 🔑 输入拦截：防止移动键输入
	setupInputBlocking()

	print("✅ VictoryAnimationClient: 移动禁用完成")
end

-- ============================================
-- RemoteEvent通信
-- ============================================

-- 处理服务器命令
local function handleServerCommand(action, data)
	if action == "disableMovement" then
		disableMovement()
	elseif action == "enableMovement" then
		enableMovement()
	elseif action == "forceStop" then
		-- 强制停止所有胜利动画相关控制
		enableMovement()
	else
		warn("VictoryAnimationClient: 未知命令 - " .. tostring(action))
	end
end

-- 初始化RemoteEvent通信
local function initializeRemoteEvents()
	-- 等待RemoteEvents文件夹
	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEventsFolder then
		warn("VictoryAnimationClient: RemoteEvents文件夹不存在")
		return false
	end

	-- 查找或创建VictoryAnimationControl RemoteEvent
	local victoryControlEvent = remoteEventsFolder:FindFirstChild("VictoryAnimationControl")
	if not victoryControlEvent then
		warn("VictoryAnimationClient: VictoryAnimationControl RemoteEvent不存在，等待服务器创建")
		-- 等待服务器创建
		victoryControlEvent = remoteEventsFolder:WaitForChild("VictoryAnimationControl", 5)
		if not victoryControlEvent then
			warn("VictoryAnimationClient: VictoryAnimationControl RemoteEvent创建超时")
			return false
		end
	end

	-- 监听服务器命令
	victoryControlEvent.OnClientEvent:Connect(handleServerCommand)

	print("🎭 VictoryAnimationClient: RemoteEvent通信已建立")
	return true
end

-- ============================================
-- 生命周期管理
-- ============================================

-- 处理角色重生
local function onCharacterAdded(character)
	-- 角色重生时，清理所有状态
	enableMovement()

	-- 等待Humanoid加载
	local humanoid = character:WaitForChild("Humanoid")
	if humanoid then
		-- 监听死亡事件，确保清理
		humanoid.Died:Connect(function()
			enableMovement()
		end)
	end
end

-- ============================================
-- 初始化
-- ============================================

function VictoryAnimationClient.initialize()
	-- 初始化RemoteEvent通信
	local success = initializeRemoteEvents()
	if not success then
		warn("❌ VictoryAnimationClient: 初始化失败")
		return false
	end

	-- 设置角色生命周期监听
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)

	-- 监听玩家离开游戏，清理状态
	player.AncestryChanged:Connect(function()
		if not player.Parent then
			enableMovement()
		end
	end)

	print("✅ VictoryAnimationClient: 初始化完成")
	return true
end

-- 调试接口
function VictoryAnimationClient.getState()
	return {
		isDisabled = movementControlState.isDisabled,
		hasCharacter = movementControlState.character ~= nil,
		hasHumanoid = movementControlState.humanoid ~= nil,
		hasHeartbeat = movementControlState.heartbeatConnection ~= nil
	}
end

-- ============================================
-- 启动
-- ============================================

-- 延迟启动，确保所有系统已加载
task.spawn(function()
	task.wait(2) -- 等待2秒让所有系统初始化完成
	VictoryAnimationClient.initialize()
end)

-- 导出到全局（调试用）
_G.VictoryAnimationClient = VictoryAnimationClient

return VictoryAnimationClient