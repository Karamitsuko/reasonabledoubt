#!/usr/bin/env python3
"""Build a Luau snippet that mirrors src/ into Studio (same layout as default.project.json).

Claude runs the output through the Roblox Studio connection. Scripts in the managed
folders that no longer exist in src/ are removed, so Studio always matches the repo.
"""
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAPPINGS = [
    ("src/shared", ["ReplicatedStorage", "Shared"]),
    ("src/server", ["ServerScriptService", "Server"]),
    ("src/client", ["StarterPlayer", "StarterPlayerScripts", "Client"]),
]

def long_string(s: str) -> str:
    level = 1
    while ("]" + "=" * level + "]") in s:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{s}]{eq}]"

def classify(name: str):
    if name.endswith(".server.luau"):
        return name[: -len(".server.luau")], "Script"
    if name.endswith(".client.luau"):
        return name[: -len(".client.luau")], "LocalScript"
    if name.endswith(".luau"):
        return name[: -len(".luau")], "ModuleScript"
    return None, None

out = ["local function folderAt(path)",
       "  local node = game:GetService(path[1])",
       "  for i = 2, #path do",
       "    local child = node:FindFirstChild(path[i])",
       "    if not child then child = Instance.new('Folder'); child.Name = path[i]; child.Parent = node end",
       "    node = child",
       "  end",
       "  return node",
       "end",
       "local function put(folder, name, class, source)",
       "  local s = folder:FindFirstChild(name)",
       "  if s and s.ClassName ~= class then s:Destroy(); s = nil end",
       "  if not s then s = Instance.new(class); s.Name = name end",
       "  s.Source = source",
       "  s.Parent = folder",
       "end",
       "local written = 0"]
for src, path in MAPPINGS:
    d = ROOT / src
    lua_path = "{" + ", ".join(repr(p) for p in path) + "}"
    out.append(f"do local f = folderAt({lua_path}) local keep = {{}}")
    for file in sorted(d.glob("*.luau")):
        name, cls = classify(file.name)
        out.append(f"  keep[{name!r}] = true put(f, {name!r}, {cls!r}, {long_string(file.read_text())}) written += 1")
    out.append("  for _, c in f:GetChildren() do if c:IsA('LuaSourceContainer') and not keep[c.Name] then c:Destroy() end end")
    out.append("end")
out.append("return ('synced %d scripts'):format(written)")
sys.stdout.write("\n".join(out))
