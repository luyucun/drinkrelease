-- 脚本名称: TaskConfigDiagnostic
-- 脚本作用: 诊断TaskConfig加载问题
-- 脚本类型: Script
-- 放置位置: ServerScriptService (临时诊断用)

print("=====================================")
print("TaskConfig 诊断工具")
print("=====================================")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 等待ReplicatedStorage完全加载
task.wait(3)

print("\n1. 检查ReplicatedStorage...")
print("   ReplicatedStorage存在: " .. tostring(ReplicatedStorage ~= nil))

print("\n2. 列出ReplicatedStorage中的所有ModuleScript:")
for _, child in ipairs(ReplicatedStorage:GetChildren()) do
	if child:IsA("ModuleScript") then
		print("   ✓ 找到: " .. child.Name .. " (类型: ModuleScript)")
	end
end

print("\n3. 尝试查找TaskConfig...")
local taskConfig = ReplicatedStorage:FindFirstChild("TaskConfig")
if taskConfig then
	print("   ✓ TaskConfig存在!")
	print("   · 类型: " .. taskConfig.ClassName)
	print("   · 完整路径: " .. taskConfig:GetFullName())
else
	print("   ❌ TaskConfig不存在!")
	print("   ⚠️ 请确认已在ReplicatedStorage中创建了TaskConfig (ModuleScript)")
end

print("\n4. 尝试使用WaitForChild加载TaskConfig...")
local success, result = pcall(function()
	return ReplicatedStorage:WaitForChild("TaskConfig", 5)
end)

if success and result then
	print("   ✓ WaitForChild成功!")
	print("   · 对象: " .. result:GetFullName())

	-- 尝试require
	print("\n5. 尝试require TaskConfig...")
	local requireSuccess, config = pcall(function()
		return require(result)
	end)

	if requireSuccess then
		print("   ✓ require成功!")
		print("   · 任务数量: " .. (config.getTaskCount and config.getTaskCount() or "未知"))
	else
		print("   ❌ require失败: " .. tostring(config))
	end
else
	print("   ❌ WaitForChild失败: " .. tostring(result))
	print("   ⚠️ 超时5秒未找到TaskConfig")
end

print("\n=====================================")
print("诊断完成")
print("=====================================")

print("\n📋 解决方案:")
print("1. 在Roblox Studio中，找到 ReplicatedStorage")
print("2. 右键 ReplicatedStorage > Insert Object > ModuleScript")
print("3. 将新创建的ModuleScript重命名为 'TaskConfig'")
print("4. 双击打开TaskConfig，将TaskConfig.lua的内容粘贴进去")
print("5. 按Ctrl+S保存")
print("6. 重新运行游戏")
