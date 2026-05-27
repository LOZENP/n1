-- NightOwl - presets.lua

return {

    -- Just renames variables. No obfuscation. Fastest output.
    ["Minify"] = {
        LuaVersion    = "Lua51",
        VarNamePrefix = "",
        NameGenerator = "MangledShuffled",
        PrettyPrint   = false,
        Seed          = 0,
        Steps         = {},
    },

    -- Light obfuscation. Fast, low overhead.
    ["Weak"] = {
        LuaVersion    = "Lua51",
        VarNamePrefix = "",
        NameGenerator = "MangledShuffled",
        PrettyPrint   = false,
        Seed          = 0,
        Steps         = {
            {
                Name     = "ConstantArray",
                Settings = {
                    Treshold             = 1,
                    StringsOnly          = true,
                    Shuffle              = true,
                    Rotate               = true,
                    Encoding             = "base64",
                    LocalWrapperCount    = 0,
                    LocalWrapperArgCount = 10,
                    MaxWrapperOffset     = 65535,
                    LocalWrapperTreshold = 0,
                },
            },
            {
                Name     = "WrapInFunction",
                Settings = { Iterations = 1 },
            },
        },
    },

    -- Medium obfuscation. No VM, good balance of speed and protection.
    ["Medium"] = {
        LuaVersion    = "Lua51",
        VarNamePrefix = "",
        NameGenerator = "MangledShuffled",
        PrettyPrint   = false,
        Seed          = 0,
        Steps         = {
            {
                Name     = "EncryptStrings",
                Settings = {},
            },
            {
                Name     = "ConstantArray",
                Settings = {
                    Treshold             = 1,
                    StringsOnly          = true,
                    Shuffle              = true,
                    Rotate               = true,
                    Encoding             = "base64",
                    LocalWrapperCount    = 0,
                    LocalWrapperArgCount = 10,
                    MaxWrapperOffset     = 65535,
                    LocalWrapperTreshold = 0,
                },
            },
            {
                Name     = "NumbersToExpressions",
                Settings = {
                    Threshold                    = 1,
                    InternalThreshold            = 0.2,
                    NumberRepresentationMutaton  = false,
                    AllowedNumberRepresentations = {"hex", "scientific", "normal"},
                },
            },
            {
                Name     = "WrapInFunction",
                Settings = { Iterations = 1 },
            },
        },
    },

    -- Strong obfuscation. Uses luac VM. No N2E (would explode VM bytecode numbers).
    ["Strong"] = {
        LuaVersion    = "Lua51",
        VarNamePrefix = "",
        NameGenerator = "MangledShuffled",
        PrettyPrint   = false,
        Seed          = 0,
        Steps         = {
            {
                Name     = "Vmify",
                Settings = { LuacPath = "luac5.1" },
            },
            {
                Name     = "EncryptStrings",
                Settings = {},
            },
            {
                Name     = "ConstantArray",
                Settings = {
                    Treshold             = 1,
                    StringsOnly          = true,
                    Shuffle              = true,
                    Rotate               = true,
                    Encoding             = "base64",
                    LocalWrapperCount    = 0,
                    LocalWrapperArgCount = 10,
                    MaxWrapperOffset     = 65535,
                    LocalWrapperTreshold = 0,
                },
            },
            {
                Name     = "WrapInFunction",
                Settings = { Iterations = 2 },
            },
        },
    },

    -- Maximum obfuscation. VM + all passes. Slowest but strongest.
    ["Maximum"] = {
        LuaVersion    = "Lua51",
        VarNamePrefix = "",
        NameGenerator = "MangledShuffled",
        PrettyPrint   = false,
        Seed          = 0,
        Steps         = {
            {
                Name     = "Vmify",
                Settings = { LuacPath = "luac5.1" },
            },
            {
                Name     = "EncryptStrings",
                Settings = {},
            },
            {
                Name     = "AntiTamper",
                Settings = { UseDebug = false },
            },
            {
                Name     = "ConstantArray",
                Settings = {
                    Treshold             = 1,
                    StringsOnly          = false,
                    Shuffle              = true,
                    Rotate               = true,
                    Encoding             = "base64",
                    LocalWrapperCount    = 3,
                    LocalWrapperArgCount = 10,
                    MaxWrapperOffset     = 65535,
                    LocalWrapperTreshold = 1,
                },
            },
            {
                Name     = "SplitStrings",
                Settings = {
                    Threshold = 1,
                    MinLength = 2,
                    MaxLength = 5,
                },
            },
            {
                Name     = "WrapInFunction",
                Settings = { Iterations = 3 },
            },
        },
    },

    -- VM only, no extra passes. Good for testing Vmify alone.
    ["VmOnly"] = {
        LuaVersion    = "Lua51",
        VarNamePrefix = "",
        NameGenerator = "MangledShuffled",
        PrettyPrint   = false,
        Seed          = 0,
        Steps         = {
            {
                Name     = "Vmify",
                Settings = { LuacPath = "luac5.1" },
            },
        },
    },

}
