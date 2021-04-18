struct LargeBox0 {
    let value0: UInt64 = 0xdeadbeef
    let value1: UInt64 = 0xdeadbeef
    let value2: UInt64 = 0xdeadbeef
    let value3: UInt64 = 0xdeadbeef
    let value4: UInt64 = 0xdeadbeef
    let value5: UInt64 = 0xdeadbeef
    let value6: UInt64 = 0xdeadbeef
    let value7: UInt64 = 0xdeadbeef
}

struct LargeBox {
    let value0 = LargeBox0()
    let value1 = LargeBox0()
    let value2 = LargeBox0()
    let value3 = LargeBox0()
    let value4 = LargeBox0()
    let value5 = LargeBox0()
    let value6 = LargeBox0()
    let value7 = LargeBox0()
}

func causeStackOverflow(box: LargeBox) {
    let box = LargeBox()
    causeStackOverflow(box: box)
}

causeStackOverflow(box: LargeBox())
