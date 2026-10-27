-- 決定這台機器該用哪一種 AI 補全後端。
-- 兩台機器 hostname 都是 OvO，所以只能靠硬體特徵分辨：
--   桌機 = chassis_type 3、無電池  → minuet + llamastash 本機模型
--   筆電 = chassis_type 10、有電池 → neocodeium（Windsurf 雲端）
local M = {}

-- 8 = Portable, 9 = Laptop, 10 = Notebook, 14 = Sub Notebook
-- 30 = Tablet, 31 = Convertible, 32 = Detachable
local MOBILE_CHASSIS = {
  [8] = true,
  [9] = true,
  [10] = true,
  [14] = true,
  [30] = true,
  [31] = true,
  [32] = true,
}

---@return integer|nil
local function chassis_type()
  local f = io.open("/sys/class/dmi/id/chassis_type", "r")
  if not f then
    return nil
  end
  local t = tonumber(f:read("*l"))
  f:close()
  return t
end

---@return boolean
local function has_battery()
  return vim.fn.glob("/sys/class/power_supply/BAT*", false, true)[1] ~= nil
end

---@return boolean
function M.is_laptop()
  -- 手動覆寫已停用
  -- if vim.g.ai_profile_override == "laptop" then
  --   return true
  -- elseif vim.g.ai_profile_override == "desktop" then
  --   return false
  -- end

  local chassis = chassis_type()
  if chassis and MOBILE_CHASSIS[chassis] then
    return true
  end
  -- DMI 說桌機但實際有電池（或讀不到 DMI）時，仍視為筆電
  return has_battery()
end

---目前這台機器要用的補全後端
---@return "minuet"|"neocodeium"
function M.provider()
  return M.is_laptop() and "neocodeium" or "minuet"
end

---手動覆寫 profile（已停用）
---@param name "desktop"|"laptop"
-- function M.override(name)
--   if name ~= "desktop" and name ~= "laptop" then
--     vim.notify(("AI profile 只能是 desktop 或 laptop，收到 %q"):format(name), vim.log.levels.ERROR)
--     return
--   end
--   vim.g.ai_profile_override = name
--   vim.notify(("AI profile 已覆寫為 %s，請重開 nvim"):format(name), vim.log.levels.WARN)
-- end

return M
