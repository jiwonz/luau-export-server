const inflate = require("@vendor/inflate")
const crc = require("@vendor/crc")

const function uncompress(contents: buffer): buffer
    if buffer.readu8(contents, 0) ~= 0x1f or buffer.readu8(contents, 1) ~= 0x8b then
        error("not a gzip format")
    end

    if buffer.readu8(contents, 2) ~= 0x08 then
        error("unsupported compression method")
    end

    const length = buffer.len(contents)
    const expectedCrc = buffer.readu32(contents, length - 8)
    const uncompressedSize = buffer.readu32(contents, length - 4)
    const compressedSize = length - 8 - 10
    const compressed = buffer.create(compressedSize)

    buffer.copy(compressed, 0, contents, 10, compressedSize)

    const uncompressed = inflate(compressed, uncompressedSize)

    if crc(uncompressed) ~= expectedCrc then
        error("crc mismatch")
    end

    return uncompressed
end

return table.freeze({
	uncompress = uncompress,
})
