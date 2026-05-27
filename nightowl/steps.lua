return {
    WrapInFunction       = require("nightowl.steps.WrapInFunction"),
    SplitStrings         = require("nightowl.steps.SplitStrings"),
    ConstantArray        = require("nightowl.steps.ConstantArray"),
    ProxifyLocals        = require("nightowl.steps.ProxifyLocals"),
    AntiTamper           = require("nightowl.steps.AntiTamper"),
    EncryptStrings       = require("nightowl.steps.EncryptStrings"),
    NumbersToExpressions = require("nightowl.steps.NumbersToExpressions"),
    AddVararg            = require("nightowl.steps.AddVararg"),
    Vmify                = require("nightowl.steps.Vmify"),  -- add this
}
