Bridge.Zones = Bridge.Zones or {}
local Z = Bridge.Zones

local WALL = { r = 186, g = 36, b = 2 }
local LINE = { r = 255, g = 255, b = 255 }
local DISABLED = { 1, 2, 24, 25, 36, 19, 20, 21, 81, 99, 172, 173, 174, 175, 180, 181, 191, 194, 200 }

local Freecam = { camera = nil, pos = vec3(0, 0, 0), rot = vec3(0, 0, 0), fov = 45.0,
    vecX = vec3(0, 0, 0), vecY = vec3(0, 0, 0), vecZ = vec3(0, 0, 0), active = false }

local function eulerToMatrix(rx, ry, rz)
    local ax, ay, az = math.rad(rx), math.rad(ry), math.rad(rz)
    local sx, sy, sz, cx, cy, cz = math.sin(ax), math.sin(ay), math.sin(az), math.cos(ax), math.cos(ay), math.cos(az)
    return
        vec3(cy * cz, cy * sz, -sy),
        vec3(cz * sx * sy - cx * sz, cx * cz - sx * sy * sz, cy * sx),
        vec3(-cx * cz * sy + sx * sz, -cz * sx + cx * sy * sz, cx * cy)
end

local function speedMult()
    local fast, slow = GetDisabledControlNormal(0, 21), GetDisabledControlNormal(0, 19)
    return (1 + (9 * fast)) / (1 + (9 * slow)) * GetFrameTime() * 60
end

local function rotToDir(rot)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    return vec3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
end

local function raycast(camPos)
    local dest = camPos + rotToDir(Freecam.rot) * 5000.0
    local _, hit, coords = GetShapeTestResult(
        StartShapeTestRay(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, -1, PlayerPedId(), 0))
    return hit == 1, coords
end

local function drawWall(p1, p2, minZ, maxZ, c)
    local bl, tl = vec3(p1.x, p1.y, minZ), vec3(p1.x, p1.y, maxZ)
    local br, tr = vec3(p2.x, p2.y, minZ), vec3(p2.x, p2.y, maxZ)
    DrawPoly(bl, tl, br, c.r, c.g, c.b, 48)
    DrawPoly(tl, tr, br, c.r, c.g, c.b, 48)
    DrawPoly(br, tr, tl, c.r, c.g, c.b, 48)
    DrawPoly(br, tl, bl, c.r, c.g, c.b, 48)
end

function Freecam:setPos(p)
    self.pos = p
    SetFocusArea(p)
    LockMinimapPosition(p.x, p.y)
    if self.camera then SetCamCoord(self.camera, p) end
end

function Freecam:setRot(r)
    self.rot = vec3(math.max(-90.0, math.min(90.0, r.x)), r.y % 360, r.z % 360)
    self.vecX, self.vecY, self.vecZ = eulerToMatrix(self.rot.x, self.rot.y, self.rot.z)
    LockMinimapAngle(math.floor(self.rot.z))
    if self.camera then SetCamRot(self.camera, self.rot) end
end

function Freecam:start()
    if self.active then return end
    local gp, gr = GetGameplayCamCoord(), GetGameplayCamRot()
    self.camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(self.camera, self.fov)
    self:setPos(gp)
    self:setRot(vec3(gr.x, 0.0, gr.z))
    SetPlayerControl(PlayerId(), false)
    RenderScriptCams(true, true, 1000)
    self.active = true
end

function Freecam:stop()
    if not self.active then return end
    if self.camera then DestroyCam(self.camera); self.camera = nil end
    ClearFocus()
    UnlockMinimapPosition()
    UnlockMinimapAngle()
    SetPlayerControl(PlayerId(), true)
    RenderScriptCams(false, true, 1000)
    self.active = false
end

function Freecam:update()
    if not self.active or IsPauseMenuActive() then return end
    local s = speedMult()
    local lookX, lookY = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
    local moveX, moveY = GetDisabledControlNormal(0, 30), GetDisabledControlNormal(0, 31)
    local moveZ = GetDisabledControlNormal(0, 152) - GetDisabledControlNormal(0, 153)
    self:setRot(vec3(self.rot.x - lookY * 5, self.rot.y, self.rot.z - lookX * 5))
    self:setPos(self.pos + self.vecX * moveX * s + self.vecY * -moveY * s + vec3(0, 0, moveZ * s))
