-- 脚本名称: FreeGiftManagerEntry
-- 脚本作用: V2.1 免费在线奖励系统 - 主入口脚本
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- 功能：
--   1. 初始化FreeGiftManager模块
--   2. 监听RemoteEvent事件
--   3. 处理客户端请求

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 加载FreeGiftManager模块
local FreeGiftManager = require(ServerScriptService:WaitForChild("FreeGiftManager"))

-- 初始化管理器
FreeGiftManager.initialize()

-- 等待RemoteEvent
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents")
local freeGiftEvent = remoteEventsFolder:WaitForChild("FreeGift")

-- 监听客户端事件
freeGiftEvent.OnServerEvent:Connect(function(player, action, data)
	if not player then
		warn("FreeGiftManagerEntry: player为空")
		return
	end

	-- 请求进度更新
	if action == "requestProgress" then
		local progress = FreeGiftManager.getProgress(player)
		freeGiftEvent:FireClient(player, "progressUpdate", progress)

		-- 领取奖励
	elseif action == "claim" then
		local result = FreeGiftManager.claimReward(player)
		freeGiftEvent:FireClient(player, "claimResult", result)

		-- 如果领取成功，通知客户端更新Chest状态
		if result.success then
			freeGiftEvent:FireClient(player, "claimed")
		end

		-- 未知操作
	else
		warn("FreeGiftManagerEntry: 未知操作 - " .. tostring(action))
	end
end)
