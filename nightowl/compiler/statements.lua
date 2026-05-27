local Ast     = require("nightowl.ast")
local AstKind = Ast.AstKind

local h   = {}
local pre = "nightowl.compiler.statements."

h[AstKind.ReturnStatement]             = require(pre.."return")
h[AstKind.LocalVariableDeclaration]    = require(pre.."local_variable_declaration")
h[AstKind.FunctionCallStatement]       = require(pre.."function_call")
h[AstKind.PassSelfFunctionCallStatement] = require(pre.."pass_self_function_call")
h[AstKind.LocalFunctionDeclaration]    = require(pre.."local_function_declaration")
h[AstKind.FunctionDeclaration]         = require(pre.."function_declaration")
h[AstKind.AssignmentStatement]         = require(pre.."assignment")
h[AstKind.IfStatement]                 = require(pre.."if_statement")
h[AstKind.DoStatement]                 = require(pre.."do_statement")
h[AstKind.WhileStatement]              = require(pre.."while_statement")
h[AstKind.RepeatStatement]             = require(pre.."repeat_statement")
h[AstKind.ForStatement]                = require(pre.."for_statement")
h[AstKind.ForInStatement]              = require(pre.."for_in_statement")
h[AstKind.BreakStatement]              = require(pre.."break_statement")
h[AstKind.ContinueStatement]           = require(pre.."continue_statement")

local compound = require(pre.."compound")
h[AstKind.CompoundAddStatement]    = compound
h[AstKind.CompoundSubStatement]    = compound
h[AstKind.CompoundMulStatement]    = compound
h[AstKind.CompoundDivStatement]    = compound
h[AstKind.CompoundModStatement]    = compound
h[AstKind.CompoundPowStatement]    = compound
h[AstKind.CompoundConcatStatement] = compound

return h
