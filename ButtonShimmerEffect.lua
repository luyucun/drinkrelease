-- 脚本名称: ButtonShimmerEffect
-- 脚本作用: 为按钮添加循环扫光效果
-- 脚本类型: LocalScript
-- 放置位置: StarterGui - Menu - ImageButtonInvite

local TweenService = game:GetService("TweenService")

-- ============================================
-- ⚙️ 可调配置参数 - 自己修改这些值
-- ============================================

local SHINE_DURATION = 1.2      -- 单次扫光持续时间（秒）[推荐: 0.8-2.0]
local SHINE_INTERVAL = 3        -- 两次扫光之间的间隔（秒）[推荐: 2-5]
local SHINE_ROTATION = 45       -- 渐变旋转角度（度）[推荐: 0/45/90/135]

-- 扫光颜色配置
local SHINE_COLOR = Color3.fromRGB(255, 255, 255)  -- 扫光基础色（白色）
local SHINE_ALPHA = 0.4  -- 扫光透明度（0-1，越高越明亮）[推荐: 0.3-0.6]

-- 扫光的"光宽"宽度（0-1，越小越窄）
-- 0.2 = 很窄的光   0.4 = 中等   0.6 = 很宽的光
local SHINE_WIDTH = 0.3

-- ============================================
-- 获取按钮引用
-- ============================================

local button = script.Parent

-- ============================================
-- 创建扫光层（覆盖在按钮上）
-- ============================================

local shineLayer = Instance.new("Frame")
shineLayer.Name = "ShineLayer"
shineLayer.Size = UDim2.new(1, 0, 1, 0)  -- 全覆盖
shineLayer.Position = UDim2.new(0, 0, 0, 0)
shineLayer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)  -- 白色背景
shineLayer.BackgroundTransparency = 0.6  -- 部分透明（UIGradient会进一步控制）
shineLayer.BorderSizePixel = 0
shineLayer.ZIndex = button.ZIndex + 1  -- 确保在按钮上方
shineLayer.Parent = button

-- ============================================
-- 创建UIGradient（用颜色渐变表现扫光）
-- ============================================

local gradient = Instance.new("UIGradient")

-- 使用颜色渐变实现扫光：中间是亮的，两边淡去
local midPoint = 0.5
local halfWidth = SHINE_WIDTH / 2

gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, SHINE_COLOR),
    ColorSequenceKeypoint.new(math.max(0, midPoint - halfWidth), SHINE_COLOR),
    ColorSequenceKeypoint.new(midPoint, SHINE_COLOR),
    ColorSequenceKeypoint.new(math.min(1, midPoint + halfWidth), SHINE_COLOR),
    ColorSequenceKeypoint.new(1, SHINE_COLOR)
})

-- 透明度：两边透明，中间显示
gradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),  -- 左边完全透明
    NumberSequenceKeypoint.new(math.max(0, midPoint - halfWidth), 0.7),  -- 渐变开始
    NumberSequenceKeypoint.new(midPoint, 0.2),  -- 中间最亮（0.2 = 80%可见）
    NumberSequenceKeypoint.new(math.min(1, midPoint + halfWidth), 0.7),  -- 渐变结束
    NumberSequenceKeypoint.new(1, 1)  -- 右边完全透明
})

gradient.Rotation = SHINE_ROTATION
gradient.Offset = Vector2.new(-1, 0)
gradient.Parent = shineLayer

print("[ButtonShimmerEffect] ✓ 扫光效果已初始化")
print("  · 位置: " .. button.Name)
print("  · 颜色: RGB(" .. math.floor(SHINE_COLOR.R*255) .. ", " .. math.floor(SHINE_COLOR.G*255) .. ", " .. math.floor(SHINE_COLOR.B*255) .. ")")
print("  · 透明度: " .. SHINE_ALPHA)
print("  · 光宽: " .. SHINE_WIDTH)
print("  · 速度: " .. SHINE_DURATION .. "s")

-- ============================================
-- 创建Tween信息
-- ============================================

local tweenInfo = TweenInfo.new(
    SHINE_DURATION,
    Enum.EasingStyle.Linear
)

-- ============================================
-- 扫光函数
-- ============================================

local function playShine()
    local tween = TweenService:Create(
        gradient,
        tweenInfo,
        { Offset = Vector2.new(1, 0) }
    )

    tween:Play()

    tween.Completed:Connect(function()
        gradient.Offset = Vector2.new(-1, 0)
    end)
end

-- ============================================
-- 循环扫光
-- ============================================

print("[ButtonShimmerEffect] ▶ 开始循环扫光...")

while true do
    playShine()
    task.wait(SHINE_INTERVAL)
end
