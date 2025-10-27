-- 脚本名称: SkinGuideClient
-- 脚本作用: V1.9新手皮肤引导客户端控制器，处理Daily界面显示
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 等待RemoteEvents文件夹（不阻塞，超时后跳过）
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
if not remoteEventsFolder then
	warn("[SkinGuideClient] RemoteEvents文件夹未找到，皮肤引导客户端功能禁用")
	return
end

-- 等待SkinGuideEvent（不阻塞，超时后跳过）
local skinGuideEvent = remoteEventsFolder:WaitForChild("SkinGuideEvent", 10)
if not skinGuideEvent then
	warn("[SkinGuideClient] SkinGuideEvent未找到，皮肤引导客户端功能禁用")
	return
end

-- ============================================
-- 处理服务端消息
-- ============================================

skinGuideEvent.OnClientEvent:Connect(function(action, data)
	if action == "showDailyUI" then
		-- 显示Daily界面
		local taskGui = playerGui:FindFirstChild("Task")
		if taskGui then
			taskGui.Enabled = true
		else
			warn("[SkinGuideClient] 找不到Task界面")
		end
	end
end)
