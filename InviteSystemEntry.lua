-- 脚本名称: InviteSystemEntry
-- 脚本作用: 邀请系统的入口和初始化
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 等待必要的系统初始化
task.wait(1)

-- 初始化InviteManager
local InviteManager = require(script.Parent:WaitForChild("InviteManager"))
InviteManager.initialize()

-- 初始化FriendsService
local FriendsService = require(script.Parent:WaitForChild("FriendsService"))
FriendsService.initialize()

print("[InviteSystemEntry] ✓ 邀请系统初始化完成")
