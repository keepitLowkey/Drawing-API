if getgenv().drawingAPILoaded then 
	return; 
end;
getgenv().drawingAPILoaded = true;

local drawingAPI;
local eventEnums = {
	MouseButton1Down = 'MouseButton1Down';
	MouseButton1Up = 'MouseButton1Up';
	MouseButton2Down = 'MouseButton2Down';
	MouseButton2Up = 'MouseButton2Up';
	MouseButton1Click = 'MouseButton1Click';
	MouseButton2Click = 'MouseButton2Click';
	MouseEnter = 'MouseEnter';
	MouseLeave = 'MouseLeave';
	MouseMoved = 'MouseMoved';
	InputBegan = 'InputBegan';
	InputChanged = 'InputChanged';
	InputEnded = 'InputEnded';
};

local Event = {
	Enums = {};
	Events = {};
};

for idx, obj in next, eventEnums do
	Event.Events[idx] = {};
end;

Event.new = function(Enum, Id)
	assert(eventEnums[Enum], 'Invalid eventEnum for Event.new (got ' .. tostring(Enum) .. ')');
	local eventHolder = Event.Events[Enum][Id];
	if eventHolder then
		return eventHolder;
	end;
	local bindableEvent = Instance.new'BindableEvent';
	Event.Events[Enum][Id] = bindableEvent;

	return {
		Connect = function(self, Callback, Timeout)
			local Connection = bindableEvent.Event:Connect(Callback);

			if Timeout then
				delay(Timeout, function()
					Connection:Disconnect();
				end);
			end;

			return Connection;
		end;
		Wait = function(self, Timeout)
			local Thread = coroutine.running();
			local Connection;

			Connection = bindableEvent.Event:Connect(function(...)
				coroutine.resume(Thread, ...);
				Connection:Disconnect();
			end);

			if Timeout then
				delay(Timeout, function()
					if Connection.Connected then
						Connection:Disconnect();
					end;
				end);
			end;

			return coroutine.yield();
		end;
	};
end;

Event.InvokeAll = function(self, Enum, ...)
	local foundEnums = self.Events[Enum];
	if foundEnums then
		for idx, Event in next, foundEnums do
			Event:Fire(...);
		end;
	end;
end;
Event.Invoke = function(self, Enum, objId, ...)
	self.Events[Enum][objId]:Fire(...);
end;

local Drawings = {};
local UIS = game:GetService'UserInputService';
local Mouse = game:GetService'Players'.LocalPlayer:GetMouse();

local currentlyInside = {};
local notInside = {};

local lastRemoved = {};
local lastDown = {};

local mouseX, mouseY = Mouse.X, Mouse.Y;
Mouse.Move:Connect(function()
	mouseX, mouseY = Mouse.X, Mouse.Y;

	for idx, obj in next, currentlyInside do
		local objPos = obj.Position;
		if (mouseX <= obj.leftEdge or mouseX >= obj.rightEdge) or (mouseY <= obj.topEdge or mouseY >= obj.bottomEdge) then
			warn'obj is no longer inside'
			table.remove(currentlyInside, idx);
			table.insert(notInside, obj);
			lastRemoved[obj.debugId] = tick();
			Event:Invoke('MouseLeave', obj.debugId, mouseX, mouseY);
		else
			--print'still inside'
			Event:Invoke('MouseMoved', obj.debugId, mouseX, mouseY);
		end;
	end;

	for idx, obj in next, notInside do
		local objPos = obj.Position;
		if (mouseX >= obj.leftEdge and mouseX <= obj.rightEdge) and (mouseY >= obj.topEdge and mouseY <= obj.bottomEdge) then
			warn'obj is inside'
			table.insert(currentlyInside, obj);
			table.remove(notInside, idx);
			Event:Invoke('MouseEnter', obj.debugId, mouseX, mouseY);
		end;
	end;
end);

UIS.InputBegan:Connect(function(Input, RS)
	if RS then return; end;
	local userInput = Input.UserInputType.Name;
	local isButton = userInput:find'MouseButton';

	if isButton then
		for idx, obj in next, currentlyInside do
			local debugId = obj.debugId;
			lastDown[debugId] = tick();
			Event:Invoke(userInput .. 'Down', debugId, mouseX, mouseY);
			Event:Invoke('InputBegan', debugId, Input);
		end;
	else
		for idx, obj in next, currentlyInside do
			Event:Invoke('InputBegan', obj.debugId, Input);
		end;
	end;
end);
UIS.InputChanged:Connect(function(Input, RS)
	if RS then return; end;
	for idx, obj in next, currentlyInside do
		Event:Invoke('InputEnded', obj.debugId, Input);
	end;
end);
UIS.InputEnded:Connect(function(Input, RS)
	if RS then return; end;
	local userInput = Input.UserInputType.Name;

	if userInput:find'MouseButton' then
		for idx, obj in next, currentlyInside do
			local debugId = obj.debugId;
			Event:Invoke(userInput .. 'Up', debugId, mouseX, mouseY);
			Event:Invoke('InputEnded', debugId, Input);
			if lastDown[debugId] > lastRemoved[debugId] then
				Event:Invoke(userInput .. 'Click', debugId, mouseX, mouseY);
			end;
		end;
	else
		for idx, obj in next, currentlyInside do
			Event:Invoke('InputEnded', obj.debugId, Input);
		end;
	end;
end);

local debugId = 0;
local runService = game:GetService'RunService';
local tweenService = game:GetService'TweenService';

