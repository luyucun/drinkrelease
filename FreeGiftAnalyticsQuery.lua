-- 脚本名称: FreeGiftAnalyticsQuery
-- 脚本作用: 埋点数据查询工具（在Studio Command Bar中使用）
-- 脚本类型: 工具脚本（不需要放入游戏）
-- 使用方法：在Studio的Command Bar中复制粘贴运行

--[[
使用示例：

1. 查看实时统计报告：
   _G.FreeGiftAnalytics.printReport()

2. 获取全局统计数据：
   local stats = _G.FreeGiftAnalytics.getGlobalStats()
   print("总领取次数:", stats.totalClaims)
   print("唯一玩家数:", stats.uniquePlayers)

3. 查询特定玩家是否领取过：
   local userId = 123456789  -- 替换为实际UserId
   local claimed, data = _G.FreeGiftAnalytics.hasPlayerClaimed(userId)
   if claimed then
       print("玩家已领取，时间:", os.date("%Y-%m-%d %H:%M:%S", data.timestamp))
   else
       print("玩家未领取")
   end

4. 查看最近领取记录（详细）：
   local stats = _G.FreeGiftAnalytics.getGlobalStats()
   for i, record in ipairs(stats.claimHistory) do
       print(string.format(
           "[%d] %s (ID:%d) - %d秒 - %s",
           i,
           record.playerName,
           record.userId,
           record.accumulatedSeconds,
           os.date("%Y-%m-%d %H:%M:%S", record.timestamp)
       ))
   end

5. 导出数据为JSON（复制到文件）：
   local HttpService = game:GetService("HttpService")
   local stats = _G.FreeGiftAnalytics.getGlobalStats()
   local json = HttpService:JSONEncode({
       totalClaims = stats.totalClaims,
       uniquePlayers = stats.uniquePlayers,
       exportTime = os.time(),
       claimHistory = stats.claimHistory
   })
   print(json)

--]]

-- 📊 快速查看统计
if _G.FreeGiftAnalytics then
	print("✅ FreeGiftAnalytics 已加载")
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("可用命令：")
	print("  _G.FreeGiftAnalytics.printReport()  -- 打印统计报告")
	print("  _G.FreeGiftAnalytics.getGlobalStats()  -- 获取统计数据")
	print("  _G.FreeGiftAnalytics.hasPlayerClaimed(userId)  -- 查询玩家")
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	-- 立即显示当前统计
	_G.FreeGiftAnalytics.printReport()
else
	warn("❌ FreeGiftAnalytics 未加载")
	warn("请确保 FreeGiftAnalyticsEntry 脚本已在 ServerScriptService 中运行")
end
