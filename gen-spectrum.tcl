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

set LAYOUT [list] ;# Only desktop layout

set NS ::ttk::theme::spectrum

proc rgb_to_hex {rgb_string} {
    if {[regexp {^{(\S+)}$} $rgb_string -> varname]} {
	return "\$${::NS}::COLOR($varname)" ;# An alias to another value
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

proc px_to_num {px_string} {
    if {[regexp {^{(\S+)}$} $px_string -> varname]} {
	if {[string match "*font-*" $varname]} {
	    if {! [string match "font-size-*" $varname]} {
		# Only support font-size because Tk fonts work
		# differently than CSS fonts. Fonts will be created
		# and referenced directly.
		throw {PXVAL INVALID} "Invalid size format: $px_string"
	    }
	    return "\$${::NS}::FONT($varname)"
	}
	return "\$${::NS}::LAYOUT($varname)" ;# An alias to another value
    }
    if {[regexp {^(-?[\d.]+)(?:px)?$} $px_string -> px_value]} {
        return $px_value

    } else {
        throw {PXVAL INVALID} "Invalid size format: $px_string"
    }
}

proc parse_layout {layout_dict} {
    foreach key [lsort -command cmpkeys [dict keys $layout_dict]] {
	try {
	    if {[dict exists $layout_dict $key sets]} {
		lappend ::LAYOUT $key [px_to_num [dict get $layout_dict $key sets desktop value]]

	    } else {
		lappend ::LAYOUT $key [px_to_num [dict get $layout_dict $key value]]
	    }

	} trap {PXVAL INVALID} res {
	    puts stderr $res
	}
    }
}

try {
    foreach color_file {
	color-palette.json
	semantic-color-palette.json
	color-aliases.json
	color-component.json
	icons.json
    } {
	set color_dict [parse_json_file [file join $spectrum_dir $color_file]]
	parse_colors $color_dict
    }

    foreach layout_file {
	layout.json
	layout-component.json
    } {
	set layout_dict [parse_json_file [file join $spectrum_dir $layout_file]]
	parse_layout $layout_dict
    }

    foreach {key val} $LAYOUT {
	puts "$key $val"
    }

} on error {res} {
    puts stderr "$res"
    exit 1
}