local function drawPoint(Pos)--debug
	local point = drawingAPI'Square';
	point.Position=Pos;
	point.Visible=true;
	point.ZIndex=5;
	point.Color = Color3.new(1,1,1);
	point.Size = Vector2.new(3, 3);
	point.Filled = true;
end;

drawingAPI = hookfunction(Drawing.new, function(Class)
	local createdDrawing = drawingAPI(Class);
	if Class == 'Square' then
		debugId = debugId + 1;
		local drawingObj = createdDrawing;
		local localizedId = debugId;
		local stepConnection;
		lastRemoved[localizedId] = 0;
		lastDown[debugId] = 1;

		local Events = {
			TweenSize = function(self, endSize, easingDirection, easingStyle, time, override, callback)
				if stepConnection and stepConnection.Connected and not override then 
					return; 
				end;
				assert(typeof(endSize) == 'Vector2', 'Unexpected value for \'endSize\' in function TweenSize (Vector2 expected, got ' .. typeof(endSize) .. ')');
				local currentTime = 0;
				time = time or 1;
				easingStyle = easingStyle or Enum.EasingStyle.Quad;
				easingDirection = easingDirection or Enum.EasingDirection.Out;

				local startSize = drawingObj.Size;
				stepConnection = runService.RenderStepped:Connect(function(Delta)
					currentTime = currentTime + Delta;
					drawingObj.Size = startSize:Lerp(endSize, tweenService:GetValue(currentTime / time, easingStyle, easingDirection));
					if currentTime > time then
						coroutine.wrap(callback)();
						stepConnection:Disconnect();
						stepConnection = nil;
					end;
				end);
			end;
			TweenPosition = function(self, endPosition, easingDirection, easingStyle, time, override, callback)
				if stepConnection and stepConnection.Connected and not override then 
					return; 
				end;
				local currentTime = 0;
				time = time or 1;
				assert(typeof(endSize) == 'Vector2', 'Unexpected value for \'endSize\' in function TweenSize (Vector2 expected, got ' .. typeof(endSize) .. ')');
				easingStyle = easingStyle or Enum.EasingStyle.Quad;
				easingDirection = easingDirection or Enum.EasingDirection.Out;

				local startPos = drawingObj.Position;
				stepConnection = runService.RenderStepped:Connect(function(Delta)
					currentTime = currentTime + Delta;
					drawingObj.Position = startPos:Lerp(endPosition, tweenService:GetValue(currentTime / time, easingStyle, easingDirection));
					if currentTime > time then
						coroutine.wrap(callback)();
						stepConnection:Disconnect();
						stepConnection = nil;
					end;
				end);
			end;
			TweenSizeAndPosition = function(self, endSize, endPosition, easingDirection, easingStyle, time, override, callback)
				if stepConnection and stepConnection.Connected and not override then 
					return; 
				end;
				local currentTime = 0;
				time = time or 1;
				assert(typeof(endSize) == 'Vector2', 'Unexpected value for \'endSize\' in function TweenSize (Vector2 expected, got ' .. typeof(endSize) .. ')');
				easingStyle = easingStyle or Enum.EasingStyle.Quad;
				easingDirection = easingDirection or Enum.EasingDirection.Out;

				local startPos = drawingObj.Position;
				local startSize = drawingObj.Size;
				stepConnection = runService.RenderStepped:Connect(function(Delta)
					currentTime = currentTime + Delta;
					drawingObj.Position = startPos:Lerp(endPosition, tweenService:GetValue(currentTime / time, easingStyle, easingDirection));
					drawingObj.Size = startSize:Lerp(endSize, tweenService:GetValue(currentTime / time, easingStyle, easingDirection));
					if currentTime > time then
						coroutine.wrap(callback)();
						stepConnection:Disconnect();
						stepConnection = nil;
					end;
				end);
			end;
		};
		for idx, Enum in next, eventEnums do
			local newEvent = Event.new(Enum, debugId);
			Events[idx] = newEvent;
		end;

		local Pos, Size = drawingObj.Position, drawingObj.Size;
		local xSize, ySize = Size.X, Size.Y;
		local xPos, yPos = Pos.X, Pos.Y;

		Events.leftEdge = xPos;
		Events.rightEdge = xPos + xSize;
		Events.topEdge = yPos - (ySize / 2);
		Events.bottomEdge = yPos + (ySize / 2);

		createdDrawing = setmetatable(Events, {
			__newindex = function(self, key, value)
				if key == 'Visible' then
					if value then
						table.insert(notInside, createdDrawing);
					else
						local idx = table.find(notInside, createdDrawing);
						if idx then
							table.remove(notInside, idx);
						end;
					end;
				elseif key == 'Size' then
					local xSize, ySize = value.X, value.Y;
					local Pos = drawingObj.Position;
					local xPos, yPos = Pos.X, Pos.Y;

					Events.leftEdge = xPos;
					Events.rightEdge = xPos + xSize;
					Events.topEdge = yPos - (ySize / 2);
					Events.bottomEdge = yPos + (ySize / 2);
				elseif key == 'Position' then
					local Size = drawingObj.Size;
					local xSize, ySize = Size.X / 2, Size.Y / 2;
					local xPos, yPos = value.X, value.Y;

					Events.leftEdge = xPos;
					Events.rightEdge = xPos + xSize;
					Events.topEdge = yPos - (ySize / 2);
					Events.bottomEdge = yPos + (ySize / 2);
				end;
				Event:InvokeAll(key, value);
				drawingObj[key] = value;
			end;
			__index = function(self, key)
				if key == 'debugId' then
					return localizedId;
				end;
				return drawingObj[key];
			end;
		});
		table.insert(Drawings, createdDrawing);
	end;
	return createdDrawing;
end);
