-- 脚本名称: TaskUIController
-- 脚本作用: 管理每日任务界面交互和实时更新
-- 脚本类型: LocalScript
-- 放置位置: StarterPlayer.StarterPlayerScripts
-- 版本: V1.8

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 等待TaskConfig加载
local TaskConfig = require(ReplicatedStorage:WaitForChild("TaskConfig", 10))
if not TaskConfig then
	warn("[TaskUIController] ❌ TaskConfig加载失败")
	return
end

-- 等待UI加载
local taskScreenGui = playerGui:WaitForChild("Task", 10)
if not taskScreenGui then
	warn("[TaskUIController] ❌ Task ScreenGui未找到")
	return
end

local taskBg = taskScreenGui:WaitForChild("TaskBg", 10)
if not taskBg then
	warn("[TaskUIController] ❌ TaskBg未找到")
	return
end

-- UI引用
local closeButton = taskBg:WaitForChild("CloseButton")
local scrollingFrame = taskBg:WaitForChild("ScrollingFrame")
local template = scrollingFrame:WaitForChild("Template")

-- Menu按钮引用
local menuFolder = playerGui:WaitForChild("Menu", 10)
if not menuFolder then
	warn("[TaskUIController] ❌ Menu未找到")
	return
end

local imageButtonDaily = menuFolder:WaitForChild("ImageButtonDaily")
local redPoint = imageButtonDaily:WaitForChild("RedPoint")

-- RemoteEvent
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
if not remoteEventsFolder then
	warn("[TaskUIController] ❌ RemoteEvents文件夹未找到")
	return
end

local taskEvent = remoteEventsFolder:WaitForChild("TaskEvent", 10)
if not taskEvent then
	warn("[TaskUIController] ❌ TaskEvent未找到，请确保服务端已启动TaskDataManager")
	return
end

print("[TaskUIController] ✓ TaskEvent已连接")

-- 任务UI实例缓存
local taskUIInstances = {}

-- 当前任务状态
local currentTaskStatus = nil

-- ============================================
-- 辅助函数
-- ============================================

-- 更新红点状态
local function updateRedPoint(hasUnclaimed)
	redPoint.Visible = hasUnclaimed
end

-- ============================================
-- 任务UI生成
-- ============================================

local function createTaskUI(taskConfig)
	-- 复制模板
	local taskUI = template:Clone()
	taskUI.Name = "Task_" .. taskConfig.id
	taskUI.Visible = true
	taskUI.Parent = scrollingFrame

	-- 设置任务描述
	local taskDes = taskUI:FindFirstChild("TaskDes")
	if taskDes then
		taskDes.Text = taskConfig.description
	end

	-- 设置奖励图标和数量
	local rewardBg = taskUI:FindFirstChild("RewardBg")
	if rewardBg then
		local rewardIcon = rewardBg:FindFirstChild("Rewardicon")
		if rewardIcon then
			rewardIcon.Image = taskConfig.rewardIcon
		end

		local rewardNum = rewardBg:FindFirstChild("RewardNum")
		if rewardNum then
			rewardNum.Text = "x" .. taskConfig.rewardAmount
		end
	end

	-- 设置领取按钮点击事件
	local claimButton = taskUI:FindFirstChild("ClaimButton")
	if claimButton then
		claimButton.MouseButton1Click:Connect(function()
			-- 发送领取请求到服务器
			taskEvent:FireServer("claimReward", {taskId = taskConfig.id})
			print("[TaskUIController] 请求领取任务 " .. taskConfig.id .. " 奖励")
		end)
	end

	-- 保存引用
	taskUIInstances[taskConfig.id] = {
		ui = taskUI,
		claimButton = claimButton,
		complete = taskUI:FindFirstChild("Complete"),
		taskDes = taskDes,
		progress = taskUI:FindFirstChild("Prograss")
	}

	return taskUI
end

