# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
extends ImageFormatLoaderExtension


const __support_extensions: PackedStringArray = ["pi"]


func _get_recognized_extensions() -> PackedStringArray:
    return __support_extensions


class CImagePi:
    var comment: PackedByteArray
    var platform: PackedByteArray
    var mode: int
    var ratio_n: int
    var ratio_m: int
    var planes: int
    var rect: Rect2i
    var pallet: Array[Color]

    var aryB: PackedByteArray
    var posB: int = 0
    var posB_curr: int = 0

    var ary_cc_table: Array

    func fetch_b_size(size: int) -> int:
        var result: int = 0
        for i in range(size):
            result <<= 1
            result |= self.fetch_b()
        return result

    func fetch_b() -> int:
        var v: int = self.aryB[self.posB] & (0x80 >> self.posB_curr)
        self.posB_curr += 1
        if self.posB_curr == 8:
            self.posB_curr = 0
            self.posB += 1

        if v > 0:
            return 1
        else:
            return 0

    func getcol(c: int, t: int) -> int:
        var cc: Array = self.ary_cc_table[c]
        var v: int = cc[t]

        cc.remove_at(t)
        cc.push_front(v)

        return v

    func read_len() -> int:
        var v: int = 0
        
        while true:
            if self.fetch_b() == 0:
                break
            v += 1

        if v == 0:
            return 1
        
        return self.fetch_b_size(v) + (1 << v)

    func read_color(c: int) -> int:
        if self.fetch_b_size(1) != 0:
            return self.getcol(c, self.fetch_b_size(1))

        if self.fetch_b_size(1) == 0:
            return self.getcol(c, self.fetch_b_size(1) + 2)

        if self.fetch_b_size(1) == 0:
            return self.getcol(c, self.fetch_b_size(2) + 4)

        return self.getcol(c, self.fetch_b_size(3) + 8)

    func copy_buffer(aryW: PackedByteArray, dst: int, src: int, size: int):
        var pos: int = 0
        for i in range(size):
            aryW[dst + pos + 0] = aryW[src + pos + 0]
            aryW[dst + pos + 1] = aryW[src + pos + 1]
            pos += 2
        

    func decode() -> PackedByteArray:
        var aryW: PackedByteArray
        var posW: int = 0
        var aryI: PackedByteArray
        var posI: int = 0

        aryW.resize(self.rect.size.x * (self.rect.size.y + 2))
        aryW.fill(0x00)
        aryI.resize(self.rect.size.x * self.rect.size.y * 3)
        aryI.fill(0x00)

        # prepare
        self.ary_cc_table.clear()
        for tbl in range(16):
            var ary_cc: Array
            for v in range(16):
                var code: int = (v + tbl + 1) & 0xF
                ary_cc.push_front(code)
            self.ary_cc_table.append(ary_cc)
    
        var a: int = self.read_color(0)
        var b: int = self.read_color(a)
        var c: int
        var d: int
        var w: int

        for y in range(2):
            for x in range(0, self.rect.size.x, 2):
                aryW[posW + 0] = a
                aryW[posW + 1] = b
                posW += 2

        w = -1

        while true:
            # position
            var pos_decode: int = self.fetch_b_size(2)
            if pos_decode == 3:
                pos_decode += fetch_b_size(1)

            if w == pos_decode:
                w = -1

                while true:
                    var v = aryW[posW - 1]
                    a = self.read_color(v)
                    b = self.read_color(a)

                    aryW[posW + 0] = a
                    aryW[posW + 1] = b
                    posW += 2

                    if self.fetch_b_size(1) == 0:
                        break

            else:
                w = pos_decode
                var size = self.read_len()
                
                match pos_decode:
                    0:
                        a = aryW[posW - 2]
                        b = aryW[posW - 1]

                        if a == b:
                            for i in range(size):
                                aryW[posW + 0] = a
                                aryW[posW + 1] = b
                                posW += 2
                        else:
                            c = aryW[posW - 4]
                            d = aryW[posW - 3]

                            while true:
                                aryW[posW + 0] = c
                                aryW[posW + 1] = d
                                posW += 2
                                size -= 1
                                if size <= 0:
                                    break

                                if posW < aryW.size():
                                    pass
                                else:
                                    break

                                aryW[posW + 0] = a
                                aryW[posW + 1] = b
                                posW += 2
                                size -= 1
                                if size <= 0:
                                    break

                                if posW < aryW.size():
                                    pass
                                else:
                                    break

                    1:
                        # x =  0
                        # y = -1
                        self.copy_buffer(aryW, posW, posW - ( 0 + self.rect.size.x * 1), size)
                        posW += (size * 2)

                    2:
                        # x =  0
                        # y = -2
                        self.copy_buffer(aryW, posW, posW - ( 0 + self.rect.size.x * 2), size)
                        posW += (size * 2)

                    3:
                        # x =  1
                        # y = -1
                        self.copy_buffer(aryW, posW, posW - (-1 + self.rect.size.x * 1), size)
                        posW += (size * 2)

                    4:
                        # x = -1
                        # y = -1
                        self.copy_buffer(aryW, posW, posW - ( 1 + self.rect.size.x * 1), size)
                        posW += (size * 2)

            if posW < aryW.size():
                pass
            else:
                break

        for y in range(self.rect.size.y):
            for x in range(self.rect.size.x):
                var pal: int = aryW[x + ((y + 2) * self.rect.size.x)]
                var col: Color = self.pallet[pal]
                var base: int = (x + y * self.rect.size.x) * 3 
                aryI[base + 0] = col.r8
                aryI[base + 1] = col.g8
                aryI[base + 2] = col.b8

        return aryI


func check_head(data: PackedByteArray) -> bool:
    var ary_head = "Pi".to_ascii_buffer()
    for i in range(2):
        if data[i] != ary_head[i]: return false
    return true


func _load_image(image: Image, file_access: FileAccess, flags, scale) -> Error:
    file_access.big_endian = false

    if check_head(file_access.get_buffer(2)) != true:
        return Error.FAILED

    var imclass: CImagePi = CImagePi.new()

    while true:
        var c = file_access.get_8()
        if c == 0x1A:
            break
        else:
            imclass.comment.append(c)

    while true:
        var c = file_access.get_8()
        if c == 0x00:
            break


    imclass.mode = file_access.get_8()
    # print("mode = ", imclass.mode)
    if imclass.mode != 0x00:
        return Error.FAILED

    imclass.ratio_n = file_access.get_8()
    imclass.ratio_m = file_access.get_8()

    imclass.planes = file_access.get_8()
    if imclass.planes != 0x04:
        # print("screen mode 16 only")
        return Error.FAILED

    for i in range(4):
        imclass.platform.append(file_access.get_8())

    var reserved_size = file_access.get_16()
    for i in range(reserved_size):
        file_access.get_8()

    file_access.big_endian = true

    imclass.rect = Rect2i(
        0,
        0,
        file_access.get_16(),
        file_access.get_16()
    )

    file_access.big_endian = false

    for i in range(16):
        var r = float(file_access.get_8())
        var g = float(file_access.get_8())
        var b = float(file_access.get_8())
        imclass.pallet.append(
            Color(
                r / 255.0,
                g / 255.0,
                b / 255.0
            )
        )

    imclass.aryB = file_access.get_buffer(file_access.get_length() - file_access.get_position())

    var ary_image: PackedByteArray = imclass.decode()

    image.set_data(
        imclass.rect.size.x, imclass.rect.size.y,
        false,
        Image.FORMAT_RGB8, ary_image)

    return Error.OK
