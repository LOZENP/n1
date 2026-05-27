-- NightOwl - tokenizer.lua

local Enums  = require("nightowl.enums")
local util   = require("nightowl.util")
local logger = require("logger")
local config = require("config")

local lookupify   = util.lookupify
local unlookupify = util.unlookupify
local escape      = util.escape
local chararray   = util.chararray
local keys        = util.keys
local LuaVersion  = Enums.LuaVersion

local Tokenizer = {}

Tokenizer.EOF_CHAR         = "<EOF>"
Tokenizer.WHITESPACE_CHARS = lookupify{" ","\t","\n","\r"}
Tokenizer.ANNOTATION_CHARS = lookupify(chararray("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"))
Tokenizer.ANNOTATION_START_CHARS = lookupify(chararray("!@"))
Tokenizer.Conventions      = Enums.Conventions

Tokenizer.TokenKind = {
    Eof     = "Eof",
    Keyword = "Keyword",
    Symbol  = "Symbol",
    Ident   = "Identifier",
    Number  = "Number",
    String  = "String",
}

Tokenizer.EOF_TOKEN = {
    kind="Eof", value="<EOF>",
    startPos=-1, endPos=-1, source="<EOF>",
}

local function mktoken(self, startPos, kind, value)
    local line, linePos = self:getPosition(self.index)
    local ann = self.annotations; self.annotations = {}
    return {
        kind=kind, value=value,
        startPos=startPos, endPos=self.index,
        source=self.source:sub(startPos+1, self.index),
        line=line, linePos=linePos, annotations=ann,
    }
end

local function genErr(self, msg)
    local l, p = self:getPosition(self.index)
    return "Lex Error at " .. l .. ":" .. p .. ", " .. msg
end

