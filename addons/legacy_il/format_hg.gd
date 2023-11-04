# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
extends ImageFormatLoaderExtension


const __support_extensions: PackedStringArray = ["hg"]


func _get_recognized_extensions() -> PackedStringArray:
    return __support_extensions


class CImageHg:
    var comment: PackedByteArray
    var rect: Rect2i
    var pallet: Array[Color]

    var aryB: PackedByteArray
    var posB: int = 0
    var posB_curr: int = 0
    var aryH: PackedByteArray
    var posH: int = 0
    var posH_curr: int = 0

    var ary_cc_table: Array

    func fetch_h() -> int:
        var v: int = 0
        if self.posH_curr == 0:
            v = self.aryH[self.posH] >> 4
        else:
            v = self.aryH[self.posH] & 0x0F
        self.posH_curr += 4
        if self.posH_curr == 8:
            self.posH_curr = 0
            self.posH += 1
        return v

    func fetch_b_pos() -> Vector2i:
        var vct_result: Vector2i
        if self.fetch_b() == 0:
            vct_result = Vector2i(0, -1)
        else:
            var v: int = self.fetch_b() << 1
            v |= self.fetch_b()

            match v:
                0b00: vct_result = Vector2i(-1, -1)
                0b01: vct_result = Vector2i(-1,  1)
                0b10: vct_result = Vector2i(-2, -1)
                0b11: vct_result = Vector2i(-2,  1)
                _: assert(false, "match error")

        var count: int = 0
        for i in range(4):
            if self.fetch_b() == 0:
                break
            else:
                count += 1

        if count == 0:
            if vct_result.x != 0:
                vct_result.y = 0
        else:
            vct_result.y *= pow(2, count)

        vct_result.x *= 4

        return vct_result

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

    func set_pixel(aryW: PackedByteArray, x: int, y: int, v: int):
        if self.rect.has_point(Vector2i(x, y)) == false:
            return 0
        
        var posW: int = x + y * self.rect.size.x
        aryW[posW] = v

    func get_pixel(aryW: PackedByteArray, x: int, y: int) -> int:
        if self.rect.has_point(Vector2i(x, y)) == false:
            return 0
        
        var posW: int = x + y * self.rect.size.x
        return aryW[posW]

    func inference_cc(aryW: PackedByteArray, x: int, y: int) -> int:
        var A: int = self.get_pixel(aryW, x,     y - 1)
        var B: int = self.get_pixel(aryW, x,     y - 2)
        var C: int = self.get_pixel(aryW, x - 1, y    )
        var D: int = self.get_pixel(aryW, x - 2, y    )
        var E: int = self.get_pixel(aryW, x - 1, y - 1)
        var F: int = self.get_pixel(aryW, x - 2, y - 2)

        if A == B: return A
        if B == D && B == F: return B
        if C == D: return C

        return E

    func slide_copy(aryW: PackedByteArray, vct_dst: Vector2i, vct_src: Vector2i, length: int):
        var vct_work: Vector2i = vct_dst + vct_src
        var ary_src: Array
        for y in range(length):
            for x in range(4):
                var v: int = self.get_pixel(aryW, vct_work.x + x, vct_work.y + y)
                self.set_pixel(aryW, vct_dst.x + x, vct_dst.y + y, v)
 
    func decode() -> PackedByteArray:
        var aryW: PackedByteArray
        var posW: int = 0
        aryW.resize(self.rect.size.x * self.rect.size.y)
        aryW.fill(0x00)

        # prepare
        self.ary_cc_table.clear()
        for tbl in range(16):
            var ary_cc: Array
            for v in range(15):
                var code: int = (v + tbl + 1) & 0xF
                ary_cc.append(code)
            self.ary_cc_table.append(ary_cc)
        
        # decode
        for x in range(0, self.rect.size.x, 4):
            var y: int = 0
            while y < self.rect.size.y:
                if self.fetch_b() == 1:
                    # slide copy
                    var bitsA: String = ""
                    var bitsB: String = ""
                    var bitsV: int = 0

                    while true:
                        var v: int = self.fetch_b()
                        bitsA += "%d" % [v]
                        if v == 1:
                            break

                    for n in range(bitsA.length() - 1):
                        var v: int = self.fetch_b()
                        bitsV <<= 1
                        bitsV |= v
                        bitsB += "%d" % [v]

                    var l: int = bitsV + pow(2, bitsA.length() - 1) + 1
                    var vct_src: Vector2i = self.fetch_b_pos()
                    self.slide_copy(aryW, Vector2i(x, y), vct_src, l)

                    y += l

                else:
                    # decode ColorCode
                    var data = self.fetch_h()
                    for pos in range(4):
                        var c = self.inference_cc(aryW, x + pos, y)

                        if data & (0b1000 >> pos):
                            var bitsA: String = ""
                            while true:
                                var v: int = self.fetch_b()
                                bitsA += "%d" % [v]
                                if v == 1:
                                    break

                            var cc: Array = self.ary_cc_table[c]
                            var t: int = bitsA.length() - 1
                            var v: int = cc[t]

                            c = v

                            cc.remove_at(t)
                            cc.push_front(v)

                        self.set_pixel(aryW, x + pos, y, c)

                    y += 1

        # print("posB ", self.posB)
        # print("posH ", self.posH)

        var aryI: PackedByteArray
        var posI: int = 0

        aryI.resize(self.rect.size.x * self.rect.size.y * 3)
        aryI.fill(0x00)

        for x in range(0, self.rect.size.x):
            for y in range(self.rect.size.y):
                var pal: int = aryW[x + y * self.rect.size.x]
                var col: Color = self.pallet[pal]
                var base: int = (x + y * self.rect.size.x) * 3 
                aryI[base + 0] = col.r8
                aryI[base + 1] = col.g8
                aryI[base + 2] = col.b8

        return aryI



