--[[
  UNDETEK xhub — Reminiscence Zombies (FREE STANDALONE)
  No hub / no key / no shieldDeliver
  Discord: https://discord.gg/cgRsTMUa9J
  Load: loadstring(game:HttpGet("https://xhub.blog/lua/game/zombie-uprising.lua"))()
  Place 3554092380 (Kino / Main game) is valid. This is NOT USSF Zombie Uprising.
]]

-- PlaceId guard (Reminiscence Zombies — hub + every map place)
do
  local UNIVERSE = "1003981402"
  local allowed = {
    ["2778230703"] = true,       -- hub
    ["3554092380"] = true,        -- Main game (Kino, etc.)
    ["4887402797"] = true,        -- TranZit: Remake
    ["136264694312905"] = true, -- Pumpkin Panic
  }
  local pid = tostring(game.PlaceId)
  local gid = tostring(game.GameId)
  local ok = allowed[pid] == true or gid == UNIVERSE
  if not ok then
    pcall(function()
      local info = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
      local n = string.lower(tostring(info and info.Name or ""))
      if string.find(n, "reminiscence", 1, true) or string.find(n, "tranzit", 1, true) then
        ok = true
      end
    end)
  end
  if not ok then
    pcall(function()
      if game:GetService("Lighting"):FindFirstChild("ETC") then
        ok = true
      end
    end)
  end
  if not ok and not (getgenv and getgenv().__XHUB_FORCE) then
    warn("[UNDETEK] Reminiscence Zombies: wrong PlaceId (" .. pid .. ") GameId (" .. gid .. ") — aborted")
    return
  end
end

--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║  XHUB PRESENTS · REMINISCENCE ZOMBIES                                ║
    ║  BY MRN STUDIO & PURGATORIZZ                                 ║
    ╚══════════════════════════════════════════════════════════════╝
    Combat / Argent / Armes / Vol — menu blanc, textes simples
]]

--============================================================--
--  SERVICES
--============================================================--
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local Workspace          = game:GetService("Workspace")
local Lighting           = game:GetService("Lighting")
local TeleportService    = game:GetService("TeleportService")
local CoreGui            = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

--============================================================--
--  EXECUTOR HELPERS (compat)
--============================================================--
local hookmetamethod    = hookmetamethod
local getnamecallmethod = getnamecallmethod
local getrawmetatable   = getrawmetatable
local setreadonly       = setreadonly or (make_writeable and function() end)
local newcclosure       = newcclosure or function(f) return f end
local getconnections    = getconnections
local getgc             = getgc
local firesignal        = firesignal

local function safe(f, ...)
    local ok, res = pcall(f, ...)
    if ok then return res end
    return nil
end

--============================================================--
--  ETAT / CONFIG
--============================================================--
local M = {}
M.hooked = false
M.internal = false          -- garde anti-reentrance pour nos FireServer
M.tracers = {}
M.espCache = {}

M.state = {
    -- Silent aim
    silent        = false,
    multi         = false,
    fov           = 260,      -- rayon ecran (px) pour cible unique
    multiFov      = 550,      -- rayon ecran (px) pour le mode multi
    multiRange    = 220,      -- distance monde max (studs) pour le mode multi
    silentPart    = "Head",   -- partie ciblee
    damageMult    = 1,        -- multiplicateur de degats (1 = discret)
    visibleOnly   = false,    -- (silent traverse les murs par defaut)
    silentInterval= 0.08,     -- cadence du tir silent (maintien clic)

    -- Tracer (confirmation de tir)
    tracer        = true,
    tracerColor   = Color3.fromRGB(0, 255, 140),
    tracerTime    = 0.12,

    -- Triggerbot (auto-tir quand un zombie est sous le viseur)
    trigger       = false,
    triggerDelay  = 0.08,
    triggerFov    = 100,    -- px autour du centre (plus fiable que raycast)
    triggerClick  = true,   -- simule aussi un clic (active le gun + silent)


    -- Kill aura (reutilise le dernier tir capture)
    aura          = false,
    auraRange     = 120,
    auraInterval  = 0.10,

    -- FOV circle
    fovCircle     = false,
    fovColor      = Color3.fromRGB(255, 255, 255),

    -- ESP
    esp           = false,
    espBox        = true,
    espName       = true,
    espHealth     = true,
    espDistance   = true,
    espSkeleton   = false,
    espTracer     = false,
    espSnapline   = false,
    espMaxDist    = 1000,
    teamCheck     = true,     -- ignore les autres joueurs
    espColor      = Color3.fromRGB(255, 60, 60),
    allyColor     = Color3.fromRGB(0, 170, 255),


    -- capture du dernier vrai tir (pour aura/trigger)
    dmgTemplate    = nil,   -- indices 2..9 du payload ETC "Damage6"
    lastDamage     = nil,

    -- Points / Rewards9 (argent sur kill) — maj jeu: Rewards8 -> Rewards9
    autoReward     = true,  -- 30k par zombie tue (Aimbot / Aura / Kill all)
    rewardHit      = 0,      -- pas de points sur un hit sans kill
    rewardKill     = 30000,  -- 30k par execution
    rewardHead     = 0,

    -- Kill All Instant
    killAll        = false, -- tue tous les zombies + chaque nouveau spawn
    killAllReward  = true,  -- points sur Kill All (peut flood)
    killAllRate    = 0.05,  -- boucle de securite (s)

    -- Munitions
    infAmmo        = false, -- refill client (GunInfo / Max Ammo / Extra=inf)

    -- Fly (Player tab)
    fly           = false,
    flySpeed      = 1,
    flyCFrame     = false,
    flyTransparency = 0.75,
}

--============================================================--
--  UTIL PERSONNAGE
--============================================================--
local function getChar() return LocalPlayer.Character end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getHRP()
    local c = getChar()
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

--============================================================--
--  DETECTION DES ZOMBIES (bots)
--============================================================--
local function isPlayerChar(model)
    if Players:GetPlayerFromCharacter(model) then return true end
    return false
end

local function rootOf(model, hum)
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
        or (hum and hum.RootPart)
        or model:FindFirstChild("Head")
end

local function getZombies()
    local list = {}
    local function consider(m)
        if typeof(m) ~= "Instance" or not m:IsA("Model") then return end
        local hum = m:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        if isPlayerChar(m) then return end
        local root = rootOf(m, hum)
        if not root then return end
        list[#list + 1] = { model = m, hum = hum, root = root }
    end
    -- le jeu range les zombies dans workspace.Zombies et workspace.SpecialZ
    local zf = Workspace:FindFirstChild("Zombies")
    if zf then for _, m in ipairs(zf:GetChildren()) do consider(m) end end
    local sf = Workspace:FindFirstChild("SpecialZ")
    if sf then for _, m in ipairs(sf:GetChildren()) do consider(m) end end
    -- fallback : scan workspace si les dossiers n'existent pas
    if not zf and not sf then
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Model") then consider(child) end
        end
    end
    return list
end

local function partOf(z, name)
    return z.model:FindFirstChild(name)
        or z.model:FindFirstChild("Head")
        or z.root
end

--============================================================--
--  ECRAN / CIBLAGE
--============================================================--
local function screenCenter()
    local vp = Camera.ViewportSize
    return Vector2.new(vp.X / 2, vp.Y / 2)
end

local function toScreen(pos)
    local v, on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), on, v.Z
end

local function isVisible(part)
    local hrp = getHRP()
    if not hrp then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { getChar(), Camera, Workspace:FindFirstChild("Bullets") }
    local dir = part.Position - Camera.CFrame.Position
    local res = Workspace:Raycast(Camera.CFrame.Position, dir, params)
    if not res then return true end
    return res.Instance:IsDescendantOf(part.Parent)
end

-- meilleure cible unique (la plus proche du viseur, dans le FOV)
local function getBestZombie()
    local best, bestDist
    local center = screenCenter()
    for _, z in ipairs(getZombies()) do
        local part = partOf(z, M.state.silentPart)
        local sp, on, depth = toScreen(part.Position)
        if on and depth > 0 then
            local d = (sp - center).Magnitude
            if d <= M.state.fov and (not bestDist or d < bestDist) then
                if (not M.state.visibleOnly) or isVisible(part) then
                    best, bestDist = { z = z, part = part }, d
                end
            end
        end
    end
    return best
end

