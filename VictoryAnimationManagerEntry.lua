-- 脚本名称: VictoryAnimationManagerEntry
-- 脚本作用: V2.2 胜利动作系统 - 主入口脚本
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- 功能：
--   1. 加载并初始化VictoryAnimationManager模块
--   2. 设置全局引用供其他模块调用

local ServerScriptService = game:GetService("ServerScriptService")

-- 加载VictoryAnimationManager模块
local VictoryAnimationManager = require(ServerScriptService:WaitForChild("VictoryAnimationManager"))

-- 初始化管理器
VictoryAnimationManager.initialize()