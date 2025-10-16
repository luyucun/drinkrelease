-- 脚本名称: CountdownManagerEntry
-- 脚本作用: 确保CountdownManager在服务器启动时被加载
-- 脚本类型: Script
-- 放置位置: ServerScriptService

-- 加载CountdownManager
local CountdownManager = require(script.Parent.CountdownManager)

print("CountdownManagerEntry: CountdownManager已通过入口脚本加载")