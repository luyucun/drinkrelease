-- 脚本名称: EmoteSystemEntry
-- 脚本作用: V1.1 庆祝动作系统 - 服务器端入口脚本
-- 脚本类型: Script
-- 放置位置: ServerScriptService
-- 功能：
--   1. 加载并初始化EmoteDataManager模块
--   2. 加载并初始化EmoteInteractionManager模块
--   3. 设置全局引用供其他模块调用

local ServerScriptService = game:GetService("ServerScriptService")

print("🎭 EmoteSystemEntry: 开始初始化庆祝动作系统...")

-- 加载EmoteDataManager模块
local EmoteDataManager = require(ServerScriptService:WaitForChild("EmoteDataManager"))

-- 初始化EmoteDataManager
EmoteDataManager.initialize()

-- 延迟加载EmoteInteractionManager（确保Workspace完全加载）
task.spawn(function()
	task.wait(3)  -- 等待Workspace完全加载

	-- 加载EmoteInteractionManager模块
	local EmoteInteractionManager = require(ServerScriptService:WaitForChild("EmoteInteractionManager"))

	-- 初始化EmoteInteractionManager
	EmoteInteractionManager.initialize()

	print("🎭 EmoteSystemEntry: 庆祝动作系统初始化完成")
end)
