--[[

MIT License

Copyright (c) 2019-2021 Love2D Community <love2d.org>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]]

local insert = table.insert
local format = string.format
local min = math.min

local Cursor = require(SLAB_PATH .. '.Internal.Core.Cursor')
local DrawCommands = require(SLAB_PATH .. '.Internal.Core.DrawCommands')
local LayoutManager = require(SLAB_PATH .. '.Internal.UI.LayoutManager')
local Mouse = require(SLAB_PATH .. '.Internal.Input.Mouse')
local Style = require(SLAB_PATH .. '.Style')
local Text = require(SLAB_PATH .. '.Internal.UI.Text')
local Window = require(SLAB_PATH .. '.Internal.UI.Window')
local Utility = require(SLAB_PATH .. '.Internal.Core.Utility')
local Scale = require(SLAB_PATH .. '.Internal.Core.Scale')

local Tooltip = {}
local LastDisplayTime = 0.0
local AccumDisplayTime = 0.0
local TooltipTime = 0.75
local TooltipExpireTime = 0.2
local Alpha = 0.0
local OffsetY = 0.0
local ResetSize = false
local LastTip, LastBounds

function Tooltip.Begin(Tip)
	if Tip == nil or Tip == "" or Style.TooltipsEnabled == false then
		return
	end
	Tip = tostring(Tip)

	local Elapsed = love.timer.getTime() - LastDisplayTime
	if Tip ~= LastTip or Elapsed > TooltipExpireTime then
		AccumDisplayTime = 0.0
		Alpha = 0.0
		ResetSize = true
	end
	LastTip = Tip

	local DeltaTime = love.timer.getDelta()
	AccumDisplayTime = AccumDisplayTime + DeltaTime
	LastDisplayTime = love.timer.getTime()

	if AccumDisplayTime > (Style.TooltipDelay or TooltipTime) then
		local X, Y = Mouse.Position()
		Alpha = min(Alpha + DeltaTime * 4.0, 1.0)
		local BgColor = {0.025, 0.04, 0.06, Alpha * 0.98}
		local TextColor = Utility.MakeColor(Style.TextColor)
		TextColor[4] = Alpha
		-- Measure before Begin: a zero-sized auto window draws a tiny rounded
		-- dot during its first frame and can inherit a zero content scissor.
		local ScreenW, ScreenH = Scale.GetScreenWidth(), Scale.GetScreenHeight()
		local WrapW = math.max(80, math.min(460, ScreenW - 56))
		local TextW, Lines = Style.Font:getWrap(Tip, WrapW)
		local Width = math.min(WrapW, math.max(24, TextW))
		local Height = #Lines * Style.Font:getHeight()
		local BoxW, BoxH = Width + 24, Height + 20
		X = math.max(8, math.min(X + 18, ScreenW - BoxW - 8))
		Y = Y + 25
		if Y + BoxH > ScreenH - 8 then Y = math.max(8, Y - BoxH - 42) end
		LastBounds = {x = X, y = Y, w = BoxW, h = BoxH, text = Tip}

		-- A tooltip is an overlay, not part of the caller's layout. Window.End
		-- restores the parent window's border anchor, which loses any active
		-- indentation; tooltip text also changes item/line state for SameLine.
		Cursor.PushContext()

		LayoutManager.Begin('Ignore', {Ignore = true})
		Window.Begin('tooltip',
		{
			X = X,
			Y = Y,
			W = BoxW - 10,
			H = BoxH - 10,
			Border = 10,
			BgColor = BgColor,
			AutoSizeWindow = false,
			AutoSizeContent = false,
			AllowResize = false,
			AllowFocus = false,
			Layer = 'Tooltip',
			ResetWindowSize = ResetSize,
			CanObstruct = false,
			NoSavedSettings = true
		})
		local TextX, TextY = Cursor.GetPosition()
		Cursor.SetPosition(TextX + 7, TextY + 5)
		Text.BeginFormatted(Tip, {Color = TextColor, W = Width})
		OffsetY = Window.GetHeight()
		Window.End()
		LayoutManager.End()
		Cursor.PopContext()
		ResetSize = false
	end
end

function Tooltip.GetBounds() return LastBounds end

function Tooltip.GetDebugInfo()
	local Info = {}

	local Elapsed = love.timer.getTime() - LastDisplayTime
	insert(Info, format("Time: %.2f", AccumDisplayTime))
	insert(Info, format("Is Visible: %s", tostring(AccumDisplayTime > TooltipTime and Elapsed <= TooltipExpireTime)))
	insert(Info, format("Time to Display: %.2f", TooltipTime))
	insert(Info, format("Expire Time: %f", TooltipExpireTime))

	return Info
end

return Tooltip
