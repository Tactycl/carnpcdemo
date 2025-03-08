-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HapticService = game:GetService("HapticService")
local CollectionService = game:GetService("CollectionService")

-- Variables

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

local Vehicles = workspace:WaitForChild("Vehicles")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local GameSettings = require(ReplicatedStorage.Modules.GameSettings)
local CarClient = require(Modules:WaitForChild("CarClient"))
local renderSetUps = {}

local currentCarPhysics = nil
local lastBaseAngularX, lastBaseAngularY = 0, 0
local camGoalX, camGoalY = 0, 0
local camX, camY = 0, 0

local CAM_FREE_SPACE = 0.2
local MOUSE_SENSITIVITY = .025
local camera = workspace.CurrentCamera
local cameraParams = RaycastParams.new()
cameraParams.CollisionGroup = "Default"
cameraParams.FilterDescendantsInstances = {Vehicles, workspace:WaitForChild("NPCContainer")}
cameraParams.FilterType = Enum.RaycastFilterType.Exclude
cameraParams.IgnoreWater = true
cameraParams.RespectCanCollide = true

-- Runtime

-- custom lerp function for numbers, because roblox doesn't have a built in function for that.
function lerp(a, b, t)
	return a + (b - a) * t
end

--[[
Finds the player's vehicle by humanoid.
It removes a vehicle once it has none of the basic components a car should have, so the client doesn't further check them.
At first it checks if the player has a character and humanoid, I did this to avoid erroring.
]]
function FindVehicle(player)
	if player == nil or player.Character == nil or player.Character:FindFirstChild("Humanoid") == nil then
		return
	end

	local tagged = CollectionService:GetTagged("Vehicle")
	for _, vehicle in tagged do
		if not vehicle:FindFirstChild("Base") or not vehicle.Base:FindFirstChild("Seat") then vehicle:Destroy() continue end
		local seat = vehicle.Base.Seat
		if seat.Occupant ~= player.Character.Humanoid then continue end

		return vehicle
	end
end

--[[
I made it a custom function because it is called twice.
Since this sets up a new car, I first check for an existing car which the player owns.
I did this to avoid overwriting the variable and the first car's physics running forever.
Then I check if you are seated and it is a car's seat.
If so I make new physics so the car works and set the camera to scriptable because I have my own.
Otherwise your settings get reset to default, for example if you leave a car. I don't have a "getting out"
system yet, but I wanted to implement it in the future, so I did that here.
]]
function onSeated(isSeated, seat)
	local isCarSeat = seat and seat.Parent.Name == "Base" and seat:IsDescendantOf(Vehicles)

	if currentCarPhysics then
		currentCarPhysics:remove()
		currentCarPhysics = nil
	end
	
	if isSeated and isCarSeat then
		currentCarPhysics = CarClient.init(seat.Parent.Parent)
		camera.CameraType = Enum.CameraType.Scriptable

	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true

		camera.CameraType = Enum.CameraType.Custom
	end
end

--[[
This just handles the sit event and setting some variables for other functions to use.
]]
function CharacterAdded(char)
	Character = char
	Humanoid = char:WaitForChild("Humanoid") :: Humanoid

	if Humanoid.SeatPart ~= nil then
		onSeated(true, Humanoid.SeatPart)
	end
	
	Humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeated(true, Humanoid.SeatPart)
	end)
end

