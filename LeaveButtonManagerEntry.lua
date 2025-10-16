-- 脚本名称: LeaveButtonManagerEntry
-- 脚本作用: 服务端初始化LeaveButtonManager V1.3
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- 功能：确保LeaveButtonManager在服务端正确初始化

local LeaveButtonManager = require(script.Parent.LeaveButtonManager)

-- 延迟初始化，等待RemoteEvents系统准备就绪
task.spawn(function()
    -- 等待RemoteEvents系统初始化
    task.wait(2)

    -- 显式调用初始化
    if LeaveButtonManager.initialize then
        LeaveButtonManager.initialize()
    end
end)