-- tous les zombies "devant nous" (mode multi)
local function getZombiesFront()
    local res = {}
    local center = screenCenter()
    local hrp = getHRP()
    local origin = hrp and hrp.Position or Camera.CFrame.Position
    for _, z in ipairs(getZombies()) do
        local part = partOf(z, M.state.silentPart)
        local sp, on, depth = toScreen(part.Position)
        if on and depth > 0 then
            local d = (sp - center).Magnitude
            local worldDist = (part.Position - origin).Magnitude
            if d <= M.state.multiFov and worldDist <= M.state.multiRange then
                res[#res + 1] = { z = z, part = part }
            end
        end
    end
    return res
end

-- zombies dans un rayon monde (kill aura)
local function getZombiesInRange(range)
    local res = {}
    local hrp = getHRP()
    if not hrp then return res end
    for _, z in ipairs(getZombies()) do
        local part = partOf(z, M.state.silentPart)
        if (part.Position - hrp.Position).Magnitude <= range then
            res[#res + 1] = { z = z, part = part }
        end
    end
    return res
end

--============================================================--
--  REMOTE DE DEGATS  (Lighting.ETC, action "Damage6")
--  Maj place 3554092380 : Damage5->Damage6, Rewards8->Rewards9.
--  Tir normal : { Humanoid, dmg, "Damage6<emoji>", false,false,false, p7, vec, gun }
--  Splash / batch : { hitList, 0, "Damage6<emoji>", false,false,false,true, Vector3, gun }
--  hitList : { {humanoid, damage, extra}, ... }
--============================================================--
-- Octopus emoji (jeu) en bytes UTF-8 — string.char = plus safe pour Xeno
local EMOJI = string.char(240, 159, 144, 153)
local DAMAGE_ACTION  = "Damage6" .. EMOJI
local REWARD_ACTION  = "Rewards9" .. EMOJI

local function isHum(x)
    return typeof(x) == "Instance" and x:IsA("Humanoid")
end

local function getETC(waitSec)
    local etc = Lighting:FindFirstChild("ETC")
    if etc then return etc end
    if waitSec and waitSec > 0 then
        return safe(function() return Lighting:WaitForChild("ETC", waitSec) end)
    end
    return nil
end

-- Identite ETC (pas d'instance figee) -> OK apres rejoin / nouveau remote
local function isETCRemote(inst)
    return typeof(inst) == "Instance"
        and inst.Name == "ETC"
        and inst.Parent == Lighting
        and inst:IsA("RemoteEvent")
end

-- Partie / round chargee (pas lobby, pas avant Character)
local function isInMatch()
    local ch = LocalPlayer.Character
    if not ch or not ch:FindFirstChildOfClass("Humanoid") then return false end
    if Workspace:FindFirstChild("Zombies") or Workspace:FindFirstChild("SpecialZ") then
        return true
    end
    local st = LocalPlayer:FindFirstChild("Status") or LocalPlayer:FindFirstChild("status")
    if st then
        local playing = st:FindFirstChild("Playing") or st:FindFirstChild("InGame")
        if playing then
            local v = playing.Value
            if v == true or v == "Playing" or v == "InGame" then return true end
        end
    end
    if LocalPlayer:FindFirstChildOfClass("Tool") then return true end
    if ch:FindFirstChildOfClass("Tool") then return true end
    if ch:FindFirstChild("GunInfo", true) then return true end
    -- pads mur / coffre presents
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg and (pg:FindFirstChild("Required", true) or pg:FindFirstChild("Mystery Box Gui", true)) then
        return true
    end
    return false
end

local function waitInMatch(timeout)
    local t0 = os.clock()
    local lim = tonumber(timeout) or 90
    while os.clock() - t0 < lim do
        if isInMatch() then return true end
        task.wait(0.4)
    end
    return isInMatch()
end

-- fabrique une hitList a partir d'entrees {hum=...}
local function buildHitList(entries, dmg)
    local list = {}
    for _, e in ipairs(entries) do
        list[#list + 1] = { e.hum, dmg, nil }
    end
    return list
end

-- Points (client-autoritaire) : meme remote que le jeu apres un vrai hit
local function fireReward(amount, headshotKill, headPart)
    if not amount or amount <= 0 then return end
    local Etc = getETC()
    if not Etc then return end
    M.internal = true
    safe(function()
        if headshotKill and headPart then
            Etc:FireServer({ 1, amount, REWARD_ACTION, headPart })
        else
            Etc:FireServer({ 0, amount, REWARD_ACTION })
        end
    end)
    M.internal = false
end

-- Calcule + envoie les points pour une liste de hits {hum, dmg, part?}
local function rewardHits(entries)
    if not M.state.autoReward then return end
    for _, e in ipairs(entries) do
        local hum = e.hum or e[1]
        local dmg = e.dmg or e[2]
        local part = e.part
        if hum and typeof(dmg) == "number" and hum.Health > 0 then
            local willKill = hum.Health - dmg <= 0
            local isHead = part and part.Name == "Head"
            local pts = 0
            if willKill then
                pts = M.state.rewardKill or 30000
            else
                pts = M.state.rewardHit or 0
            end
            if pts > 0 then
                fireReward(pts, willKill and isHead, isHead and part or nil)
            end
        end
    end
end

-- envoie une liste de degats (aura / trigger / multi) + points
-- hitList : { {humanoid, damage, fade}, ... }
-- parts  : optional map/list of hit parts for headshot bonus
local function fireDamage(hitList, parts)
    if #hitList == 0 then return end
    local Etc = getETC()
    if not Etc then return end

    -- Rewards AVANT le damage (comme le jeu) pour lire Health actuelle
    if M.state.autoReward then
        local entries = {}
        for i, row in ipairs(hitList) do
            local part = nil
            if type(parts) == "table" then
                part = parts[i] or parts[row[1]]
            end
            entries[#entries + 1] = { hum = row[1], dmg = row[2], part = part }
        end
        rewardHits(entries)
    end

    local tpl = M.state.dmgTemplate
    M.internal = true
    safe(function()
        -- Toujours le format splash (hitList). Le tir "Humanoid first" casse
        -- si on rejoue le template brut capture sur un vrai coup.
        local gunData = {}
        if type(tpl) == "table" and type(tpl[8]) == "table" then
            gunData = tpl[8]
        end
        Etc:FireServer({ hitList, 0, DAMAGE_ACTION, false, false, false, true, Vector3.new(), gunData })
    end)
    M.internal = false
end

--============================================================--
--  KILL ALL INSTANT
--  Spawn = serveur (impossible de bloquer). Damage6 = client.
--  -> one-shot tous les vivants + ChildAdded sur Zombies/SpecialZ
--     = chaque nouveau spawn meurt au frame ou il apparait
--     = manches suivantes quasi-instantanees.
--============================================================--
local function clearList(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

local function instaDamageFor(hum)
    local zh = Workspace:FindFirstChild("ZHealth")
    local base = (zh and tonumber(zh.Value)) or 0
    local hp = math.max(hum.MaxHealth or 0, hum.Health or 0, base, 1)
    return hp * 5 + 999999
end

local function wipeZombies(zList, doReward)
    if not zList or #zList == 0 then return 0 end
    local prevReward = M.state.autoReward
    if doReward == false then M.state.autoReward = false end
    local n = 0
    local hitList, parts = {}, {}
    local function flush()
        if #hitList == 0 then return end
        fireDamage(hitList, parts)
        n = n + #hitList
        clearList(hitList)
        clearList(parts)
    end
    for _, z in ipairs(zList) do
        if z.hum and z.hum.Parent and z.hum.Health > 0 then
            hitList[#hitList + 1] = { z.hum, instaDamageFor(z.hum), nil }
            parts[#parts + 1] = partOf(z, "Head")
            if #hitList >= 25 then flush() end
        end
    end
    flush()
    M.state.autoReward = prevReward
    return n
end

local function killAllNow()
    return wipeZombies(getZombies(), M.state.killAllReward)
end

local function tryInstaKillModel(m)
    if not M.state.killAll then return end
    if typeof(m) ~= "Instance" or not m:IsA("Model") then return end
    if isPlayerChar(m) then return end
    task.spawn(function()
        local hum = m:FindFirstChildOfClass("Humanoid")
        if not hum then
            hum = m:WaitForChild("Humanoid", 4)
        end
        if not (hum and M.state.killAll) then return end
        local t0 = os.clock()
        while M.state.killAll and hum.Parent and hum.Health > 0 and os.clock() - t0 < 2.5 do
            local root = rootOf(m, hum)
            if root then
                wipeZombies({ { model = m, hum = hum, root = root } }, M.state.killAllReward)
                if hum.Health > 0 then
                    task.wait(0.06)
                    if M.state.killAll and hum.Health > 0 then
                        wipeZombies({ { model = m, hum = hum, root = root } }, M.state.killAllReward)
                    end
                end
                return
            end
            task.wait(0.03)
        end
    end)
end

local killAllHooks = {}
local function hookZombieFolder(folder)
    if not folder or killAllHooks[folder] then return end
    killAllHooks[folder] = folder.ChildAdded:Connect(function(child)
        tryInstaKillModel(child)
    end)
    if M.state.killAll then
        for _, child in ipairs(folder:GetChildren()) do
            tryInstaKillModel(child)
        end
    end
end

local function setupKillAllWatchers()
    hookZombieFolder(Workspace:FindFirstChild("Zombies"))
    hookZombieFolder(Workspace:FindFirstChild("SpecialZ"))
    Workspace.ChildAdded:Connect(function(child)
        if child.Name == "Zombies" or child.Name == "SpecialZ" then
            hookZombieFolder(child)
        end
    end)
end

task.spawn(function()
    while true do
        if M.state.killAll then
            local zs = getZombies()
            if #zs > 0 then
                wipeZombies(zs, M.state.killAllReward)
            else
                hookZombieFolder(Workspace:FindFirstChild("Zombies"))
                hookZombieFolder(Workspace:FindFirstChild("SpecialZ"))
            end
            task.wait(M.state.killAllRate)
        else
            task.wait(0.25)
        end
    end
end)

setupKillAllWatchers()

--============================================================--
--  TRACERS (Drawing)
--============================================================--
local function newLine(color, thickness)
    local ok, line = pcall(function()
        local l = Drawing.new("Line")
        l.Thickness = thickness or 1.6
        l.Color = color
        l.Transparency = 1
        l.Visible = false
        return l
    end)
    return ok and line or nil
end

local function spawnTracer(fromWorld, toWorld)
    if not M.state.tracer then return end
    local a, onA = toScreen(fromWorld)
    local b, onB = toScreen(toWorld)
    if not (onA or onB) then return end
    local line = newLine(M.state.tracerColor, 2)
    if not line then return end
    line.From = a
    line.To = b
    line.Visible = true
    M.tracers[#M.tracers + 1] = { line = line, expire = os.clock() + M.state.tracerTime }
end

RunService.RenderStepped:Connect(function()
    local now = os.clock()
    for i = #M.tracers, 1, -1 do
        local t = M.tracers[i]
        if now >= t.expire then
            pcall(function() t.line:Remove() end)
            table.remove(M.tracers, i)
        end
    end
end)

--============================================================--
--  HOOK SILENT AIM
--============================================================--
local function currentDamage(payload)
    -- degats depuis le tir original, sinon dernier capture, sinon fallback
    if payload then
        if isHum(payload[1]) and type(payload[2]) == "number" then
            return payload[2]
        end
        local orig = payload[1]
        if type(orig) == "table" and type(orig[1]) == "table" and type(orig[1][2]) == "number" then
            return orig[1][2]
        end
        if type(payload[2]) == "number" then
            return payload[2]
        end
    end
    if M.state.lastDamage then return M.state.lastDamage end
    local zh = Workspace:FindFirstChild("ZHealth")
    return (zh and zh.Value) or 1000
end

local function handleDamagePayload(payload)
    -- capture template + degats reels pour aura/trigger
    M.state.dmgTemplate = {
        payload[2], payload[3], payload[4], payload[5],
        payload[6], payload[7], payload[8], payload[9],
    }
    if isHum(payload[1]) and type(payload[2]) == "number" then
        M.state.lastDamage = payload[2]
    else
        local orig = payload[1]
        if type(orig) == "table" and type(orig[1]) == "table" and type(orig[1][2]) == "number" then
            M.state.lastDamage = orig[1][2]
        end
    end

    if not M.state.silent then return payload end

    local dmg = currentDamage(payload)
    if M.state.damageMult ~= 1 then dmg = dmg * M.state.damageMult end

    local origin = (getHRP() and getHRP().Position) or Camera.CFrame.Position
    local humanoidShot = isHum(payload[1])

    if M.state.multi then
        local front = getZombiesFront()
        if #front == 0 then return payload end
        local entries = {}
        local parts = {}
        for i, f in ipairs(front) do
            entries[#entries + 1] = { hum = f.z.hum }
            parts[i] = f.part
            spawnTracer(origin, f.part.Position)
        end
        payload[1] = buildHitList(entries, dmg)
        payload[2] = 0
        payload[3] = DAMAGE_ACTION
        payload[4] = false
        payload[5] = false
        payload[6] = false
        payload[7] = true
        if payload[8] == nil then payload[8] = Vector3.new() end
        if payload[9] == nil then payload[9] = {} end
        -- Rewards pour les cibles redirigees (le jeu a deja paye la cible originale du raycast)
        if M.state.autoReward then
            local re = {}
            for i, f in ipairs(front) do
                re[#re + 1] = { hum = f.z.hum, dmg = dmg, part = f.part }
            end
            rewardHits(re)
        end
        return payload
    else
        local best = getBestZombie()
        if not best then return payload end
        spawnTracer(origin, best.part.Position)
        if humanoidShot then
            payload[1] = best.z.hum
            payload[2] = dmg
        else
            payload[1] = buildHitList({ { hum = best.z.hum } }, dmg)
        end
        if M.state.autoReward then
            rewardHits({ { hum = best.z.hum, dmg = dmg, part = best.part } })
        end
        return payload
    end
end

local function setupHook()
    if M.hooked then return true end
    -- Ne bloque PAS sur ETC : le hook filtre par Name/Parent a chaque FireServer
    -- (apres rejoin Lighting.ETC peut etre une NOUVELLE instance)

    local function processArgs(args)
        if M.internal then return args end
        local p = args[1]
        if type(p) == "table" and p[3] == DAMAGE_ACTION then
            -- silent OFF = capture template seulement, payload inchange
            -- p[1] = Humanoid (tir normal) OU hitList (splash)
            args[1] = handleDamagePayload(p)
        end
        return args
    end

    -- methode preferee : hookmetamethod
    if hookmetamethod and getnamecallmethod then
        local ok = pcall(function()
            local old
            old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if not M.internal and method == "FireServer" and isETCRemote(self) then
                    local n = select("#", ...)
                    local args = { ... }
                    args = processArgs(args)
                    return old(self, table.unpack(args, 1, n))
                end
                return old(self, ...)
            end))
            M.hooked = true
        end)
        if ok and M.hooked then return true end
    end

    -- fallback : getrawmetatable
    pcall(function()
        local mt = getrawmetatable(game)
        local oldNC = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod and getnamecallmethod() or ""
            if not M.internal and method == "FireServer" and isETCRemote(self) then
                local n = select("#", ...)
                local args = { ... }
                args = processArgs(args)
                return oldNC(self, table.unpack(args, 1, n))
            end
            return oldNC(self, ...)
        end)
        setreadonly(mt, true)
        M.hooked = true
    end)
    return M.hooked
end

--============================================================--
--  KILL AURA (loop)
--============================================================--
task.spawn(function()
    while true do
        if M.state.aura then
            local inrange = getZombiesInRange(M.state.auraRange)
            if #inrange > 0 then
                local dmg = currentDamage(nil)
                if M.state.damageMult ~= 1 then dmg = dmg * M.state.damageMult end
                local origin = (getHRP() and getHRP().Position) or Camera.CFrame.Position
                local hitList = {}
                local parts = {}
                for _, item in ipairs(inrange) do
                    hitList[#hitList + 1] = { item.z.hum, dmg, nil }
                    parts[#parts + 1] = item.part
                    spawnTracer(origin, item.part.Position)
                end
                fireDamage(hitList, parts)
            end
            task.wait(M.state.auraInterval)
        else
            task.wait(0.2)
        end
    end
end)

--============================================================--
--  TRIGGERBOT (auto-tir sur zombie proche du viseur)
--  Ancien = raycast monde (rate murs / CanQuery=false).
--  Nouveau = meme logic que silent (ecran + FOV) + clic virtuel.
--============================================================--
local function getTriggerTarget()
    local best, bestDist
    local center = screenCenter()
    local fov = M.state.triggerFov or 100
    for _, z in ipairs(getZombies()) do
        local part = partOf(z, M.state.silentPart)
        if part then
            local sp, on, depth = toScreen(part.Position)
            if on and depth and depth > 0 then
                local d = (sp - center).Magnitude
                if d <= fov and (not bestDist or d < bestDist) then
                    if (not M.state.visibleOnly) or isVisible(part) then
                        best, bestDist = { z = z, part = part }, d
                    end
                end
            end
        end
    end
    if best then return best end

    -- fallback raycast (si un part est pile sous le viseur)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { getChar(), Camera, Workspace:FindFirstChild("Bullets") }
    params.IgnoreWater = true
    local origin = Camera.CFrame.Position
    local dir = Camera.CFrame.LookVector * 800
    local res = Workspace:Raycast(origin, dir, params)
    if res and res.Instance then
        local model = res.Instance:FindFirstAncestorWhichIsA("Model")
        if model then
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and not isPlayerChar(model) then
                local part = model:FindFirstChild(M.state.silentPart)
                    or model:FindFirstChild("Head")
                    or res.Instance
                return { z = { model = model, hum = hum, root = rootOf(model, hum) }, part = part }
            end
        end
    end
    return nil
end

local function simulateGunClick()
    -- active le vrai tir du jeu (utile avec silent + capture gunData)
    if mouse1click then
        pcall(mouse1click)
        return
    end
    if mouse1press and mouse1release then
        pcall(function()
            mouse1press()
            task.wait(0.02)
            mouse1release()
        end)
        return
    end
    local vim = safe(function() return game:GetService("VirtualInputManager") end)
    if vim then
        pcall(function()
            local vp = Camera.ViewportSize
            local x, y = vp.X / 2, vp.Y / 2
            vim:SendMouseButtonEvent(x, y, 0, true, game, 1)
            task.wait(0.02)
            vim:SendMouseButtonEvent(x, y, 0, false, game, 1)
        end)
    end
end

task.spawn(function()
    while true do
        if M.state.trigger then
            local target = getTriggerTarget()
            if target and target.z and target.z.hum and target.z.hum.Health > 0 then
                local hum = target.z.hum
                local part = target.part
                local dmg = currentDamage(nil)
                if (not dmg) or dmg < 1 then
                    local zh = Workspace:FindFirstChild("ZHealth")
                    dmg = (zh and tonumber(zh.Value)) or 1000
                end
                if M.state.damageMult ~= 1 then dmg = dmg * M.state.damageMult end

                local origin = (getHRP() and getHRP().Position) or Camera.CFrame.Position
                if part then spawnTracer(origin, part.Position) end

                -- 1) degats directs (comme aura)
                fireDamage({ { hum, dmg, nil } }, { part })

                -- 2) clic reel -> le gun tire (silent redirige si actif)
                if M.state.triggerClick then
                    simulateGunClick()
                end

                task.wait(M.state.triggerDelay or 0.08)
            else
                task.wait(0.03)
            end
        else
            task.wait(0.12)
        end
    end
end)

--============================================================--
--  SILENT AIM ACTIF (tire en maintenant clic gauche)
--   Ne depend pas du jeu : envoie directement les degats a la
--   cible visee (FOV) ou a tous les zombies devant (multi).
--============================================================--
local mouseHeld = false
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        mouseHeld = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        mouseHeld = false
    end
end)

task.spawn(function()
    while true do
        if M.state.silent and mouseHeld then
            local dmg = currentDamage(nil)
            if M.state.damageMult ~= 1 then dmg = dmg * M.state.damageMult end
            local origin = (getHRP() and getHRP().Position) or Camera.CFrame.Position
            local hitList = {}
            local parts = {}
            if M.state.multi then
                for _, f in ipairs(getZombiesFront()) do
                    hitList[#hitList + 1] = { f.z.hum, dmg, nil }
                    parts[#parts + 1] = f.part
                    spawnTracer(origin, f.part.Position)
                end
            else
                local best = getBestZombie()
                if best then
                    hitList[1] = { best.z.hum, dmg, nil }
                    parts[1] = best.part
                    spawnTracer(origin, best.part.Position)
                end
            end
            if #hitList > 0 then fireDamage(hitList, parts) end
            task.wait(M.state.silentInterval)
        else
            task.wait(0.03)
        end
    end
end)

--============================================================--
--  WALL BUYS / ARMES / MYSTERY BOX
--============================================================--
M.wallBuys = {}   -- pads mur
M.boxPads  = {}   -- mystery box remotes
M.papPads  = {}   -- Pack-a-Punch (ToolNeeded + Ammo)
M.catalog  = {}   -- toutes les armes (WeaponModule)
M.weaponIndex = {} -- label -> entry

local function extractWeaponName(text)
    if not text or text == "" then return nil end
    local name = text:match("%]%s*([^%[%]]+)%s*%[")
        or text:match("[Bb]uy%s+(.+)%s*%[")
        or text:match("to%s+[Bb]uy%s+(.+)")
        or text:match("[Hh]old.-%s(.+)%s*%[")
    if name then
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        name = name:gsub("%s+%d[%d,]*%s*$", "")
        name = name:gsub("^to%s+", "")
        if #name > 1 then return name end
    end
    if #text > 2 and #text < 60 then return text end
    return nil
end

local function getPoints()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local p = ls and ls:FindFirstChild("Points")
    return p and p.Value or 0
end

local function isPerkOrDoor(name)
    local low = (name or ""):lower()
    if low:find("door") or low:find("open") or low:find("debris") or low:find("barrier") then return true end
    if low:find("juggernog") or low:find("speed cola") or low:find("double tap")
        or low:find("quick revive") or low:find("stamin") or low:find("mule kick")
        or low:find("phd") or low:find("electric cherry") or low:find("deadshot")
        or low:find("widow") or low:find("vulture") or low:find("tombstone")
        or low:find("afterlife") or low:find("revive") then
        return true
    end
    return false
end

local function isPapLabel(name)
    local low = (name or ""):lower()
    return low:find("pack", 1, true) ~= nil
        or low:find("punch", 1, true) ~= nil
        or low:find("pap", 1, true) ~= nil
        or low:find("upgrade", 1, true) ~= nil
        or low:find("aat", 1, true) ~= nil
end

local function getHeldGun()
    local char = LocalPlayer.Character
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return nil end
    if tool:FindFirstChild("Gun Script") or tool:FindFirstChild("PAP")
        or tool:FindFirstChild("GunScript") or tool:GetAttribute("AAT") then
        return tool
    end
    -- fallback : Tool avec Handle + nom dans catalogue
    if tool:FindFirstChild("Handle") then return tool end
    return nil
end

local function getUpgradeLevel(tool)
    if not tool then return 0, "aucune arme" end
    local hasAat = tool:GetAttribute("AAT") ~= nil
    local hasPap = tool:FindFirstChild("PAP") ~= nil
    local name = tool.Name
    local isPapName = false
    for _, c in ipairs(M.catalog) do
        if c.name == name and c.isPap then
            isPapName = true
            break
        end
    end
    if hasAat then
        return 2, "MAX (PAP + AAT: " .. tostring(tool:GetAttribute("AAT")) .. ")"
    end
    if hasPap or isPapName then
        return 1, "PAP (manque AAT)"
    end
    return 0, "base (" .. name .. ")"
end

local function findRemoteNear(inst)
    if not inst then return nil end
    -- Event ObjectValue
    for _, d in ipairs(inst:GetDescendants()) do
        if d.Name == "Event" and d:IsA("ObjectValue") and d.Value and d.Value:IsA("RemoteEvent") then
            return d.Value
        end
    end
    -- RemoteEvent sibling / child
    if inst:IsA("RemoteEvent") then return inst end
    local r = inst:FindFirstChildWhichIsA("RemoteEvent", true)
    if r then return r end
    local p = inst.Parent
    for _ = 1, 4 do
        if not p then break end
        r = p:FindFirstChildWhichIsA("RemoteEvent")
        if r then return r end
        p = p.Parent
    end
    return nil
end

local function readLabelText(inst)
    if not inst then return "" end
    if inst:IsA("TextLabel") or inst:IsA("TextButton") then
        local t = inst:GetAttribute("Converted") or inst.Text or ""
        local ct = inst:FindFirstChild("ContentText")
        if (not t or t == "" or t == " ") and ct then
            t = ct.Value or ct.Text or ""
        end
        return t
    end
    if inst:IsA("StringValue") then return inst.Value or "" end
    return ""
end

local function ingestWeaponsTable(weapons)
    if type(weapons) ~= "table" then return 0 end
    local seen = {}
    local n = 0
    for name, data in pairs(weapons) do
        if type(name) == "string" and not seen[name] then
            local isPap = type(data) == "table" and data.ISPAP == true
            local original = type(data) == "table" and data.Original
            seen[name] = true
            n = n + 1
            M.catalog[#M.catalog + 1] = {
                name = name,
                original = original or name,
                isPap = isPap and true or false,
                wepType = type(data) == "table" and data.WepType or "?",
                source = "BOX/MODULE",
            }
        end
    end
    return n
end

local function loadWeaponCatalog(allowRequire)
    M.catalog = {}

    -- 1) Preferer une table Weapons deja chargee par le jeu (getgc) — zero side-effect
    if getgc then
        local found = false
        pcall(function()
            for _, obj in ipairs(getgc(true)) do
                if found then break end
                if type(obj) == "table" then
                    local w = rawget(obj, "Weapons")
                    if type(w) == "table" and (rawget(w, "M14") or rawget(w, "Ray Gun") or rawget(w, "M1911")) then
                        if ingestWeaponsTable(w) > 0 then
                            found = true
                        end
                    end
                end
            end
        end)
        if #M.catalog > 0 then
            table.sort(M.catalog, function(a, b) return a.name < b.name end)
            return M.catalog
        end
    end

    -- 2) require SEULEMENT si demande + deja en partie (sinon casse equip/achat au lobby)
    if allowRequire and isInMatch() then
        local ok, mod = pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            local wm = rs:FindFirstChild("WeaponModule") or rs:FindFirstChild("WeaponModule", true)
            if not wm then return nil end
            local ret = require(wm)
            if type(ret) == "function" then
                return ret(false, true)
            end
            return ret
        end)
        if ok and type(mod) == "table" and type(mod.Weapons) == "table" then
            ingestWeaponsTable(mod.Weapons)
        end
    end

    table.sort(M.catalog, function(a, b) return a.name < b.name end)
    return M.catalog
end

local function scanWallBuys()
    M.wallBuys = {}
    M.boxPads = {}
    M.papPads = {}
    M.weaponIndex = {}
    local seenRemote = {}

    local function addEntry(name, price, remote, kind)
        if not remote or not remote:IsA("RemoteEvent") then return end
        if seenRemote[remote] then return end
        if kind ~= "PAP" and isPerkOrDoor(name) then return end
        seenRemote[remote] = true
        local label
        if kind == "BOX" then
            label = string.format("[Coffre] Mystery Box [%d]", price or 950)
            M.boxPads[#M.boxPads + 1] = {
                label = label, name = "Mystery Box", price = price or 950,
                remote = remote, kind = "BOX",
            }
            M.weaponIndex[label] = M.boxPads[#M.boxPads]
        elseif kind == "PAP" then
            local e = {
                name = "Pack-a-Punch", price = price or 2500,
                remote = remote, kind = "PAP",
            }
            M.papPads[#M.papPads + 1] = e
            e.label = string.format("[PAP] Pack-a-Punch [%d] #%d", e.price, #M.papPads)
            M.weaponIndex[e.label] = e
        else
            label = string.format("[Mur] %s [%d]", name, price or 0)
            local e = {
                label = label, name = name, price = price or 0,
                remote = remote, kind = "WALL",
            }
            M.wallBuys[#M.wallBuys + 1] = e
            M.weaponIndex[label] = e
        end
    end

    local function considerRoot(root)
        if not root then return end
        local required = root:FindFirstChild("Required")
        if not required then
            for _, d in ipairs(root:GetDescendants()) do
                if d.Name == "Required" and (d:IsA("IntValue") or d:IsA("NumberValue")) then
                    required = d
                    break
                end
            end
        end
        local price = required and tonumber(required.Value) or 0

        local toolNeeded = root:FindFirstChild("ToolNeeded")
        local ammoFlag = root:FindFirstChild("Ammo")
        local needsTool = toolNeeded and toolNeeded:IsA("BoolValue") and toolNeeded.Value == true
        local passesTool = ammoFlag and ammoFlag:IsA("BoolValue") and ammoFlag.Value == true

        -- Mystery box ? (meme sans Required)
        local isBox = false
        if root.Name == "MBS" or root:FindFirstChild("Mystery Box Gui")
            or root:FindFirstChild("Mystery Box Gui", true) then
            isBox = true
        end
        if not isBox then
            for _, d in ipairs(root:GetDescendants()) do
                if d.Name == "Mystery Box Gui" or d.Name == "MBS" then
                    isBox = true
                    break
                end
            end
        end

        local remote = findRemoteNear(root)
        if not remote and (isBox or needsTool) then
            local p = root
            for _ = 1, 5 do
                if not p then break end
                remote = p:FindFirstChildWhichIsA("RemoteEvent")
                if remote then break end
                local ev = p:FindFirstChild("Event")
                if ev and ev:IsA("ObjectValue") and ev.Value and ev.Value:IsA("RemoteEvent") then
                    remote = ev.Value
                    break
                end
                p = p.Parent
            end
        end
        if not remote then return end

        if isBox then
            addEntry("Mystery Box", price > 0 and price or 950, remote, "BOX")
            return
        end

        -- Nom arme
        local text = ""
        local frame = root:FindFirstChild("Frame") or root:FindFirstChild("Frame", true)
        local weaponLbl = frame and (frame:FindFirstChild("Weapon") or frame:FindFirstChild("ContentText"))
        if not weaponLbl then
            for _, d in ipairs(root:GetDescendants()) do
                if d.Name == "Weapon" or d.Name == "ContentText" then
                    weaponLbl = d
                    break
                end
            end
        end
        text = readLabelText(weaponLbl)

        local toolName
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("Tool") then toolName = d.Name break end
        end
        if text == "" then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("TextLabel") and d.Text and #d.Text > 2 then
                    local n = extractWeaponName(d.Text)
                    if n and not isPerkOrDoor(n) then text = d.Text break end
                end
            end
        end

        local name = extractWeaponName(text) or toolName or root.Name
        if name == "MBS" or name == "Required" or name == "Key Pressed" then
            name = toolName or ("Pad " .. remote:GetFullName():sub(-20))
        end

        -- Pack-a-Punch : label pack/punch, cout 2500 + ToolNeeded, ou modele PAP
        local isPap = isPapLabel(name) or isPapLabel(text)
            or (price == 2500 and (needsTool or passesTool))
            or (price == 5000 and needsTool)
        if not isPap then
            local p = root
            for _ = 1, 8 do
                if not p then break end
                local pn = p.Name or ""
                if pn == "PAP" or pn == "PoolPAP" or pn == "OverPAP"
                    or isPapLabel(pn) then
                    isPap = true
                    break
                end
                p = p.Parent
            end
        end

        if isPap then
            addEntry("Pack-a-Punch", price > 0 and price or 2500, remote, "PAP")
            return
        end

        addEntry(name, price, remote, "WALL")
    end

    -- PlayerGui
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        for _, g in ipairs(pg:GetDescendants()) do
            if g.Name == "Required" and (g:IsA("IntValue") or g:IsA("NumberValue")) then
                considerRoot(g.Parent)
            end
            if g.Name == "Mystery Box Gui" then
                considerRoot(g.Parent)
            end
            if g.Name == "ToolNeeded" and g:IsA("BoolValue") and g.Value == true then
                considerRoot(g.Parent)
            end
        end
    end

    -- Workspace + Lighting
    for _, svc in ipairs({ Workspace, Lighting, game:GetService("ReplicatedStorage") }) do
        pcall(function()
            for _, d in ipairs(svc:GetDescendants()) do
                if d.Name == "Required" and (d:IsA("IntValue") or d:IsA("NumberValue")) then
                    considerRoot(d.Parent)
                elseif d.Name == "MBS" or d.Name == "Mystery Box Gui" then
                    considerRoot(d:IsA("ScreenGui") and d.Parent or d)
                elseif d.Name == "ToolNeeded" and d:IsA("BoolValue") and d.Value == true then
                    considerRoot(d.Parent)
                elseif d.Name == "PAP" or d.Name == "PoolPAP" or d.Name == "OverPAP" then
                    considerRoot(d)
                end
            end
        end)
    end

    pcall(function()
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d.Name == "MBS" then considerRoot(d) end
        end
    end)

    table.sort(M.wallBuys, function(a, b)
        if a.price == b.price then return a.name < b.name end
        return a.price < b.price
    end)

    -- catalogue : getgc d'abord ; require seulement en match
    loadWeaponCatalog(true)
    return M.wallBuys, M.boxPads, M.catalog, M.papPads
end

local function getBuyableLabels()
    local t = {}
    for _, b in ipairs(M.papPads) do t[#t + 1] = b.label end
    for _, b in ipairs(M.boxPads) do t[#t + 1] = b.label end
    for _, b in ipairs(M.wallBuys) do t[#t + 1] = b.label end
    -- catalogue coffre (noms seuls, pas de remote mur)
    for _, c in ipairs(M.catalog) do
        if not c.isPap then
            local lab = string.format("[Liste] %s", c.name)
            if not M.weaponIndex[lab] then
                M.weaponIndex[lab] = {
                    label = lab, name = c.name, price = 0,
                    remote = nil, kind = "CATALOG",
                }
            end
            t[#t + 1] = lab
        end
    end
    return t
end

local function buyWeapon(entry, givePointsFirst)
    if not entry then return false, "Entree invalide" end
    if entry.kind == "PAP" then
        local tool = getHeldGun()
        if not tool then return false, "Equipe une arme a feu d'abord." end
        local lvl, desc = getUpgradeLevel(tool)
        if lvl >= 2 then return true, "Deja MAX: " .. desc end
        if givePointsFirst then
            fireReward((entry.price or 2500) + 1000, false, nil)
            task.wait(0.2)
        end
        local ok = pcall(function()
            entry.remote:FireServer(true, tool, {})
        end)
        return ok, ok and ("PAP envoye sur " .. tool.Name) or "Echec PAP"
    end
    if entry.kind == "CATALOG" then
        -- Pas de remote direct : on spin un coffre si dispo
        if #M.boxPads == 0 then
            return false, "Arme coffre : aucun Mystery Box remote. Approche un coffre / rescan."
        end
        if givePointsFirst then
            fireReward(2000, false, nil)
            task.wait(0.2)
        end
        local box = M.boxPads[1]
        local ok = pcall(function() box.remote:FireServer(true, nil, {}) end)
        return ok, ok and ("Spin coffre envoye (random, vise: " .. entry.name .. ")") or "Echec spin coffre"
    end
    if not entry.remote then return false, "Remote introuvable" end
    if givePointsFirst then
        local need = (entry.price or 0) - getPoints()
        if need > 0 then
            fireReward(need + 500, false, nil)
            task.wait(0.2)
        elseif entry.price == 0 then
            fireReward(2000, false, nil)
            task.wait(0.15)
        end
    end
    local ok = pcall(function()
        entry.remote:FireServer(true, nil, {})
    end)
    return ok, ok and ("Achat envoye: " .. entry.name) or "Echec FireServer"
end

local function buyWeaponByLabel(label, givePointsFirst)
    if not label or label == "" then return false, "Aucune selection" end
    local e = M.weaponIndex[label]
    if e then return buyWeapon(e, givePointsFirst) end
    local low = tostring(label):lower()
    for _, b in ipairs(M.wallBuys) do
        if b.label == label or b.name == label then return buyWeapon(b, givePointsFirst) end
        if b.name:lower() == low or b.label:lower():find(low, 1, true) then
            return buyWeapon(b, givePointsFirst)
        end
    end
    for _, b in ipairs(M.boxPads) do
        if b.label == label or low:find("coffre", 1, true) or low:find("mystery", 1, true) or low:find("box", 1, true) then
            return buyWeapon(b, givePointsFirst)
        end
    end
    for lab, ent in pairs(M.weaponIndex) do
        if lab:lower():find(low, 1, true) or (ent.name and ent.name:lower() == low) then
            return buyWeapon(ent, givePointsFirst)
        end
    end
    -- arme liste seule : spin coffre
    for _, c in ipairs(M.catalog) do
        if not c.isPap and (c.name:lower() == low or c.name:lower():find(low, 1, true)) then
            return buyWeapon({
                label = "[Liste] " .. c.name, name = c.name, price = 0,
                remote = nil, kind = "CATALOG",
            }, givePointsFirst)
        end
    end
    return false, "Arme introuvable (resseanne)"
end

--============================================================--
--  PACK-A-PUNCH (upgrade arme tenue -> max = PAP + AAT)
--============================================================--
-- Jeu : machine ~2500 pts. FireServer(true, Tool, {}).
-- Tier 0 = base | Tier 1 = PAP (ISPAP) | Tier 2 = PAP + AAT (max).

local function pickPapMachine()
    if #M.papPads == 0 then scanWallBuys() end
    if #M.papPads == 0 then return nil end
    -- prend la machine la plus proche du joueur si possible
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return M.papPads[1] end
    local best, bestDist = M.papPads[1], math.huge
    for _, e in ipairs(M.papPads) do
        local part
        local root = e.remote and e.remote.Parent
        if root then
            part = root:IsA("BasePart") and root or root:FindFirstChildWhichIsA("BasePart", true)
        end
        if part then
            local d = (part.Position - hrp.Position).Magnitude
            if d < bestDist then
                bestDist = d
                best = e
            end
        end
    end
    return best
end

local function firePapUpgrade(pad, tool)
    if not pad or not pad.remote then return false end
    if not tool then return false end
    local ok = pcall(function()
        -- meme signature que Key Pressed : FireServer(true, Tool, {})
        pad.remote:FireServer(true, tool, {})
    end)
    return ok
end

local function waitUpgradeChange(prevName, prevLevel, timeout)
    timeout = timeout or 3.5
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local tool = getHeldGun()
        if tool then
            local lvl = getUpgradeLevel(tool)
            if lvl > prevLevel then return true, tool, lvl end
            if tool.Name ~= prevName then return true, tool, lvl end
            if tool:GetAttribute("AAT") then return true, tool, 2 end
        end
        task.wait(0.15)
    end
    local tool = getHeldGun()
    local lvl = getUpgradeLevel(tool)
    return false, tool, lvl
end

local function upgradeHeldOnce(givePoints)
    local tool = getHeldGun()
    if not tool then return false, "Equipe une arme a feu d'abord." end
    local lvl, desc = getUpgradeLevel(tool)
    if lvl >= 2 then return true, "Deja MAX: " .. desc end

    local pad = pickPapMachine()
    if not pad then
        return false, "Aucune machine PAP trouvee. Approche le Pack-a-Punch puis rescan."
    end

    local cost = pad.price or 2500
    if givePoints then
        local need = cost - getPoints()
        if need > 0 then
            fireReward(need + 500, false, nil)
            task.wait(0.25)
        else
            fireReward(cost + 500, false, nil)
            task.wait(0.15)
        end
    end

    local prevName = tool.Name
    local ok = firePapUpgrade(pad, tool)
    if not ok then return false, "Echec FireServer PAP" end

    local changed, newTool, newLvl = waitUpgradeChange(prevName, lvl, 4)
    if changed then
        local _, d2 = getUpgradeLevel(newTool)
        return true, "Upgrade OK -> " .. d2
    end
    return true, "PAP envoye (niveau encore: " .. desc .. "). Reessaie / attends l'anim."
end

local function upgradeHeldToMax(givePoints)
    local tool = getHeldGun()
    if not tool then return false, "Equipe une arme a feu d'abord." end
    local lvl, desc = getUpgradeLevel(tool)
    if lvl >= 2 then return true, "Deja MAX: " .. desc end

    local pad = pickPapMachine()
    if not pad then
        return false, "Aucune machine PAP. Approche Pack-a-Punch / rescan."
    end

    -- Max = 2 paliers (PAP puis AAT). On tente jusqu'a 4 fois au cas ou.
    local maxTries = 4
    local reports = {}
    for i = 1, maxTries do
        tool = getHeldGun()
        if not tool then
            reports[#reports + 1] = "arme perdue mid-upgrade"
            break
        end
        lvl = getUpgradeLevel(tool)
        if lvl >= 2 then break end

        local cost = pad.price or 2500
        if givePoints then
            fireReward(math.max(cost + 1000, 3000), false, nil)
            task.wait(0.2)
        end

        local prevName = tool.Name
        local prevLvl = lvl
        firePapUpgrade(pad, tool)
        local changed, newTool, newLvl = waitUpgradeChange(prevName, prevLvl, 3.5)
        tool = newTool or getHeldGun()
        lvl = newLvl or getUpgradeLevel(tool)
        reports[#reports + 1] = string.format(
            "#%d %s -> lvl%d %s",
            i, prevName, lvl, changed and "OK" or "wait"
        )
        if lvl >= 2 then break end
        task.wait(0.45)
    end

    tool = getHeldGun()
    local finalLvl, finalDesc = getUpgradeLevel(tool)
    local summary = table.concat(reports, " | ")
    if finalLvl >= 2 then
        return true, "MAX atteint: " .. finalDesc
    end
    return true, "Fini lvl" .. tostring(finalLvl) .. " (" .. finalDesc .. "). " .. summary
end

--============================================================--
--  POINTS AUTO (Rewards9 loop)
--============================================================--
M.state.pointsAmount = 30000
M.state.pointsAuto = false

task.spawn(function()
    while true do
        if M.state.pointsAuto then
            fireReward(M.state.pointsAmount, false, nil)
            task.wait(1)
        else
            task.wait(0.25)
        end
    end
end)

--============================================================--
--  FOV CIRCLE
--============================================================--
local fovCircleObj = safe(function()
    local c = Drawing.new("Circle")
    c.Thickness = 1.5
    c.NumSides = 64
    c.Filled = false
    c.Visible = false
    c.Transparency = 1
    return c
end)

RunService.RenderStepped:Connect(function()
    if fovCircleObj then
        if M.state.fovCircle then
            fovCircleObj.Visible = true
            fovCircleObj.Radius = M.state.multi and M.state.multiFov or M.state.fov
            fovCircleObj.Color = M.state.fovColor
            fovCircleObj.Position = screenCenter()
        else
            fovCircleObj.Visible = false
        end
    end
end)

--============================================================--
--  ESP (Drawing)
--============================================================--
local BONES = {
    {"Head","UpperTorso"}, {"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"}, {"LeftUpperArm","LeftLowerArm"}, {"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"}, {"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"}, {"LeftUpperLeg","LeftLowerLeg"}, {"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"}, {"RightLowerLeg","RightFoot"},
    -- R6 fallback
    {"Head","Torso"}, {"Torso","Left Arm"}, {"Torso","Right Arm"},
    {"Torso","Left Leg"}, {"Torso","Right Leg"},
}

local function newText()
    return safe(function()
        local t = Drawing.new("Text")
        t.Size = 14
        t.Center = true
        t.Outline = true
        t.Visible = false
        return t
    end)
end

local function newSquare(color)
    return safe(function()
        local s = Drawing.new("Square")
        s.Thickness = 1.6
        s.Filled = false
        s.Color = color or Color3.new(1,1,1)
        s.Transparency = 1
        s.Visible = false
        return s
    end)
end

local function makeEspObj()
    return {
        box     = newSquare(Color3.new(1,1,1)),
        name    = newText(),
        health  = newText(),
        dist    = newText(),
        tracer  = newLine(Color3.new(1,1,1), 1.4),
        snap    = newLine(Color3.new(1,1,1), 1.4),
        bones   = {},
    }
end

local function hideEsp(o)
    if o.box then o.box.Visible = false end
    if o.name then o.name.Visible = false end
    if o.health then o.health.Visible = false end
    if o.dist then o.dist.Visible = false end
    if o.tracer then o.tracer.Visible = false end
    if o.snap then o.snap.Visible = false end
    for _, b in pairs(o.bones) do b.Visible = false end
end

local function removeEsp(o)
    hideEsp(o)
    pcall(function() if o.box then o.box:Remove() end end)
    pcall(function() if o.name then o.name:Remove() end end)
    pcall(function() if o.health then o.health:Remove() end end)
    pcall(function() if o.dist then o.dist:Remove() end end)
    pcall(function() if o.tracer then o.tracer:Remove() end end)
    pcall(function() if o.snap then o.snap:Remove() end end)
    for _, b in pairs(o.bones) do pcall(function() b:Remove() end) end
end

-- ESP principal
RunService.RenderStepped:Connect(function()
    -- reset used flag
    for _, o in pairs(M.espCache) do o._used = false end

    if M.state.esp then
        local hrp = getHRP()
        local myPos = hrp and hrp.Position or Camera.CFrame.Position
        local center = screenCenter()
        local vpBottom = Vector2.new(center.X, Camera.ViewportSize.Y)

        -- cibles = zombies
        local targets = {}
        for _, z in ipairs(getZombies()) do
            targets[#targets+1] = { model = z.model, hum = z.hum, root = z.root, ally = false }
        end
        -- allies (autres joueurs) si teamCheck off -> on peut les afficher en bleu
        if not M.state.teamCheck then
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl ~= LocalPlayer and pl.Character then
                    local hum = pl.Character:FindFirstChildOfClass("Humanoid")
                    local root = rootOf(pl.Character, hum)
                    if hum and root and hum.Health > 0 then
                        targets[#targets+1] = { model = pl.Character, hum = hum, root = root, ally = true }
                    end
                end
            end
        end

        for _, tg in ipairs(targets) do
            local model = tg.model
            local o = M.espCache[model]
            if not o then o = makeEspObj(); M.espCache[model] = o end
            o._used = true

            local root = tg.root
            local head = model:FindFirstChild("Head") or root
            local dist = (root.Position - myPos).Magnitude
            local color = tg.ally and M.state.allyColor or M.state.espColor

            if dist <= M.state.espMaxDist then
                local headTop = head.Position + Vector3.new(0, 1.5, 0)
                local footPos = root.Position - Vector3.new(0, 3, 0)
                local topS, onTop = toScreen(headTop)
                local botS, onBot = toScreen(footPos)
                local rootS, onRoot = toScreen(root.Position)

                if onTop or onBot or onRoot then
                    local h = math.abs(topS.Y - botS.Y)
                    local w = h * 0.6
                    local cx = rootS.X

                    -- Box (rectangle)
                    if M.state.espBox and o.box then
                        o.box.Visible = true
                        o.box.Color = color
                        o.box.Size = Vector2.new(w, h)
                        o.box.Position = Vector2.new(cx - w / 2, topS.Y)
                    elseif o.box then o.box.Visible = false end

                    -- Name
                    if M.state.espName and o.name then
                        o.name.Visible = true
                        o.name.Color = color
                        o.name.Position = Vector2.new(cx, topS.Y - 16)
                        o.name.Text = tg.ally and ("[ALLIE] " .. (model.Name or "")) or (model.Name or "Zombie")
                    elseif o.name then o.name.Visible = false end

                    -- Health
                    if M.state.espHealth and o.health then
                        o.health.Visible = true
                        o.health.Color = color
                        o.health.Position = Vector2.new(cx, botS.Y + 2)
                        o.health.Text = string.format("HP %d", math.floor(tg.hum.Health))
                    elseif o.health then o.health.Visible = false end

                    -- Distance
                    if M.state.espDistance and o.dist then
                        o.dist.Visible = true
                        o.dist.Color = color
                        o.dist.Position = Vector2.new(cx, botS.Y + 16)
                        o.dist.Text = string.format("%dm", math.floor(dist))
                    elseif o.dist then o.dist.Visible = false end

                    -- Tracer (bas ecran -> cible)
                    if M.state.espTracer and o.tracer then
                        o.tracer.Visible = true
                        o.tracer.Color = color
                        o.tracer.From = vpBottom
                        o.tracer.To = rootS
                    elseif o.tracer then o.tracer.Visible = false end

                    -- Snapline (centre ecran -> tete)
                    if M.state.espSnapline and o.snap then
                        o.snap.Visible = true
                        o.snap.Color = color
                        o.snap.From = center
                        o.snap.To = topS
                    elseif o.snap then o.snap.Visible = false end

                    -- Skeleton
                    if M.state.espSkeleton then
                        local bi = 0
                        for _, pair in ipairs(BONES) do
                            local p0 = model:FindFirstChild(pair[1])
                            local p1 = model:FindFirstChild(pair[2])
                            if p0 and p1 then
                                bi = bi + 1
                                local b = o.bones[bi]
                                if not b then b = newLine(color, 1.4); o.bones[bi] = b end
                                if b then
                                    local s0, v0 = toScreen(p0.Position)
                                    local s1, v1 = toScreen(p1.Position)
                                    if v0 or v1 then
                                        b.Color = color
                                        b.From = s0
                                        b.To = s1
                                        b.Visible = true
                                    else b.Visible = false end
                                end
                            end
                        end
                        for j = bi + 1, #o.bones do o.bones[j].Visible = false end
                    else
                        for _, b in pairs(o.bones) do b.Visible = false end
                    end
                else
                    hideEsp(o)
                end
            else
                hideEsp(o)
            end
        end
    end

    -- nettoyage des objets non utilises
    for model, o in pairs(M.espCache) do
        if not o._used or not model.Parent then
            removeEsp(o)
            M.espCache[model] = nil
        end
    end
end)

--============================================================--
--  PLAYER : mouvement
--============================================================--
local function refillAllGuns()
    local function bump(root)
        if not root then return end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("IntValue") or d:IsA("NumberValue") then
                local n = string.lower(d.Name)
                if n:find("ammo", 1, true) or n == "extra" or n:find("clip", 1, true)
                    or n == "mag" or n == "reserve" or n == "stock" then
                    pcall(function()
                        d.Value = math.max(tonumber(d.Value) or 0, 999)
                    end)
                end
            end
        end
    end
    bump(getChar())
    bump(LocalPlayer:FindFirstChild("Backpack"))
    local ma = Lighting:FindFirstChild("Max Ammo")
    if ma and ma:IsA("RemoteEvent") then
        pcall(function() ma:FireServer() end)
        pcall(function() ma:FireServer(true) end)
    end
end

local function boostExtraInfinite()
    refillAllGuns()
end

task.spawn(function()
    while true do
        if M.state.infAmmo then
            refillAllGuns()
            task.wait(0.2)
        else
            task.wait(0.3)
        end
    end
end)

--============================================================--
--  FLY (onglet Player) — BodyVelocity + option CFrame, noclip
--============================================================--
local flyCtl = { F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0 }
local flyFlying = false
local flyGyro, flyVel, flyCFloop, flyNoclip

local function flyCharParts()
    return getChar(), getHum(), getHRP()
end

local function flyNoclipLoop()
    local ch = getChar()
    if not ch then return end
    for _, child in ipairs(ch:GetDescendants()) do
        if child:IsA("BasePart") and child.CanCollide then
            child.CanCollide = false
        end
    end
end

local function flyApplyGhost(on)
    local ch = getChar()
    if not ch then return end
    local t = on and M.state.flyTransparency or 0
    for _, part in ipairs(ch:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            part.Transparency = t
        end
        if part:IsA("BasePart") and not on then
            part.CanCollide = true
        end
    end
end

local function flyStopMovers()
    flyFlying = false
    if flyCFloop then flyCFloop:Disconnect(); flyCFloop = nil end
    if flyNoclip then flyNoclip:Disconnect(); flyNoclip = nil end
    local ch = getChar()
    if ch then
        local head = ch:FindFirstChild("Head")
        if head then head.Anchored = false end
    end
    if flyGyro then pcall(function() flyGyro:Destroy() end); flyGyro = nil end
    if flyVel then pcall(function() flyVel:Destroy() end); flyVel = nil end
    local hum = getHum()
    if hum then hum.PlatformStand = false end
    flyCtl = { F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0 }
    flyApplyGhost(false)
end

local function startCFrameFlyLoop()
    local ch, hum = flyCharParts()
    if not ch or not ch:FindFirstChild("Head") or not hum then return end
    flyFlying = true
    local Head = ch.Head
    Head.Anchored = true
    for _, part in ipairs(ch:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end
    flyCFloop = RunService.Heartbeat:Connect(function(deltaTime)
        if not M.state.fly then return end
        ch = getChar(); hum = getHum()
        if not ch or not ch:FindFirstChild("Head") or not hum then return end
        Head = ch.Head
        local effectiveSpeed = M.state.flySpeed * 10
        local moveDirection = hum.MoveDirection * (effectiveSpeed * deltaTime)
        local headCFrame = Head.CFrame
        local camera = Workspace.CurrentCamera
        local cameraCFrame = camera.CFrame
        local cameraOffset = headCFrame:ToObjectSpace(cameraCFrame).Position
        cameraCFrame = cameraCFrame * CFrame.new(-cameraOffset.X, -cameraOffset.Y, -cameraOffset.Z + 1)
        local cameraPosition, headPosition = cameraCFrame.Position, headCFrame.Position
        local objectSpaceVelocity = CFrame.new(cameraPosition, Vector3.new(headPosition.X, cameraPosition.Y, headPosition.Z)):VectorToObjectSpace(moveDirection)
        Head.CFrame = CFrame.new(headPosition) * (cameraCFrame - cameraPosition) * CFrame.new(objectSpaceVelocity)
    end)
end

local function startBodyMoverFlyLoop()
    local ch, hum, root = flyCharParts()
    if not ch or not root or not hum then return end
    flyFlying = true
    flyNoclip = RunService.Heartbeat:Connect(flyNoclipLoop)
    task.spawn(function()
        flyGyro = Instance.new("BodyGyro")
        flyGyro.P = 9e4
        flyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        flyGyro.CFrame = root.CFrame
        flyGyro.Parent = root
        flyVel = Instance.new("BodyVelocity")
        flyVel.Velocity = Vector3.new(0, 0, 0)
        flyVel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        flyVel.Parent = root
        hum.PlatformStand = true
        repeat
            task.wait()
            root = getHRP(); hum = getHum()
            if not (flyFlying and root and root.Parent) then break end
            local camera = Workspace.CurrentCamera
            local moveVector = ((camera.CFrame.LookVector * (flyCtl.F + flyCtl.B))
                + ((camera.CFrame * CFrame.new((flyCtl.L + flyCtl.R), (flyCtl.Q + flyCtl.E) * 0.2, 0).p) - camera.CFrame.p))
            flyVel.Velocity = moveVector.Magnitude > 0 and moveVector.Unit * M.state.flySpeed or Vector3.new(0, 0, 0)
            flyGyro.CFrame = camera.CFrame
        until not flyFlying or not root or not root.Parent
        flyStopMovers()
    end)
end

local function setFlying(state)
    M.state.fly = state and true or false
    local ch = getChar()
    if not ch or not ch.Parent then
        flyStopMovers()
        return
    end
    if not state then
        flyStopMovers()
        return
    end
    flyStopMovers()
    M.state.fly = true
    flyApplyGhost(true)
    if M.state.flyCFrame then
        startCFrameFlyLoop()
    else
        startBodyMoverFlyLoop()
    end
end

local flyKeys = {
    [Enum.KeyCode.W] = { "F", 1 },
    [Enum.KeyCode.S] = { "B", -1 },
    [Enum.KeyCode.A] = { "L", -1 },
    [Enum.KeyCode.D] = { "R", 1 },
    [Enum.KeyCode.Q] = { "Q", -1 },
    [Enum.KeyCode.E] = { "E", 1 },
}
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or not M.state.fly then return end
    local k = flyKeys[input.KeyCode]
    if k then flyCtl[k[1]] = k[2] end
end)
UserInputService.InputEnded:Connect(function(input)
    local k = flyKeys[input.KeyCode]
    if k then flyCtl[k[1]] = 0 end
end)

LocalPlayer.CharacterAdded:Connect(function()
    flyStopMovers()
    task.wait(0.4)
    if M.state.fly then
        setFlying(true)
    end
end)

--============================================================--
--  UI (Rayfield)
--============================================================--
-- Hook leger des le load (ne touche PAS WeaponModule / GunInfo / scan)
-- Features combat restent OFF tant que les toggles ne sont pas actives
pcall(setupHook)
task.spawn(function()
    for _ = 1, 25 do
        if M.hooked then break end
        task.wait(0.4)
        pcall(setupHook)
    end
end)

local Rayfield = (typeof(getgenv) == "function" and getgenv().XHubRayfield) or nil
if not (type(Rayfield) == "table" and Rayfield.CreateWindow) then
    local sources = {
        "https://xhub.blog/lua/rayfield.lua",
        "https://xhub-vanguard.vercel.app/lua/rayfield.lua",
        "https://sirius.menu/rayfield",
        "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
    }
    local function httpGet(url)
        local ok, body = pcall(function() return game:HttpGet(url, true) end)
        if ok and type(body) == "string" and #body > 100 then return body end
        ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and type(body) == "string" and #body > 100 then return body end
        for _, fn in ipairs({ request, http_request }) do
            if typeof(fn) == "function" then
                ok, body = pcall(function()
                    local r = fn({ Url = url, Method = "GET" })
                    return r and r.Body
                end)
                if ok and type(body) == "string" and #body > 100 then return body end
            end
        end
        if syn and typeof(syn.request) == "function" then
            ok, body = pcall(function()
                local r = syn.request({ Url = url, Method = "GET" })
                return r and r.Body
            end)
            if ok and type(body) == "string" and #body > 100 then return body end
        end
        return nil
    end
    for _, src in ipairs(sources) do
        local body = httpGet(src)
        if body then
            local fn = loadstring(body)
            if type(fn) == "function" then
                local ok, lib = pcall(fn)
                if ok and type(lib) == "table" and lib.CreateWindow then
                    Rayfield = lib
                    break
                end
            end
        end
    end
end
if not Rayfield then
    warn("[Reminiscence Zombies] Rayfield introuvable")
    return
end
if typeof(getgenv) == "function" then getgenv().XHubRayfield = Rayfield end

-- ===== THEME FULL BLANC =====
local XHUB_THEME = {
    TextColor = Color3.fromRGB(20, 20, 20),
    Background = Color3.fromRGB(255, 255, 255),
    Topbar = Color3.fromRGB(255, 255, 255),
    Shadow = Color3.fromRGB(210, 210, 210),
    NotificationBackground = Color3.fromRGB(255, 255, 255),
    NotificationActionsBackground = Color3.fromRGB(255, 255, 255),
    TabBackground = Color3.fromRGB(245, 245, 245),
    TabStroke = Color3.fromRGB(210, 210, 210),
    TabBackgroundSelected = Color3.fromRGB(255, 255, 255),
    TabTextColor = Color3.fromRGB(40, 40, 40),
    SelectedTabTextColor = Color3.fromRGB(0, 0, 0),
    ElementBackground = Color3.fromRGB(255, 255, 255),
    ElementBackgroundHover = Color3.fromRGB(240, 240, 240),
    SecondaryElementBackground = Color3.fromRGB(250, 250, 250),
    ElementStroke = Color3.fromRGB(210, 210, 210),
    SecondaryElementStroke = Color3.fromRGB(220, 220, 220),
    SliderBackground = Color3.fromRGB(230, 230, 230),
    SliderProgress = Color3.fromRGB(30, 30, 30),
    SliderStroke = Color3.fromRGB(40, 40, 40),
    ToggleBackground = Color3.fromRGB(235, 235, 235),
    ToggleEnabled = Color3.fromRGB(20, 20, 20),
    ToggleDisabled = Color3.fromRGB(220, 220, 220),
    ToggleEnabledStroke = Color3.fromRGB(0, 0, 0),
    ToggleDisabledStroke = Color3.fromRGB(190, 190, 190),
    ToggleEnabledOuterStroke = Color3.fromRGB(180, 180, 180),
    ToggleDisabledOuterStroke = Color3.fromRGB(200, 200, 200),
    DropdownSelected = Color3.fromRGB(245, 245, 245),
    DropdownUnselected = Color3.fromRGB(255, 255, 255),
    InputBackground = Color3.fromRGB(255, 255, 255),
    InputStroke = Color3.fromRGB(200, 200, 200),
    PlaceholderColor = Color3.fromRGB(140, 140, 140),
}
local I18N = {
    fr = {
        ["win.name"] = "XHUB · Reminiscence",
        ["win.sub"] = "Combat · Argent · Armes · Vol",
        ["tab.lang"] = "Langue",
        ["tab.guide"] = "Guide",
        ["tab.combat"] = "Combat",
        ["tab.money"] = "Argent",
        ["tab.ammo"] = "Munitions",
        ["tab.guns"] = "Armes",
        ["tab.vision"] = "Vision",
        ["tab.fly"] = "Vol",
        ["tab.server"] = "Serveur",
        ["lang.howTitle"] = "Changer la langue du menu",
        ["lang.howBody"] = "Clique Francais ou English (ou une autre langue). TOUS les onglets et TOUS les boutons changent. Tes options (Aimbot, Fly...) restent allumees.",
        ["lang.pick"] = "Ou choisis dans la liste",
        ["guide.tabsTitle"] = "Les onglets (en haut)",
        ["guide.tabsBody"] = "Combat = tuer.   Argent = points (30 000 par zombie).   Munitions = bientot.   Armes = bientot.   Vision = voir les zombies.   Vol = voler.   Serveur = relancer.",
        ["guide.startTitle"] = "Tu debutes ? Fais juste ca",
        ["guide.startBody"] = "1) Clique Combat.  2) Allume Aura (tue autour de toi) OU Silent Aim (reste clic gauche appuye).  3) Tire 1 vraie balle au debut.  4) Argent = 30 000 points par zombie tue.  5) Vol = voler.",
        ["combat.howTitle"] = "Choisis UN mode (ou plusieurs)",
        ["combat.howBody"] = "Silent Aim = tu restes clic gauche, ca vise pour toi.   Aura = ca tape tout autour, sans viser.   Tout tuer = plus besoin de tirer.   Tire 1 balle au debut, sinon les degats sont trop faibles.   Chaque zombie tue = 30 000 points.",

        ["combat.silentTitle"] = "SILENT AIM",
        ["combat.silentBody"] = "Allume SILENT AIM en dessous, puis RESTE clic gauche. Ca vise pour toi sans bouger le viseur.",
        ["combat.secSilent"] = "Silent Aim",
        ["combat.secKill"] = "Tuer",
        ["combat.aimbot"] = "Silent Aim — vise pour toi (reste clic gauche)",
        ["combat.multi"] = "Multi — touche TOUS les zombies devant toi",
        ["combat.aura"] = "Aura — tue autour de toi (sans viser)",
        ["combat.trigger"] = "Auto-tir — tire tout seul sur le zombie au centre",
        ["combat.killAll"] = "Tout tuer — tous les zombies meurent tout seuls",
        ["combat.killNow"] = "Tuer tout le monde MAINTENANT (1 fois)",
        ["combat.secSet"] = "Reglages (tu peux tout laisser comme ca)",
        ["combat.aimWhere"] = "Ou viser sur le zombie",
        ["aim.head"] = "Tete",
        ["aim.body"] = "Corps",
        ["aim.chest"] = "Poitrine",
        ["aim.torso"] = "Torse",
        ["combat.fov"] = "Zone de visee Aimbot (plus grand = plus facile)",
        ["combat.multiFov"] = "Zone de visee Multi",
        ["combat.multiRange"] = "Distance max Multi",
        ["combat.auraRange"] = "Distance de l'aura",
        ["combat.dmg"] = "Force des degats (1 = normal, 20 = tres fort)",
        ["combat.visible"] = "Aimbot : seulement les zombies que tu VOIS (pas a travers le mur)",
        ["combat.aimRate"] = "Vitesse Aimbot (clic maintenu)",
        ["combat.trigFov"] = "Precision auto-tir (plus grand = plus facile)",
        ["combat.trigRate"] = "Vitesse auto-tir",
        ["combat.trigClick"] = "Auto-tir : cliquer aussi avec la souris",
        ["combat.tracer"] = "Ligne verte = confirmation du tir",
        ["combat.tracerColor"] = "Couleur de la ligne",
        ["combat.fovCircle"] = "Cercle a l'ecran (montre la zone de visee)",
        ["combat.killRate"] = "Tout tuer : vitesse (laisse 1 si tu sais pas)",
        ["money.howTitle"] = "Comment avoir des points",
        ["money.howBody"] = "Chaque zombie que tu tues (Aimbot / Aura / Tout tuer) = 30 000 points. Tu peux aussi Ajouter un montant, ou Auto toutes les secondes. Ca sert a ouvrir les portes et acheter les armes.",
        ["money.secKills"] = "Points quand tu tues (30 000 / zombie)",
        ["money.autoReward"] = "Gagner 30 000 points par zombie (Aimbot / Aura)",
        ["money.killAllReward"] = "Gagner 30 000 aussi avec Tout tuer (Combat)",
        ["money.secGive"] = "Donner des points",
        ["money.amount"] = "Combien d'argent (ecris un nombre)",
        ["money.amountPh"] = "exemple : 30000",
        ["money.slider"] = "Ou choisis avec le curseur",
        ["money.add"] = "Ajouter l'argent (1 fois)",
        ["money.auto"] = "Ajouter tout seul toutes les secondes",
        ["ammo.howTitle"] = "Bientot disponible",
        ["ammo.howBody"] = "Les munitions infinies arrivent bientot. Cet onglet n'est pas encore actif.",
        ["ammo.inf"] = "Munitions infinies — plus jamais a recharger",
        ["ammo.fill"] = "Remplir les armes maintenant (1 fois)",
        ["guns.howTitle"] = "Bientot disponible",
        ["guns.howBody"] = "Les armes (mur, coffre, PAP) arrivent bientot. Cet onglet n'est pas encore actif.",
        ["guns.result"] = "Resultat",
        ["guns.needScan"] = "Pas encore cherche. Clique Chercher les armes.",
        ["guns.waitLobby"] = "Pas encore en partie. Attends que les zombies / murs apparaissent, puis Chercher.",
        ["guns.noneFound"] = "0 arme. Approche un mur, le coffre ou la machine PAP, puis Chercher.",
        ["guns.none"] = "(aucune arme)",
        ["guns.needPick"] = "(Chercher d'abord)",
        ["guns.scanFmt"] = "%d armes | Mur %d | Coffre %d | PAP %d | Liste %d\nArme en main: %s\n%s%s",
        ["guns.more"] = "\n... +%s autres",
        ["guns.notifyFound"] = "%d armes (mur %d, coffre %d, PAP %d)",
        ["guns.scan"] = "Chercher les armes (murs + coffre)",
        ["guns.pick"] = "Choisis l'arme ici",
        ["guns.type"] = "Ou ecris le nom de l'arme",
        ["guns.namePh"] = "ex: M14 ou Ray Gun",
        ["guns.buy"] = "Acheter l'arme choisie (avec tes points)",
        ["guns.free"] = "Acheter gratuitement (donne l'argent + l'arme)",
        ["guns.box"] = "Ouvrir le coffre mystere (1 fois)",
        ["guns.allWalls"] = "Acheter TOUTES les armes au mur",
        ["guns.papSec"] = "Ameliorer l'arme (Pack-a-Punch)",
        ["guns.papHowTitle"] = "Comment ameliorer",
        ["guns.papHowBody"] = "Prends l'arme en main, approche la machine PAP, clique Chercher si besoin, puis Ameliorer au maximum. Ca donne PAP puis l'effet (ex: Dead Wire).",
        ["guns.papScan"] = "Chercher la machine PAP",
        ["guns.up1"] = "Ameliorer 1 fois (arme en main)",
        ["guns.upMax"] = "Ameliorer au maximum",
        ["guns.status"] = "Voir si mon arme est amelioree",
        ["guns.enterMatch"] = "Entre en partie (zombies / murs), puis clique Chercher les armes.",
        ["esp.howTitle"] = "Voir les zombies",
        ["esp.howBody"] = "Allume Voir a travers les murs. Tu vois nom, vie et distance. Les lignes sont optionnelles.",
        ["esp.on"] = "Voir a travers les murs",
        ["esp.name"] = "Afficher le nom",
        ["esp.hp"] = "Afficher la vie",
        ["esp.dist"] = "Afficher la distance",
        ["esp.skel"] = "Dessiner les os du zombie",
        ["esp.tracer"] = "Ligne depuis le bas de l'ecran",
        ["esp.snap"] = "Ligne depuis le viseur vers la tete",
        ["esp.team"] = "Cacher tes coequipiers (ne montrer que les zombies)",
        ["esp.max"] = "Distance max",
        ["esp.zcolor"] = "Couleur des zombies",
        ["esp.acolor"] = "Couleur des allies",
        ["fly.howTitle"] = "Comment voler",
        ["fly.howBody"] = "Allume Voler. ZQSD / WASD = bouger. Q = descendre, E = monter. Si tu vas trop lentement, monte la vitesse (essaie 50). Mode 2 = seulement si le vol normal bug.",
        ["fly.on"] = "Voler",
        ["fly.mode2"] = "Mode 2 (si le vol normal bug)",
        ["fly.speed"] = "Vitesse (1 = lent, 50 = rapide, 200 = tres rapide)",
        ["fly.alpha"] = "Perso transparent en volant",
        ["srv.howTitle"] = "Si un truc marche plus",
        ["srv.howBody"] = "Relancer la partie = tu reviens dans la meme map.  Recoller le script = si Combat ne tue plus.",
        ["srv.rejoin"] = "Relancer la partie (meme map)",
        ["srv.rehook"] = "Recoller le script (si Combat ne tue plus)",
        ["srv.waitGuns"] = "Attendre la partie + chercher les armes",
        ["srv.count"] = "Combien de zombies la ?",
        ["n.aura"] = "Aura",
        ["n.auraBody"] = "Tire 1 balle une fois, ensuite l'aura tape plus fort.",
        ["n.trigger"] = "Auto-tir",
        ["n.triggerBody"] = "Regarde un zombie. Tire 1 balle d'abord.",
        ["n.killAll"] = "Tout tuer",
        ["n.killOn"] = "ON. %s tues + les prochains aussi.",
        ["n.killOff"] = "OFF.",
        ["n.killed"] = "%s zombie(s) tues.",
        ["n.money"] = "Argent",
        ["n.moneyAdd"] = "+%s points.",
        ["n.autoOn"] = "AUTO ON : +%s / s",
        ["n.autoOff"] = "AUTO OFF",
        ["n.ammo"] = "Munitions",
        ["n.ammoOn"] = "ON — tes armes se remplissent.",
        ["n.ammoOff"] = "OFF.",
        ["n.ammoFill"] = "Remplissage envoye.",
        ["n.guns"] = "Armes",
        ["n.enterFirst"] = "Entre en partie d'abord, puis Chercher les armes.",
        ["n.noneFound"] = "Rien trouve. Approche un mur puis Chercher.",
        ["n.scanWait"] = "Attente de la partie (max 20s)...",
        ["n.pickFirst"] = "Cherche les armes, puis choisis-en une.",
        ["n.pickOne"] = "Choisis une arme dans la liste.",
        ["n.noBox"] = "Aucun coffre. Approche le Mystery Box puis Chercher.",
        ["n.wallsBought"] = "%s arme(s) de mur achetee(s).",
        ["n.pap"] = "PAP",
        ["n.noPap"] = "0 machine. Approche le Pack-a-Punch puis Chercher.",
        ["n.papFound"] = "%s machine(s) trouvee(s).",
        ["n.held"] = "Arme en main: %s",
        ["n.papBusy"] = "Amelioration max en cours...",
        ["n.noGun"] = "Aucune arme en main.",
        ["n.gunStat"] = "%s | niveau %d | %s%s",
        ["n.effect"] = " | effet=%s",
        ["n.fly"] = "Vol",
        ["n.flyOn"] = "ON — vitesse %s",
        ["n.flyOff"] = "OFF",
        ["n.mode2"] = "Mode 2 ON",
        ["n.modeNorm"] = "Mode normal",
        ["n.script"] = "Script",
        ["n.okCombat"] = "OK, Combat pret",
        ["n.notReady"] = "Pas pret",
        ["n.remoteOk"] = " | remote OK",
        ["n.noRemote"] = " | remote introuvable",
        ["n.waitPart"] = "Attente de la partie...",
        ["n.notInMatch"] = "Pas encore en partie. Reessaie une fois les zombies / murs la.",
        ["n.zombies"] = "Zombies",
        ["n.zcount"] = "%s zombie(s).",
        ["n.readyTitle"] = "XHUB",
        ["n.readyBody"] = "Pret. Langue = FR/EN. Combat = tuer (30k / zombie). Argent = points. Vol = voler.",
        ["n.langTitle"] = "Langue",
        ["n.langBody"] = "Menu entier en Francais.",
    },
    en = {
        ["win.name"] = "XHUB · Reminiscence",
        ["win.sub"] = "Combat · Money · Guns · Fly",
        ["tab.lang"] = "Language",
        ["tab.guide"] = "Guide",
        ["tab.combat"] = "Combat",
        ["tab.money"] = "Money",
        ["tab.ammo"] = "Ammo",
        ["tab.guns"] = "Guns",
        ["tab.vision"] = "ESP",
        ["tab.fly"] = "Fly",
        ["tab.server"] = "Server",
        ["lang.howTitle"] = "Change the whole menu language",
        ["lang.howBody"] = "Click Francais or English (or another language). EVERY tab and EVERY button updates. Your toggles (Aimbot, Fly...) stay on.",
        ["lang.pick"] = "Or pick from the list",
        ["guide.tabsTitle"] = "The tabs (at the top)",
        ["guide.tabsBody"] = "Combat = kill.   Money = points (30,000 per zombie).   Ammo = coming soon.   Guns = coming soon.   ESP = see zombies.   Fly = fly.   Server = rejoin.",
        ["guide.startTitle"] = "New here? Do this",
        ["guide.startBody"] = "1) Open Combat.  2) Turn on Aura (kills around you) OR Silent Aim (hold left click).  3) Fire 1 real bullet first.  4) Money = 30,000 points per zombie killed.  5) Fly tab to fly.",
        ["combat.howTitle"] = "Pick ONE mode (or several)",
        ["combat.howBody"] = "Silent Aim = hold left click, it aims for you.   Aura = hits around you, no aim.   Kill all = no shooting needed.   Fire 1 bullet first or damage is too low.   Each zombie killed = 30,000 points.",

        ["combat.silentTitle"] = "SILENT AIM",
        ["combat.silentBody"] = "Turn on SILENT AIM below, then HOLD left click. It aims for you without moving your crosshair.",
        ["combat.secSilent"] = "Silent Aim",
        ["combat.secKill"] = "Kill",
        ["combat.aimbot"] = "Silent Aim — aims for you (hold left click)",
        ["combat.multi"] = "Multi — hit ALL zombies in front of you",
        ["combat.aura"] = "Aura — kills around you (no aiming)",
        ["combat.trigger"] = "Auto-fire — shoots the zombie in the center",
        ["combat.killAll"] = "Kill all — every zombie dies by itself",
        ["combat.killNow"] = "Kill everyone NOW (once)",
        ["combat.secSet"] = "Settings (you can leave these)",
        ["combat.aimWhere"] = "Where to aim on the zombie",
        ["aim.head"] = "Head",
        ["aim.body"] = "Body",
        ["aim.chest"] = "Chest",
        ["aim.torso"] = "Torso",
        ["combat.fov"] = "Aimbot aim zone (bigger = easier)",
        ["combat.multiFov"] = "Multi aim zone",
        ["combat.multiRange"] = "Max Multi distance",
        ["combat.auraRange"] = "Aura distance",
        ["combat.dmg"] = "Damage strength (1 = normal, 20 = very strong)",
        ["combat.visible"] = "Aimbot: only zombies you SEE (not through walls)",
        ["combat.aimRate"] = "Aimbot speed (while holding click)",
        ["combat.trigFov"] = "Auto-fire precision (bigger = easier)",
        ["combat.trigRate"] = "Auto-fire speed",
        ["combat.trigClick"] = "Auto-fire: also click the mouse",
        ["combat.tracer"] = "Green line = shot confirmation",
        ["combat.tracerColor"] = "Line color",
        ["combat.fovCircle"] = "On-screen circle (shows aim zone)",
        ["combat.killRate"] = "Kill all: speed (leave at 1 if unsure)",
        ["money.howTitle"] = "How to get points",
        ["money.howBody"] = "Each zombie you kill (Aimbot / Aura / Kill all) = 30,000 points. You can also Add an amount, or Auto every second. Used to open doors and buy guns.",
        ["money.secKills"] = "Points when you kill (30,000 / zombie)",
        ["money.autoReward"] = "Earn 30,000 points per zombie (Aimbot / Aura)",
        ["money.killAllReward"] = "Also earn 30,000 with Kill all (Combat)",
        ["money.secGive"] = "Give points",
        ["money.amount"] = "How much money (type a number)",
        ["money.amountPh"] = "example: 30000",
        ["money.slider"] = "Or pick with the slider",
        ["money.add"] = "Add money (once)",
        ["money.auto"] = "Add automatically every second",
        ["ammo.howTitle"] = "Coming soon",
        ["ammo.howBody"] = "Infinite ammo is coming soon. This tab is not active yet.",
        ["ammo.inf"] = "Infinite ammo — never reload again",
        ["ammo.fill"] = "Refill guns now (once)",
        ["guns.howTitle"] = "Coming soon",
        ["guns.howBody"] = "Guns (wall, box, PAP) are coming soon. This tab is not active yet.",
        ["guns.result"] = "Result",
        ["guns.needScan"] = "Not searched yet. Click Find guns.",
        ["guns.waitLobby"] = "Not in a match yet. Wait for zombies / walls, then Find.",
        ["guns.noneFound"] = "0 guns. Walk to a wall, the box or PAP, then Find.",
        ["guns.none"] = "(no gun)",
        ["guns.needPick"] = "(Find first)",
        ["guns.scanFmt"] = "%d guns | Wall %d | Box %d | PAP %d | List %d\nHeld: %s\n%s%s",
        ["guns.more"] = "\n... +%s more",
        ["guns.notifyFound"] = "%d guns (wall %d, box %d, PAP %d)",
        ["guns.scan"] = "Find guns (walls + box)",
        ["guns.pick"] = "Pick the gun here",
        ["guns.type"] = "Or type the gun name",
        ["guns.namePh"] = "ex: M14 or Ray Gun",
        ["guns.buy"] = "Buy the selected gun (with your points)",
        ["guns.free"] = "Buy for free (gives money + the gun)",
        ["guns.box"] = "Open mystery box (once)",
        ["guns.allWalls"] = "Buy ALL wall guns",
        ["guns.papSec"] = "Upgrade the gun (Pack-a-Punch)",
        ["guns.papHowTitle"] = "How to upgrade",
        ["guns.papHowBody"] = "Hold the gun, walk to PAP, click Find if needed, then Upgrade to max. That does PAP then the effect (ex: Dead Wire).",
        ["guns.papScan"] = "Find the PAP machine",
        ["guns.up1"] = "Upgrade once (held gun)",
        ["guns.upMax"] = "Upgrade to maximum",
        ["guns.status"] = "See if my gun is upgraded",
        ["guns.enterMatch"] = "Join a match (zombies / walls), then click Find guns.",
        ["esp.howTitle"] = "See the zombies",
        ["esp.howBody"] = "Turn on See through walls. You get name, health and distance. Lines are optional.",
        ["esp.on"] = "See through walls",
        ["esp.name"] = "Show name",
        ["esp.hp"] = "Show health",
        ["esp.dist"] = "Show distance",
        ["esp.skel"] = "Draw zombie bones",
        ["esp.tracer"] = "Line from the bottom of the screen",
        ["esp.snap"] = "Line from crosshair to the head",
        ["esp.team"] = "Hide teammates (only show zombies)",
        ["esp.max"] = "Max distance",
        ["esp.zcolor"] = "Zombie color",
        ["esp.acolor"] = "Teammate color",
        ["fly.howTitle"] = "How to fly",
        ["fly.howBody"] = "Turn on Fly. WASD = move. Q = down, E = up. If too slow, raise speed (try 50). Mode 2 = only if normal fly bugs.",
        ["fly.on"] = "Fly",
        ["fly.mode2"] = "Mode 2 (if normal fly bugs)",
        ["fly.speed"] = "Speed (1 = slow, 50 = fast, 200 = very fast)",
        ["fly.alpha"] = "See-through character while flying",
        ["srv.howTitle"] = "If something stops working",
        ["srv.howBody"] = "Rejoin = same map.  Re-attach script = if Combat stops killing.",
        ["srv.rejoin"] = "Rejoin the match (same map)",
        ["srv.rehook"] = "Re-attach the script (if Combat stops killing)",
        ["srv.waitGuns"] = "Wait for match + find guns",
        ["srv.count"] = "How many zombies here?",
        ["n.aura"] = "Aura",
        ["n.auraBody"] = "Fire 1 bullet once, then aura hits harder.",
        ["n.trigger"] = "Auto-fire",
        ["n.triggerBody"] = "Look at a zombie. Fire 1 bullet first.",
        ["n.killAll"] = "Kill all",
        ["n.killOn"] = "ON. %s killed + new ones too.",
        ["n.killOff"] = "OFF.",
        ["n.killed"] = "%s zombie(s) killed.",
        ["n.money"] = "Money",
        ["n.moneyAdd"] = "+%s points.",
        ["n.autoOn"] = "AUTO ON: +%s / s",
        ["n.autoOff"] = "AUTO OFF",
        ["n.ammo"] = "Ammo",
        ["n.ammoOn"] = "ON — your guns refill.",
        ["n.ammoOff"] = "OFF.",
        ["n.ammoFill"] = "Refill sent.",
        ["n.guns"] = "Guns",
        ["n.enterFirst"] = "Join a match first, then Find guns.",
        ["n.noneFound"] = "Nothing found. Walk to a wall then Find.",
        ["n.scanWait"] = "Waiting for match (max 20s)...",
        ["n.pickFirst"] = "Find guns, then pick one.",
        ["n.pickOne"] = "Pick a gun from the list.",
        ["n.noBox"] = "No box. Walk to the Mystery Box then Find.",
        ["n.wallsBought"] = "%s wall gun(s) bought.",
        ["n.pap"] = "PAP",
        ["n.noPap"] = "0 machine. Walk to Pack-a-Punch then Find.",
        ["n.papFound"] = "%s machine(s) found.",
        ["n.held"] = "Held gun: %s",
        ["n.papBusy"] = "Max upgrade in progress...",
        ["n.noGun"] = "No gun in hand.",
        ["n.gunStat"] = "%s | level %d | %s%s",
        ["n.effect"] = " | effect=%s",
        ["n.fly"] = "Fly",
        ["n.flyOn"] = "ON — speed %s",
        ["n.flyOff"] = "OFF",
        ["n.mode2"] = "Mode 2 ON",
        ["n.modeNorm"] = "Normal mode",
        ["n.script"] = "Script",
        ["n.okCombat"] = "OK, Combat ready",
        ["n.notReady"] = "Not ready",
        ["n.remoteOk"] = " | remote OK",
        ["n.noRemote"] = " | remote missing",
        ["n.waitPart"] = "Waiting for the match...",
        ["n.notInMatch"] = "Not in a match yet. Try again once zombies / walls are there.",
        ["n.zombies"] = "Zombies",
        ["n.zcount"] = "%s zombie(s).",
        ["n.readyTitle"] = "XHUB",
        ["n.readyBody"] = "Ready. Language = FR/EN. Combat = kill (30k / zombie). Money = points. Fly = fly.",
        ["n.langTitle"] = "Language",
        ["n.langBody"] = "Whole menu is now English.",
    },
    es = {
        ["win.name"] = "XHUB · Reminiscence",
        ["win.sub"] = "Combate · Dinero · Armas · Volar",
        ["tab.lang"] = "Idioma",
        ["tab.guide"] = "Guia",
        ["tab.combat"] = "Combate",
        ["tab.money"] = "Dinero",
        ["tab.ammo"] = "Municion",
        ["tab.guns"] = "Armas",
        ["tab.vision"] = "Vision",
        ["tab.fly"] = "Volar",
        ["tab.server"] = "Servidor",
        ["lang.howTitle"] = "Cambia el idioma del menu",
        ["lang.howBody"] = "Clic en Francais o English (u otro). TODOS los textos cambian. Tus opciones se quedan.",
        ["lang.pick"] = "O elige en la lista",
        ["guide.tabsTitle"] = "Las pestanas (arriba)",
        ["guide.tabsBody"] = "Combate = matar.   Dinero = puntos (30.000 por zombie).   Municion = pronto.   Armas = pronto.   Vision = ver.   Volar = volar.   Servidor = reiniciar.",
        ["guide.startTitle"] = "Nuevo? Haz esto",
        ["guide.startBody"] = "1) Abre Combate.  2) Aura (mata alrededor) O Aimbot (mantén clic izquierdo).  3) Dispara 1 bala real primero.  4) 30.000 puntos por zombie.  5) Volar para volar.",
        ["combat.howTitle"] = "Elige UN modo (o varios)",
        ["combat.howBody"] = "Aimbot = mantén clic izquierdo.   Aura = pega alrededor.   Matar todo = no disparas.   1 bala primero.   Cada zombie = 30.000 puntos.",

        ["combat.silentTitle"] = "SILENT AIM",
        ["combat.silentBody"] = "Activa SILENT AIM abajo y MANTEN clic izquierdo. Apunta por ti sin mover la mira.",
        ["combat.secSilent"] = "Silent Aim",
        ["combat.secKill"] = "Matar",
        ["combat.aimbot"] = "Silent Aim — apunta por ti (mantén clic izquierdo)",
        ["combat.multi"] = "Multi — golpea TODOS los zombies delante",
        ["combat.aura"] = "Aura — mata alrededor (sin apuntar)",
        ["combat.trigger"] = "Auto-disparo — dispara solo al zombie del centro",
        ["combat.killAll"] = "Matar todo — todos mueren solos",
        ["combat.killNow"] = "Matar a todos AHORA (1 vez)",
        ["combat.secSet"] = "Ajustes (puedes dejarlos)",
        ["combat.aimWhere"] = "Donde apuntar en el zombie",
        ["aim.head"] = "Cabeza",
        ["aim.body"] = "Cuerpo",
        ["aim.chest"] = "Pecho",
        ["aim.torso"] = "Torso",
        ["combat.fov"] = "Zona de aimbot (mas grande = mas facil)",
        ["combat.multiFov"] = "Zona Multi",
        ["combat.multiRange"] = "Distancia max Multi",
        ["combat.auraRange"] = "Distancia del aura",
        ["combat.dmg"] = "Fuerza de dano (1 = normal, 20 = muy fuerte)",
        ["combat.visible"] = "Aimbot: solo zombies que VES (no a traves de paredes)",
        ["combat.aimRate"] = "Velocidad aimbot (clic mantenido)",
        ["combat.trigFov"] = "Precision auto-disparo (mas grande = mas facil)",
        ["combat.trigRate"] = "Velocidad auto-disparo",
        ["combat.trigClick"] = "Auto-disparo: tambien hacer clic",
        ["combat.tracer"] = "Linea verde = confirmacion del disparo",
        ["combat.tracerColor"] = "Color de la linea",
        ["combat.fovCircle"] = "Circulo en pantalla (zona de apuntado)",
        ["combat.killRate"] = "Matar todo: velocidad (deja 1 si no sabes)",
        ["money.howTitle"] = "Como tener puntos",
        ["money.howBody"] = "Cada zombie que matas = 30.000 puntos. Tambien puedes Anadir un monto, o Auto cada segundo. Sirve para puertas y armas.",
        ["money.secKills"] = "Puntos al matar (30.000 / zombie)",
        ["money.autoReward"] = "Ganar 30.000 puntos por zombie (Aimbot / Aura)",
        ["money.killAllReward"] = "Ganar 30.000 tambien con Matar todo",
        ["money.secGive"] = "Dar puntos",
        ["money.amount"] = "Cuanto dinero (escribe un numero)",
        ["money.amountPh"] = "ejemplo: 30000",
        ["money.slider"] = "O elige con el control",
        ["money.add"] = "Anadir el dinero (1 vez)",
        ["money.auto"] = "Anadir solo cada segundo",
        ["ammo.howTitle"] = "Disponible pronto",
        ["ammo.howBody"] = "La municion infinita llega pronto. Esta pestana no esta activa.",
        ["ammo.inf"] = "Municion infinita — nunca recargar",
        ["ammo.fill"] = "Recargar armas ahora (1 vez)",
        ["guns.howTitle"] = "Disponible pronto",
        ["guns.howBody"] = "Las armas (muro, cofre, PAP) llegan pronto. Esta pestana no esta activa.",
        ["guns.result"] = "Resultado",
        ["guns.needScan"] = "Aun no buscado. Clic Buscar armas.",
        ["guns.waitLobby"] = "Aun no en partida. Espera zombies / muros, luego Buscar.",
        ["guns.noneFound"] = "0 armas. Acercate a un muro, cofre o PAP, luego Buscar.",
        ["guns.none"] = "(ningun arma)",
        ["guns.needPick"] = "(Buscar primero)",
        ["guns.scanFmt"] = "%d armas | Muro %d | Cofre %d | PAP %d | Lista %d\nEn mano: %s\n%s%s",
        ["guns.more"] = "\n... +%s mas",
        ["guns.notifyFound"] = "%d armas (muro %d, cofre %d, PAP %d)",
        ["guns.scan"] = "Buscar armas (muros + cofre)",
        ["guns.pick"] = "Elige el arma aqui",
        ["guns.type"] = "O escribe el nombre",
        ["guns.namePh"] = "ej: M14 o Ray Gun",
        ["guns.buy"] = "Comprar el arma (con tus puntos)",
        ["guns.free"] = "Comprar gratis (da dinero + arma)",
        ["guns.box"] = "Abrir el cofre misterioso (1 vez)",
        ["guns.allWalls"] = "Comprar TODAS las armas de muro",
        ["guns.papSec"] = "Mejorar el arma (Pack-a-Punch)",
        ["guns.papHowTitle"] = "Como mejorar",
        ["guns.papHowBody"] = "Arma en mano, acerca a PAP, Buscar si hace falta, Mejorar al maximo.",
        ["guns.papScan"] = "Buscar la maquina PAP",
        ["guns.up1"] = "Mejorar 1 vez (arma en mano)",
        ["guns.upMax"] = "Mejorar al maximo",
        ["guns.status"] = "Ver si mi arma esta mejorada",
        ["guns.enterMatch"] = "Entra en partida (zombies / muros), luego Buscar armas.",
        ["esp.howTitle"] = "Ver los zombies",
        ["esp.howBody"] = "Activa Ver a traves de paredes. Nombre, vida y distancia. Las lineas son opcionales.",
        ["esp.on"] = "Ver a traves de las paredes",
        ["esp.name"] = "Mostrar el nombre",
        ["esp.hp"] = "Mostrar la vida",
        ["esp.dist"] = "Mostrar la distancia",
        ["esp.skel"] = "Dibujar los huesos",
        ["esp.tracer"] = "Linea desde abajo de la pantalla",
        ["esp.snap"] = "Linea desde la mira a la cabeza",
        ["esp.team"] = "Ocultar aliados (solo zombies)",
        ["esp.max"] = "Distancia max",
        ["esp.zcolor"] = "Color de zombies",
        ["esp.acolor"] = "Color de aliados",
        ["fly.howTitle"] = "Como volar",
        ["fly.howBody"] = "Activa Volar. WASD = mover. Q = bajar, E = subir. Si vas lento, sube velocidad (prueba 50). Modo 2 = si el vuelo falla.",
        ["fly.on"] = "Volar",
        ["fly.mode2"] = "Modo 2 (si el vuelo normal falla)",
        ["fly.speed"] = "Velocidad (1 = lento, 50 = rapido, 200 = muy rapido)",
        ["fly.alpha"] = "Personaje transparente al volar",
        ["srv.howTitle"] = "Si algo deja de funcionar",
        ["srv.howBody"] = "Reiniciar = misma mapa.  Reenganchar = si Combate no mata.",
        ["srv.rejoin"] = "Reiniciar la partida (mismo mapa)",
        ["srv.rehook"] = "Reenganchar el script (si Combate no mata)",
        ["srv.waitGuns"] = "Esperar partida + buscar armas",
        ["srv.count"] = "Cuantos zombies hay?",
        ["n.aura"] = "Aura",
        ["n.auraBody"] = "Dispara 1 bala, luego el aura pega mas fuerte.",
        ["n.trigger"] = "Auto-disparo",
        ["n.triggerBody"] = "Mira un zombie. Dispara 1 bala primero.",
        ["n.killAll"] = "Matar todo",
        ["n.killOn"] = "ON. %s muertos + los nuevos tambien.",
        ["n.killOff"] = "OFF.",
        ["n.killed"] = "%s zombie(s) muertos.",
        ["n.money"] = "Dinero",
        ["n.moneyAdd"] = "+%s puntos.",
        ["n.autoOn"] = "AUTO ON: +%s / s",
        ["n.autoOff"] = "AUTO OFF",
        ["n.ammo"] = "Municion",
        ["n.ammoOn"] = "ON — tus armas se recargan.",
        ["n.ammoOff"] = "OFF.",
        ["n.ammoFill"] = "Recarga enviada.",
        ["n.guns"] = "Armas",
        ["n.enterFirst"] = "Entra en partida primero, luego Buscar armas.",
        ["n.noneFound"] = "Nada. Acercate a un muro luego Buscar.",
        ["n.scanWait"] = "Esperando partida (max 20s)...",
        ["n.pickFirst"] = "Busca armas, luego elige una.",
        ["n.pickOne"] = "Elige un arma de la lista.",
        ["n.noBox"] = "Sin cofre. Acercate al Mystery Box luego Buscar.",
        ["n.wallsBought"] = "%s arma(s) de muro comprada(s).",
        ["n.pap"] = "PAP",
        ["n.noPap"] = "0 maquina. Acercate al Pack-a-Punch luego Buscar.",
        ["n.papFound"] = "%s maquina(s) encontrada(s).",
        ["n.held"] = "Arma en mano: %s",
        ["n.papBusy"] = "Mejora max en curso...",
        ["n.noGun"] = "Ningun arma en mano.",
        ["n.gunStat"] = "%s | nivel %d | %s%s",
        ["n.effect"] = " | efecto=%s",
        ["n.fly"] = "Volar",
        ["n.flyOn"] = "ON — velocidad %s",
        ["n.flyOff"] = "OFF",
        ["n.mode2"] = "Modo 2 ON",
        ["n.modeNorm"] = "Modo normal",
        ["n.script"] = "Script",
        ["n.okCombat"] = "OK, Combate listo",
        ["n.notReady"] = "No listo",
        ["n.remoteOk"] = " | remote OK",
        ["n.noRemote"] = " | remote no encontrado",
        ["n.waitPart"] = "Esperando la partida...",
        ["n.notInMatch"] = "Aun no en partida. Reintenta cuando haya zombies / muros.",
        ["n.zombies"] = "Zombies",
        ["n.zcount"] = "%s zombie(s).",
        ["n.readyTitle"] = "XHUB",
        ["n.readyBody"] = "Listo. Idioma = FR/EN. Combate = matar (30k / zombie). Dinero = puntos. Volar = volar.",
        ["n.langTitle"] = "Idioma",
        ["n.langBody"] = "Todo el menu esta en Espanol.",
    },
    pt = {
        ["win.name"] = "XHUB · Reminiscence",
        ["win.sub"] = "Combate · Dinheiro · Armas · Voar",
        ["tab.lang"] = "Idioma",
        ["tab.guide"] = "Guia",
        ["tab.combat"] = "Combate",
        ["tab.money"] = "Dinheiro",
        ["tab.ammo"] = "Municao",
        ["tab.guns"] = "Armas",
        ["tab.vision"] = "Visao",
        ["tab.fly"] = "Voar",
        ["tab.server"] = "Servidor",
        ["lang.howTitle"] = "Muda o idioma do menu",
        ["lang.howBody"] = "Clica Francais ou English (ou outra). TODOS os textos mudam. Teus toggles ficam ligados.",
        ["lang.pick"] = "Ou escolhe na lista",
        ["guide.tabsTitle"] = "As abas (em cima)",
        ["guide.tabsBody"] = "Combate = matar.   Dinheiro = pontos (30.000 por zumbi).   Municao = em breve.   Armas = em breve.   Visao = ver.   Voar = voar.   Servidor = reiniciar.",
        ["guide.startTitle"] = "Novo? Faz isto",
        ["guide.startBody"] = "1) Abre Combate.  2) Liga Aura (mata em volta) OU Aimbot (segura clique esquerdo).  3) Dispara 1 bala de verdade.  4) 30.000 pontos por zumbi.  5) Voar para voar.",
        ["combat.howTitle"] = "Escolhe UM modo (ou varios)",
        ["combat.howBody"] = "Aimbot = segura clique esquerdo.   Aura = bate em volta.   Matar todos = sem atirar.   1 bala primeiro.   Cada zumbi = 30.000 pontos.",

        ["combat.silentTitle"] = "SILENT AIM",
        ["combat.silentBody"] = "Liga SILENT AIM abaixo e SEGURA clique esquerdo. Mira por ti sem mexer a mira.",
        ["combat.secSilent"] = "Silent Aim",
        ["combat.secKill"] = "Matar",
        ["combat.aimbot"] = "Silent Aim — mira por ti (segura clique esquerdo)",
        ["combat.multi"] = "Multi — acerta TODOS os zumbis na frente",
        ["combat.aura"] = "Aura — mata em volta (sem mirar)",
        ["combat.trigger"] = "Auto-tiro — atira sozinho no zumbi do centro",
        ["combat.killAll"] = "Matar todos — todos morrem sozinhos",
        ["combat.killNow"] = "Matar todos AGORA (1 vez)",
        ["combat.secSet"] = "Ajustes (podes deixar assim)",
        ["combat.aimWhere"] = "Onde mirar no zumbi",
        ["aim.head"] = "Cabeca",
        ["aim.body"] = "Corpo",
        ["aim.chest"] = "Peito",
        ["aim.torso"] = "Torso",
        ["combat.fov"] = "Zona do aimbot (maior = mais facil)",
        ["combat.multiFov"] = "Zona Multi",
        ["combat.multiRange"] = "Distancia max Multi",
        ["combat.auraRange"] = "Distancia da aura",
        ["combat.dmg"] = "Forca do dano (1 = normal, 20 = muito forte)",
        ["combat.visible"] = "Aimbot: so zumbis que VES (nao atraves da parede)",
        ["combat.aimRate"] = "Velocidade aimbot (clique seguro)",
        ["combat.trigFov"] = "Precisao auto-tiro (maior = mais facil)",
        ["combat.trigRate"] = "Velocidade auto-tiro",
        ["combat.trigClick"] = "Auto-tiro: tambem clicar o rato",
        ["combat.tracer"] = "Linha verde = confirmacao do tiro",
        ["combat.tracerColor"] = "Cor da linha",
        ["combat.fovCircle"] = "Circulo no ecran (zona de mira)",
        ["combat.killRate"] = "Matar todos: velocidade (deixa 1 se nao souberes)",
        ["money.howTitle"] = "Como ter pontos",
        ["money.howBody"] = "Cada zumbi que matas = 30.000 pontos. Tambem podes Adicionar um valor, ou Auto a cada segundo. Serve para portas e armas.",
        ["money.secKills"] = "Pontos ao matar (30.000 / zumbi)",
        ["money.autoReward"] = "Ganhar 30.000 pontos por zumbi (Aimbot / Aura)",
        ["money.killAllReward"] = "Ganhar 30.000 tambem com Matar todos",
        ["money.secGive"] = "Dar pontos",
        ["money.amount"] = "Quanto dinheiro (escreve um numero)",
        ["money.amountPh"] = "exemplo: 30000",
        ["money.slider"] = "Ou escolhe com o cursor",
        ["money.add"] = "Adicionar o dinheiro (1 vez)",
        ["money.auto"] = "Adicionar sozinho a cada segundo",
        ["ammo.howTitle"] = "Em breve",
        ["ammo.howBody"] = "Municao infinita em breve. Esta aba ainda nao esta ativa.",
        ["ammo.inf"] = "Municao infinita — nunca recarregar",
        ["ammo.fill"] = "Recarregar armas agora (1 vez)",
        ["guns.howTitle"] = "Em breve",
        ["guns.howBody"] = "Armas (parede, caixa, PAP) em breve. Esta aba ainda nao esta ativa.",
        ["guns.result"] = "Resultado",
        ["guns.needScan"] = "Ainda nao procurado. Clica Procurar armas.",
        ["guns.waitLobby"] = "Ainda nao na partida. Espera zumbis / paredes, depois Procurar.",
        ["guns.noneFound"] = "0 armas. Chega a uma parede, caixa ou PAP, depois Procurar.",
        ["guns.none"] = "(nenhuma arma)",
        ["guns.needPick"] = "(Procurar primeiro)",
        ["guns.scanFmt"] = "%d armas | Parede %d | Caixa %d | PAP %d | Lista %d\nNa mao: %s\n%s%s",
        ["guns.more"] = "\n... +%s outras",
        ["guns.notifyFound"] = "%d armas (parede %d, caixa %d, PAP %d)",
        ["guns.scan"] = "Procurar armas (paredes + caixa)",
        ["guns.pick"] = "Escolhe a arma aqui",
        ["guns.type"] = "Ou escreve o nome",
        ["guns.namePh"] = "ex: M14 ou Ray Gun",
        ["guns.buy"] = "Comprar a arma (com teus pontos)",
        ["guns.free"] = "Comprar gratis (da dinheiro + arma)",
        ["guns.box"] = "Abrir a caixa misteriosa (1 vez)",
        ["guns.allWalls"] = "Comprar TODAS as armas da parede",
        ["guns.papSec"] = "Melhorar a arma (Pack-a-Punch)",
        ["guns.papHowTitle"] = "Como melhorar",
        ["guns.papHowBody"] = "Arma na mao, chega ao PAP, Procurar se preciso, Melhorar ao maximo.",
        ["guns.papScan"] = "Procurar a maquina PAP",
        ["guns.up1"] = "Melhorar 1 vez (arma na mao)",
        ["guns.upMax"] = "Melhorar ao maximo",
        ["guns.status"] = "Ver se a arma esta melhorada",
        ["guns.enterMatch"] = "Entra na partida (zumbis / paredes), depois Procurar armas.",
        ["esp.howTitle"] = "Ver os zumbis",
        ["esp.howBody"] = "Liga Ver atraves das paredes. Nome, vida e distancia. Linhas opcionais.",
        ["esp.on"] = "Ver atraves das paredes",
        ["esp.name"] = "Mostrar o nome",
        ["esp.hp"] = "Mostrar a vida",
        ["esp.dist"] = "Mostrar a distancia",
        ["esp.skel"] = "Desenhar os ossos",
        ["esp.tracer"] = "Linha desde o fundo do ecran",
        ["esp.snap"] = "Linha da mira ate a cabeca",
        ["esp.team"] = "Esconder aliados (so zumbis)",
        ["esp.max"] = "Distancia max",
        ["esp.zcolor"] = "Cor dos zumbis",
        ["esp.acolor"] = "Cor dos aliados",
        ["fly.howTitle"] = "Como voar",
        ["fly.howBody"] = "Liga Voar. WASD = mover. Q = descer, E = subir. Se for lento, sobe velocidade (tenta 50). Modo 2 = se o voo falhar.",
        ["fly.on"] = "Voar",
        ["fly.mode2"] = "Modo 2 (se o voo normal falhar)",
        ["fly.speed"] = "Velocidade (1 = lento, 50 = rapido, 200 = muito rapido)",
        ["fly.alpha"] = "Personagem transparente ao voar",
        ["srv.howTitle"] = "Se algo parar de funcionar",
        ["srv.howBody"] = "Reiniciar = mesmo mapa.  Recolocar script = se Combate nao mata.",
        ["srv.rejoin"] = "Reiniciar a partida (mesmo mapa)",
        ["srv.rehook"] = "Recolocar o script (se Combate nao mata)",
        ["srv.waitGuns"] = "Esperar partida + procurar armas",
        ["srv.count"] = "Quantos zumbis ha?",
        ["n.aura"] = "Aura",
        ["n.auraBody"] = "Dispara 1 bala, depois a aura bate mais forte.",
        ["n.trigger"] = "Auto-tiro",
        ["n.triggerBody"] = "Olha um zumbi. Dispara 1 bala primeiro.",
        ["n.killAll"] = "Matar todos",
        ["n.killOn"] = "ON. %s mortos + os proximos tambem.",
        ["n.killOff"] = "OFF.",
        ["n.killed"] = "%s zumbi(s) mortos.",
        ["n.money"] = "Dinheiro",
        ["n.moneyAdd"] = "+%s pontos.",
        ["n.autoOn"] = "AUTO ON: +%s / s",
        ["n.autoOff"] = "AUTO OFF",
        ["n.ammo"] = "Municao",
        ["n.ammoOn"] = "ON — tuas armas recarregam.",
        ["n.ammoOff"] = "OFF.",
        ["n.ammoFill"] = "Recarga enviada.",
        ["n.guns"] = "Armas",
        ["n.enterFirst"] = "Entra na partida primeiro, depois Procurar armas.",
        ["n.noneFound"] = "Nada. Chega a uma parede depois Procurar.",
        ["n.scanWait"] = "A espera da partida (max 20s)...",
        ["n.pickFirst"] = "Procura armas, depois escolhe uma.",
        ["n.pickOne"] = "Escolhe uma arma da lista.",
        ["n.noBox"] = "Sem caixa. Chega a Mystery Box depois Procurar.",
        ["n.wallsBought"] = "%s arma(s) de parede comprada(s).",
        ["n.pap"] = "PAP",
        ["n.noPap"] = "0 maquina. Chega ao Pack-a-Punch depois Procurar.",
        ["n.papFound"] = "%s maquina(s) encontrada(s).",
        ["n.held"] = "Arma na mao: %s",
        ["n.papBusy"] = "Melhoria max em curso...",
        ["n.noGun"] = "Nenhuma arma na mao.",
        ["n.gunStat"] = "%s | nivel %d | %s%s",
        ["n.effect"] = " | efeito=%s",
        ["n.fly"] = "Voar",
        ["n.flyOn"] = "ON — velocidade %s",
        ["n.flyOff"] = "OFF",
        ["n.mode2"] = "Modo 2 ON",
        ["n.modeNorm"] = "Modo normal",
        ["n.script"] = "Script",
        ["n.okCombat"] = "OK, Combate pronto",
        ["n.notReady"] = "Nao pronto",
        ["n.remoteOk"] = " | remote OK",
        ["n.noRemote"] = " | remote nao encontrado",
        ["n.waitPart"] = "A espera da partida...",
        ["n.notInMatch"] = "Ainda nao na partida. Tenta quando houver zumbis / paredes.",
        ["n.zombies"] = "Zumbis",
        ["n.zcount"] = "%s zumbi(s).",
        ["n.readyTitle"] = "XHUB",
        ["n.readyBody"] = "Pronto. Idioma = FR/EN. Combate = matar (30k / zumbi). Dinheiro = pontos. Voar = voar.",
        ["n.langTitle"] = "Idioma",
        ["n.langBody"] = "Menu inteiro em Portugues.",
    },
    de = {
        ["win.name"] = "XHUB · Reminiscence",
        ["win.sub"] = "Kampf · Geld · Waffen · Flug",
        ["tab.lang"] = "Sprache",
        ["tab.guide"] = "Hilfe",
        ["tab.combat"] = "Kampf",
        ["tab.money"] = "Geld",
        ["tab.ammo"] = "Munition",
        ["tab.guns"] = "Waffen",
        ["tab.vision"] = "Sicht",
        ["tab.fly"] = "Flug",
        ["tab.server"] = "Server",
        ["lang.howTitle"] = "Sprache des ganzen Menus",
        ["lang.howBody"] = "Klick Francais oder English (oder andere). ALLE Texte wechseln. Deine Toggles bleiben an.",
        ["lang.pick"] = "Oder aus der Liste wahlen",
        ["guide.tabsTitle"] = "Die Tabs (oben)",
        ["guide.tabsBody"] = "Kampf = toten.   Geld = Punkte (30.000 pro Zombie).   Munition = bald.   Waffen = bald.   Sicht = sehen.   Flug = fliegen.   Server = rejoinen.",
        ["guide.startTitle"] = "Neu? Mach genau das",
        ["guide.startBody"] = "1) Kampf offnen.  2) Aura (um dich) ODER Aimbot (Linksklick halten).  3) Erst 1 echte Kugel.  4) 30.000 Punkte pro Kill.  5) Flug zum Fliegen.",
        ["combat.howTitle"] = "Waehle EINEN Modus (oder mehrere)",
        ["combat.howBody"] = "Aimbot = Linksklick halten.   Aura = trifft um dich.   Alle toten = kein Schiessen.   Erst 1 Kugel.   Jeder Kill = 30.000 Punkte.",

        ["combat.silentTitle"] = "SILENT AIM",
        ["combat.silentBody"] = "SILENT AIM unten an, dann Linksklick HALTEN. Zielt fuer dich ohne Fadenkreuz zu bewegen.",
        ["combat.secSilent"] = "Silent Aim",
        ["combat.secKill"] = "Toten",
        ["combat.aimbot"] = "Silent Aim — zielt fuer dich (Linksklick halten)",
        ["combat.multi"] = "Multi — trifft ALLE Zombies vor dir",
        ["combat.aura"] = "Aura — toetet um dich (ohne Zielen)",
        ["combat.trigger"] = "Auto-Feuer — schiesst das Zombie in der Mitte",
        ["combat.killAll"] = "Alle toten — alle Zombies sterben von selbst",
        ["combat.killNow"] = "Alle JETZT toten (1x)",
        ["combat.secSet"] = "Einstellungen (kannst du lassen)",
        ["combat.aimWhere"] = "Wohin auf den Zombie zielen",
        ["aim.head"] = "Kopf",
        ["aim.body"] = "Koerper",
        ["aim.chest"] = "Brust",
        ["aim.torso"] = "Torso",
        ["combat.fov"] = "Aimbot-Zone (groesser = leichter)",
        ["combat.multiFov"] = "Multi-Zone",
        ["combat.multiRange"] = "Max Multi-Distanz",
        ["combat.auraRange"] = "Aura-Distanz",
        ["combat.dmg"] = "Schadensstaerke (1 = normal, 20 = sehr stark)",
        ["combat.visible"] = "Aimbot: nur Zombies die du SIEHST (nicht durch Waende)",
        ["combat.aimRate"] = "Aimbot-Tempo (Klick gehalten)",
        ["combat.trigFov"] = "Auto-Feuer Genauigkeit (groesser = leichter)",
        ["combat.trigRate"] = "Auto-Feuer Tempo",
        ["combat.trigClick"] = "Auto-Feuer: auch Maus klicken",
        ["combat.tracer"] = "Gruene Linie = Schussbestaetigung",
        ["combat.tracerColor"] = "Linienfarbe",
        ["combat.fovCircle"] = "Kreis auf dem Bildschirm (Zielzone)",
        ["combat.killRate"] = "Alle toten: Tempo (lass 1 wenn unsicher)",
        ["money.howTitle"] = "Wie du Punkte bekommst",
        ["money.howBody"] = "Jeder Kill = 30.000 Punkte. Du kannst auch einen Betrag Addieren, oder Auto jede Sekunde. Fuer Tueren und Waffen.",
        ["money.secKills"] = "Punkte beim Kill (30.000 / Zombie)",
        ["money.autoReward"] = "30.000 Punkte pro Zombie (Aimbot / Aura)",
        ["money.killAllReward"] = "Auch 30.000 mit Alle toten",
        ["money.secGive"] = "Punkte geben",
        ["money.amount"] = "Wie viel Geld (Zahl eingeben)",
        ["money.amountPh"] = "Beispiel: 30000",
        ["money.slider"] = "Oder mit dem Schieber",
        ["money.add"] = "Geld hinzufuegen (1x)",
        ["money.auto"] = "Automatisch jede Sekunde",
        ["ammo.howTitle"] = "Bald verfuegbar",
        ["ammo.howBody"] = "Unendliche Munition kommt bald. Dieser Tab ist noch nicht aktiv.",
        ["ammo.inf"] = "Unendliche Munition — nie nachladen",
        ["ammo.fill"] = "Waffen jetzt fuellen (1x)",
        ["guns.howTitle"] = "Bald verfuegbar",
        ["guns.howBody"] = "Waffen (Wand, Box, PAP) kommen bald. Dieser Tab ist noch nicht aktiv.",
        ["guns.result"] = "Ergebnis",
        ["guns.needScan"] = "Noch nicht gesucht. Klick Waffen suchen.",
        ["guns.waitLobby"] = "Noch nicht in der Runde. Warte auf Zombies / Waende, dann Suchen.",
        ["guns.noneFound"] = "0 Waffen. Geh zu Wand, Box oder PAP, dann Suchen.",
        ["guns.none"] = "(keine Waffe)",
        ["guns.needPick"] = "(Zuerst suchen)",
        ["guns.scanFmt"] = "%d Waffen | Wand %d | Box %d | PAP %d | Liste %d\nIn der Hand: %s\n%s%s",
        ["guns.more"] = "\n... +%s weitere",
        ["guns.notifyFound"] = "%d Waffen (Wand %d, Box %d, PAP %d)",
        ["guns.scan"] = "Waffen suchen (Waende + Box)",
        ["guns.pick"] = "Waffe hier waehlen",
        ["guns.type"] = "Oder Waffenname tippen",
        ["guns.namePh"] = "z.B. M14 oder Ray Gun",
        ["guns.buy"] = "Gewaehlte Waffe kaufen (mit Punkten)",
        ["guns.free"] = "Gratis kaufen (gibt Geld + Waffe)",
        ["guns.box"] = "Mystery Box oeffnen (1x)",
        ["guns.allWalls"] = "ALLE Wandwaffen kaufen",
        ["guns.papSec"] = "Waffe upgraden (Pack-a-Punch)",
        ["guns.papHowTitle"] = "Wie upgraden",
        ["guns.papHowBody"] = "Waffe in der Hand, zur PAP, Suchen falls noetig, dann Max-Upgrade.",
        ["guns.papScan"] = "PAP-Maschine suchen",
        ["guns.up1"] = "1x upgraden (Waffe in der Hand)",
        ["guns.upMax"] = "Maximal upgraden",
        ["guns.status"] = "Sehen ob meine Waffe upgraded ist",
        ["guns.enterMatch"] = "Geh in eine Runde (Zombies / Waende), dann Waffen suchen.",
        ["esp.howTitle"] = "Zombies sehen",
        ["esp.howBody"] = "Durch Waende sehen an. Name, Leben, Distanz. Linien optional.",
        ["esp.on"] = "Durch Waende sehen",
        ["esp.name"] = "Name anzeigen",
        ["esp.hp"] = "Leben anzeigen",
        ["esp.dist"] = "Distanz anzeigen",
        ["esp.skel"] = "Knochen zeichnen",
        ["esp.tracer"] = "Linie vom unteren Bildschirmrand",
        ["esp.snap"] = "Linie vom Fadenkreuz zum Kopf",
        ["esp.team"] = "Teamkameraden verstecken (nur Zombies)",
        ["esp.max"] = "Max Distanz",
        ["esp.zcolor"] = "Zombie-Farbe",
        ["esp.acolor"] = "Team-Farbe",
        ["fly.howTitle"] = "Wie fliegen",
        ["fly.howBody"] = "Flug an. WASD = bewegen. Q = runter, E = hoch. Zu langsam? Tempo 50. Modus 2 = nur wenn Flug buggy.",
        ["fly.on"] = "Fliegen",
        ["fly.mode2"] = "Modus 2 (wenn normaler Flug buggy)",
        ["fly.speed"] = "Tempo (1 = langsam, 50 = schnell, 200 = sehr schnell)",
        ["fly.alpha"] = "Charakter durchsichtig beim Fliegen",
        ["srv.howTitle"] = "Wenn etwas nicht mehr geht",
        ["srv.howBody"] = "Rejoin = gleiche Map.  Script neu = wenn Kampf nicht toetet.",
        ["srv.rejoin"] = "Runde neu joinen (gleiche Map)",
        ["srv.rehook"] = "Script neu verbinden (wenn Kampf nicht toetet)",
        ["srv.waitGuns"] = "Auf Runde warten + Waffen suchen",
        ["srv.count"] = "Wie viele Zombies hier?",
        ["n.aura"] = "Aura",
        ["n.auraBody"] = "1 Kugel schiessen, dann trifft Aura staerker.",
        ["n.trigger"] = "Auto-Feuer",
        ["n.triggerBody"] = "Schau auf ein Zombie. Erst 1 Kugel.",
        ["n.killAll"] = "Alle toten",
        ["n.killOn"] = "AN. %s tot + neue auch.",
        ["n.killOff"] = "AUS.",
        ["n.killed"] = "%s Zombie(s) getoetet.",
        ["n.money"] = "Geld",
        ["n.moneyAdd"] = "+%s Punkte.",
        ["n.autoOn"] = "AUTO AN: +%s / s",
        ["n.autoOff"] = "AUTO AUS",
        ["n.ammo"] = "Munition",
        ["n.ammoOn"] = "AN — Waffen fuellen sich.",
        ["n.ammoOff"] = "AUS.",
        ["n.ammoFill"] = "Fuellen gesendet.",
        ["n.guns"] = "Waffen",
        ["n.enterFirst"] = "Erst in die Runde, dann Waffen suchen.",
        ["n.noneFound"] = "Nichts. Geh zu einer Wand, dann Suchen.",
        ["n.scanWait"] = "Warte auf Runde (max 20s)...",
        ["n.pickFirst"] = "Erst Waffen suchen, dann eine waehlen.",
        ["n.pickOne"] = "Waehle eine Waffe aus der Liste.",
        ["n.noBox"] = "Keine Box. Geh zur Mystery Box, dann Suchen.",
        ["n.wallsBought"] = "%s Wandwaffe(n) gekauft.",
        ["n.pap"] = "PAP",
        ["n.noPap"] = "0 Maschine. Geh zum Pack-a-Punch, dann Suchen.",
        ["n.papFound"] = "%s Maschine(n) gefunden.",
        ["n.held"] = "Waffe in der Hand: %s",
        ["n.papBusy"] = "Max-Upgrade laeuft...",
        ["n.noGun"] = "Keine Waffe in der Hand.",
        ["n.gunStat"] = "%s | Stufe %d | %s%s",
        ["n.effect"] = " | Effekt=%s",
        ["n.fly"] = "Flug",
        ["n.flyOn"] = "AN — Tempo %s",
        ["n.flyOff"] = "AUS",
        ["n.mode2"] = "Modus 2 AN",
        ["n.modeNorm"] = "Normaler Modus",
        ["n.script"] = "Script",
        ["n.okCombat"] = "OK, Kampf bereit",
        ["n.notReady"] = "Nicht bereit",
        ["n.remoteOk"] = " | Remote OK",
        ["n.noRemote"] = " | Remote fehlt",
        ["n.waitPart"] = "Warte auf die Runde...",
        ["n.notInMatch"] = "Noch nicht in der Runde. Nochmal wenn Zombies / Waende da sind.",
        ["n.zombies"] = "Zombies",
        ["n.zcount"] = "%s Zombie(s).",
        ["n.readyTitle"] = "XHUB",
        ["n.readyBody"] = "Bereit. Sprache = FR/EN. Kampf = toten (30k / Zombie). Geld = Punkte. Flug = fliegen.",
        ["n.langTitle"] = "Sprache",
        ["n.langBody"] = "Ganzes Menu jetzt auf Deutsch.",
    },
    it = {
        ["win.name"] = "XHUB · Reminiscence",
        ["win.sub"] = "Combattimento · Soldi · Armi · Volo",
        ["tab.lang"] = "Lingua",
        ["tab.guide"] = "Guida",
        ["tab.combat"] = "Combattimento",
        ["tab.money"] = "Soldi",
        ["tab.ammo"] = "Munizioni",
        ["tab.guns"] = "Armi",
        ["tab.vision"] = "Visione",
        ["tab.fly"] = "Volo",
        ["tab.server"] = "Server",
        ["lang.howTitle"] = "Cambia la lingua del menu",
        ["lang.howBody"] = "Clicca Francais o English (o un'altra). TUTTI i testi cambiano. I toggle restano attivi.",
        ["lang.pick"] = "O scegli dalla lista",
        ["guide.tabsTitle"] = "Le schede (in alto)",
        ["guide.tabsBody"] = "Combattimento = uccidere.   Soldi = punti (30.000 per zombie).   Munizioni = prossimamente.   Armi = prossimamente.   Visione = vedere.   Volo = volare.   Server = rientrare.",
        ["guide.startTitle"] = "Nuovo? Fai questo",
        ["guide.startBody"] = "1) Apri Combattimento.  2) Aura (intorno a te) O Aimbot (tieni clic sinistro).  3) Spara 1 proiettile vero.  4) 30.000 punti per zombie.  5) Volo per volare.",
        ["combat.howTitle"] = "Scegli UN modo (o piu)",
        ["combat.howBody"] = "Aimbot = tieni clic sinistro.   Aura = colpisce intorno.   Uccidi tutti = non spari.   1 colpo prima.   Ogni zombie = 30.000 punti.",

        ["combat.silentTitle"] = "SILENT AIM",
        ["combat.silentBody"] = "Attiva SILENT AIM sotto e TIENI clic sinistro. Mira per te senza muovere il mirino.",
        ["combat.secSilent"] = "Silent Aim",
        ["combat.secKill"] = "Uccidere",
        ["combat.aimbot"] = "Silent Aim — mira per te (tieni clic sinistro)",
        ["combat.multi"] = "Multi — colpisce TUTTI gli zombie davanti",
        ["combat.aura"] = "Aura — uccide intorno (senza mirare)",
        ["combat.trigger"] = "Auto-fuoco — spara allo zombie al centro",
        ["combat.killAll"] = "Uccidi tutti — tutti gli zombie muoiono da soli",
        ["combat.killNow"] = "Uccidi tutti ORA (1 volta)",
        ["combat.secSet"] = "Impostazioni (puoi lasciarle)",
        ["combat.aimWhere"] = "Dove mirare sullo zombie",
        ["aim.head"] = "Testa",
        ["aim.body"] = "Corpo",
        ["aim.chest"] = "Petto",
        ["aim.torso"] = "Torso",
        ["combat.fov"] = "Zona aimbot (piu grande = piu facile)",
        ["combat.multiFov"] = "Zona Multi",
        ["combat.multiRange"] = "Distanza max Multi",
        ["combat.auraRange"] = "Distanza aura",
        ["combat.dmg"] = "Forza danno (1 = normale, 20 = molto forte)",
        ["combat.visible"] = "Aimbot: solo zombie che VEDI (non attraverso i muri)",
        ["combat.aimRate"] = "Velocita aimbot (clic tenuto)",
        ["combat.trigFov"] = "Precisione auto-fuoco (piu grande = piu facile)",
        ["combat.trigRate"] = "Velocita auto-fuoco",
        ["combat.trigClick"] = "Auto-fuoco: clicca anche il mouse",
        ["combat.tracer"] = "Linea verde = conferma dello sparo",
        ["combat.tracerColor"] = "Colore della linea",
        ["combat.fovCircle"] = "Cerchio a schermo (zona di mira)",
        ["combat.killRate"] = "Uccidi tutti: velocita (lascia 1 se non sai)",
        ["money.howTitle"] = "Come avere punti",
        ["money.howBody"] = "Ogni zombie ucciso = 30.000 punti. Puoi anche Aggiungere un importo, o Auto ogni secondo. Serve per porte e armi.",
        ["money.secKills"] = "Punti quando uccidi (30.000 / zombie)",
        ["money.autoReward"] = "Guadagna 30.000 punti per zombie (Aimbot / Aura)",
        ["money.killAllReward"] = "Anche 30.000 con Uccidi tutti",
        ["money.secGive"] = "Dai punti",
        ["money.amount"] = "Quanto denaro (scrivi un numero)",
        ["money.amountPh"] = "esempio: 30000",
        ["money.slider"] = "O scegli con lo slider",
        ["money.add"] = "Aggiungi i soldi (1 volta)",
        ["money.auto"] = "Aggiungi da solo ogni secondo",
        ["ammo.howTitle"] = "Prossimamente",
        ["ammo.howBody"] = "Munizioni infinite in arrivo. Questa scheda non e ancora attiva.",
        ["ammo.inf"] = "Munizioni infinite — non ricaricare mai",
        ["ammo.fill"] = "Riempi le armi ora (1 volta)",
        ["guns.howTitle"] = "Prossimamente",
        ["guns.howBody"] = "Le armi (muro, cassa, PAP) arrivano presto. Questa scheda non e ancora attiva.",
        ["guns.result"] = "Risultato",
        ["guns.needScan"] = "Non ancora cercato. Clicca Cerca armi.",
        ["guns.waitLobby"] = "Non ancora in partita. Aspetta zombie / muri, poi Cerca.",
        ["guns.noneFound"] = "0 armi. Avvicinati a muro, cassa o PAP, poi Cerca.",
        ["guns.none"] = "(nessuna arma)",
        ["guns.needPick"] = "(Cerca prima)",
        ["guns.scanFmt"] = "%d armi | Muro %d | Cassa %d | PAP %d | Lista %d\nIn mano: %s\n%s%s",
        ["guns.more"] = "\n... +%s altre",
        ["guns.notifyFound"] = "%d armi (muro %d, cassa %d, PAP %d)",
        ["guns.scan"] = "Cerca armi (muri + cassa)",
        ["guns.pick"] = "Scegli l'arma qui",
        ["guns.type"] = "O scrivi il nome",
        ["guns.namePh"] = "es: M14 o Ray Gun",
        ["guns.buy"] = "Compra l'arma (con i tuoi punti)",
        ["guns.free"] = "Compra gratis (da soldi + arma)",
        ["guns.box"] = "Apri la cassa misteriosa (1 volta)",
        ["guns.allWalls"] = "Compra TUTTE le armi al muro",
        ["guns.papSec"] = "Migliora l'arma (Pack-a-Punch)",
        ["guns.papHowTitle"] = "Come migliorare",
        ["guns.papHowBody"] = "Arma in mano, vai alla PAP, Cerca se serve, poi Upgrade max.",
        ["guns.papScan"] = "Cerca la macchina PAP",
        ["guns.up1"] = "Migliora 1 volta (arma in mano)",
        ["guns.upMax"] = "Migliora al massimo",
        ["guns.status"] = "Vedi se l'arma e migliorata",
        ["guns.enterMatch"] = "Entra in partita (zombie / muri), poi Cerca armi.",
        ["esp.howTitle"] = "Vedi gli zombie",
        ["esp.howBody"] = "Attiva Vedi attraverso i muri. Nome, vita, distanza. Linee opzionali.",
        ["esp.on"] = "Vedi attraverso i muri",
        ["esp.name"] = "Mostra il nome",
        ["esp.hp"] = "Mostra la vita",
        ["esp.dist"] = "Mostra la distanza",
        ["esp.skel"] = "Disegna le ossa",
        ["esp.tracer"] = "Linea dal basso dello schermo",
        ["esp.snap"] = "Linea dal mirino alla testa",
        ["esp.team"] = "Nascondi alleati (solo zombie)",
        ["esp.max"] = "Distanza max",
        ["esp.zcolor"] = "Colore zombie",
        ["esp.acolor"] = "Colore alleati",
        ["fly.howTitle"] = "Come volare",
        ["fly.howBody"] = "Attiva Vola. WASD = muovi. Q = scendi, E = sali. Troppo lento? Velocita 50. Modo 2 = se il volo bugga.",
        ["fly.on"] = "Vola",
        ["fly.mode2"] = "Modo 2 (se il volo normale bugga)",
        ["fly.speed"] = "Velocita (1 = lento, 50 = veloce, 200 = molto veloce)",
        ["fly.alpha"] = "Personaggio trasparente in volo",
        ["srv.howTitle"] = "Se qualcosa smette di funzionare",
        ["srv.howBody"] = "Rientra = stessa mappa.  Ricollega = se Combattimento non uccide.",
        ["srv.rejoin"] = "Rientra in partita (stessa mappa)",
        ["srv.rehook"] = "Ricollega lo script (se Combattimento non uccide)",
        ["srv.waitGuns"] = "Aspetta partita + cerca armi",
        ["srv.count"] = "Quanti zombie ci sono?",
        ["n.aura"] = "Aura",
        ["n.auraBody"] = "Spara 1 colpo, poi l'aura colpisce di piu.",
        ["n.trigger"] = "Auto-fuoco",
        ["n.triggerBody"] = "Guarda uno zombie. Spara 1 colpo prima.",
        ["n.killAll"] = "Uccidi tutti",
        ["n.killOn"] = "ON. %s uccisi + anche i prossimi.",
        ["n.killOff"] = "OFF.",
        ["n.killed"] = "%s zombie uccisi.",
        ["n.money"] = "Soldi",
        ["n.moneyAdd"] = "+%s punti.",
        ["n.autoOn"] = "AUTO ON: +%s / s",
        ["n.autoOff"] = "AUTO OFF",
        ["n.ammo"] = "Munizioni",
        ["n.ammoOn"] = "ON — le armi si riempiono.",
        ["n.ammoOff"] = "OFF.",
        ["n.ammoFill"] = "Riempimento inviato.",
        ["n.guns"] = "Armi",
        ["n.enterFirst"] = "Entra in partita prima, poi Cerca armi.",
        ["n.noneFound"] = "Niente. Avvicinati a un muro poi Cerca.",
        ["n.scanWait"] = "Attesa partita (max 20s)...",
        ["n.pickFirst"] = "Cerca armi, poi scegline una.",
        ["n.pickOne"] = "Scegli un'arma dalla lista.",
        ["n.noBox"] = "Nessuna cassa. Avvicinati alla Mystery Box poi Cerca.",
        ["n.wallsBought"] = "%s arma/i al muro comprata/e.",
        ["n.pap"] = "PAP",
        ["n.noPap"] = "0 macchina. Avvicinati al Pack-a-Punch poi Cerca.",
        ["n.papFound"] = "%s macchina/e trovata/e.",
        ["n.held"] = "Arma in mano: %s",
        ["n.papBusy"] = "Upgrade max in corso...",
        ["n.noGun"] = "Nessuna arma in mano.",
        ["n.gunStat"] = "%s | livello %d | %s%s",
        ["n.effect"] = " | effetto=%s",
        ["n.fly"] = "Volo",
        ["n.flyOn"] = "ON — velocita %s",
        ["n.flyOff"] = "OFF",
        ["n.mode2"] = "Modo 2 ON",
        ["n.modeNorm"] = "Modo normale",
        ["n.script"] = "Script",
        ["n.okCombat"] = "OK, Combattimento pronto",
        ["n.notReady"] = "Non pronto",
        ["n.remoteOk"] = " | remote OK",
        ["n.noRemote"] = " | remote assente",
        ["n.waitPart"] = "Attesa della partita...",
        ["n.notInMatch"] = "Non ancora in partita. Riprova quando ci sono zombie / muri.",
        ["n.zombies"] = "Zombie",
        ["n.zcount"] = "%s zombie.",
        ["n.readyTitle"] = "XHUB",
        ["n.readyBody"] = "Pronto. Lingua = FR/EN. Combattimento = uccidere (30k / zombie). Soldi = punti. Volo = volare.",
        ["n.langTitle"] = "Lingua",
        ["n.langBody"] = "Tutto il menu e in Italiano.",
    },
    ru = {
        ["win.name"] = "XHUB · Reminiscence",
        ["win.sub"] = "Бой · Деньги · Оружие · Полёт",
        ["tab.lang"] = "Язык",
        ["tab.guide"] = "Гайд",
        ["tab.combat"] = "Бой",
        ["tab.money"] = "Деньги",
        ["tab.ammo"] = "Патроны",
        ["tab.guns"] = "Оружие",
        ["tab.vision"] = "ESP",
        ["tab.fly"] = "Полёт",
        ["tab.server"] = "Сервер",
        ["lang.howTitle"] = "Сменить язык всего меню",
        ["lang.howBody"] = "Нажми Francais или English (или другой). Весь текст меню меняется. Твои опции остаются.",
        ["lang.pick"] = "Или выбери из списка",
        ["guide.tabsTitle"] = "Вкладки (сверху)",
        ["guide.tabsBody"] = "Бой = убивать.   Деньги = очки (30 000 за зомби).   Патроны = скоро.   Оружие = скоро.   ESP = видеть.   Полёт = летать.   Сервер = перезаход.",
        ["guide.startTitle"] = "Новичок? Сделай так",
        ["guide.startBody"] = "1) Открой Бой.  2) Aura (вокруг тебя) ИЛИ Aimbot (держи ЛКМ).  3) Сначала 1 настоящий выстрел.  4) 30 000 очков за зомби.  5) Полёт — чтобы летать.",
        ["combat.howTitle"] = "Выбери ОДИН режим (или несколько)",
        ["combat.howBody"] = "Aimbot = держи ЛКМ.   Aura = бьёт вокруг.   Убить всех = без стрельбы.   Сначала 1 выстрел.   Каждый зомби = 30 000 очков.",

        ["combat.silentTitle"] = "SILENT AIM",
        ["combat.silentBody"] = "Включи SILENT AIM ниже и ДЕРЖИ ЛКМ. Целится за тебя, прицел не двигается.",
        ["combat.secSilent"] = "Silent Aim",
        ["combat.secKill"] = "Убивать",
        ["combat.aimbot"] = "Silent Aim — целится за тебя (держи ЛКМ)",
        ["combat.multi"] = "Multi — бьёт ВСЕХ зомби перед тобой",
        ["combat.aura"] = "Aura — убивает вокруг (без прицела)",
        ["combat.trigger"] = "Автоогонь — сам стреляет в зомби в центре",
        ["combat.killAll"] = "Убить всех — все зомби умирают сами",
        ["combat.killNow"] = "Убить всех СЕЙЧАС (1 раз)",
        ["combat.secSet"] = "Настройки (можно не трогать)",
        ["combat.aimWhere"] = "Куда целиться по зомби",
        ["aim.head"] = "Голова",
        ["aim.body"] = "Тело",
        ["aim.chest"] = "Грудь",
        ["aim.torso"] = "Торс",
        ["combat.fov"] = "Зона Aimbot (больше = проще)",
        ["combat.multiFov"] = "Зона Multi",
        ["combat.multiRange"] = "Макс. дистанция Multi",
        ["combat.auraRange"] = "Дистанция ауры",
        ["combat.dmg"] = "Сила урона (1 = обычно, 20 = очень сильно)",
        ["combat.visible"] = "Aimbot: только тех, кого ВИДИШЬ (не сквозь стены)",
        ["combat.aimRate"] = "Скорость Aimbot (пока держишь клик)",
        ["combat.trigFov"] = "Точность автоогня (больше = проще)",
        ["combat.trigRate"] = "Скорость автоогня",
        ["combat.trigClick"] = "Автоогонь: также кликать мышью",
        ["combat.tracer"] = "Зелёная линия = подтверждение выстрела",
        ["combat.tracerColor"] = "Цвет линии",
        ["combat.fovCircle"] = "Круг на экране (зона прицела)",
        ["combat.killRate"] = "Убить всех: скорость (оставь 1 если не знаешь)",
        ["money.howTitle"] = "Как получить очки",
        ["money.howBody"] = "Каждый убитый зомби = 30 000 очков. Можно также Добавить сумму или Авто каждую секунду. Для дверей и оружия.",
        ["money.secKills"] = "Очки за убийства (30 000 / зомби)",
        ["money.autoReward"] = "30 000 очков за зомби (Aimbot / Aura)",
        ["money.killAllReward"] = "Также 30 000 с Убить всех",
        ["money.secGive"] = "Выдать очки",
        ["money.amount"] = "Сколько денег (напиши число)",
        ["money.amountPh"] = "пример: 30000",
        ["money.slider"] = "Или выбери ползунком",
        ["money.add"] = "Добавить деньги (1 раз)",
        ["money.auto"] = "Добавлять каждую секунду",
        ["ammo.howTitle"] = "Скоро будет",
        ["ammo.howBody"] = "Бесконечные патроны скоро. Эта вкладка пока не активна.",
        ["ammo.inf"] = "Бесконечные патроны — без перезарядки",
        ["ammo.fill"] = "Наполнить оружие сейчас (1 раз)",
        ["guns.howTitle"] = "Скоро будет",
        ["guns.howBody"] = "Оружие (стена, ящик, PAP) скоро. Эта вкладка пока не активна.",
        ["guns.result"] = "Результат",
        ["guns.needScan"] = "Ещё не искали. Нажми Найти оружие.",
        ["guns.waitLobby"] = "Ещё не в матче. Дождись зомби / стен, потом Найти.",
        ["guns.noneFound"] = "0 оружия. Подойди к стене, ящику или PAP, потом Найти.",
        ["guns.none"] = "(нет оружия)",
        ["guns.needPick"] = "(Сначала найти)",
        ["guns.scanFmt"] = "%d оружия | Стена %d | Ящик %d | PAP %d | Список %d\nВ руках: %s\n%s%s",
        ["guns.more"] = "\n... +%s ещё",
        ["guns.notifyFound"] = "%d оружия (стена %d, ящик %d, PAP %d)",
        ["guns.scan"] = "Найти оружие (стены + ящик)",
        ["guns.pick"] = "Выбери оружие здесь",
        ["guns.type"] = "Или напиши название",
        ["guns.namePh"] = "напр: M14 или Ray Gun",
        ["guns.buy"] = "Купить выбранное (за свои очки)",
        ["guns.free"] = "Купить бесплатно (даёт деньги + оружие)",
        ["guns.box"] = "Открыть ящик (1 раз)",
        ["guns.allWalls"] = "Купить ВСЕ оружие со стен",
        ["guns.papSec"] = "Улучшить оружие (Pack-a-Punch)",
        ["guns.papHowTitle"] = "Как улучшить",
        ["guns.papHowBody"] = "Возьми оружие, подойди к PAP, Найти если нужно, Улучшить на максимум.",
        ["guns.papScan"] = "Найти машину PAP",
        ["guns.up1"] = "Улучшить 1 раз (в руках)",
        ["guns.upMax"] = "Улучшить на максимум",
        ["guns.status"] = "Проверить улучшение оружия",
        ["guns.enterMatch"] = "Зайди в матч (зомби / стены), потом Найти оружие.",
        ["esp.howTitle"] = "Видеть зомби",
        ["esp.howBody"] = "Включи Видеть сквозь стены. Имя, HP, дистанция. Линии по желанию.",
        ["esp.on"] = "Видеть сквозь стены",
        ["esp.name"] = "Показать имя",
        ["esp.hp"] = "Показать HP",
        ["esp.dist"] = "Показать дистанцию",
        ["esp.skel"] = "Рисовать кости зомби",
        ["esp.tracer"] = "Линия снизу экрана",
        ["esp.snap"] = "Линия от прицела к голове",
        ["esp.team"] = "Скрыть союзников (только зомби)",
        ["esp.max"] = "Макс. дистанция",
        ["esp.zcolor"] = "Цвет зомби",
        ["esp.acolor"] = "Цвет союзников",
        ["fly.howTitle"] = "Как летать",
        ["fly.howBody"] = "Включи Полёт. WASD = движение. Q = вниз, E = вверх. Медленно — скорость 50. Режим 2 — если обычный полёт глючит.",
        ["fly.on"] = "Летать",
        ["fly.mode2"] = "Режим 2 (если обычный полёт глючит)",
        ["fly.speed"] = "Скорость (1 = медленно, 50 = быстро, 200 = очень быстро)",
        ["fly.alpha"] = "Прозрачный персонаж в полёте",
        ["srv.howTitle"] = "Если что-то сломалось",
        ["srv.howBody"] = "Перезаход = та же карта.  Переподключить = если Бой не убивает.",
        ["srv.rejoin"] = "Перезайти (та же карта)",
        ["srv.rehook"] = "Переподключить скрипт (если Бой не убивает)",
        ["srv.waitGuns"] = "Ждать матч + найти оружие",
        ["srv.count"] = "Сколько тут зомби?",
        ["n.aura"] = "Aura",
        ["n.auraBody"] = "Сделай 1 выстрел, потом аура бьёт сильнее.",
        ["n.trigger"] = "Автоогонь",
        ["n.triggerBody"] = "Смотри на зомби. Сначала 1 выстрел.",
        ["n.killAll"] = "Убить всех",
        ["n.killOn"] = "ВКЛ. %s убито + следующие тоже.",
        ["n.killOff"] = "ВЫКЛ.",
        ["n.killed"] = "%s зомби убито.",
        ["n.money"] = "Деньги",
        ["n.moneyAdd"] = "+%s очков.",
        ["n.autoOn"] = "АВТО ВКЛ: +%s / с",
        ["n.autoOff"] = "АВТО ВЫКЛ",
        ["n.ammo"] = "Патроны",
        ["n.ammoOn"] = "ВКЛ — оружие наполняется.",
        ["n.ammoOff"] = "ВЫКЛ.",
        ["n.ammoFill"] = "Наполнение отправлено.",
        ["n.guns"] = "Оружие",
        ["n.enterFirst"] = "Сначала зайди в матч, потом Найти оружие.",
        ["n.noneFound"] = "Ничего. Подойди к стене, потом Найти.",
        ["n.scanWait"] = "Ждём матч (макс. 20с)...",
        ["n.pickFirst"] = "Найди оружие, потом выбери.",
        ["n.pickOne"] = "Выбери оружие из списка.",
        ["n.noBox"] = "Нет ящика. Подойди к Mystery Box, потом Найти.",
        ["n.wallsBought"] = "%s оружие со стен куплено.",
        ["n.pap"] = "PAP",
        ["n.noPap"] = "0 машин. Подойди к Pack-a-Punch, потом Найти.",
        ["n.papFound"] = "%s машин найдено.",
        ["n.held"] = "В руках: %s",
        ["n.papBusy"] = "Макс. улучшение...",
        ["n.noGun"] = "Нет оружия в руках.",
        ["n.gunStat"] = "%s | уровень %d | %s%s",
        ["n.effect"] = " | эффект=%s",
        ["n.fly"] = "Полёт",
        ["n.flyOn"] = "ВКЛ — скорость %s",
        ["n.flyOff"] = "ВЫКЛ",
        ["n.mode2"] = "Режим 2 ВКЛ",
        ["n.modeNorm"] = "Обычный режим",
        ["n.script"] = "Скрипт",
        ["n.okCombat"] = "ОК, Бой готов",
        ["n.notReady"] = "Не готово",
        ["n.remoteOk"] = " | remote ОК",
        ["n.noRemote"] = " | remote нет",
        ["n.waitPart"] = "Ждём матч...",
        ["n.notInMatch"] = "Ещё не в матче. Повтори когда появятся зомби / стены.",
        ["n.zombies"] = "Зомби",
        ["n.zcount"] = "%s зомби.",
        ["n.readyTitle"] = "XHUB",
        ["n.readyBody"] = "Готово. Язык = FR/EN. Бой = убивать (30k / зомби). Деньги = очки. Полёт = летать.",
        ["n.langTitle"] = "Язык",
        ["n.langBody"] = "Всё меню теперь на русском.",
    },
}

local LANG_LIST = {
    { id = "fr", label = "Francais" },
    { id = "en", label = "English" },
    { id = "es", label = "Espanol" },
    { id = "pt", label = "Portugues" },
    { id = "de", label = "Deutsch" },
    { id = "it", label = "Italiano" },
    { id = "ru", label = "Russkiy" },
}
local LANG_BY_LABEL = {}
for _, Lrow in ipairs(LANG_LIST) do
    LANG_BY_LABEL[Lrow.label] = Lrow.id
end

M.state.lang = "fr"
local I18N_CTRL = {}
local applyLang

local function T(key)
    local p = I18N[M.state.lang] or I18N.fr
    if p and p[key] then return p[key] end
    if I18N.en and I18N.en[key] then return I18N.en[key] end
    if I18N.fr and I18N.fr[key] then return I18N.fr[key] end
    return tostring(key)
end

local function Tf(key, ...)
    return string.format(T(key), ...)
end

local function guiRoots()
    local r = {}
    pcall(function()
        if typeof(gethui) == "function" then
            local h = gethui()
            if h then r[#r + 1] = h end
        end
    end)
    r[#r + 1] = CoreGui
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then r[#r + 1] = pg end
    return r
end

local function findLastTitle(text)
    local last
    for _, root in ipairs(guiRoots()) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text == text then
                    last = d
                end
            end
        end
    end
    return last
end

local function findLastPlaceholder(ph)
    local last
    for _, root in ipairs(guiRoots()) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("TextBox") and d.PlaceholderText == ph then
                    last = d
                end
            end
        end
    end
    return last
end

local AIM_PARTS = {
    ["Head"] = "Head",
    ["HumanoidRootPart"] = "HumanoidRootPart",
    ["UpperTorso"] = "UpperTorso",
    ["Torso"] = "Torso",
}

local function fillAimMap()
    for _, code in ipairs({ "fr", "en", "es", "pt", "de", "it", "ru" }) do
        local p = I18N[code]
        if p then
            AIM_PARTS[p["aim.head"]] = "Head"
            AIM_PARTS[p["aim.body"]] = "HumanoidRootPart"
            AIM_PARTS[p["aim.chest"]] = "UpperTorso"
            AIM_PARTS[p["aim.torso"]] = "Torso"
        end
    end
end

local function aimOptions()
    return { T("aim.head"), T("aim.body"), T("aim.chest"), T("aim.torso") }
end

local function isGunPlaceholder(s)
    if not s then return true end
    for _, pack in pairs(I18N) do
        if type(pack) == "table" and (s == pack["guns.needPick"] or s == pack["guns.none"]) then
            return true
        end
    end
    return false
end

local function bindCtrl(kind, key, obj, extra)
    local rec = extra or {}
    rec.kind = kind
    rec.key = key
    rec.obj = obj
    rec.label = rec.label or findLastTitle(T(key))
    I18N_CTRL[#I18N_CTRL + 1] = rec
    return obj
end

local function bindTab(tab, key)
    local name = T(key)
    local rec = { kind = "tab", key = key }
    for _, root in ipairs(guiRoots()) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("TextLabel") and d.Name == "Title" and d.Text == name then
                    local p = d.Parent
                    if p and p:IsA("Frame") then
                        rec.label = d
                        rec.button = p
                    end
                end
                if d:IsA("ScrollingFrame") and d.Name == name then
                    rec.page = d
                end
            end
        end
    end
    I18N_CTRL[#I18N_CTRL + 1] = rec
    return tab
end

local TAB_ICON = 4483362458
local Window = Rayfield:CreateWindow({
    Theme = XHUB_THEME,
    Name = T("win.name"),
    LoadingTitle = "XHUB · Reminiscence Zombies",
    LoadingSubtitle = T("win.sub"),
    ConfigurationSaving = { Enabled = true, FolderName = "ReminiscenceZombiesHub", FileName = "Config" },
    KeySystem = false,
})

M._winTitle = findLastTitle(T("win.name"))

local function notify(title, content, dur)
    Rayfield:Notify({ Title = title, Content = content, Duration = dur or 4 })
end

local function CTab(key)
    local tab = Window:CreateTab(T(key), TAB_ICON)
    return bindTab(tab, key)
end

local function CPara(tab, titleKey, contentKey)
    local el = tab:CreateParagraph({ Title = T(titleKey), Content = T(contentKey) })
    I18N_CTRL[#I18N_CTRL + 1] = { kind = "para", obj = el, titleKey = titleKey, contentKey = contentKey }
    return el
end

local function CSection(tab, key)
    local el = tab:CreateSection(T(key))
    return bindCtrl("section", key, el)
end

local function CToggle(tab, spec)
    local key = spec.Key
    spec.Name = T(key)
    spec.Key = nil
    local el = tab:CreateToggle(spec)
    return bindCtrl("toggle", key, el)
end

local function CSlider(tab, spec)
    local key = spec.Key
    spec.Name = T(key)
    spec.Key = nil
    local el = tab:CreateSlider(spec)
    return bindCtrl("slider", key, el)
end

local function CButton(tab, spec)
    local key = spec.Key
    spec.Name = T(key)
    spec.Key = nil
    local el = tab:CreateButton(spec)
    return bindCtrl("button", key, el)
end

local function CColor(tab, spec)
    local key = spec.Key
    spec.Name = T(key)
    spec.Key = nil
    local el = tab:CreateColorPicker(spec)
    return bindCtrl("color", key, el)
end

local function CInput(tab, spec)
    local key = spec.Key
    local phKey = spec.PhKey
    spec.Name = T(key)
    spec.PlaceholderText = T(phKey)
    spec.Key = nil
    spec.PhKey = nil
    local el = tab:CreateInput(spec)
    return bindCtrl("input", key, el, { phKey = phKey, box = findLastPlaceholder(T(phKey)) })
end

fillAimMap()

--------------------------------------------------------------
-- ONGLET LANGUE
--------------------------------------------------------------
local Lang = CTab("tab.lang")
CPara(Lang, "lang.howTitle", "lang.howBody")

local function langBtn(code, label)
    Lang:CreateButton({
        Name = label,
        Callback = function()
            applyLang(code)
        end,
    })
end
langBtn("fr", "Francais")
langBtn("en", "English")
langBtn("es", "Espanol")
langBtn("pt", "Portugues")
langBtn("de", "Deutsch")
langBtn("it", "Italiano")
langBtn("ru", "Russkiy")

local langDropdown
langDropdown = Lang:CreateDropdown({
    Name = T("lang.pick"),
    Options = { "Francais", "English", "Espanol", "Portugues", "Deutsch", "Italiano", "Russkiy" },
    CurrentOption = { "Francais" },
    MultipleOptions = false,
    Flag = "uiLang",
    Callback = function(o)
        if M._langLock then return end
        local pick = (type(o) == "table" and o[1]) or o
        local code = LANG_BY_LABEL[pick]
        if code then applyLang(code) end
    end,
})
bindCtrl("dropdown", "lang.pick", langDropdown)

applyLang = function(code, silent)
    if not I18N[code] then return end
    M._langLock = true
    M.state.lang = code
    for _, rec in ipairs(I18N_CTRL) do
        if rec.kind == "para" then
            pcall(function()
                rec.obj:Set({ Title = T(rec.titleKey), Content = T(rec.contentKey) })
            end)
        elseif rec.kind == "para_dyn" then
            pcall(function()
                rec.obj:Set({ Title = T(rec.titleKey), Content = rec.lastContent or T("guns.needScan") })
            end)
        elseif rec.kind == "tab" then
            local text = T(rec.key)
            if rec.label then rec.label.Text = text end
            if rec.page then rec.page.Name = text end
            if rec.button then
                pcall(function() rec.button.Name = text end)
                pcall(function()
                    if rec.label and rec.label.TextBounds then
                        rec.button.Size = UDim2.new(0, rec.label.TextBounds.X + 36, 0, 30)
                    end
                end)
            end
        elseif rec.kind == "input" then
            local text = T(rec.key)
            rec.obj.Name = text
            if rec.label then rec.label.Text = text end
            if rec.box then rec.box.PlaceholderText = T(rec.phKey) end
        elseif rec.kind == "aimdrop" then
            rec.obj.Name = T(rec.key)
            if rec.label then rec.label.Text = T(rec.key) end
            local opts = aimOptions()
            pcall(function()
                if rec.obj.Refresh then
                    rec.obj:Refresh(opts, true)
                end
            end)
        elseif rec.kind == "button" or rec.kind == "section" then
            local text = T(rec.key)
            rec.obj.Name = text
            if rec.label then rec.label.Text = text end
            pcall(function() rec.obj:Set(text) end)
        else
            local text = T(rec.key)
            rec.obj.Name = text
            if rec.label then rec.label.Text = text end
        end
    end
    if M._winTitle then
        pcall(function() M._winTitle.Text = T("win.name") end)
    end
    -- sync dropdown label without retriggering
    pcall(function()
        if langDropdown and langDropdown.Set then
            for _, Lrow in ipairs(LANG_LIST) do
                if Lrow.id == code then
                    langDropdown:Set({ Lrow.label })
                    break
                end
            end
        end
    end)
    M._langLock = false
    if not silent then
        notify(T("n.langTitle"), T("n.langBody"), 4)
    end
end

--------------------------------------------------------------
-- ONGLET GUIDE
--------------------------------------------------------------
local Guide = CTab("tab.guide")
CPara(Guide, "guide.tabsTitle", "guide.tabsBody")
CPara(Guide, "guide.startTitle", "guide.startBody")

--------------------------------------------------------------
-- ONGLET COMBAT
--------------------------------------------------------------
local Combat = CTab("tab.combat")
CPara(Combat, "combat.howTitle", "combat.howBody")
CPara(Combat, "combat.silentTitle", "combat.silentBody")
CSection(Combat, "combat.secSilent")

CToggle(Combat, {
    Key = "combat.aimbot",
    CurrentValue = false,
    Flag = "silent",
    Callback = function(v) M.state.silent = v end,
})
CToggle(Combat, {
    Key = "combat.multi",
    CurrentValue = false,
    Flag = "multi",
    Callback = function(v) M.state.multi = v end,
})
CSection(Combat, "combat.secKill")
CToggle(Combat, {
    Key = "combat.aura",
    CurrentValue = false, Flag = "aura",
    Callback = function(v)
        M.state.aura = v
        if v and not M.state.dmgTemplate then
            notify(T("n.aura"), T("n.auraBody"), 6)
        end
    end,
})
CToggle(Combat, {
    Key = "combat.trigger",
    CurrentValue = false, Flag = "trigger",
    Callback = function(v)
        M.state.trigger = v
        if v then
            notify(T("n.trigger"), T("n.triggerBody"), 6)
        end
    end,
})
CToggle(Combat, {
    Key = "combat.killAll",
    CurrentValue = false, Flag = "killAll",
    Callback = function(v)
        M.state.killAll = v
        if v then
            local n = killAllNow()
            hookZombieFolder(Workspace:FindFirstChild("Zombies"))
            hookZombieFolder(Workspace:FindFirstChild("SpecialZ"))
            notify(T("n.killAll"), Tf("n.killOn", tostring(n)), 5)
        else
            notify(T("n.killAll"), T("n.killOff"), 3)
        end
    end,
})
CButton(Combat, {
    Key = "combat.killNow",
    Callback = function()
        local n = killAllNow()
        notify(T("n.killAll"), Tf("n.killed", tostring(n)), 4)
    end,
})

CSection(Combat, "combat.secSet")

local aimDrop = Combat:CreateDropdown({
    Name = T("combat.aimWhere"),
    Options = aimOptions(),
    CurrentOption = { T("aim.head") },
    Flag = "silentPart",
    Callback = function(o)
        local pick = (type(o) == "table" and o[1]) or o
        M.state.silentPart = AIM_PARTS[pick] or "Head"
    end,
})
bindCtrl("aimdrop", "combat.aimWhere", aimDrop)

CSlider(Combat, {
    Key = "combat.fov",
    Range = { 40, 700 }, Increment = 10, Suffix = "px",
    CurrentValue = 220, Flag = "fov",
    Callback = function(v) M.state.fov = v end,
})
CSlider(Combat, {
    Key = "combat.multiFov",
    Range = { 100, 1200 }, Increment = 20, Suffix = "px",
    CurrentValue = 500, Flag = "multiFov",
    Callback = function(v) M.state.multiFov = v end,
})
CSlider(Combat, {
    Key = "combat.multiRange",
    Range = { 30, 500 }, Increment = 10, Suffix = "m",
    CurrentValue = 200, Flag = "multiRange",
    Callback = function(v) M.state.multiRange = v end,
})
CSlider(Combat, {
    Key = "combat.auraRange",
    Range = { 20, 300 }, Increment = 10, Suffix = "m",
    CurrentValue = 120, Flag = "auraRange",
    Callback = function(v) M.state.auraRange = v end,
})
CSlider(Combat, {
    Key = "combat.dmg",
    Range = { 1, 20 }, Increment = 1, Suffix = "x",
    CurrentValue = 1, Flag = "damageMult",
    Callback = function(v) M.state.damageMult = v end,
})
CToggle(Combat, {
    Key = "combat.visible",
    CurrentValue = false, Flag = "visibleOnly",
    Callback = function(v) M.state.visibleOnly = v end,
})
CSlider(Combat, {
    Key = "combat.aimRate",
    Range = { 3, 30 }, Increment = 1, Suffix = "/s",
    CurrentValue = 12, Flag = "silentRate",
    Callback = function(v) M.state.silentInterval = 1 / v end,
})
CSlider(Combat, {
    Key = "combat.trigFov",
    Range = { 40, 300 }, Increment = 10, Suffix = "px",
    CurrentValue = 100, Flag = "triggerFov",
    Callback = function(v) M.state.triggerFov = v end,
})
CSlider(Combat, {
    Key = "combat.trigRate",
    Range = { 4, 30 }, Increment = 1, Suffix = "/s",
    CurrentValue = 12, Flag = "triggerRate",
    Callback = function(v) M.state.triggerDelay = 1 / v end,
})
CToggle(Combat, {
    Key = "combat.trigClick",
    CurrentValue = true, Flag = "triggerClick",
    Callback = function(v) M.state.triggerClick = v end,
})
CToggle(Combat, {
    Key = "combat.tracer",
    CurrentValue = true, Flag = "tracer",
    Callback = function(v) M.state.tracer = v end,
})
CColor(Combat, {
    Key = "combat.tracerColor",
    Color = M.state.tracerColor, Flag = "tracerColor",
    Callback = function(c) M.state.tracerColor = c end,
})
CToggle(Combat, {
    Key = "combat.fovCircle",
    CurrentValue = false, Flag = "fovCircle",
    Callback = function(v) M.state.fovCircle = v end,
})
CSlider(Combat, {
    Key = "combat.killRate",
    Range = { 1, 20 }, Increment = 1, Suffix = "",
    CurrentValue = 1, Flag = "killAllRate",
    Callback = function(v) M.state.killAllRate = v * 0.05 end,
})

--------------------------------------------------------------
-- ONGLET ARGENT
--------------------------------------------------------------
local Argent = CTab("tab.money")
CPara(Argent, "money.howTitle", "money.howBody")
CSection(Argent, "money.secKills")
CToggle(Argent, {
    Key = "money.autoReward",
    CurrentValue = true, Flag = "autoReward",
    Callback = function(v) M.state.autoReward = v end,
})
CToggle(Argent, {
    Key = "money.killAllReward",
    CurrentValue = true, Flag = "killAllReward",
    Callback = function(v) M.state.killAllReward = v end,
})
CSection(Argent, "money.secGive")
CInput(Argent, {
    Key = "money.amount",
    PhKey = "money.amountPh",
    CurrentValue = "30000",
    Flag = "pointsAmount",
    Callback = function(txt)
        local n = tonumber(txt)
        if n and n > 0 then
            M.state.pointsAmount = math.floor(n)
        end
    end,
})
CSlider(Argent, {
    Key = "money.slider",
    Range = { 1000, 200000 }, Increment = 1000, Suffix = "pts",
    CurrentValue = 30000, Flag = "pointsSlider",
    Callback = function(v) M.state.pointsAmount = v end,
})
CButton(Argent, {
    Key = "money.add",
    Callback = function()
        local amt = M.state.pointsAmount or 30000
        fireReward(amt, false, nil)
        notify(T("n.money"), Tf("n.moneyAdd", tostring(amt)), 4)
    end,
})
CToggle(Argent, {
    Key = "money.auto",
    CurrentValue = false, Flag = "pointsAuto",
    Callback = function(v)
        M.state.pointsAuto = v
        if v then
            notify(T("n.money"), Tf("n.autoOn", tostring(M.state.pointsAmount)), 4)
        else
            notify(T("n.money"), T("n.autoOff"), 4)
        end
    end,
})

--------------------------------------------------------------
-- ONGLET MUNITIONS
--------------------------------------------------------------
local AmmoTab = CTab("tab.ammo")
CPara(AmmoTab, "ammo.howTitle", "ammo.howBody")

--------------------------------------------------------------
-- ONGLET ARMES
--------------------------------------------------------------
local Armes = CTab("tab.guns")
CPara(Armes, "guns.howTitle", "guns.howBody")

--------------------------------------------------------------
-- ONGLET VISION
--------------------------------------------------------------
local Esp = CTab("tab.vision")
CPara(Esp, "esp.howTitle", "esp.howBody")
CToggle(Esp, { Key = "esp.on", CurrentValue = false, Flag = "esp",
    Callback = function(v) M.state.esp = v end })
CToggle(Esp, { Key = "esp.name", CurrentValue = true, Flag = "espName",
    Callback = function(v) M.state.espName = v end })
CToggle(Esp, { Key = "esp.hp", CurrentValue = true, Flag = "espHealth",
    Callback = function(v) M.state.espHealth = v end })
CToggle(Esp, { Key = "esp.dist", CurrentValue = true, Flag = "espDistance",
    Callback = function(v) M.state.espDistance = v end })
CToggle(Esp, { Key = "esp.skel", CurrentValue = false, Flag = "espSkeleton",
    Callback = function(v) M.state.espSkeleton = v end })
CToggle(Esp, { Key = "esp.tracer", CurrentValue = false, Flag = "espTracer",
    Callback = function(v) M.state.espTracer = v end })
CToggle(Esp, { Key = "esp.snap", CurrentValue = false, Flag = "espSnapline",
    Callback = function(v) M.state.espSnapline = v end })
CToggle(Esp, { Key = "esp.team", CurrentValue = true, Flag = "teamCheck",
    Callback = function(v) M.state.teamCheck = v end })
CSlider(Esp, { Key = "esp.max", Range = { 100, 3000 }, Increment = 50, Suffix = "m",
    CurrentValue = 1000, Flag = "espMaxDist", Callback = function(v) M.state.espMaxDist = v end })
CColor(Esp, { Key = "esp.zcolor", Color = M.state.espColor, Flag = "espColor",
    Callback = function(c) M.state.espColor = c end })
CColor(Esp, { Key = "esp.acolor", Color = M.state.allyColor, Flag = "allyColor",
    Callback = function(c) M.state.allyColor = c end })

--------------------------------------------------------------
-- ONGLET VOL
--------------------------------------------------------------
local PlayerTab = CTab("tab.fly")
CPara(PlayerTab, "fly.howTitle", "fly.howBody")
CToggle(PlayerTab, {
    Key = "fly.on",
    CurrentValue = false,
    Flag = "flyOn",
    Callback = function(v)
        setFlying(v)
        if v then
            notify(T("n.fly"), Tf("n.flyOn", tostring(math.floor(M.state.flySpeed))), 3)
        else
            notify(T("n.fly"), T("n.flyOff"), 3)
        end
    end,
})
CToggle(PlayerTab, {
    Key = "fly.mode2",
    CurrentValue = false,
    Flag = "flyCFrame",
    Callback = function(v)
        M.state.flyCFrame = v
        if M.state.fly then
            setFlying(true)
        end
        notify(T("n.fly"), v and T("n.mode2") or T("n.modeNorm"), 3)
    end,
})
CSlider(PlayerTab, {
    Key = "fly.speed",
    Range = { 1, 500 }, Increment = 1, Suffix = "",
    CurrentValue = 1, Flag = "flySpeed",
    Callback = function(v) M.state.flySpeed = v end,
})
CSlider(PlayerTab, {
    Key = "fly.alpha",
    Range = { 0, 100 }, Increment = 5, Suffix = "%",
    CurrentValue = 75, Flag = "flyAlpha",
    Callback = function(v)
        M.state.flyTransparency = v / 100
        if M.state.fly then flyApplyGhost(true) end
    end,
})

--------------------------------------------------------------
-- ONGLET SERVEUR
--------------------------------------------------------------
local Misc = CTab("tab.server")
CPara(Misc, "srv.howTitle", "srv.howBody")
CButton(Misc, {
    Key = "srv.rejoin",
    Callback = function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end,
})
CButton(Misc, {
    Key = "srv.rehook",
    Callback = function()
        if not M.hooked then
            setupHook()
        end
        local etc = getETC(3)
        notify(T("n.script"),
            (M.hooked and T("n.okCombat") or T("n.notReady"))
                .. (etc and T("n.remoteOk") or T("n.noRemote")),
            5)
    end,
})
CButton(Misc, {
    Key = "srv.count",
    Callback = function()
        notify(T("n.zombies"), Tf("n.zcount", tostring(#getZombies())), 4)
    end,
})

-- Anti-AFK
local VirtualUser = safe(function() return game:GetService("VirtualUser") end)
if VirtualUser then
    LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
end

notify(T("n.readyTitle"), T("n.readyBody"), 6)

pcall(function()
    if Rayfield and Rayfield.LoadConfiguration then Rayfield:LoadConfiguration() end
end)

M.state.infAmmo = false

-- Re-apply after config (uiLang flag) so every bound control is translated
pcall(function()
    local code = M.state.lang or "fr"
    if type(code) ~= "string" or not I18N[code] then code = "fr" end
    applyLang(code, true)
end)
