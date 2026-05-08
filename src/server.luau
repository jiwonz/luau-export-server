const Server = require("@lute/net/server")
const Parser = require("@std/syntax/parser")
const Query = require("@std/syntax/query")
const Utils = require("@std/syntax/utils")
const Printer = require("@std/syntax/printer")
const Types = require("@std/syntax/types")
const Luau = require("@lute/luau")
const Process = require("@lute/process")
const Gzip = require("./gzip")
const Json = require("@std/json")

type ExportableAst = Types.AstStatTypeAlias | Types.AstStatTypeFunction

const DEFAULT_MODULE_REFERENCE = "module"

const port = tonumber(Process.env.PORT) or 8080
const baseReExportType = (
	Parser.parseExpr(`_::__MODULE__.__REF__`) :: Types.AstExprTypeAssertion
).annotation :: Types.AstTypeReference
const baseTypeRef = (
	Parser.parseExpr("_::__REF__") :: Types.AstExprTypeAssertion
).annotation :: Types.AstTypeReference
const baseTypeExport = Parser.parseBlock("export type _=_").statements[1] :: Types.AstStatTypeAlias
const dummySpan = Luau.span.create({ beginLine = 0, beginColumn = 0, endLine = 0, endColumn = 0 })
const isDevMode = Process.env.DEV ~= nil

const function createToken<T>(str: T | ""): Types.Token<T>
    return {
        leadingTrivia = {},
        location = dummySpan,
        text = str,
        trailingTrivia = {},
        kind = "token",
    }
end

--- This is needed for mutating a read-only table with lute's luau AST types
@native const function forceMutate<T, K>(tbl: T & {}, key: K & keyof<T>, newValue: index<T, K>)
	tbl[key] = newValue
end

const function toReExported(exportable: ExportableAst, moduleReference: string): Types.AstStatTypeAlias
    const newType = table.clone(baseReExportType)

    const newTypeName = table.clone(newType.name)
	forceMutate(newTypeName, "text", exportable.name.text)

	const newTypePrefix = table.clone(assert(newType.prefix))
	forceMutate(newTypePrefix, "text", moduleReference)

	forceMutate(newType, "name", newTypeName)
	forceMutate(newType, "prefix", newTypePrefix)

    const typeExport = table.clone(baseTypeExport)
	forceMutate(typeExport, "name", newTypeName)
	forceMutate(typeExport, "type", newType)

    if exportable.tag == "typealias" then
		forceMutate(newType, "openParameters", exportable.openGenerics)
		forceMutate(newType, "closeParameters", exportable.closeGenerics)

		forceMutate(typeExport, "openGenerics", exportable.openGenerics)
		forceMutate(typeExport, "genericPacks", exportable.genericPacks)
		forceMutate(typeExport, "closeGenerics", exportable.closeGenerics)

        const parameters: Types.Punctuated<Types.AstType | Types.AstTypePack> = {}
        const generics = exportable.generics
        const genericPacks = exportable.genericPacks

        if generics then
			forceMutate(typeExport, "generics", generics)
            for _, generic in generics do
                const genericNode = generic.node
                const paramNode = table.clone(baseTypeRef)
				forceMutate(paramNode, "name", genericNode.name)
                table.insert(parameters, {
                    node = paramNode,
                    separator = generic.separator,
                })
            end
        end

        if genericPacks then
			forceMutate(typeExport, "genericPacks", genericPacks)
            for _, generic in genericPacks do
                const genericNode = generic.node
                const paramNode: Types.AstTypePackGeneric = {
                    location = dummySpan,
                    kind = "typepack",
                    tag = "generic",
                    name = genericNode.name,
                    ellipsis = genericNode.ellipsis,
                }
                table.insert(parameters, {
                    node = paramNode,
                    separator = generic.separator,
                })
            end
        end

		forceMutate(newType, "parameters", parameters)
    elseif exportable.tag == "typefunction" then
        const typeFuncParameters = exportable.body.parameters
        const typeFuncParamCount = #typeFuncParameters
        if typeFuncParamCount > 0 then
            const generics = table.create(typeFuncParamCount) :: Types.Punctuated<Types.AstGenericType>
            const parameters = table.create(typeFuncParamCount) :: Types.Punctuated<Types.AstType | Types.AstTypePack>
            for i, typeFuncParam in typeFuncParameters do
                const typeFuncParamNode = typeFuncParam.node
                const paramNode = table.clone(baseTypeRef)
				forceMutate(paramNode, "name", typeFuncParamNode.name)
                parameters[i] = {
                    node = paramNode,
                    separator = typeFuncParam.separator,
                }

                const genericNode: Types.AstGenericType = {
                    tag = "generic",
                    name = paramNode.name,
                    equals = nil,
                    default = nil,
                }
                generics[i] = {
                    node = genericNode,
                    separator = typeFuncParam.separator,
                }
            end

			forceMutate(newType, "parameters", parameters)
			forceMutate(newType, "openParameters", createToken("<"))
            const closeParamToken = createToken(">")
			const whitespace: Types.Trivia = {
				tag = "whitespace",
				location = dummySpan,
				text = " ",
			}
			forceMutate(closeParamToken, "trailingTrivia", { whitespace })
			forceMutate(newType, "closeParameters", closeParamToken)

			forceMutate(typeExport, "openGenerics", newType.openParameters)
			forceMutate(typeExport, "generics", generics)
			forceMutate(typeExport, "closeGenerics", newType.closeParameters)
        end
    end

    return typeExport
