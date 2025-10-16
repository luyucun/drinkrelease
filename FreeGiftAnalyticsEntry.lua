-- 脚本名称: FreeGiftAnalyticsEntry
-- 脚本作用: V2.1 免费在线奖励 - 埋点系统入口
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- 功能：初始化埋点系统

local ServerScriptService = game:GetService("ServerScriptService")

-- 加载埋点模块
local FreeGiftAnalytics = require(ServerScriptService:WaitForChild("FreeGiftAnalytics"))

-- 初始化
FreeGiftAnalytics.initialize()

-- 定期打印统计报告（可选，用于调试）
spawn(function()
	while true do
		wait(300)  -- 每5分钟打印一次
		FreeGiftAnalytics.printReport()
	end
end)
