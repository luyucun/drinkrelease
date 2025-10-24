-- 脚本名称: AdminResetCommandsEntry
-- 脚本作用: 启动管理员重置命令系统
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- 版本: V1.9

-- 加载管理员重置命令模块
local success, result = pcall(function()
	return require(script.Parent.AdminResetCommands)
end)

if success then
	print("[AdminResetCommandsEntry] ✓ AdminResetCommands 模块加载成功")
	print("[AdminResetCommandsEntry] 管理员重置系统已就绪")
else
	warn("[AdminResetCommandsEntry] ✗ AdminResetCommands 模块加载失败: " .. tostring(result))
	-- 打印完整错误堆栈
	print("[AdminResetCommandsEntry] 错误详情:")
	print(debug.traceback())
end