--[[
This gets the computer steering (-1 to 1), which I use twice and didn't want to have written out four times.
I did this so I don't have to write it four times or have two boolean variables and check with them when you begin or end input.
]]
function getComputerSteer()
	return (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
end

--[[
This function adjusts angles from in a range from -180° to 180°, so the camera doesn't do a full 360° rotation back when you move your camera.
]]
function adjustAngleWraparound(angle)
	if angle > math.pi then
		return angle - (2 * math.pi)
		
	elseif angle < -math.pi then
		return angle + (2 * math.pi)
	end
	return angle
end

--[[
This function updates the camera every frame with the deltaTime.
It wraps the goal Y rotation (horizontal rotation), so it doesn't do a 360° (the camera).
The camX and camY are lerped to make a smoother camera experience.
The "Free" attribute is used, because I want to be able to edit all cameras inside the Cameras attachment more easily.
I also want it to be easier, for example, if someone else needed a new camera. They can edit it easily, just make a new attachment
name it the index and move it to the position you want it to be relative to the car.
At the bottom it does some raycasting to prevent clipping inside walls or similar.
]]
function updateCamera(delta)
	local alpha = 3 * delta
	camGoalX = math.clamp(camGoalX, math.rad(-70), math.rad(20))

	if camGoalY > math.pi then
		camGoalY -= 2 * math.pi
		camY -= 2 * math.pi

	elseif camGoalY < -math.pi then
		camGoalY += 2 * math.pi
		camY += 2 * math.pi
	end

	camX = lerp(camX, camGoalX, alpha)
	camY = lerp(camY, camGoalY, alpha)

	local cam = currentCarPhysics.Vehicle.Base.Base.Cameras:FindFirstChild(currentCarPhysics.currentCamera)
	if not cam then
		return
	end

	if not cam:GetAttribute("Free") then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true

		camera.CFrame = cam.WorldCFrame
		return
	end

	local BaseAngularX, BaseAngularY = currentCarPhysics.Vehicle.Base.Base.CFrame:ToOrientation()
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		UserInputService.MouseIconEnabled = false

		local mouseDelta = UserInputService:GetMouseDelta()
		local xdiff, ydiff = (BaseAngularX - lastBaseAngularX), (BaseAngularY - lastBaseAngularY)

		camGoalX += adjustAngleWraparound(xdiff) - (mouseDelta.Y * MOUSE_SENSITIVITY * (GameSettings["Sensitivity"] / 100))
		camGoalY += adjustAngleWraparound(ydiff) - (mouseDelta.X * MOUSE_SENSITIVITY * (GameSettings["Sensitivity"] / 100))

	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true

		camGoalX, camGoalY = currentCarPhysics.Vehicle.Base.Base.CFrame:ToOrientation()
		local diffy = (camGoalY - camY)
		if diffy > math.pi then
			camGoalY -= 2 * math.pi

		elseif diffy < -math.pi then
			camGoalY += 2 * math.pi
		end
	end

	local newCameraCFrame = (CFrame.fromOrientation(camX, camY, 0) * cam.CFrame + currentCarPhysics.Vehicle.Base.Base.Position) - currentCarPhysics.Vehicle.Base.Base.AssemblyLinearVelocity / 25
	local origin = currentCarPhysics.Vehicle.Base.Base.Position
	local goalPosition = newCameraCFrame.Position + newCameraCFrame.Position.Unit * CAM_FREE_SPACE
	local raycast = workspace:Raycast(origin, (goalPosition - origin), cameraParams)

	if raycast and not raycast.Instance:IsDescendantOf(Character) then
		newCameraCFrame += -newCameraCFrame.Position + raycast.Position + raycast.Normal * CAM_FREE_SPACE
	end

	camera.CFrame = newCameraCFrame
	lastBaseAngularX, lastBaseAngularY = BaseAngularX, BaseAngularY
end

--[[
This gets the name of the gear you're currently in to be displayed on the GUI.
I did this so I don't have to do this in a different function. I split it into two
for better readability.
]]
function getGearDefinition()
	if currentCarPhysics.parked then
		return "P"
		
	elseif currentCarPhysics.currentGear == -1 then
		return "R"
		
	elseif currentCarPhysics.currentGear == 0 then
		return "N"
		
	elseif currentCarPhysics.config.AUTOMATIC then
		return "A" .. currentCarPhysics.currentGear
	end
	
	return "M" .. currentCarPhysics.currentGear
end

--[[
This updates the UI every frame with a delta variable (deltaTime).
I did this so you can see your rpm? I don't really know what to explain here. I just show the km/h, rpm meter and that's all.
This is so users can better see when to shift in manual shifting mode.
]]
function updateUI(delta)
	local delta60 = delta * 60
	local goalRotation = lerp(currentCarPhysics.UI_START_ROTATION, currentCarPhysics.UI_END_ROTATION, currentCarPhysics.currentRPM / (currentCarPhysics.UI_RPM_ITEMS * 1000))

	currentCarPhysics.UI.Main.Circle.Gear.Text = getGearDefinition()
	currentCarPhysics.UI.Main.Display.Rotation = lerp(currentCarPhysics.UI.Main.Display.Rotation, goalRotation, .9 * delta60)

	local speed = math.round(currentCarPhysics.currentSpeed)
	local splitSpeed = string.split(tostring(speed), "")

	currentCarPhysics.UI.Main.Speed1.TextTransparency = speed >= 100 and 0 or .5
	currentCarPhysics.UI.Main.Speed2.TextTransparency = speed >= 10 and 0 or .5
	currentCarPhysics.UI.Main.Speed3.TextTransparency = speed > 0 and 0 or .5
	currentCarPhysics.UI.Main.Speed1.Text = splitSpeed[#splitSpeed - 2] or "0"
	currentCarPhysics.UI.Main.Speed2.Text = splitSpeed[#splitSpeed - 1] or "0"
	currentCarPhysics.UI.Main.Speed3.Text = splitSpeed[#splitSpeed] or "0"
end

--[[
I did this so the code which uses it is more readable.
It puts a table with the index of the car into "renderSetUps".
A table with indexes because there can be multiple cars.
I did the print for debugging.
]]
function initRender(car)

	renderSetUps[car] = {
		RunService.Heartbeat:Connect(function(delta)
			local success, errorMessage = pcall(function()
				for _, wheel in car.Base.Wheels:GetChildren() do
					if not wheel:IsA("BasePart") then
						continue
					end

					local correspondingAttachment = car.Base.Base:FindFirstChild(wheel.Name)
					local FixedAttachment = car.Base.Base:FindFirstChild("FixedAttachment" .. wheel.Name)
					if not correspondingAttachment or not FixedAttachment then continue end

					local aX, aY, aZ = correspondingAttachment.WorldCFrame:ToOrientation()
					FixedAttachment.WorldCFrame = CFrame.new(wheel.Attachment.WorldPosition) * CFrame.fromOrientation(aX, aY, aZ)
				end
			end)
			if not success then
				print("Disconnecting car rendering from", car.Name)
				removeRender(car)
			end
		end),

		CarClient.initVisuals(car),
	}
end

--[[
Removes a render with a function, I did this so I can more easily remove one.
]]
function removeRender(car)
	if not renderSetUps[car] then
		return
	end
	
	renderSetUps[car][1]:Disconnect()
	renderSetUps[car][2]:removeVisuals()
	renderSetUps[car] = nil
end

--[[
This inits all existing vehicles, I did this because when you join there could already be vehicles, because it's multiplayer.
]]
for _, vehicle in CollectionService:GetTagged("Vehicle") do
	initRender(vehicle)
end

--[[
This is the same as InputEnded (see below), but does the inverse.
Features added here like Shift Down and Shift Up are used for manual shifting users.
The flip car button is used, so you don't need to rejoin if your car flips.
]]
local flipDebounce = false
UserInputService.InputBegan:Connect(function(inp, gpe)
	if gpe and inp.UserInputType ~= Enum.UserInputType.Gamepad1 then
		return
	end

	if currentCarPhysics then
		if inp.KeyCode == Enum.KeyCode.W or inp.KeyCode == Enum.KeyCode.ButtonR2 then
			currentCarPhysics.gas = 1

		elseif inp.KeyCode == Enum.KeyCode.S or inp.KeyCode == Enum.KeyCode.ButtonL2 then
			currentCarPhysics.brake = 1

		elseif inp.KeyCode == Enum.KeyCode.A then
			currentCarPhysics.steer = getComputerSteer()

		elseif inp.KeyCode == Enum.KeyCode.D then
			currentCarPhysics.steer = getComputerSteer()

		elseif inp.KeyCode == Enum.KeyCode.P and math.abs(currentCarPhysics.currentSpeed) < 5 then
			currentCarPhysics.parked = not currentCarPhysics.parked

		elseif inp.KeyCode == Enum.KeyCode.Thumbstick1 then
			currentCarPhysics.steer = inp.Position.X

		elseif not currentCarPhysics.config.AUTOMATIC and (inp.KeyCode == GameSettings["Shift Down"] or inp.KeyCode == Enum.KeyCode.ButtonX) and currentCarPhysics.currentGear ~= 0 then
			local curGear = currentCarPhysics.currentGear
			local nextGear = math.clamp(curGear - 1, -1, #currentCarPhysics.config.GEAR_RATIOS - 1)
			nextGear = nextGear == 0 and -1 or nextGear

			if currentCarPhysics.currentGear ~= nextGear then
				currentCarPhysics.currentGear = 0
				task.wait(currentCarPhysics.config.MANUAL_GEAR_CHANGE_TIME)

				currentCarPhysics.currentGear = nextGear
			end

		elseif not currentCarPhysics.config.AUTOMATIC and (inp.KeyCode == GameSettings["Shift Up"] or inp.KeyCode == Enum.KeyCode.ButtonY) and currentCarPhysics.currentGear ~= 0 then
			local curGear = currentCarPhysics.currentGear
			local nextGear = math.clamp(curGear + 1, -1, #currentCarPhysics.config.GEAR_RATIOS - 1)
			nextGear = nextGear == 0 and 1 or nextGear
			if currentCarPhysics.currentGear ~= nextGear then
				currentCarPhysics.currentGear = 0
				task.wait(currentCarPhysics.config.MANUAL_GEAR_CHANGE_TIME)

				currentCarPhysics.currentGear = nextGear

				local amountBackfire = math.random(1, 100) <= 50 and (math.random(1, 100) <= 50 and 2 or 1) or 0
				task.spawn(function()
					for i = 1, amountBackfire, 1 do
						currentCarPhysics:Backfire(currentCarPhysics.Vehicle)
						task.wait(.2)
					end
				end)
			end

		elseif inp.KeyCode == Enum.KeyCode.C or inp.KeyCode == Enum.KeyCode.ButtonR1 then
			currentCarPhysics.currentCamera = currentCarPhysics.currentCamera % #currentCarPhysics.Vehicle.Base.Base.Cameras:GetChildren() + 1

		elseif inp.KeyCode == GameSettings["Handbrake"] or inp.KeyCode == Enum.KeyCode.ButtonB then
			currentCarPhysics.handbrake = true

		elseif inp.KeyCode == GameSettings["Flip Car"] or inp.KeyCode == Enum.KeyCode.ButtonA then
			if currentCarPhysics.Vehicle.Base.Base.AssemblyLinearVelocity.Magnitude <= 5 and not flipDebounce then
				flipDebounce = true

				local bodyPosition = Instance.new("BodyPosition", currentCarPhysics.Vehicle.Base.Base)
				bodyPosition.Position = currentCarPhysics.Vehicle.Base.Base.Position + Vector3.yAxis * 10
				bodyPosition.MaxForce = Vector3.one * 99999
				bodyPosition.P = 99999
				bodyPosition.D = 2500

				local _, gyroY = currentCarPhysics.Vehicle.Base.Base.CFrame:ToOrientation()

				local bodyGyro = Instance.new("BodyGyro", currentCarPhysics.Vehicle.Base.Base)
				bodyGyro.CFrame = CFrame.fromOrientation(0, gyroY, 0)
				bodyGyro.MaxTorque = Vector3.one * 99999
				bodyGyro.P = 99999
				bodyGyro.D = 2500

				task.wait(1.5)

				bodyPosition:Destroy()
				bodyGyro:Destroy()

				task.wait(1.5)

				flipDebounce = false
			end
		end
	end
end)

--[[
This is being used, so your inputs don't stay forever.
Stuff gets turned off as you don't press the button anymore.
At the beginning I check for gamepad1 because roblox classifies it as a gameProcessedEvent
]]
UserInputService.InputEnded:Connect(function(inp, gpe)
	if gpe and inp.UserInputType ~= Enum.UserInputType.Gamepad1 then
		return
	end

	if currentCarPhysics then
		if inp.KeyCode == Enum.KeyCode.W or inp.KeyCode == Enum.KeyCode.ButtonR2 then
			currentCarPhysics.gas = 0

		elseif inp.KeyCode == Enum.KeyCode.S or inp.KeyCode == Enum.KeyCode.ButtonL2 then
			currentCarPhysics.brake = 0

		elseif inp.KeyCode == Enum.KeyCode.A then
			currentCarPhysics.steer = getComputerSteer()

		elseif inp.KeyCode == Enum.KeyCode.D then
			currentCarPhysics.steer = getComputerSteer()

		elseif inp.KeyCode == Enum.KeyCode.Thumbstick1 then
			currentCarPhysics.steer = 0

		elseif inp.KeyCode == GameSettings["Handbrake"] or inp.KeyCode == Enum.KeyCode.ButtonB then
			currentCarPhysics.handbrake = false
		end
	end
end)

--[[
This is used for inputs inbetween for example a thumbstick at 50% X axis would only be at 0 and 100 if we didn't use Changed and only used Began and Ended.
This is just used for controller precision.
]]
UserInputService.InputChanged:Connect(function(inp, gpe)
	if gpe and inp.UserInputType ~= Enum.UserInputType.Gamepad1 then
		return
	end

	if currentCarPhysics then
		if inp.KeyCode == Enum.KeyCode.ButtonR2 then
			currentCarPhysics.gas = inp.Position.Z

		elseif inp.KeyCode == Enum.KeyCode.ButtonL2 then
			currentCarPhysics.brake = inp.Position.Z

		elseif inp.KeyCode == Enum.KeyCode.Thumbstick1 then
			currentCarPhysics.steer = inp.Position.X
		end
	end
end)

--[[
Runs every frame.
Sets haptic motors for better controller/console experience.
Calls update functions.
]]
RunService.RenderStepped:Connect(function(delta)
	if not currentCarPhysics then
		return
	end
	
	if currentCarPhysics.Vehicle == nil then
		currentCarPhysics = nil
		return
	end

	HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, math.clamp(currentCarPhysics.avgSlip / 20, 0, 1))
	HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, math.clamp((currentCarPhysics.currentRPM - currentCarPhysics.previousRPM) / 400, 0, 1))
	updateCamera(delta)
	updateUI(delta)
end)

--[[
RBXScriptSignals
]]
Vehicles.ChildAdded:Connect(initRender)
Vehicles.ChildRemoved:Connect(removeRender)
LocalPlayer.CharacterAdded:Connect(CharacterAdded)

--[[
Two .OnClientEvents used for multiplayer purposes.
CarBackfire is an Unreliable one, car lights is a Reliable (normal) remote event.
]]
Remotes.CarLights.OnClientEvent:Connect(function(userid, lightName, lightActive)
	local player = Players:GetPlayerByUserId(userid)
	local vehicle = FindVehicle(player)
	if not vehicle then
		return
	end

	CarClient:SetLights(vehicle, lightName, lightActive, false)
end)

Remotes.CarBackfire.OnClientEvent:Connect(function(userid)
	local player = Players:GetPlayerByUserId(userid)
	local vehicle = FindVehicle(player)
	if not vehicle then
		return
	end

	CarClient:Backfire(vehicle, false)
end)

--[[
Used, because at the start we wait for CharacterAdded by :Wait(), so the function doesn't get called in "RBXScriptSignals" anymore.
We do this to do the first Character, when you join.

Hopefully I explained this better now, I also replaced a :GetChildren() with CollectionService like I always should've done.
The "Vehicle" tag is added in a server script. Hopefully I get accepted this time :p
]]
CharacterAdded(Character)
