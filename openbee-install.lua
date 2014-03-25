--http://pastebin.com/Nq5jEJfM

if not http then
  print("No access to web")
  return
end

local branch = "master"

local files = {
  {
    name = "openbee-install",
    url = "https://raw.github.com/Forte40/openbee/"..branch.."/openbee-install.lua"
  },
  {
    name = "openbee",
    url = "https://raw.github.com/Forte40/openbee/"..branch.."/openbee.lua"
  }
}

for _, file in ipairs(files) do
  local path
  if file.folder then
    if not fs.exists(file.folder) then
      fs.makeDir(file.folder)
    end
    path = fs.combine(file.folder, file.name)
  else
    path = file.name
  end
  local currText = ""
  if fs.exists(path) then
    local f = fs.open(path, "r")
    currText = f.readAll()
    f.close()
    io.write("update  ")
  else
    io.write("install ")
  end
  io.write("'"..file.name.."'"..string.rep(" ", math.max(0, 8 - #file.name)))
  if file.folder then
    io.write(" in '"..file.folder.."'"..string.rep(".", math.max(0, 8 - #file.folder)).."...")
  else
    io.write("    .............")
  end
  local request = http.get(file.url)
  if request then
    local response = request.getResponseCode()
    if response == 200 then
      local newText = request.readAll()
      if newText == currText then
        print("skip")
      else
        local f = fs.open(path, "w")
        f.write(newText)
        f.close()
        print("done")
      end
    else
      print(" bad HTTP response code " .. response)
    end
  else
    print(" no request handle")
  end
  os.sleep(0.1)
end
print("Finished")