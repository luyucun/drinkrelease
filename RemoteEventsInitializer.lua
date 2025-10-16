-- 脚本名称: RemoteEventInitializer
-- 脚本作用: 初始化所有RemoteEvents，确保客户端连接时它们已存在
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 创建RemoteEvents文件夹
local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not remoteEventsFolder then
	remoteEventsFolder = Instance.new("Folder")
	remoteEventsFolder.Name = "RemoteEvents"
	remoteEventsFolder.Parent = ReplicatedStorage
end

-- 需要初始化的RemoteEvent列表
local remoteEventNames = {
	"MenuControl",        -- 菜单控制
	"CameraControl",      -- 镜头控制
	"SeatLock",          -- 座位锁定
	"DrinkSelection",    -- 饮料选择
	"PoisonSelection",   -- 毒药选择
	"CountdownUI",       -- 倒计时UI
	"DeathEffect",       -- 死亡效果
	"SkinDataSync",      -- 皮肤数据同步
	"SkinEquip",         -- 皮肤装备
	"SkinPurchase",      -- 皮肤购买
	"PropPurchase",      -- 道具购买
	"NewPlayerGift",     -- 新手礼包
	"FreeGift",          -- V2.1: 免费在线奖励
	"ShopEvent",         -- 商店事件
	"VictoryAudio",      -- V2.2: 胜利音效控制
	"CoinUpdate",        -- 金币更新
	"PropUpdate",        -- 道具更新
	"PropUse",           -- 道具使用
	"PoisonIndicator",   -- 毒药指示器
	"WinStreakPurchase", -- 连胜购买恢复
	"LeaveButtonControl", -- V1.3: Leave按钮控制
	"SeatControl"        -- V1.3: 座位控制
}

-- 创建所有RemoteEvents
for _, eventName in ipairs(remoteEventNames) do
	local remoteEvent = remoteEventsFolder:FindFirstChild(eventName)
	if not remoteEvent then
		remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = eventName
		remoteEvent.Parent = remoteEventsFolder
	end
end