-- 生成所有任务UI (只执行一次)
local function generateAllTasksUI()
	print("[TaskUIController] 生成任务UI...")

	-- 隐藏模板
	template.Visible = false

	-- 为每个任务生成UI
	for _, taskConfig in ipairs(TaskConfig.TASKS) do
		createTaskUI(taskConfig)
	end

	print("[TaskUIController] ✓ 已生成 " .. #TaskConfig.TASKS .. " 个任务UI")
end

-- ============================================
-- 任务状态更新
-- ============================================

local function updateTaskUI(taskId)
	if not currentTaskStatus then return end

	local instance = taskUIInstances[taskId]
	if not instance then return end

	local taskConfig = TaskConfig.getTaskById(taskId)
	if not taskConfig then return end

	local matchesCompleted = currentTaskStatus.dailyMatchesCompleted
	local taskKey = "task_" .. taskId
	local isClaimed = currentTaskStatus.claimedRewards[taskKey] or false

	-- 更新进度文本
	if instance.progress then
		instance.progress.Text = matchesCompleted .. "/" .. taskConfig.requiredMatches
	end

	-- 更新按钮状态
	if isClaimed then
		-- 已领取: 隐藏按钮，显示Complete
		if instance.claimButton then
			instance.claimButton.Visible = false
		end
		if instance.complete then
			instance.complete.Visible = true
		end
	else
		-- 未领取: 显示按钮，隐藏Complete
		if instance.complete then
			instance.complete.Visible = false
		end
		if instance.claimButton then
			instance.claimButton.Visible = true

			-- 根据进度设置按钮状态
			if matchesCompleted >= taskConfig.requiredMatches then
				-- 可领取: 按钮可点击
				instance.claimButton.BackgroundColor3 = Color3.fromRGB(76, 175, 80)  -- 绿色
				instance.claimButton.AutoButtonColor = true
			else
				-- 未完成: 按钮置灰
				instance.claimButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)  -- 灰色
				instance.claimButton.AutoButtonColor = false
			end
		end
	end
end

-- 更新所有任务UI
local function updateAllTasksUI()
	if not currentTaskStatus then return end

	for taskId, _ in pairs(taskUIInstances) do
		updateTaskUI(taskId)
	end

	-- 更新红点
	updateRedPoint(currentTaskStatus.hasUnclaimedRewards)
end

-- ============================================
-- RemoteEvent处理
-- ============================================

taskEvent.OnClientEvent:Connect(function(action, data)
	if action == "statusResponse" then
		-- 服务器响应状态请求
		currentTaskStatus = data
		updateAllTasksUI()
		print("[TaskUIController] ✓ 收到任务状态更新")

	elseif action == "statusRefresh" then
		-- 服务器主动刷新(UTC0重置)
		currentTaskStatus = data
		updateAllTasksUI()
		print("[TaskUIController] ✓ 任务已重置")

	elseif action == "progressUpdate" then
		-- 进度更新(对局完成)
		currentTaskStatus = data
		updateAllTasksUI()
		print("[TaskUIController] ✓ 任务进度已更新")

	elseif action == "rewardSuccess" then
		-- 奖励领取成功
		print("[TaskUIController] ✓ 奖励领取成功: 任务 " .. data.taskId)
		-- 请求刷新状态
		taskEvent:FireServer("requestStatus")

	elseif action == "rewardFailed" then
		-- 奖励领取失败
		warn("[TaskUIController] ❌ 奖励领取失败: " .. data.reason)
	end
end)

-- ============================================
-- 界面交互
-- ============================================

-- 打开界面按钮
imageButtonDaily.MouseButton1Click:Connect(function()
	taskScreenGui.Enabled = true
	-- 请求最新状态
	taskEvent:FireServer("requestStatus")
	print("[TaskUIController] 打开每日任务界面")
end)

-- 关闭界面按钮
closeButton.MouseButton1Click:Connect(function()
	taskScreenGui.Enabled = false
	print("[TaskUIController] 关闭每日任务界面")
end)

-- ============================================
-- 初始化
-- ============================================

local function initialize()
	print("[TaskUIController] 🚀 开始初始化...")

	-- 生成任务UI (只执行一次)
	generateAllTasksUI()

	-- 默认隐藏界面
	taskScreenGui.Enabled = false

	-- 默认隐藏红点
	redPoint.Visible = false

	-- 等待2秒后请求初始状态
	task.wait(2)
	taskEvent:FireServer("requestStatus")

	print("[TaskUIController] ✅ 初始化完成")
end

-- 启动初始化
initialize()