func check_head(data: PackedByteArray) -> bool:
    var ary_head = "HG2  ".to_ascii_buffer()
    for i in range(3):
        if data[i] != ary_head[i]: return false
    return true


func _load_image(image: Image, file_access: FileAccess, flags, scale) -> Error:
    file_access.big_endian = false

    if check_head(file_access.get_buffer(5)) != true:
        return Error.FAILED

    var imclass: CImageHg = CImageHg.new()

    while true:
        var c = file_access.get_8()
        if c == 0x1A:
            break
        else:
            imclass.comment.append(c)

    imclass.rect = Rect2i(
        file_access.get_16() * 8,
        file_access.get_16(),
        file_access.get_16() * 8,
        file_access.get_16()
    )

    for i in range(16):
        var v: int = file_access.get_16()
        var g = float(((v & 0b11111000_00000000) >> 8))
        var r = float(((v & 0b00000111_11000000) >> 3))
        var b = float(((v & 0b00000000_00111110) << 2))
        var c = v & 0b00000000_00000001
        # print("%2d %3d %3d %3d %d" % [i, r, g, b, c])
        imclass.pallet.append(
            Color(
                r / 255.0,
                g / 255.0,
                b / 255.0
            )
        )

    var aryBsize: int = 0
    while true:
        var v = file_access.get_16()
        if v == 0:
            aryBsize += 0x8000
        else:
            aryBsize += v
            break

    imclass.aryB = file_access.get_buffer(aryBsize)
    # print("aryB = ", imclass.aryB.size())
    imclass.aryH = file_access.get_buffer(file_access.get_length() - file_access.get_position())
    # print("aryH = ", imclass.aryH.size())

    var ary_image: PackedByteArray = imclass.decode()

    image.set_data(
        imclass.rect.size.x, imclass.rect.size.y,
        false,
        Image.FORMAT_RGB8, ary_image)

    return Error.OK
