-- 脚本名称: AdminResetCommands
-- 脚本作用: 管理员重置玩家数据为新玩家的命令系统
-- 脚本类型: ModuleScript
-- 放置位置: ServerScriptService
-- 版本: V1.9

local AdminReset = {}
AdminReset.__index = AdminReset

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 管理员白名单（UserId）
local ADMIN_WHITELIST = {
	-- 137503366,  -- 示例管理员ID（需要替换为实际ID）
}

-- 操作日志存储（仅在非Studio环境）
local auditLogStore = nil
local isStudio = game:GetService("RunService"):IsStudio()

if not isStudio then
	auditLogStore = DataStoreService:GetDataStore("AdminAuditLog")
end

-- ============================================
-- 模块导入
-- ============================================

local function loadModules()
	-- 加载各个数据管理模块（带错误提示）
	local modules = {}

	local moduleNames = {
		-- "CoinManager",  -- ⚠️ CoinManager 是 Script，无法 require
		"PropManager",
		"PlayerDataService",
		"InviteManager",
		"WheelDataManager",
		"SkinDataManager",
		"EmoteDataManager",
		"FreeGiftManager"
	}

	for _, moduleName in ipairs(moduleNames) do
		local success, module = pcall(function()
			return require(script.Parent[moduleName])
		end)

		if success then
			modules[moduleName] = module
			print("[AdminReset] ✓ 已加载模块: " .. moduleName)
		else
			warn("[AdminReset] ✗ 无法加载模块 " .. moduleName .. ": " .. tostring(module))
			-- 继续加载其他模块，而不是全部失败
			modules[moduleName] = nil
		end
	end

	-- 尝试从全局变量加载 CoinManager（如果它是 Script）
	if _G.CoinManager then
		modules.CoinManager = _G.CoinManager
		print("[AdminReset] ✓ 已从全局变量加载模块: CoinManager")
	else
		-- warn("[AdminReset] ⚠️  CoinManager 未找到（可能是 Script 但未导出到 _G）")
		modules.CoinManager = nil
	end

	return modules
end

-- ============================================
-- 权限检查
-- ============================================

local function isAdmin(adminId)
	if not adminId then return false end

	-- 开发服务器模式：允许所有人（仅用于开发测试）
	if isStudio then
		return true
	end

	-- 检查白名单
	for _, id in ipairs(ADMIN_WHITELIST) do
		if id == adminId then
			return true
		end
	end

	return false
end

-- ============================================
-- 操作日志
-- ============================================

local function logAdminAction(adminId, adminName, targetUserId, targetName, action, success, details)
	if not auditLogStore then
		return
	end

	local timestamp = os.time()
	local logEntry = {
		timestamp = timestamp,
		adminId = adminId,
		adminName = adminName,
		targetUserId = targetUserId,
		targetName = targetName,
		action = action,
		success = success,
		details = details or ""
	}

	-- 异步保存日志
	spawn(function()
		local logKey = "Admin_" .. adminId .. "_" .. timestamp
		local success, err = pcall(function()
			auditLogStore:SetAsync(logKey, logEntry)
		end)

		if not success then
			warn("[AdminReset] 操作日志保存失败: " .. tostring(err))
		end
	end)
end

-- ============================================
-- 用户ID解析
-- ============================================

local function resolveUserId(identifier)
	-- 如果已是数字，直接返回
	if tonumber(identifier) then
		return tonumber(identifier)
	end

	-- 尝试按名称查找
	local success, userId = pcall(Players.GetUserIdFromNameAsync, Players, identifier)

	if success and userId then
		return userId
	else
		error("找不到用户: " .. tostring(identifier))
	end
end

-- ============================================
-- 玩家重置主函数
-- ============================================

