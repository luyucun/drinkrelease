-- 脚本名称: PlayerNameHider
-- 脚本作用: 显示所有玩家头顶的名字
-- 脚本类型: Script
-- 放置位置: ServerScriptService

local PlayerNameHider = {}
local Players = game:GetService("Players")

-- 显示单个玩家的名字
function PlayerNameHider.hidePlayerName(player)
	if not player then return end

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		-- 显示名字
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.NameDisplayDistance = 100 -- 设置名字显示距离（studs）
	end
end

-- 处理玩家角色重新生成时显示名字
function PlayerNameHider.onCharacterAdded(player, character)
	-- 等待Humanoid加载
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		-- 显示名字
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.NameDisplayDistance = 100 -- 设置名字显示距离（studs）
	else
		warn("玩家 " .. player.Name .. " 的角色缺少Humanoid")
	end
end

-- 处理新玩家加入
function PlayerNameHider.onPlayerAdded(player)

	-- 如果玩家已有角色，立即处理
	if player.Character then
		PlayerNameHider.onCharacterAdded(player, player.Character)
	end

	-- 监听角色重新生成
	player.CharacterAdded:Connect(function(character)
		PlayerNameHider.onCharacterAdded(player, character)
	end)
end

-- 处理所有当前在线的玩家，显示名字
function PlayerNameHider.hideAllCurrentPlayers()
	local currentPlayers = Players:GetPlayers()

	for _, player in pairs(currentPlayers) do
		PlayerNameHider.onPlayerAdded(player)
	end
end

-- 初始化名字显示系统
function PlayerNameHider.initialize()

	-- 处理当前所有在线玩家
	PlayerNameHider.hideAllCurrentPlayers()

	-- 监听新玩家加入
	Players.PlayerAdded:Connect(PlayerNameHider.onPlayerAdded)

end

-- 启动名字显示系统
PlayerNameHider.initialize()

-- 导出到全局供其他脚本使用
_G.PlayerNameHider = PlayerNameHider

return PlayerNameHider