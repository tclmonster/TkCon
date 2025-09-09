#!/usr/bin/env tclsh

# Copyright (c) 2025, Bandoti Ltd.

package require tjson

# Helper script to generate Tcl initialization procedures for spectrum
# color palettes, layouts and fonts. This parses JSON design tokens and
# generates corresponding var array containing amalgamated variables.

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

set var [list]

proc rgb_to_hex {rgb_string} {
    if {[regexp {^{(\S+)}$} $rgb_string -> varname]} {
	return "\$var($varname)" ;# An alias to another value
    }

    if {[regexp {rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)} $rgb_string -> r g b]} {
        return [format "\"#%02X%02X%02X\"" $r $g $b]

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
		set lightval [rgb_to_hex [dict get $color_dict $key sets light value]]
		set darkval  [rgb_to_hex [dict get $color_dict $key sets dark  value]]
		lappend ::var $key "\[expr {\$var(darkmode) ? $darkval : $lightval}\]"

	    } else {
		lappend ::var $key [rgb_to_hex [dict get $color_dict $key value]]
	    }

	} trap {RGBSTR INVALID} res {
	    if {$::verbose} { puts stderr $res }
	}
    }
}

# Process values for layout & font JSON entries.
proc val_to_num {px_string} {
    if {[regexp {^{(\S+)}$} $px_string -> varname]} {
	# Handle variable references
	if {[string match "*font*" $varname]} {
	    if {! [string match "*font-size*" $varname]} {
		# Only support font-size because Tk fonts work
		# differently than CSS fonts. Fonts will be created
		# and referenced directly.
		throw {PXVAL INVALID} "Invalid size format: $px_string"
	    }
	}
	return "\$var($varname)"
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
		lappend ::var $key [val_to_num [dict get $layout_dict $key sets desktop value]]

	    } else {
		lappend ::var $key [val_to_num [dict get $layout_dict $key value]]
	    }

	} trap {PXVAL INVALID} res {
	    if {$::verbose} { puts stderr $res }
	}
    }
}

proc parse_font {font_dict} {
    # The only font variables of use to Tk are the sizing-/spacing-
    # related values and font families. This routine expects that there will be
    # appropriate font names populated in var at runtime. For example,
    # set var(sans-serif-font-family) "Segoe UI"
    # This is required because Adobe's fonts are proprietary and so the
    # best available system font should be calculated.
    foreach key [lsort -command cmpkeys [dict keys $font_dict]] {
	if {[dict exists $font_dict $key value fontFamily]} {
	    set family [dict get $font_dict $key value fontFamily]
	    set size [dict get $font_dict $key value fontSize]
	    set bold [string match "*bold*" [dict get $font_dict $key value fontWeight]]
	    lappend ::var $key "\[get_or_create_font $family $size $bold\]"
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
			lappend ::var $key [val_to_num [dict get $font_dict $key sets desktop value]]

		    } else {
			lappend ::var $key [val_to_num [dict get $font_dict $key value]]
		    }

		} trap {PXVAL INVALID} res {
		    if {$::verbose} { puts stderr $res }
		}
	    }
	}
    }
}

oo::class create DependencySorter {
    variable Visited
    variable Sorted
    variable Elements

    method GetDependencies {value} {
        set deps    {}
        set pattern "\\\$var\\((\[^)]+)\\)"
        set matches [regexp -all -inline -- $pattern $value]
	if {$matches ne ""} {
	    foreach {_ dep} $matches {
		if {$dep eq "darkmode"} { continue }
		lappend deps $dep
	    }
	}
        return $deps
    }

    method Dfs {key value} {
	set Visited($key) 1
	set deps [my GetDependencies $value]
	foreach dep $deps {
	    if {! [dict exists $Elements $dep] || $Visited($dep) == 2} {
		set Visited($key) 2
		puts stderr "Skipping \"$key\" due to missing dependency \"$dep\""
		return
	    }
	    if {$Visited($dep) == -1} {
		my Dfs $dep [dict get $Elements $dep]

	    }
	}
	lappend Sorted $key $value
    }

    constructor {elements} {
	set Elements $elements
    }

    method sort {} {
	array set Visited {}
	set Sorted [list]
	foreach {key _} $Elements { set Visited($key) -1 }
	foreach {key value} $Elements {
	    if {$Visited($key) == -1} {
		my Dfs $key $value
	    }
	}
	return $Sorted
    }
}

proc toposort {elements} {
    set sorter [DependencySorter new $elements]
    set result [$sorter sort]
    $sorter destroy
    return $result
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

    set ::var [toposort $::var]

    set template {
    # The following was auto-generated by gen-spectrum.tcl.
    namespace eval ::ttk::theme::spectrum {
	variable var

	if {[tk windowingsystem] eq "win32"} {
	    package require registry

	    proc GetDarkModeSetting {} {
		set keyPath {HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize}
		try {
		    set appsUseLightTheme [registry get $keyPath AppsUseLightTheme]
		    return [expr {$appsUseLightTheme == 0}]

		} on error {} {
		    return 0
		}
	    }

	} elseif {[tk windowingsystem] eq "aqua"} {
	    proc GetDarkModeSetting {} { return 0 }

	} else {
	    proc GetDarkModeSetting {} { return 0 }
	}

	proc get_or_create_font {family_key size bold} {
	    variable var
	    set weight [expr {$bold ? "bold" : "normal"}]
	    set tk_font_name "${family_key}-${size}-${weight}"
	    if {$tk_font_name in [font names]} {
		return $tk_font_name
	    }
	    set family  $var($family_key)
	    set size_px $var($size)
	    return [font create $tk_font_name -family $family -size -${size_px} -weight $weight]
	}

	if {![info exists var(darkmode)]} {
	    set var(darkmode) [GetDarkModeSetting]
	}
@VARS@
    }
    }

    set variables [join [lmap key [dict keys $var] val [dict values $var] {
	expr {"        set var($key) $val"}
    }] \n]

    puts [string map [list @VARS@ $variables] $template]

} on error res {
    puts stderr "$res"
    exit 1
}
