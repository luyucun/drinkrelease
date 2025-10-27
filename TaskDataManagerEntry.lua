-- 脚本名称: TaskDataManagerEntry
-- 脚本作用: 启动TaskDataManager模块
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- 版本: V1.8

print("[TaskDataManagerEntry] 🚀 加载TaskDataManager...")

-- 等待TaskConfig加载到ReplicatedStorage
task.wait(2)

-- 加载并启动TaskDataManager
local TaskDataManager = require(script.Parent:WaitForChild("TaskDataManager"))

-- 调用初始化
TaskDataManager.initialize()

print("[TaskDataManagerEntry] ✅ TaskDataManager已启动")
