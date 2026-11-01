-- =========================================================================
-- CLAY TAGS  —  every player running the client shows "Clay Client User" over their head.
-- Accounts you pick in Discord (/clay tag, /clay owner) get a custom name, and the OWNER
-- also gets a gold crown sitting on their head. Only Clay Client users with Clay Tags on see any of it.
-- Replace everything between the "CLAY TAGS" banner and the "PAGES" banner with this block.
-- =========================================================================
local Tags
do
	Tags = { On = false, Users = {}, Roles = {} }
	local HttpService = game:GetService("HttpService")
	local POLL = 5
	local SHOW_SELF = false   -- true = also draw your own tag/crown
	local gen = 0
	local made = {}   -- [Player] = { gui, role, clay, adornee, hasCrown, crown }
	local crownConn

	local GOLD = Color3.fromRGB(255, 205, 80)
	local RUBY = Color3.fromRGB(220, 40, 60)

	local function getRequestFn()
		local ok, fn = pcall(function()
			return (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
		end)
		if ok and type(fn) == "function" then return fn end
		return nil
	end

	local function guiParent()
		local ok, h = pcall(function() return gethui and gethui() end)
		if ok and h then return h end
		local ok2 = pcall(function() return game:GetService("CoreGui"):GetChildren() end)
		if ok2 then return game:GetService("CoreGui") end
		return player:WaitForChild("PlayerGui")
	end

	local function post(payload)
		local url, fn = CONFIG.TagRelayUrl, getRequestFn()
		if type(url) ~= "string" or url == "" or not fn then return nil end
		local base = url:gsub("/+$", "")
		local ok, res = pcall(fn, {
			Url = base .. "/beat",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode(payload),
		})
		if not ok or type(res) ~= "table" then return nil end
		if (res.StatusCode or res.Status) ~= 200 then return nil end
		local ok2, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if ok2 and type(data) == "table" then return data end
		return nil
	end

	local function beat(leave)
		return post({ key = CONFIG.TagRelayKey, user = player.Name, job = game.JobId, leave = leave })
	end

	local function hexColor(s)
		if type(s) ~= "string" then return nil end
		local r, g, b = s:match("^#?(%x%x)(%x%x)(%x%x)$")
		if not r then return nil end
		return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
	end

	local function applyData(data)
		local users, roles = {}, {}
		if type(data.users) == "table" then
			for _, n in ipairs(data.users) do users[string.lower(tostring(n))] = true end
		end
		if type(data.roles) == "table" then
			for n, r in pairs(data.roles) do
				if type(r) == "table" and type(r.text) == "string" and r.text ~= "" then
					roles[string.lower(tostring(n))] = {
						text = string.sub(r.text, 1, 24),
						color = hexColor(r.color) or THEME.Accent,
						crown = r.crown == true,
					}
				end
			end
		end
		Tags.Users, Tags.Roles = users, roles
	end

	-- ===== crown: a little gold band with spikes and ruby tips, riding on top of the head =====
	local function buildCrown()
		local model = Instance.new("Model")
		model.Name = "ClayCrown"
		local list = {}
		local function add(shape, size, pos, rot, color, material)
			local p = Instance.new("Part")
			p.Name = "CrownPart"
			if shape then p.Shape = shape end
			p.Anchored = true
			p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = false, false, false, false
			p.Material, p.Color = material, color
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			p.Size = size
			p.Parent = model
			table.insert(list, { part = p, size = size, pos = pos, rot = rot or CFrame.identity })
		end
		-- band (cylinder axis is X, so roll it upright)
		add(Enum.PartType.Cylinder, Vector3.new(0.3, 1.15, 1.15), Vector3.new(0, 0.15, 0),
			CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal)
		for i = 0, 4 do
			local a = math.rad(i * 72)
			local x, z = math.cos(a) * 0.5, math.sin(a) * 0.5
			add(nil, Vector3.new(0.16, 0.5, 0.16), Vector3.new(x, 0.55, z), CFrame.Angles(0, -a, 0), GOLD, Enum.Material.Metal)
			add(Enum.PartType.Ball, Vector3.new(0.19, 0.19, 0.19), Vector3.new(x, 0.88, z), nil, RUBY, Enum.Material.Neon)
		end
		model.Parent = workspace
		return { model = model, list = list }
	end

	local function destroyCrown(c)
		if c and c.model then pcall(function() c.model:Destroy() end) end
	end

	local function updateCrowns()
		for plr, t in pairs(made) do
			local c = t.crown
			if c then
				local head = t.adornee
				if head and head.Parent then
					local s = math.clamp(math.min(head.Size.X, head.Size.Z) / 1.2, 0.5, 4)
					local top = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0)
					for _, e in ipairs(c.list) do
						e.part.Size = e.size * s
						e.part.CFrame = top * CFrame.new(e.pos * s) * e.rot
					end
				end
			end
		end
	end

	local function removeTag(plr)
		local t = made[plr]
		if t then
			destroyCrown(t.crown)
			pcall(function() t.gui:Destroy() end)
		end
		made[plr] = nil
	end

	local function adorneeFor(plr)
		local char = plr.Character
		if not char then return nil end
		return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
	end

	local function buildTag(adornee, hasCrown)
		local lift = hasCrown and 1.0 or 0
		local gui = New("BillboardGui", {
			Name = "ClayTag", Adornee = adornee, AlwaysOnTop = true, LightInfluence = 0,
			ResetOnSpawn = false, MaxDistance = 300,
			-- VR: sized in studs so it scales with distance like a real sign; PC: fixed pixel size
			Size = VRService.VREnabled and UDim2.fromScale(6, 1.7) or UDim2.fromOffset(220, 52),
			StudsOffset = Vector3.new(0, math.max(adornee.Size.Y / 2, 0.5) + 1.4 + lift, 0),
		}, guiParent())
		local list = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}, list)
		local role = New("TextLabel", {
			LayoutOrder = 1, Size = UDim2.fromScale(1, 0.5), BackgroundTransparency = 1, Visible = false,
			TextScaled = true, FontFace = FONT_HEAVY, Text = "", TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.15, TextStrokeColor3 = Color3.new(0, 0, 0),
		}, list)
		local clay = New("TextLabel", {
			LayoutOrder = 2, Size = UDim2.fromScale(1, 0.5), BackgroundTransparency = 1, Visible = false,
			TextScaled = true, FontFace = FONT_HEAVY, Text = "Clay Client User", TextColor3 = THEME.Accent,
			TextStrokeTransparency = 0.25, TextStrokeColor3 = THEME.Deep,
		}, list)
		return { gui = gui, role = role, clay = clay, adornee = adornee, hasCrown = hasCrown, crown = hasCrown and buildCrown() or nil }
	end

	local function refreshAll()
		local seen = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= player or SHOW_SELF then
				seen[plr] = true
				local key = string.lower(plr.Name)
				local isClay, role = Tags.Users[key] == true, Tags.Roles[key]
				-- tags only ever show on people actually running the client
				local ad = isClay and adorneeFor(plr) or nil
				if ad then
					local wantCrown = role ~= nil and role.crown == true
					local t = made[plr]
					if t and (t.adornee ~= ad or not t.gui.Parent or t.hasCrown ~= wantCrown) then removeTag(plr); t = nil end
					if not t then t = buildTag(ad, wantCrown); made[plr] = t end
					t.role.Visible = role ~= nil
					if role then t.role.Text = role.text; t.role.TextColor3 = role.color end
					t.clay.Visible = true
				else
					removeTag(plr)
				end
			end
		end
		for plr in pairs(made) do
			if not seen[plr] then removeTag(plr) end
		end
	end

	function Tags.Start()
		if type(CONFIG.TagRelayUrl) ~= "string" or CONFIG.TagRelayUrl == "" then
			error("set TagRelayUrl (and TagRelayKey) in CONFIG first", 0)
		end
		if not getRequestFn() then
			error("your executor has no HTTP request function", 0)
		end
		if Tags.On then return end
		Tags.On = true
		gen += 1
		local my = gen
		if crownConn then crownConn:Disconnect() end
		crownConn = RS.RenderStepped:Connect(updateCrowns)
		table.insert(connections, crownConn)
		task.spawn(function()
			local fails = 0
			while Tags.On and gen == my and not Clay.Unloaded do
				local data = beat()
				if data then
					fails = 0
					applyData(data)
				else
					fails += 1
					if fails == 3 then Notify("Clay Tags: can't reach the tag server") end
				end
				task.wait(POLL)
			end
		end)
		task.spawn(function()
			while Tags.On and gen == my and not Clay.Unloaded do
				pcall(refreshAll)
				task.wait(0.5)
			end
		end)
	end

	function Tags.Stop()
		if not Tags.On then return end
		Tags.On = false
		gen += 1
		if crownConn then crownConn:Disconnect(); crownConn = nil end
		for plr in pairs(made) do removeTag(plr) end
		Tags.Users, Tags.Roles = {}, {}
		task.spawn(function() beat(true) end)   -- tell the server we left so the tag disappears for others
	end
end
