--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local hello = require(Shared:WaitForChild("Hello")) :: (string) -> string

print(hello("client"))
