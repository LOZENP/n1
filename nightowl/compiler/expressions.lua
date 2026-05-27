local Ast     = require("nightowl.ast")
local AstKind = Ast.AstKind

local h   = {}
local pre = "nightowl.compiler.expressions."

h[AstKind.StringExpression]    = require(pre.."string")
h[AstKind.NumberExpression]    = require(pre.."number")
h[AstKind.BooleanExpression]   = require(pre.."boolean")
h[AstKind.NilExpression]       = require(pre.."nil")
h[AstKind.VariableExpression]  = require(pre.."variable")
h[AstKind.FunctionCallExpression]      = require(pre.."function_call")
h[AstKind.PassSelfFunctionCallExpression] = require(pre.."pass_self_function_call")
h[AstKind.IndexExpression]     = require(pre.."index")
h[AstKind.NotExpression]       = require(pre.."not")
h[AstKind.NegateExpression]    = require(pre.."negate")
h[AstKind.LenExpression]       = require(pre.."len")
h[AstKind.OrExpression]        = require(pre.."or")
h[AstKind.AndExpression]       = require(pre.."and")
h[AstKind.TableConstructorExpression]  = require(pre.."table_constructor")
h[AstKind.FunctionLiteralExpression]   = require(pre.."function_literal")
h[AstKind.VarargExpression]    = require(pre.."vararg")

local binary = require(pre.."binary")
h[AstKind.LessThanExpression]              = binary
h[AstKind.GreaterThanExpression]           = binary
h[AstKind.LessThanOrEqualsExpression]      = binary
h[AstKind.GreaterThanOrEqualsExpression]   = binary
h[AstKind.NotEqualsExpression]             = binary
h[AstKind.EqualsExpression]                = binary
h[AstKind.StrCatExpression]                = binary
h[AstKind.AddExpression]                   = binary
h[AstKind.SubExpression]                   = binary
h[AstKind.MulExpression]                   = binary
h[AstKind.DivExpression]                   = binary
h[AstKind.ModExpression]                   = binary
h[AstKind.PowExpression]                   = binary

return h