function AdminReset.resetPlayerToNew(identifier, adminId, adminName)
	print("[AdminReset] 开始处理玩家重置请求...")
	print("  标识符: " .. tostring(identifier))
	print("  管理员ID: " .. tostring(adminId))
	print("  管理员名: " .. tostring(adminName))

	-- ========== 步骤1：权限检查 ==========
	if not isAdmin(adminId) then
		local errMsg = "权限不足: 管理员 " .. tostring(adminId) .. " 无权执行此操作"
		warn("[AdminReset] " .. errMsg)
		logAdminAction(adminId, adminName, 0, "", "reset", false, errMsg)
		error(errMsg)
	end

	-- ========== 步骤2：解析用户ID ==========
	local userId
	local success, err = pcall(function()
		userId = resolveUserId(identifier)
	end)

	if not success or not userId then
		local errMsg = "无法解析用户ID: " .. tostring(err)
		warn("[AdminReset] " .. errMsg)
		logAdminAction(adminId, adminName, 0, "", "reset", false, errMsg)
		error(errMsg)
	end

	-- ========== 步骤3：获取玩家信息 ==========
	local player = Players:GetPlayerByUserId(userId)
	local playerName = player and player.Name or "Unknown"

	print("[AdminReset] 目标玩家: " .. playerName .. " (UserId: " .. userId .. ")")

	-- ⚠️ 重要：检查玩家是否在线
	-- 由于大多数数据管理模块在离线状态下无法正确处理（没有 player 实例）
	-- 我们要求玩家必须在线才能执行重置
	if not player or not player.Parent then
		local errMsg = "玩家必须在线才能执行重置 (UserId: " .. userId .. ")"
		warn("[AdminReset] " .. errMsg)
		logAdminAction(adminId, adminName, userId, playerName, "reset", false, errMsg)
		error(errMsg)
	end

	print("[AdminReset] ✓ 玩家在线状态检查通过")

	-- ========== 步骤4：加载所有管理模块 ==========
	local modules = loadModules()

	-- ========== 步骤5：逐个调用重置函数 ==========
	local resetResults = {}

	local resetFunctions = {
		-- { name = "CoinManager", func = modules.CoinManager.resetPlayerData },  -- ⚠️ 已跳过（CoinManager 是 Script）
		-- { name = "PropManager", func = modules.PropManager.resetPlayerData },  -- ⚠️ 已跳过（PropManager 加载失败）
		{ name = "PlayerDataService", func = modules.PlayerDataService.resetPlayerData },
		{ name = "InviteManager", func = modules.InviteManager.resetPlayerData },
		-- { name = "WheelDataManager", func = modules.WheelDataManager.resetPlayerData },  -- ⚠️ 已跳过（WheelDataManager 加载失败）
		-- { name = "SkinDataManager", func = modules.SkinDataManager.resetPlayerData },  -- ⚠️ 已跳过（SkinDataManager 加载失败）
		{ name = "EmoteDataManager", func = modules.EmoteDataManager.resetPlayerData },
		{ name = "FreeGiftManager", func = modules.FreeGiftManager.resetPlayerData }
	}

	for _, resetInfo in ipairs(resetFunctions) do
		print("\n[AdminReset] 重置 " .. resetInfo.name .. "...")

		-- 检查模块是否存在
		if not resetInfo.func then
			warn("[AdminReset] ✗ " .. resetInfo.name .. " 模块未加载，跳过")
			resetResults[resetInfo.name] = { success = false, error = "模块未加载" }
		else
			local pcallSuccess, resetResult = pcall(function()
				return resetInfo.func(userId, player)
			end)

			-- 需要同时检查：
			-- 1. pcall 是否执行成功（没有抛错）
			-- 2. 模块的 resetPlayerData 返回值是否为真
			local moduleResetSuccess = pcallSuccess and resetResult == true

			if moduleResetSuccess then
				print("[AdminReset] ✓ " .. resetInfo.name .. " 重置成功")
				resetResults[resetInfo.name] = { success = true }
			else
				local errorMsg
				if not pcallSuccess then
					-- pcall 执行出错
					errorMsg = tostring(resetResult)
				else
					-- 模块返回 false（例如玩家离线）
					errorMsg = "重置失败（玩家可能离线或模块处理出错）"
				end
				warn("[AdminReset] ✗ " .. resetInfo.name .. " 重置失败: " .. errorMsg)
				resetResults[resetInfo.name] = { success = false, error = errorMsg }
			end
		end
	end

	-- ========== 步骤6：记录日志 ==========
	local logDetails = "重置的模块: "
	for moduleName, result in pairs(resetResults) do
		logDetails = logDetails .. moduleName .. "(" .. (result.success and "✓" or "✗") .. ") "
	end

	logAdminAction(adminId, adminName, userId, playerName, "reset_player", true, logDetails)

	-- ========== 步骤7：输出最终结果 ==========
	print("\n" .. string.rep("=", 50))
	print("[AdminReset] 玩家重置完成")
	print("  玩家: " .. playerName .. " (UserId: " .. userId .. ")")
	print("  管理员: " .. adminName .. " (AdminId: " .. adminId .. ")")
	print("  时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
	print("\n重置结果:")

	for moduleName, result in pairs(resetResults) do
		local status = result.success and "✓" or "✗"
		print("  " .. status .. " " .. moduleName)
		if not result.success then
			print("      错误: " .. result.error)
		end
	end

	print(string.rep("=", 50))

	return {
		success = true,
		userId = userId,
		playerName = playerName,
		results = resetResults
	}
end

-- ============================================
-- 添加管理员
-- ============================================

function AdminReset.addAdmin(userId)
	if not isStudio then
		warn("[AdminReset] 仅在Studio环境中可添加管理员")
		return false
	end

	-- 检查是否已存在
	for _, id in ipairs(ADMIN_WHITELIST) do
		if id == userId then
			print("[AdminReset] 管理员已存在: " .. userId)
			return false
		end
	end

	table.insert(ADMIN_WHITELIST, userId)
	print("[AdminReset] ✓ 管理员已添加: " .. userId)
	return true
end

-- ============================================
-- 列出管理员
-- ============================================

function AdminReset.listAdmins()
	print("[AdminReset] 当前管理员列表:")
	if #ADMIN_WHITELIST == 0 then
		print("  （无管理员）")
		return
	end

	for i, id in ipairs(ADMIN_WHITELIST) do
		print("  " .. i .. ". UserId: " .. id)
	end
end

-- ============================================
-- 初始化
-- ============================================

function AdminReset.initialize()
	print("[AdminReset] 初始化完成")
	print("[AdminReset] 使用方法: _G.AdminReset.resetPlayerToNew(\"PlayerName\", adminId, adminName)")

	-- 在Studio环境下添加一个测试管理员
	if isStudio then
		AdminReset.addAdmin(1)  -- 测试ID
		print("[AdminReset] Studio环境已启用，UserId=1 可作为管理员测试")
	end
end

-- 延迟初始化，等待模块加载
task.wait(1)
AdminReset.initialize()

-- 全局导出
_G.AdminReset = AdminReset

return AdminReset