end

const function reExport(source: string, moduleReference: string?): string
	moduleReference = moduleReference or DEFAULT_MODULE_REFERENCE

    const result = Parser.parse(source)
    const q = Query.findAllFromRoot(result, function(node): ExportableAst?
        return if Utils.isStatTypeAlias(node) or Utils.isStatTypeFunction(node) then
            node :: ExportableAst? else nil
    end):filter(function(node)
        return node.export ~= nil
    end):map(function(node)
		return toReExported(node, moduleReference :: string) -- Luau WHAT??
    end) :: Query.Query
    const contents = table.create(#q.nodes) :: { string }

    for i, node in q.nodes do
        local content = Printer.printNode(node)
        --content = string.gsub(string.gsub(content, "^%s+", ""), "%s+$", "")
        contents[i] = content
    end

    return table.concat(contents, "\n")
end

if isDevMode then
    const code = [[
        export type N = number
        export type function F(t: type) return t end
        export type A<T> = F<T>
        export type K<A...> = <G>() -> G
        export type D<T=number> = T
    ]]
    const result = reExport(code)
    print(`dev mode test:\n{result}\n`)
    Parser.parse(result)
end

const function processRequest(request: Server.ReceivedRequest): string
	-- TODO: schema validation
	const input = Json.deserialize(if request.headers["content-encoding"] == "gzip" then
		buffer.tostring(Gzip.uncompress(buffer.fromstring(request.body)))
	else request.body)
	if typeof(input) ~= "table" then
		error("input must be a table.")
	end

	const moduleReference = (input :: Json.Object).moduleReference
	if moduleReference ~= nil and typeof(moduleReference) ~= "string" then
		error("'moduleReference' field must be a string or null.")
	end

	const source = (input :: Json.Object).source
	if typeof(source) ~= "string" then
		error("'source' field must be a string.")
	end

	return reExport(source, moduleReference)
end

Server.serve({
    port = port,
    handler = function(request, server)
		if request.headers["content-type"] ~= "application/json" then
			return { status = 415 }
		end

		-- TODO: result over exception(using pcall) (for a better error handling.. maybe?)
		const ok, result = pcall(processRequest, request)
		if not ok then
			if isDevMode then
				print(`got a bad request:\n{result}\n`)
			end

			return {
				status = 400,
				headers = {
					["content-type"] = "application/json",
				},
				body = Json.serialize({
					error = result,
				}),
			}
		end

        return { status = 200, body = result }
    end,
})

print(`server started at localhost:{port}`)
