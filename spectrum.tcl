
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

if {[tk windowingsystem] eq "win32"} {
    if {! [catch {package require cffi}]} {
	namespace eval ::spectrum {
	    cffi::alias load win32

	    cffi::Wrapper create dwmapi [file join $env(windir) system32 dwmapi.dll]
	    cffi::Wrapper create user32 [file join $env(windir) system32 user32.dll]

	    cffi::alias define HRESULT {long nonnegative winerror}
	    dwmapi stdcall DwmSetWindowAttribute HRESULT {
		hwnd        pointer.HWND
		dwAttribute DWORD
		pvAttribute pointer
		cbAttribute DWORD
	    }

	    user32 stdcall GetParent pointer.HWND {
		hwnd pointer.HWND
	    }
	}

	proc ::spectrum::SetWindowDarkMode {window value} {
	    update
	    set hwndptr [cffi::pointer make [winfo id $window] HWND]
	    cffi::pointer safe $hwndptr
	    set parentptr [GetParent $hwndptr]

	    set darkmodeptr [cffi::arena pushframe BOOL]
	    cffi::memory set $darkmodeptr BOOL $value

	    set size [cffi::type size BOOL]
	    DwmSetWindowAttribute $parentptr 19 $darkmodeptr $size
	    DwmSetWindowAttribute $parentptr 20 $darkmodeptr $size

	    cffi::arena popframe
	    cffi::pointer dispose $hwndptr
	    cffi::pointer dispose $parentptr
	}
    }
}

oo::class create ::spectrum::Theme {
    constructor {} {
	ttk::style theme create spectrum -parent clam
	set appname [winfo class .]
	bind $appname <<ThemeChanged>> +[list [self] refreshOptions]
	bind $appname <<ThemeChanged>> +[list [self] refreshBindings]
	bind Menu <<ThemeChanged>> +[list [self] refreshMenu %W]
    }

    method refreshBindings {} {
	if {[ttk::style theme use] ne "spectrum"} {
	    return
	}
	if {[info commands ::spectrum::SetWindowDarkMode] ne ""} {
	    bind [winfo class .] <Map> {
		::spectrum::SetWindowDarkMode %W $::spectrum::var(darkmode)
	    }
	    bind Toplevel <Map> {
		::spectrum::SetWindowDarkMode %W $::spectrum::var(darkmode)
	    }
	}
    }

    method refreshMenu {window} {
	namespace upvar ::spectrum COLOR C
	if {[ttk::style theme use] ne "spectrum"} {
	    return
	}
	# TODO: when it is desireable to switch theme at runtime
	# the existing menus will have to be updated here.
    }

    method refreshOptions {} {
	namespace upvar ::spectrum var var
	if {[ttk::style theme use] ne "spectrum"} {
	    return
	}

	if 0 {
	ttk::style theme settings spectrum {
	    ttk::style configure "." \
		-background $C(background) \
		-foreground $C(foreground) \
		-selectbackground $C(selectBackground) \
		-selectforeground $C(selectForeground) \
		-font spectrumui \
		-relief flat \
		-bordercolor $C(borderColor) \
		-troughcolor $C(troughColor) \
		-highlightcolor $C(highlightColor) \
		-bordercolor $C(borderColor)

	    ttk::style map . -foreground [list {active !disabled} $C(activeForeground) disabled $C(disabledForeground)]
	    ttk::style map . -background [list {active !disabled} $C(activeBackground) disabled $C(disabledBackground)]

	    set arrowsize [expr {int(9/8.0 * [font measure spectrumui "M"])}]
	    ttk::style configure TScrollbar -arrowsize $arrowsize -arrowcolor $C(foreground) -gripcount 0 \
		-borderwidth 0 -lightcolor $C(background) -darkcolor $C(background)

	    ttk::style map TScrollbar -lightcolor [list {active !disabled} $C(activeBackground)] \
		-darkcolor [list {active !disabled} $C(activeBackground)] \
		-arrowcolor [list disabled $C(disabledForeground)]

	    ttk::style configure TButton -background $C(selectBackground) -foreground $C(selectForeground)
	    ttk::style map TButton -background [list {hover !disabled} $C(highlightColor)] \
		-foreground [list {hover !disabled} $C(selectForeground)]

	    ttk::style configure TSeparator -background $C(borderColor)
	}

	tk_setPalette \
	    background $C(background) \
	    foreground $C(foreground) \
	    activeBackground $C(activeBackground) \
	    activeForeground $C(activeForeground) \
	    selectForeground $C(selectForeground) \
	    selectBackground $C(selectBackground) \
	    highlightColor $C(highlightColor) \
	    highlightBackground $C(highlightBackground) \
	    disabledForeground $C(disabledForeground) \
	    insertBackground $C(insertBackground) \
	    troughColor $C(troughColor)

	option add *Menu.activeBackground $C(selectBackground) ;# Accent color
	option add *Menu.activeForeground $C(selectForeground)

	option add *Text.background $C(consoleBackground)
	} ;# IF 0
    }

    method use {} {
	ttk::style theme use spectrum
    }
}

namespace eval ::spectrum {
    Theme create theme
}
