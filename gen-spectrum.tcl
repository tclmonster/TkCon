#!/usr/bin/env tclsh

# Copyright (c) 2025, Bandoti Ltd.

package require tjson

# Helper script to generate Tcl initialization procedures for spectrum
# color palettes, layouts, etc. This parses JSON design tokens and converts
# them to setters for corresponding arrays: ::tkcon::COLOR, ::tkcon::SCALE.

if {[llength $argv] != 1} {
    puts stderr "Usage: tclsh gen-spectrum.tcl <spectrum-tokens-dir>"
    exit 1
}

set spectrum_dir [lindex $argv 0]

if {! [file isdirectory $spectrum_dir]} {
    puts stderr "\"$spectrumdir\" must be a valid directory"
    exit 1
}

set COLOR       [list] ;# Both light & dark
set COLOR_LIGHT [list]
set COLOR_DARK  [list]

proc rgb_to_hex {rgb_string} {
    if {[regexp {^{(\S+)}$} $rgb_string -> varname]} {
	return "\$COLOR($varname)" ;# An alias to another value
    }

    if {[regexp {rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)} $rgb_string -> r g b]} {
        return [format "#%02X%02X%02X" $r $g $b]

    } else {
        throw {RGBSTR INVALID} "Invalid RGB format: $rgb_string"
    }
}

proc parse_json_file {file} {
    try {
	set fd [open $file r]
	return [::tjson::json_to_simple [read $fd]]

    } finally {
	catch {close $fd}
    }
}

proc cmpkeys {a b} {
    if {![regexp {^(.+)-(\d+)$} $a -> a_prefix a_num]} {
        set a_prefix $a
        set a_num -1
    }
    if {![regexp {^(.+)-(\d+)$} $b -> b_prefix b_num]} {
        set b_prefix $b
        set b_num -1
    }
    set color_cmp [string compare $a_prefix $b_prefix]
    expr {$color_cmp != 0 ? $color_cmp : ($a_num < $b_num ? -1 : ($a_num > $b_num ? 1 : 0))}
}

proc parse_colors {color_dict} {
    foreach key [lsort -command cmpkeys [dict keys $color_dict]] {
	try {
	    if {[dict exists $color_dict $key sets]} {
		lappend ::COLOR_LIGHT $key [rgb_to_hex [dict get $color_dict $key sets light value]]
		lappend ::COLOR_DARK  $key [rgb_to_hex [dict get $color_dict $key sets dark  value]]

	    } else {
		lappend ::COLOR $key [rgb_to_hex [dict get $color_dict $key value]]
	    }

	} trap {RGBSTR INVALID} res {
	    puts stderr $res
	}
    }
}

try {
    foreach json_file {
	color-palette.json
	semantic-color-palette.json
	color-aliases.json
	color-component.json
    } {
	set color_dict [parse_json_file [file join $spectrum_dir $json_file]]
	parse_colors $color_dict
    }

    foreach {key val} $COLOR {
	puts "$key $val"
    }

} on error {res} {
    puts stderr "$res"
    exit 1
}
