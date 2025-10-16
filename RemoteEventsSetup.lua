-- 脚本名称: RemoteEventsSetup
-- 脚本作用: 创建游戏所需的RemoteEvents用于客户端服务器通信
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local RemoteEventsSetup = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 创建RemoteEvents文件夹
function RemoteEventsSetup.createRemoteEventsFolder()
	local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEventsFolder then
		remoteEventsFolder = Instance.new("Folder")
		remoteEventsFolder.Name = "RemoteEvents"
		remoteEventsFolder.Parent = ReplicatedStorage
	end
	return remoteEventsFolder
end

-- 创建所需的RemoteEvents
function RemoteEventsSetup.createRemoteEvents()
	local folder = RemoteEventsSetup.createRemoteEventsFolder()

	local events = {
		"CameraControl",      -- 镜头控制
		"GameStateUpdate",    -- 游戏状态更新
		"PoisonSelection",    -- 毒药选择
		"DrinkSelection",     -- 奶茶选择
		"GameResult",         -- 游戏结果
		"SeatLock",           -- 座位锁定控制
		"PoisonIndicator",    -- 毒药标识显示
		"CoinUpdate",         -- 金币系统更新
		"ShopEvent",          -- V1.8: 商店系统事件
		"WheelSpin",          -- V2.0: 转盘旋转请求
		"WheelDataSync",      -- V2.0: 转盘数据同步
		"WheelPurchase",      -- V2.0: 转盘次数购买
		"WheelInteraction",   -- V2.0: 转盘交互控制
		"EmoteDataSync",      -- V1.1: 庆祝动作数据同步
		"EmoteEquip",         -- V1.1: 庆祝动作装备
		"ShowNotification",   -- V1.1: 通用通知系统
		"FreeGift",           -- V2.1: 免费在线奖励系统
		"BgmControl",         -- V1.2: BGM静音控制系统
		"VictoryAnimationControl", -- V1.2.1: 胜利动画客户端移动控制
		"LeaveButtonControl", -- V1.3: Leave按钮控制
		"SeatControl"         -- V1.3: 座位控制
	}

	for _, eventName in ipairs(events) do
		if not folder:FindFirstChild(eventName) then
			local remoteEvent = Instance.new("RemoteEvent")
			remoteEvent.Name = eventName
			remoteEvent.Parent = folder
		end
	end

	return folder
end

-- 初始化
RemoteEventsSetup.createRemoteEvents()

return RemoteEventsSetup