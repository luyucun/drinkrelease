-- 脚本名称: PropDebugCommands
-- 脚本作用: 道具系统调试命令处理
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local PropDebugCommands = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引入配置和管理器
local PropConfig = require(script.Parent.PropConfig)

-- 管理员列表（可以使用调试命令的玩家）
local ADMIN_USERS = {"matuanksc"
	-- 可以在这里添加管理员的用户名或UserId
	-- 例如: ["YourUsername"] = true,
	-- 或者: [123456789] = true, -- UserId
}

-- 检查玩家是否是管理员
local function isAdmin(player)
	-- 在Studio中，所有玩家都被视为管理员（方便调试）
	if game:GetService("RunService"):IsStudio() then
		return true
	end

	-- 检查用户名
	if ADMIN_USERS[player.Name] then
		return true
	end

	-- 检查UserId
	if ADMIN_USERS[player.UserId] then
		return true
	end

	return false
end

-- 发送消息给玩家
local function sendMessage(player, message, color)
	local chatService = game:GetService("StarterGui")
	spawn(function()
		chatService:SetCore("ChatMakeSystemMessage", {
			Text = "[DEBUG] " .. message;
			Color = color or Color3.new(1, 1, 0); -- 默认黄色
			Font = Enum.Font.SourceSansBold;
			FontSize = Enum.FontSize.Size18;
		})
	end)
end

-- 处理道具添加命令
local function handleAddPropCommand(player, args)
	if #args < 2 then
		sendMessage(player, "用法: /道具 <道具ID> <数量>", Color3.new(1, 0, 0))
		sendMessage(player, "道具ID: 1=毒药验证, 2=跳过选择, 3=清除毒药", Color3.new(0.8, 0.8, 0.8))
		return
	end

	local propId = tonumber(args[1])
	local quantity = tonumber(args[2])

	-- 验证参数
	if not propId or not PropConfig.isValidPropId(propId) then
		sendMessage(player, "无效的道具ID: " .. tostring(args[1]), Color3.new(1, 0, 0))
		sendMessage(player, "有效ID: 1=毒药验证, 2=跳过选择, 3=清除毒药", Color3.new(0.8, 0.8, 0.8))
		return
	end

	if not quantity or quantity <= 0 or quantity > 999 then
		sendMessage(player, "无效的数量: " .. tostring(args[2]) .. " (范围: 1-999)", Color3.new(1, 0, 0))
		return
	end

	-- 检查PropManager是否可用
	if not _G.PropManager or not _G.PropManager.addProp then
		sendMessage(player, "PropManager未加载，无法添加道具", Color3.new(1, 0, 0))
		return
	end

	-- 添加道具
	local success = _G.PropManager.addProp(player, propId, quantity)

	if success then
		local propName = PropConfig.getPropName(propId)
		sendMessage(player, "成功添加 " .. propName .. " x" .. quantity, Color3.new(0, 1, 0))
		print("[DEBUG] 管理员 " .. player.Name .. " 添加了道具: " .. propName .. " x" .. quantity)
	else
		sendMessage(player, "添加道具失败", Color3.new(1, 0, 0))
	end
end

-- 显示道具帮助信息
local function showPropHelp(player)
	sendMessage(player, "=== 道具调试命令帮助 ===", Color3.new(0, 1, 1))
	sendMessage(player, "用法: /道具 <道具ID> <数量>", Color3.new(1, 1, 1))
	sendMessage(player, "", Color3.new(1, 1, 1))
	sendMessage(player, "道具列表:", Color3.new(0.8, 0.8, 0.8))

	for propId, propInfo in pairs(PropConfig.getAllProps()) do
		sendMessage(player, propId .. " = " .. propInfo.name, Color3.new(0.8, 0.8, 0.8))
	end

	sendMessage(player, "", Color3.new(1, 1, 1))
	sendMessage(player, "示例: /道具 1 5  (添加5个毒药验证)", Color3.new(0.6, 1, 0.6))
end

-- 显示玩家当前道具
local function showPlayerProps(player)
	if not _G.PropManager or not _G.PropManager.getPropQuantity then
		sendMessage(player, "PropManager未加载", Color3.new(1, 0, 0))
		return
	end

	sendMessage(player, "=== 当前道具数量 ===", Color3.new(0, 1, 1))

	for propId, propInfo in pairs(PropConfig.getAllProps()) do
		local quantity = _G.PropManager.getPropQuantity(player, propId)
		sendMessage(player, propInfo.name .. ": " .. quantity, Color3.new(1, 1, 1))
	end
end

-- 处理聊天命令
local function onPlayerChatted(player, message)
	-- 只有管理员才能使用调试命令
	if not isAdmin(player) then
		return
	end

	-- 转换为小写并去除首尾空格
	local lowerMessage = message:lower():gsub("^%s*", ""):gsub("%s*$", "")

	-- 检查是否是道具命令
	if lowerMessage:sub(1, 3) == "/道具" or lowerMessage:sub(1, 5) == "/prop" then
		local args = {}

		-- 解析参数
		for arg in message:gmatch("%S+") do
			table.insert(args, arg)
		end

		-- 移除命令本身
		table.remove(args, 1)

		if #args == 0 then
			showPropHelp(player)
		elseif args[1]:lower() == "help" or args[1] == "帮助" then
			showPropHelp(player)
		elseif args[1]:lower() == "list" or args[1] == "列表" then
			showPlayerProps(player)
		else
			handleAddPropCommand(player, args)
		end
	end
end

-- 设置事件监听
function PropDebugCommands.setupEvents()
	-- 监听玩家聊天
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(message)
			onPlayerChatted(player, message)
		end)
	end)

	-- 处理已存在的玩家
	for _, player in pairs(Players:GetPlayers()) do
		player.Chatted:Connect(function(message)
			onPlayerChatted(player, message)
		end)
	end

	print("PropDebugCommands 事件监听已设置")
end

-- 初始化
function PropDebugCommands.initialize()
	PropDebugCommands.setupEvents()
	print("PropDebugCommands 调试命令系统已启动")
	print("可用命令: /道具 <ID> <数量> | /道具 help | /道具 list")
end

-- 启动调试命令系统
PropDebugCommands.initialize()

return PropDebugCommands