end

local Builder = { points = {}, minZ = 0, maxZ = 0, active = false, cb = nil }

local function renderPoly()
    local pts = Builder.points
    for i = 1, #pts do
        local p = pts[i]
        DrawLine(p.x, p.y, Builder.minZ, p.x, p.y, Builder.maxZ, LINE.r, LINE.g, LINE.b, 164)
        local nxt = pts[i + 1]
        if nxt then
            DrawLine(p.x, p.y, Builder.maxZ, nxt.x, nxt.y, Builder.maxZ, LINE.r, LINE.g, LINE.b, 184)
            drawWall(p, nxt, Builder.minZ, Builder.maxZ, WALL)
        end
    end
    if #pts > 2 then
        local f, l = pts[1], pts[#pts]
        DrawLine(f.x, f.y, Builder.maxZ, l.x, l.y, Builder.maxZ, LINE.r, LINE.g, LINE.b, 184)
        drawWall(f, l, Builder.minZ, Builder.maxZ, WALL)
    end
end

local function finish()
    if #Builder.points < 3 then
        lib.notify({ type = 'error', description = 'Necesitas al menos 3 puntos' })
        return
    end
    local points, thickness = {}, math.floor(Builder.maxZ - Builder.minZ) + 2
    for _, p in ipairs(Builder.points) do
        points[#points + 1] = { x = p.x, y = p.y, z = Builder.minZ }
    end
    local cb = Builder.cb
    Builder:cleanup()
    if cb then cb({ type = 'poly', points = points, thickness = thickness }) end
end

local function cancel()
    local cb = Builder.cb
    Builder:cleanup()
    if cb then cb(nil) end
end

function Builder:cleanup()
    Freecam:stop()
    self.active, self.points, self.minZ, self.maxZ, self.cb = false, {}, 0, 0, nil
    lib.hideTextUI()
end

---@param opts? table  reservado para futuras opciones
---@param cb fun(geometry: table|nil)  recibe la geometría, o nil si se cancela
function Z.OpenCreator(opts, cb)
    if Builder.active then return end
    local coords = GetEntityCoords(cache.ped)
    Builder.points, Builder.minZ, Builder.maxZ, Builder.cb, Builder.active = {}, coords.z, coords.z + 5, cb, true
    Freecam:start()
    lib.showTextUI(
        '[Mouse Izq] Punto  \n[Mouse Der] Deshacer  \n[Flechas/Scroll] Altura  \n[Enter] Guardar  \n[Backspace] Cancelar',
        { position = 'left-center' })

    CreateThread(function()
        while Builder.active do
            Freecam:update()
            renderPoly()
            local hit, hitCoords = raycast(Freecam.pos)
            if hit then
                DrawMarker(28, hitCoords.x, hitCoords.y, hitCoords.z, 0, 0, 0, 0, 180, 0, 0.5, 0.5, 0.5, 0, 195, 255, 200,
                    false, true, 2, nil, nil, false)
                if IsDisabledControlJustPressed(0, 24) then
                    Builder.minZ = hitCoords.z
                    Builder.points[#Builder.points + 1] = vec3(hitCoords.x, hitCoords.y, hitCoords.z)
                end
            end
            if IsDisabledControlJustPressed(0, 25) and #Builder.points > 0 then
                Builder.points[#Builder.points] = nil
            end
            if IsDisabledControlJustPressed(0, 181) then Builder.maxZ = Builder.maxZ + 1
            elseif IsDisabledControlJustPressed(0, 180) then Builder.maxZ = Builder.maxZ - 1
            elseif IsDisabledControlJustPressed(0, 172) then Builder.maxZ = Builder.maxZ + 1
            elseif IsDisabledControlJustPressed(0, 173) then Builder.minZ = Builder.minZ - 1 end
            if IsDisabledControlJustPressed(0, 191) then finish()
            elseif IsDisabledControlJustPressed(0, 194) then cancel() end
            for i = 1, #DISABLED do DisableControlAction(0, DISABLED[i], true) end
            Wait(0)
        end
    end)
end

function Z.IsCreating() return Builder.active end

AddEventHandler('onResourceStop', function(res)
    if GetCurrentResourceName() == res and Builder.active then Builder:cleanup() end
end)
