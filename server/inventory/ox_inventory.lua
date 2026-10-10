local inv = exports.ox_inventory
local I = Bridge.Inventory

function I.AddItem(src, item, count, metadata, slot)
    return inv:AddItem(src, item, count or 1, metadata, slot)
end

function I.RemoveItem(src, item, count, metadata, slot)
    return inv:RemoveItem(src, item, count or 1, metadata, slot)
end

function I.GetItemCount(src, item, metadata)
    return inv:GetItemCount(src, item, metadata) or 0
end

function I.Search(src, searchType, item, metadata)
    return inv:Search(src, searchType, item, metadata)
end

function I.CanCarryItem(src, item, count, metadata)
    return inv:CanCarryItem(src, item, count or 1, metadata)
end

function I.GetItemDefinition(item)
    local ok, def = pcall(function() return inv:Items(item) end)
    return ok and def or nil
end

function I.GetItem(src, item, metadata, returnsCount)
    return inv:GetItem(src, item, metadata, returnsCount)
end

function I.GetSlot(src, slot)
    return inv:GetSlot(src, slot)
end

function I.SetMetadata(src, slot, metadata)
    return inv:SetMetadata(src, slot, metadata)
end

function I.GetInventoryItems(src)
    return inv:GetInventoryItems(src)
end

function I.GetInventory(src)
    return inv:GetInventory(src)
end

function I.ClearInventory(src, keep)
    return inv:ClearInventory(src, keep)
end

function I.RegisterStash(id, label, slots, weight, owner, groups, coords)
    return inv:RegisterStash(id, label, slots, weight, owner, groups, coords)
end

function I.openInventory(...) return inv:openInventory(...) end
function I.openNearbyInventory(...) return inv:openNearbyInventory(...) end
function I.forceOpenInventory(...) return inv:forceOpenInventory(...) end
function I.registerHook(...) return inv:registerHook(...) end
function I.displayMetadata(...) return inv:displayMetadata(...) end

---@return table<string, table>
function I.GetItems()
    local ok, items = pcall(function() return inv:Items() end)
    return (ok and type(items) == 'table') and items or {}
end

---@param raw any  columna JSON de ox_inventory
---@return table[]
local function decodeItems(raw)
    if type(raw) == 'string' and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        raw = ok and decoded or nil
    end
    if type(raw) ~= 'table' then return {} end
    local out = {}
    for _, item in pairs(raw) do
        if type(item) == 'table' and item.name then
            out[#out + 1] = {
                name = item.name,
                count = tonumber(item.count) or 0,
                slot = item.slot,
                metadata = type(item.metadata) == 'table' and item.metadata or {},
            }
        end
    end
    return out
end

---@param identifier string
---@return table[]
function I.GetOfflineInventory(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return {} end
    local esx = Bridge.framework == 'esx'
    local ok, rows = pcall(MySQL.query.await, esx
        and 'SELECT inventory FROM users WHERE identifier = ? LIMIT 1'
        or 'SELECT inventory FROM players WHERE citizenid = ? LIMIT 1', { identifier })
    if not ok or not rows or not rows[1] then return {} end
    return decodeItems(rows[1].inventory)
end

---@param identifier string
---@return { name: string, items: table[] }[]
function I.GetOwnedStashes(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return {} end
    local ok, rows = pcall(MySQL.query.await, 'SELECT name, data FROM ox_inventory WHERE owner = ?', { identifier })
    if not ok or not rows then return {} end
    local out = {}
    for i = 1, #rows do
        out[i] = { name = rows[i].name, items = decodeItems(rows[i].data) }
    end
    return out
end

---@param name string
---@param owner? string
---@return table[]?  nil si no hay fila guardada
function I.GetStashData(name, owner)
    if type(name) ~= 'string' or name == '' then return nil end
    local ok, rows = pcall(MySQL.query.await,
        'SELECT data FROM ox_inventory WHERE name = ? AND owner = ? LIMIT 1', { name, owner or '' })
    if not ok or not rows or not rows[1] then return nil end
    return decodeItems(rows[1].data)
end

Bridge.Inventory = I
