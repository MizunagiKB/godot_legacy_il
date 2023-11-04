# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
extends ImageFormatLoaderExtension


const __support_extensions: PackedStringArray = ["mag"]
const ary_pickup: Array[Vector2i] = [
    Vector2i( 0, 0), Vector2i( 4, 0), Vector2i( 8, 0), Vector2i(16, 0),
    Vector2i( 0, 1), Vector2i( 4, 1),
    Vector2i( 0, 2), Vector2i( 4, 2), Vector2i( 8, 2),
    Vector2i( 0, 4), Vector2i( 4, 4), Vector2i( 8, 4),
    Vector2i( 0, 8), Vector2i( 4, 8), Vector2i( 8, 8),
    Vector2i( 0,16)
]


func _get_recognized_extensions() -> PackedStringArray:
    return __support_extensions


class CImageMag:
    var model_code: PackedByteArray
    var username: PackedByteArray
    var comment: PackedByteArray

    var platform_code: int
    var platform_flag: int
    var screen_mode: int

    var rect: Rect2i
    var pallet: Array[Color]

    var aryA: PackedByteArray
    var posA: int = 0
    var posA_curr: int = 0
    var aryB: PackedByteArray
    var posB: int = 0
    var aryP: PackedByteArray
    var posP: int = 0

    func fetch_A() -> int:
        var v: int = self.aryA[self.posA] & (0x80 >> self.posA_curr)
        self.posA_curr += 1
        if self.posA_curr == 8:
            self.posA_curr = 0
            self.posA += 1
        
        if v > 0:
            return 1
        else:
            return 0

    func fetch_B() -> int:
        var v: int = 0
        if self.posB < self.aryB.size():
            v = self.aryB[self.posB]
            self.posB += 1
        else:
            # print("ERR: self.posB < self.aryB.size()")
            pass
        return v

    func draw_pixel(aryI: PackedByteArray, vct_dst: Vector2i):
        if self.posP < self.aryP.size():
            var dst = (vct_dst.x + (vct_dst.y * self.rect.size.x)) * 3
            var ary_color: Array[Color] = [
                self.pallet[self.aryP[self.posP] >> 4],
                self.pallet[self.aryP[self.posP] & 0xF]
            ]
            self.posP += 1

            for i in range(2):
                if dst < aryI.size():
                    aryI[dst + 0] = ary_color[i].r8
                    aryI[dst + 1] = ary_color[i].g8
                    aryI[dst + 2] = ary_color[i].b8
                    dst += 3
   
    func copy_pixel(aryI: PackedByteArray, vct_dst: Vector2i, vct_src: Vector2i):
        var src = (vct_src.x + (vct_src.y * self.rect.size.x)) * 3
        var dst = (vct_dst.x + (vct_dst.y * self.rect.size.x)) * 3

        for n in range(4):
            if dst < aryI.size():
                aryI[dst + 0] = aryI[src + 0]
                aryI[dst + 1] = aryI[src + 1]
                aryI[dst + 2] = aryI[src + 2]
                src += 3
                dst += 3

    func decode() -> PackedByteArray:
        var aryI: PackedByteArray
        var posI: int = 0
        aryI.resize(self.rect.size.x * self.rect.size.y * 3)
    
        var aryT: PackedByteArray
        aryT.resize(self.rect.size.x)
        aryT.fill(0x00)

        for y in range(self.rect.size.y):
            var posT: int = 0
            var x: int = 0

            posT = 0
            x = 0
            while x < self.rect.size.x:
                if self.fetch_A() == 1:
                    aryT[posT] ^= self.fetch_B()
                posT += 1
                x += 8

            posT = 0
            x = 0
            var ppos: int = 0
            while x < self.rect.size.x:
                var mode: int = 0
                if ppos == 0:
                    mode = aryT[posT] >> 4
                    ppos = 1
                else:
                    mode = aryT[posT] & 0xF
                    ppos = 0
                    posT += 1

                if mode == 0:
                    self.draw_pixel(aryI, Vector2i(x + 0, y))
                    self.draw_pixel(aryI, Vector2i(x + 2, y))
                else:
                    self.copy_pixel(
                        aryI,
                        Vector2i(x, y),
                        Vector2i(x, y) - ary_pickup[mode]
                    )
                x += 4

        return aryI


func check_head(data: PackedByteArray) -> bool:
    var ary_head = "MAKI02  ".to_ascii_buffer()
    for i in range(8):
        if data[i] != ary_head[i]: return false
    return true


func _load_image(image: Image, file_access: FileAccess, flags, scale) -> Error:
    flags = flags as ImageFormatLoader.LoaderFlags

    file_access.big_endian = false

    if check_head(file_access.get_buffer(8)) != true:
        return Error.FAILED

    var imclass = CImageMag.new()
    imclass.model_code = file_access.get_buffer(4)
    # imclass.username = file_access.get_buffer(18)

    var ix: int = 0
    while true:
        var c = file_access.get_8()
        ix += 1
        if c == 0x1A:
            break
        else:
            imclass.comment.append(c)

    var base_offset: int = file_access.get_position()

    if file_access.get_8() != 0x00:
        return Error.FAILED

    imclass.platform_code = file_access.get_8()
    imclass.platform_flag = file_access.get_8()
    imclass.screen_mode = file_access.get_8()

    var x1: int = file_access.get_16()
    var y1: int = file_access.get_16()
    var x2: int = file_access.get_16() + 1
    var y2: int = file_access.get_16() + 1
    
    imclass.rect = Rect2i(
        x1,
        y1,
        x2 - x1,
        y2 - y1
    )
    # print("%3d %3d %3d %3d" % [x1, y1, x2, y2])
    # print(imclass.rect)
    
    var flgA_offset = file_access.get_32()
    var flgB_offset = file_access.get_32()
    var flgB_size = file_access.get_32()
    var pixel_offset = file_access.get_32()
    var pixel_size = file_access.get_32()

    var pallet_size: int = 16
    if imclass.screen_mode & 0x80:
        pallet_size = 256

    for i in range(pallet_size):
        var g = float(file_access.get_8())
        var r = float(file_access.get_8())
        var b = float(file_access.get_8())
        imclass.pallet.append(
            Color(
                r / 255.0,
                g / 255.0,
                b / 255.0
            )
        )

    file_access.seek(base_offset + flgA_offset)
    imclass.aryA = file_access.get_buffer(flgB_offset - flgA_offset)
    # print(imclass.aryA.size())
    file_access.seek(base_offset + flgB_offset)
    imclass.aryB = file_access.get_buffer(flgB_size)
    # print(imclass.aryB.size())

    file_access.seek(base_offset + pixel_offset)
    imclass.aryP = file_access.get_buffer(pixel_size)
    # print(imclass.aryP.size())

    var ary_image: PackedByteArray = imclass.decode()

    image.set_data(
        imclass.rect.size.x, imclass.rect.size.y,
        false,
        Image.FORMAT_RGB8, ary_image)

    return Error.OK
