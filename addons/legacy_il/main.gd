# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
@tool
extends EditorPlugin


const format_hg  = preload("res://addons/legacy_il/format_hg.gd")
const format_mag = preload("res://addons/legacy_il/format_mag.gd")
const format_pi  = preload("res://addons/legacy_il/format_pi.gd")

var ary_instance: Array = []


func _enter_tree():
    ary_instance.append(format_hg.new())
    ary_instance.append(format_mag.new())
    ary_instance.append(format_pi.new())

    for instance in ary_instance:
        instance.add_format_loader()

func _exit_tree():
    for instance in ary_instance:
        instance.remove_format_loader()
    ary_instance.clear()
