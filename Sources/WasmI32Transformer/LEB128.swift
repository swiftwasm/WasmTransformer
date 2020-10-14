func decodeLEB128(_ bytes: ArraySlice<UInt8>) -> (value: UInt32, offset: Int) {
    var index: Int = bytes.startIndex
    var value: UInt32 = 0
    var shift: UInt = 0
    var byte: UInt8
    repeat {
        byte = bytes[index]
        index += 1
        value |= UInt32(byte & 0x7F) << shift
        shift += 7
    } while byte >= 128
    return (value, index - bytes.startIndex)
}


func encodeULEB128<T>(_ value: T, padTo: Int? = nil) -> [UInt8]
    where T: UnsignedInteger, T: FixedWidthInteger
{
    var value = value
    var length = 0
    var results: [UInt8] = []
    var needPad: Bool {
        guard let padTo = padTo else { return false }
        return length < padTo
    }
    repeat {
        var byte = UInt8(value & 0x7F)
        value >>= 7
        length += 1
        if value != 0 || needPad {
            byte |= 0x80
        }
        results.append(byte)
    } while value != 0

    if let padTo = padTo, length < padTo {
        while length < padTo - 1 {
            results.append(0x80)
            length += 1
        }
        results.append(0x00)
    }
    return results
}
