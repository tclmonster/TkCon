
# Copyright (c) 2025, Bandoti Ltd.

namespace eval ::spectrum {
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

    set var(darkmode) [GetDarkModeSetting]

    set var(sans-serif-font-family) [::apply {{} {
	set families [switch -- [tk windowingsystem] {
	    win32   {expr {{"Segoe UI" "Tahoma" "MS Sans Serif" "Arial"}}}
	    aqua    {expr {{"SF Pro Text" "Lucida Grande" "Geneva"}}}
	    default {expr {{"Noto Sans" "DejaVu Sans" "Liberation Sans" "Ubuntu"}}}
	}]
	foreach fam [concat "Source Sans Pro" $families] {
	    if {$fam in [font families]} {
		return $fam
	    }
	}
	return "Helvetica"
    }}]

    set var(serif-font-family) [::apply {{} {
        set families [switch -- [tk windowingsystem] {
            win32   {expr {{"Cambria" "Georgia"}}}
            aqua    {expr {{"Palatino" "Times"}}}
            default {expr {{"Noto Serif" "DejaVu Serif" "Liberation Serif"}}}
        }]
        foreach fam [concat "Source Serif Pro" $families] {
            if {$fam in [font families]} {
                return $fam
            }
        }
        return "Times New Roman"
    }}]

    set var(code-font-family) [::apply {{} {
	set families [switch -- [tk windowingsystem] {
	    win32   {expr {{"Cascadia Code" "Consolas" "Lucida Console" "Courier New"}}}
	    aqua    {expr {{"SF Mono" "Menlo" "Monaco"}}}
	    default {expr {{"Noto Sans Mono" "DejaVu Sans Mono" "Liberation Mono" "Ubuntu Mono"}}}
	}]
	foreach fam [concat "Source Code Pro" $families] {
	    if {$fam in [font families]} {
		return $fam
	    }
	}
	return "Courier"
    }}]
}

namespace eval ::spectrum::priv {}

proc ::spectrum::priv::get_or_create_font {family_key size bold} {
    namespace upvar ::spectrum var var
    set weight [expr {$bold ? "bold" : "normal"}]
    set tk_font_name "${family_key}-${size}-${weight}"
    if {$tk_font_name in [font names]} {
	return $tk_font_name
    }
    set family  $var($family_key)
    set size_px $var($size)
    return [font create $tk_font_name -family $family -size -${size_px} -weight $weight]
}

source [file join [file dirname [info script]] spectrum-vars.tcl]