function Tokenizer:getPosition(i)
    local col = self.columnMap[i] or self.columnMap[#self.columnMap]
    return col.id, col.charMap[i]
end

function Tokenizer:prepareGetPosition()
    local columnMap = {}
    local column = {charMap={}, id=1, length=0}
    for idx = 1, self.length do
        local c = self.source:sub(idx,idx)
        local cl = column.length + 1
        column.length = cl
        column.charMap[idx] = cl
        if c == "\n" then column = {charMap={}, id=column.id+1, length=0} end
        columnMap[idx] = column
    end
    self.columnMap = columnMap
end

function Tokenizer:new(settings)
    local ver = (settings and (settings.luaVersion or settings.LuaVersion)) or LuaVersion.LuaU
    local conv = Tokenizer.Conventions[ver]
    if not conv then
        logger:error("Unknown Lua version: " .. ver)
    end
    local t = {
        index=0, length=0, source="",
        luaVersion=ver, conventions=conv,
        NumberChars=conv.NumberChars,
        NumberCharsLookup=lookupify(conv.NumberChars),
        Keywords=conv.Keywords,
        KeywordsLookup=lookupify(conv.Keywords),
        BinaryNumberChars=conv.BinaryNumberChars,
        BinaryNumberCharsLookup=lookupify(conv.BinaryNumberChars),
        BinaryNums=conv.BinaryNums,
        HexadecimalNums=conv.HexadecimalNums,
        HexNumberChars=conv.HexNumberChars,
        HexNumberCharsLookup=lookupify(conv.HexNumberChars),
        DecimalExponent=conv.DecimalExponent,
        DecimalSeperators=conv.DecimalSeperators,
        IdentChars=conv.IdentChars,
        IdentCharsLookup=lookupify(conv.IdentChars),
        EscapeSequences=conv.EscapeSequences,
        NumericalEscapes=conv.NumericalEscapes,
        EscapeZIgnoreNextWhitespace=conv.EscapeZIgnoreNextWhitespace,
        HexEscapes=conv.HexEscapes,
        UnicodeEscapes=conv.UnicodeEscapes,
        SymbolChars=conv.SymbolChars,
        SymbolCharsLookup=lookupify(conv.SymbolChars),
        MaxSymbolLength=conv.MaxSymbolLength,
        Symbols=conv.Symbols,
        SymbolsLookup=lookupify(conv.Symbols),
        StringStartLookup=lookupify({"\"","'"}),
        annotations={},
    }
    setmetatable(t, self); self.__index = self
    return t
end

function Tokenizer:reset()
    self.index=0; self.length=0; self.source=""; self.annotations={}; self.columnMap={}
end

function Tokenizer:append(code)
    self.source = self.source .. code
    self.length = self.length + #code
    self:prepareGetPosition()
end

local function peek(self, n)
    n = n or 0
    local i = self.index + n + 1
    if i > self.length then return Tokenizer.EOF_CHAR end
    return self.source:sub(i,i)
end

local function get(self)
    local i = self.index + 1
    if i > self.length then logger:error(genErr(self, "Unexpected end of input")) end
    self.index = i
    return self.source:sub(i,i)
end

local function expect(self, charOrLookup)
    if type(charOrLookup) == "string" then charOrLookup = {[charOrLookup]=true} end
    local c = peek(self)
    if not charOrLookup[c] then
        local exp = unlookupify(charOrLookup)
        for i,v in ipairs(exp) do exp[i] = escape(v) end
        logger:error(genErr(self, "Unexpected \"" .. escape(c) .. "\", expected one of \"" .. table.concat(exp,'","') .. "\""))
    end
    self.index = self.index + 1
    return c
end

local function is(self, charOrLookup, n)
    local c = peek(self, n)
    if type(charOrLookup) == "string" then return c == charOrLookup end
    return charOrLookup[c]
end

function Tokenizer:parseAnnotation()
    if is(self, Tokenizer.ANNOTATION_START_CHARS) then
        self.index = self.index + 1
        local src, len = {}, 0
        while is(self, Tokenizer.ANNOTATION_CHARS) do
            src[len+1] = get(self); len = #src
        end
        if len > 0 then self.annotations[string.lower(table.concat(src))] = true end
        return nil
    end
    return get(self)
end

function Tokenizer:skipComment()
    if is(self,"-",0) and is(self,"-",1) then
        self.index = self.index + 2
        if is(self,"[") then
            self.index = self.index + 1
            local eq = 0
            while is(self,"=") do self.index=self.index+1; eq=eq+1 end
            if is(self,"[") then
                while true do
                    if self:parseAnnotation() == "]" then
                        local eq2 = 0
                        while is(self,"=") do self.index=self.index+1; eq2=eq2+1 end
                        if is(self,"]") and eq2==eq then self.index=self.index+1; return true end
                    end
                end
            end
        end
        while self.index < self.length and self:parseAnnotation() ~= "\n" do end
        return true
    end
    return false
end

function Tokenizer:skipWhitespaceAndComments()
    while self:skipComment() do end
    while is(self, Tokenizer.WHITESPACE_CHARS) do
        self.index = self.index + 1
        while self:skipComment() do end
    end
end

local function readInt(self, chars, seps)
    local buf = {}
    while true do
        if is(self, chars) then buf[#buf+1] = get(self)
        elseif seps and is(self, seps) then self.index = self.index+1
        else break end
    end
    return table.concat(buf)
end

function Tokenizer:number()
    local startPos = self.index
    local src = expect(self, setmetatable({["."] = true}, {__index = self.NumberCharsLookup}))
    if src == "0" then
        if self.BinaryNums and is(self, lookupify(self.BinaryNums)) then
            self.index = self.index + 1
            local s = readInt(self, self.BinaryNumberCharsLookup, self.DecimalSeperators and lookupify(self.DecimalSeperators) or nil)
            return mktoken(self, startPos, Tokenizer.TokenKind.Number, tonumber(s, 2))
        end
        if self.HexadecimalNums and is(self, lookupify(self.HexadecimalNums)) then
            self.index = self.index + 1
            local s = readInt(self, self.HexNumberCharsLookup, self.DecimalSeperators and lookupify(self.DecimalSeperators) or nil)
            return mktoken(self, startPos, Tokenizer.TokenKind.Number, tonumber(s, 16))
        end
    end
    local seps = self.DecimalSeperators and lookupify(self.DecimalSeperators) or nil
    if src == "." then
        src = src .. readInt(self, self.NumberCharsLookup, seps)
    else
        src = src .. readInt(self, self.NumberCharsLookup, seps)
        if is(self, ".") then src = src .. get(self) .. readInt(self, self.NumberCharsLookup, seps) end
    end
    if self.DecimalExponent and is(self, lookupify(self.DecimalExponent)) then
        src = src .. get(self)
        if is(self, lookupify({"+","-"})) then src = src .. get(self) end
        local v = readInt(self, self.NumberCharsLookup, seps)
        if #v < 1 then logger:error(genErr(self, "Expected valid exponent")) end
        src = src .. v
    end
    return mktoken(self, startPos, Tokenizer.TokenKind.Number, tonumber(src))
end

function Tokenizer:ident()
    local startPos = self.index
    local src = expect(self, self.IdentCharsLookup)
    local parts = {src}
    while is(self, self.IdentCharsLookup) do parts[#parts+1] = get(self) end
    src = table.concat(parts)
    if self.KeywordsLookup[src] then
        return mktoken(self, startPos, Tokenizer.TokenKind.Keyword, src)
    end
    local tk = mktoken(self, startPos, Tokenizer.TokenKind.Ident, src)
    if src:sub(1, #config.IdentPrefix) == config.IdentPrefix then
        logger:warn("Warning: identifier starts with reserved prefix \"" .. config.IdentPrefix .. "\"")
    end
    return tk
end

function Tokenizer:singleLineString()
    local startPos = self.index
    local startChar = expect(self, self.StringStartLookup)
    local buf = {}
    while not is(self, startChar) do
        local c = get(self)
        if c == "\n" then self.index = self.index-1; logger:error(genErr(self, "Unterminated string")) end
        if c == "\\" then
            c = get(self)
            local esc = self.EscapeSequences[c]
            if type(esc) == "string" then
                c = esc
            elseif self.NumericalEscapes and self.NumberCharsLookup[c] then
                local ns = c
                if is(self, self.NumberCharsLookup) then ns = ns .. get(self) end
                if is(self, self.NumberCharsLookup) then ns = ns .. get(self) end
                c = string.char(tonumber(ns))
            elseif self.UnicodeEscapes and c == "u" then
                expect(self, "{")
                local num = ""
                while is(self, self.HexNumberCharsLookup) do num = num .. get(self) end
                expect(self, "}")
                c = util.utf8char(tonumber(num, 16))
            elseif self.HexEscapes and c == "x" then
                local hex = expect(self, self.HexNumberCharsLookup) .. expect(self, self.HexNumberCharsLookup)
                c = string.char(tonumber(hex, 16))
            elseif self.EscapeZIgnoreNextWhitespace and c == "z" then
                c = ""
                while is(self, Tokenizer.WHITESPACE_CHARS) do self.index = self.index+1 end
            end
        end
        buf[#buf+1] = c
    end
    expect(self, startChar)
    return mktoken(self, startPos, Tokenizer.TokenKind.String, table.concat(buf))
end

function Tokenizer:multiLineString()
    local startPos = self.index
    if is(self, "[") then
        self.index = self.index + 1
        local eq = 0
        while is(self, "=") do self.index=self.index+1; eq=eq+1 end
        if is(self, "[") then
            self.index = self.index + 1
            if is(self, "\n") then self.index = self.index+1 end
            local val = ""
            while true do
                local c = get(self)
                if c == "]" then
                    local eq2 = 0
                    while is(self,"=") do c=c..get(self); eq2=eq2+1 end
                    if is(self,"]") and eq2==eq then
                        self.index = self.index+1
                        return mktoken(self, startPos, Tokenizer.TokenKind.String, val), true
                    end
                end
                val = val .. c
            end
        end
    end
    self.index = startPos
    return nil, false
end

function Tokenizer:symbol()
    local startPos = self.index
    for len = self.MaxSymbolLength, 1, -1 do
        local str = self.source:sub(self.index+1, self.index+len)
        if self.SymbolsLookup[str] then
            self.index = self.index + len
            return mktoken(self, startPos, Tokenizer.TokenKind.Symbol, str)
        end
    end
    logger:error(genErr(self, "Unknown symbol"))
end

function Tokenizer:next()
    self:skipWhitespaceAndComments()
    local startPos = self.index
    if startPos >= self.length then
        return mktoken(self, startPos, Tokenizer.TokenKind.Eof)
    end
    if is(self, self.NumberCharsLookup) then return self:number() end
    if is(self, self.IdentCharsLookup)  then return self:ident() end
    if is(self, self.StringStartLookup) then return self:singleLineString() end
    if is(self, "[", 0) then
        local val, isStr = self:multiLineString()
        if isStr then return val end
    end
    if is(self, ".") and is(self, self.NumberCharsLookup, 1) then return self:number() end
    if is(self, self.SymbolCharsLookup) then return self:symbol() end
    logger:error(genErr(self, "Unexpected char \"" .. escape(peek(self)) .. "\""))
end

function Tokenizer:scanAll()
    local tb = {}
    repeat
        local tk = self:next()
        tb[#tb+1] = tk
    until tk.kind == Tokenizer.TokenKind.Eof
    return tb
end

return Tokenizer
