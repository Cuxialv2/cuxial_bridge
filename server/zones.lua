Bridge.Zones = Bridge.Zones or {}
local Z = Bridge.Zones
Z.DB = Z.DB or {}

local function decodeRow(row)
    row.geometry = row.geometry and json.decode(row.geometry) or nil
    row.metadata = row.metadata and json.decode(row.metadata) or {}
    row.active = row.active == 1 or row.active == true
    return row
end

---@param tableName string
---@param onlyActive? boolean  solo zonas con active = 1
---@return table[] rows  con geometry/metadata ya decodificados
function Z.DB.Fetch(tableName, onlyActive)
    local where = onlyActive and ' WHERE active = 1' or ''
    local rows = MySQL.query.await(('SELECT * FROM `%s`%s ORDER BY id ASC'):format(tableName, where)) or {}
    for i = 1, #rows do decodeRow(rows[i]) end
    return rows
end

---@param tableName string
---@param zone { label: string, geometry: table, metadata?: table, active?: boolean, created_by?: string }
---@return integer id
function Z.DB.Insert(tableName, zone)
    return MySQL.insert.await(
        ('INSERT INTO `%s` (label, geometry, metadata, active, created_by) VALUES (?, ?, ?, ?, ?)'):format(tableName),
        {
            zone.label,
            json.encode(zone.geometry),
            json.encode(zone.metadata or {}),
            zone.active == false and 0 or 1,
            zone.created_by,
        }
    )
end

---@param tableName string
---@param id integer
---@param fields { label?: string, geometry?: table, metadata?: table, active?: boolean }
---@return integer affected
function Z.DB.Update(tableName, id, fields)
    local sets, params = {}, {}
    if fields.label ~= nil then sets[#sets + 1] = 'label = ?'; params[#params + 1] = fields.label end
    if fields.geometry ~= nil then sets[#sets + 1] = 'geometry = ?'; params[#params + 1] = json.encode(fields.geometry) end
    if fields.metadata ~= nil then sets[#sets + 1] = 'metadata = ?'; params[#params + 1] = json.encode(fields.metadata) end
    if fields.active ~= nil then sets[#sets + 1] = 'active = ?'; params[#params + 1] = fields.active and 1 or 0 end
    if #sets == 0 then return 0 end
    params[#params + 1] = id
    return MySQL.update.await(('UPDATE `%s` SET %s WHERE id = ?'):format(tableName, table.concat(sets, ', ')), params)
end

---@return integer affected
function Z.DB.SetActive(tableName, id, active)
    return MySQL.update.await(('UPDATE `%s` SET active = ? WHERE id = ?'):format(tableName), { active and 1 or 0, id })
end

---@return integer affected
function Z.DB.Delete(tableName, id)
    return MySQL.update.await(('DELETE FROM `%s` WHERE id = ?'):format(tableName), { id })
end
