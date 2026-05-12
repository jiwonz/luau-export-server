const Server = require("@lute/net/server")
const Parser = require("@std/syntax/parser")
const Query = require("@std/syntax/query")
const SyntaxUtils = require("@std/syntax/utils")
const Printer = require("@std/syntax/printer")
const SyntaxTypes = require("@std/syntax/types")
const Luau = require("@lute/luau")
const Process = require("@lute/process")
const Gzip = require("./gzip")
const Json = require("@std/json")

type ExportableAst = SyntaxTypes.AstStatTypeAlias | SyntaxTypes.AstStatTypeFunction

const port = tonumber(Process.env.SERVER_PORT) or 8080
const host = Process.env.SERVER_HOST or "0.0.0.0"
-- TODO: Utilize official API building Asts
const baseReExportType = (
	Parser.parseExpr(`_::__MODULE__.__REF__`) :: SyntaxTypes.AstExprTypeAssertion
).annotation :: SyntaxTypes.AstTypeReference
const baseTypeRef = (
	Parser.parseExpr("_::__REF__") :: SyntaxTypes.AstExprTypeAssertion
).annotation :: SyntaxTypes.AstTypeReference
const baseTypeExport = Parser.parseBlock("export type _=_").statements[1] :: SyntaxTypes.AstStatTypeAlias
const dummySpan = Luau.span.create({ beginLine = 0, beginColumn = 0, endLine = 0, endColumn = 0 })
const isDevMode = Process.env.DEV ~= nil
const logs: { string } = {}

const function createToken<T>(str: T | ""): SyntaxTypes.Token<T>
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

const function toReExported(exportable: ExportableAst, moduleReference: string): SyntaxTypes.AstStatTypeAlias
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

        const parameters: SyntaxTypes.Punctuated<SyntaxTypes.AstType | SyntaxTypes.AstTypePack> = {}
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
                const paramNode: SyntaxTypes.AstTypePackGeneric = {
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
            const generics = table.create(typeFuncParamCount) :: SyntaxTypes.Punctuated<SyntaxTypes.AstGenericType>
            const parameters = table.create(typeFuncParamCount) :: SyntaxTypes.Punctuated<SyntaxTypes.AstType | SyntaxTypes.AstTypePack>
            for i, typeFuncParam in typeFuncParameters do
                const typeFuncParamNode = typeFuncParam.node
                const paramNode = table.clone(baseTypeRef)
				forceMutate(paramNode, "name", typeFuncParamNode.name)
                parameters[i] = {
                    node = paramNode,
                    separator = typeFuncParam.separator,
                }

                const genericNode: SyntaxTypes.AstGenericType = {
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
			const whitespace: SyntaxTypes.Trivia = {
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

const function reExport(source: string, moduleReference: string): string
    const result = Parser.parse(source)
    const q = Query.findAllFromRoot(result, function(node): ExportableAst?
        return if SyntaxUtils.isStatTypeAlias(node) or SyntaxUtils.isStatTypeFunction(node) then
            node :: ExportableAst? else nil
    end):filter(function(node)
        return node.export ~= nil
    end):map(function(node)
		return toReExported(node, moduleReference)
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
    const result = reExport(code, "module")
    print(`dev mode test result:\n{result}\n`)
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
	if typeof(moduleReference) ~= "string" then
		error("'moduleReference' field must be a string or null.")
	end

	const source = (input :: Json.Object).source
	if typeof(source) ~= "string" then
		error("'source' field must be a string.")
	end

	return reExport(source, moduleReference)
end

Server.serve({
	hostname = host,
    port = port,
    handler = function(request)
		if request.method == "GET" then
			if request.path == "/logs" then
				return {
					status = 200,
					headers = {
						["content-type"] = "text/plain",
					},
					body = table.concat(logs, "\n"),
				}
			elseif request.path == "/" then
				return {
					status = 200,
					headers = {
						["content-type"] = "application/json",
					},
					body = Json.serialize({
						message = "ok",
					}),
				}
			end

			return {
				status = 404,
			}
		end

		if request.method ~= "POST" then
			return {
				status = 405,
			}
		end

		const loweredHeaders: { [string]: string } = {}
		for key, value in request.headers do
			loweredHeaders[string.lower(key)] = value
		end

		if not loweredHeaders["content-type"] or not string.find(string.lower(loweredHeaders["content-type"]), "application/json") then
			table.insert(logs, `error: content-type is not json(headers: { Json.serialize(loweredHeaders :: Json.Object) })`)
			return {
				status = 415,
			}
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

print(`server started at {host}:{port}`)
