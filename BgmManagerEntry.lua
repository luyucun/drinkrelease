-- 脚本名称: BgmManagerEntry
-- 脚本作用: V1.2 BGM管理器入口
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- 功能：初始化BGM管理器并监听RemoteEvent

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 加载BGM管理器
local BgmManager = require(ServerScriptService:WaitForChild("BgmManager"))

-- 初始化BGM管理器
BgmManager.initialize()

-- 等待RemoteEvent
task.spawn(function()
	task.wait(3)  -- 等待RemoteEvents系统初始化

	local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEventsFolder then
		warn("❌ BgmManagerEntry: RemoteEvents文件夹不存在")
		return
	end

	local bgmControlEvent = remoteEventsFolder:WaitForChild("BgmControl", 5)
	if not bgmControlEvent then
		warn("❌ BgmManagerEntry: BgmControl RemoteEvent不存在")
		return
	end

	-- 监听客户端的BGM控制请求
	bgmControlEvent.OnServerEvent:Connect(function(player, action, ...)
		if not player or not player.Parent then
			return
		end

		if action == "setMuted" then
			local isMuted = ...
			if type(isMuted) == "boolean" then
				BgmManager.setMuted(player, isMuted)
			else
				warn("BgmManagerEntry: 无效的静音状态参数")
			end

		elseif action == "getMuted" then
			-- 返回玩家当前静音状态
			local isMuted = BgmManager.isMuted(player)
			bgmControlEvent:FireClient(player, "muteStateResponse", isMuted)

		elseif action == "getBgmStatus" then
			-- 返回BGM播放状态（用于调试）
			local status = BgmManager.getBgmStatus()
			bgmControlEvent:FireClient(player, "bgmStatusResponse", status)

		else
			warn("BgmManagerEntry: 未知的BGM控制操作 - " .. tostring(action))
		end
	end)
end)