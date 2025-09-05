#!/usr/bin/env tclsh

# Copyright (c) 2025, Bandoti Ltd.

package require tjson

# Helper script to generate Tcl initialization procedures for spectrum
# color palettes, layouts and fonts. This parses JSON design tokens and
# generates corresponding COLOR, LAYOUT, and FONT arrays.

set verbose [::apply {{} {
    set found [lsearch -exact $::argv "-verbose"]
    if {$found != -1} {
	set ::argv [lreplace $::argv $found $found]
	return 1
    }
    return 0
}}]

if {[llength $argv] != 1} {
    puts stderr "Usage: tclsh gen-spectrum.tcl ?-verbose? <spectrum-tokens-dir>"
    exit 1
}

set spectrum_dir [lindex $argv 0]

if {! [file isdirectory $spectrum_dir]} {
    puts stderr "\"$spectrumdir\" must be a valid directory"
    exit 1
}

set NS ::ttk::theme::spectrum ;# When loading at runtime

set COLOR       [list] ;# Both light & dark
set COLOR_LIGHT [list]
set COLOR_DARK  [list]
set LAYOUT      [list] ;# Only desktop layout
set FONT        [list]

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

proc refs_to_bottom {a b} {
    set a_is_var [expr {[string index $a 0] eq "\[" || [string index $a 0] eq "\$"}]
    set b_is_var [expr {[string index $b 0] eq "\[" || [string index $b 0] eq "\$"}]
    if {$a_is_var && !$b_is_var} {
	return 1
    } elseif {$b_is_var && !$a_is_var} {
	return -1
    } else {
	return 0
    }
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
	    if {$::verbose} { puts stderr $res }
	}
    }
    set ::COLOR_LIGHT [lsort -stride 2 -index 1 -command refs_to_bottom $::COLOR_LIGHT]
    set ::COLOR_DARK  [lsort -stride 2 -index 1 -command refs_to_bottom $::COLOR_DARK]
    set ::COLOR [lsort -stride 2 -index 1 -command refs_to_bottom $::COLOR]
}

proc in_colors? {name} {
    expr {
	  $name in $::COLOR_LIGHT || $name in $::COLOR_DARK || $name in $::COLOR
      }
}

# Process values for layout & font JSON entries.
proc val_to_num {px_string} {
    if {[regexp {^{(\S+)}$} $px_string -> varname]} {
	# Layout & font entries sometimes reference variables
	# outside of the "FONT" variable (in CSS of course these
	# are all lumped together, but here they are split by
	# category).
	if {[string match "*font*" $varname]} {
	    if {! [string match "*font-size*" $varname]} {
		# Only support font-size because Tk fonts work
		# differently than CSS fonts. Fonts will be created
		# and referenced directly.
		throw {PXVAL INVALID} "Invalid size format: $px_string"
	    }
	    return "\$FONT($varname)"

	} elseif {[in_colors? $varname]} {
	    return "\$COLOR($varname)"
	}

	return "\$LAYOUT($varname)"
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
		lappend ::LAYOUT $key [val_to_num [dict get $layout_dict $key sets desktop value]]

	    } else {
		lappend ::LAYOUT $key [val_to_num [dict get $layout_dict $key value]]
	    }

	} trap {PXVAL INVALID} res {
	    if {$::verbose} { puts stderr $res }
	}
    }
    set ::LAYOUT [lsort -stride 2 -index 1 -command refs_to_bottom $::LAYOUT]
}

proc parse_font {font_dict} {
    # The only font variables of use to Tk are the sizing-/spacing-
    # related values and font families. This routine expects that there will be
    # appropriate font names populated in FONT at runtime. For example,
    # set FONT(sans-serif-font-family) "Segoe UI"
    # This is required because Adobe's fonts are proprietary and so the
    # best available system font should be calculated.
    foreach key [lsort -command cmpkeys [dict keys $font_dict]] {
	if {[dict exists $font_dict $key value fontFamily]} {
	    set family [dict get $font_dict $key value fontFamily]
	    set size [dict get $font_dict $key value fontSize]
	    set bold [string match "*bold*" [dict get $font_dict $key value fontWeight]]
	    lappend ::FONT $key "\[get_or_create_font $family $size $bold\]"
	    continue
	}
	switch -glob -- $key {
	    *size*    -
	    *height*  -
	    *margin*  -
	    *color*   -
	    *spacing* {
		try {
		    if {[dict exists $font_dict $key sets]} {
			lappend ::FONT $key [val_to_num [dict get $font_dict $key sets desktop value]]

		    } else {
			lappend ::FONT $key [val_to_num [dict get $font_dict $key value]]
		    }

		} trap {PXVAL INVALID} res {
		    if {$::verbose} { puts stderr $res }
		}
	    }
	}
    }
    set ::FONT [lsort -stride 2 -index 1 -command refs_to_bottom $::FONT]
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

    set font_dict [parse_json_file [file join $spectrum_dir typography.json]]
    parse_font $font_dict

    set template {
    # The following was auto-generated by gen-spectrum.tcl.
    namespace eval ::ttk::theme::spectrum {
	variable FONT
	variable COLOR
	variable LAYOUT

	proc get_or_create_font {family_key size bold} {
	    variable FONT
	    set weight [expr {$bold ? "bold" : "normal"}]
	    set tk_font_name "${family_key}-${size}-${weight}"
	    if {$tk_font_name in [font names]} {
		return $tk_font_name
	    }
	    set family  $FONT($family_key)
	    set size_px $FONT($size)
	    return [font create $tk_font_name -family $family -size -${size_px} -weight $weight]
	}

	if {$COLOR(darkmode)} {
@DARK_COLOR@
	} else {
@LIGHT_COLOR@
	}
@COLOR@
@LAYOUT@
@FONT@
    }
    }

    set dark_color [join [lmap key [dict keys $COLOR_DARK] val [dict values $COLOR_DARK] {
	expr {"            set COLOR($key) $val"}
    }] \n]

    set light_color [join [lmap key [dict keys $COLOR_LIGHT] val [dict values $COLOR_LIGHT] {
	expr {"            set COLOR($key) $val"}
    }] \n]

    set color [join [lmap key [dict keys $COLOR] val [dict values $COLOR] {
	expr {"        set COLOR($key) $val"}
    }] \n]

    set font [join [lmap key [dict keys $FONT] val [dict values $FONT] {
	expr {"        set FONT($key) $val"}
    }] \n]

    set layout [join [lmap key [dict keys $LAYOUT] val [dict values $LAYOUT] {
	expr {"        set LAYOUT($key) $val"}
    }] \n]

    set mapping [list @DARK_COLOR@ $dark_color @LIGHT_COLOR@ $light_color \
		      @COLOR@ $color @FONT@ $font @LAYOUT $layout]

    puts [string map $mapping $template]

} on error {res} {
    puts stderr "$res"
    exit 1
}
