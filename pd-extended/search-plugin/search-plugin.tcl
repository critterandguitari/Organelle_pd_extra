# browse docs or search all the documentation using a regexp
# check the Help menu for the Browser item to use it

# todo: cancel button
# todo: make libdir listing check for duplicates
# todo: hook into the dialog_bindings
# TODO remove the doc_ prefix on procs where its not needed
# TODO enter and up/down/left/right arrow key bindings for nav

package require Tk 8.5
package require pd_bindings
package require pd_menucommands

namespace eval ::dialog_helpbrowser2:: {

    variable doctypes "*.{pd,pat,mxb,mxt,help,txt,htm,html,pdf}"

    variable searchfont [list {DejaVu Sans}]
    variable searchtext {}
    variable formatted_searchtext {}
    variable search_history {}
    variable count {}
    # $i controls the search_and_update loop
    variable i
    variable filelist {}
    variable progress {}
    variable navbar {}
    variable genres
    variable cancelled
}

################## help browser and support functions #########################
proc ::dialog_helpbrowser2::open_helpbrowser {mytoplevel} {
    if {[winfo exists $mytoplevel]} {
        wm deiconify $mytoplevel
        raise $mytoplevel
    } else {
        create_dialog $mytoplevel
    }
}

proc ::dialog_helpbrowser2::create_dialog {mytoplevel} {
    variable searchfont
    variable selected_file
    variable genres [list [_ "All documents"] \
                        [_ "Object Help Patches"] \
                        [_ "All About Pd"] \
                        [_ "Tutorials"] \
                        [_ "Manual"] \
                        [_ "Uncategorized"] \
    ]
    variable count
    foreach genre $genres {
	lappend count 0
    }
    toplevel $mytoplevel -class DialogWindow
    wm title $mytoplevel [_ "Search and Browse Documentation"]
    wm geometry $mytoplevel 670x550+0+30
    wm minsize $mytoplevel 230 360
    # tweak: get rid of arrow so the combobox looks like a simple entry widget
    ttk::style configure Entry.TCombobox -arrowsize 0
    ttk::style configure Genre.TCombobox
    ttk::style configure Search.TButton -font menufont
    ttk::style configure Search.TCheckbutton -font menufont
    # widgets
    # for some reason ttk widgets didn't inherit menufont, and this causes tiny
    # fonts on Windows-- so let's hack!
    foreach widget {f.genrebox advancedlabel } {
        option add *[string trim "$mytoplevel.$widget" .]*font menufont
    }
    foreach combobox {searchtextentry f.genrebox} {
	option add *[string trim "$mytoplevel.$combobox" .]*Listbox.font menufont
    }
    ttk::frame $mytoplevel.f -padding 3
    ttk::combobox $mytoplevel.f.searchtextentry -textvar ::dialog_helpbrowser2::searchtext \
	-font "$searchfont 12" -style "Entry.TCombobox" -cursor "xterm"
    ttk::button $mytoplevel.f.searchbutton -text [_ "Search"] -takefocus 0 \
	-command ::dialog_helpbrowser2::search -style Search.TButton
    ttk::combobox $mytoplevel.f.genrebox -values $genres -state readonly \
	-style "Genre.TCombobox"
    $mytoplevel.f.genrebox current 0
    ttk::checkbutton $mytoplevel.f.matchall_check -text [_ "Match all terms"] \
	-variable ::dialog_helpbrowser2::matchall -style Search.TCheckbutton
    ttk::checkbutton $mytoplevel.f.matchwords_check -text [_ "Match whole words"] \
	-variable ::dialog_helpbrowser2::matchwords -style Search.TCheckbutton
    ttk::label $mytoplevel.f.advancedlabel -text [_ "Help"] -foreground "#0000ff" \
	-anchor center -style Foo.TLabel
    text $mytoplevel.navtext -font "$searchfont 12" -height 1 -bd 0 -highlightthickness 0\
	-padx 8 -pady 3 -bg white -fg black
    text $mytoplevel.resultstext -yscrollcommand "$mytoplevel.yscrollbar set" \
        -bg white -highlightcolor blue -height 30 -wrap word -state disabled \
	-padx 8 -pady 3 -spacing3 2 -bd 0 -highlightthickness 0 -fg black
    ttk::scrollbar $mytoplevel.yscrollbar -command "$mytoplevel.resultstext yview" \
        -takefocus 0
    ttk::label $mytoplevel.statusbar -text [_ "Pure Data Search"] -justify left \
        -padding {4 4 4 4}

    grid $mytoplevel.f.searchtextentry -column 0 -columnspan 3 -row 0 -padx 3 \
        -pady 2 -sticky ew
    grid $mytoplevel.f.searchbutton -column 3 -columnspan 2 -row 0 -padx 3 \
        -sticky ew
    grid $mytoplevel.f.genrebox -column 0 -row 1 -padx 3 -sticky w
    grid $mytoplevel.f.matchall_check -column 1 -row 1 -padx 3 -sticky w
    grid $mytoplevel.f.matchwords_check -column 2 -row 1 -padx 3 -sticky w
    grid $mytoplevel.f.advancedlabel -column 3 -columnspan 2 -row 1 -sticky ew
    grid $mytoplevel.f -column 0 -columnspan 5 -row 0 -sticky ew
    grid $mytoplevel.navtext -column 0 -columnspan 5 -row 2 -sticky nsew
    grid $mytoplevel.resultstext -column 0 -columnspan 4 -row 3 -sticky nsew -ipady 0 -pady 0
    grid $mytoplevel.yscrollbar -column 4 -row 3 -sticky nsew
    grid $mytoplevel.statusbar -column 0 -columnspan 4 -row 4 -sticky nsew
    grid columnconfigure $mytoplevel.f 0 -weight 0
    grid columnconfigure $mytoplevel.f 1 -weight 0
    grid columnconfigure $mytoplevel.f 2 -weight 1
    grid columnconfigure $mytoplevel.f 3 -weight 0
    grid columnconfigure $mytoplevel 0 -weight 1
    grid columnconfigure $mytoplevel 4 -weight 0
    grid rowconfigure    $mytoplevel 2 -weight 0
    grid rowconfigure    $mytoplevel 3 -weight 1
    # tags
    $mytoplevel.resultstext tag configure hide -elide on
    $mytoplevel.navtext tag configure is_libdir -elide on
    $mytoplevel.resultstext tag configure is_libdir -elide on
    $mytoplevel.resultstext tag configure title -foreground "#0000ff" -underline on \
	-font "$searchfont 12" -spacing1 6
    $mytoplevel.resultstext tag configure dir_title -font "$searchfont 12" \
	-underline on -spacing1 6
    $mytoplevel.resultstext tag configure filename -elide on
    $mytoplevel.navtext tag configure filename -elide on
    $mytoplevel.resultstext tag configure metakey -font "$searchfont 10"
    $mytoplevel.resultstext tag configure metavalue_h -elide on
    $mytoplevel.resultstext tag configure basedir -elide on
    $mytoplevel.navtext tag configure basedir -elide on
    $mytoplevel.resultstext tag configure description -font "$searchfont 12"
    $mytoplevel.resultstext tag configure homepage_title -font "$searchfont 12" \
	-underline on -spacing1 10 -spacing3 5
    $mytoplevel.navtext tag configure homepage_title -underline on
    $mytoplevel.resultstext tag configure homepage_description -font "$searchfont 12" \
	-spacing3 7
    $mytoplevel.resultstext tag configure intro_libdirs -font "$searchfont 12"
    # make tags for both the results and the nav text widgets
    foreach textwidget [list "$mytoplevel.resultstext" "$mytoplevel.navtext"] {
        $textwidget tag configure link -foreground "#0000ff"
        $textwidget tag bind link <Enter> "$textwidget configure \
            -cursor hand2"
        $textwidget tag bind link <Leave> "$textwidget configure \
            -cursor xterm; $mytoplevel.statusbar configure -text \"\""
        $textwidget tag bind intro <Button-1> "::dialog_helpbrowser2::intro \
	    $mytoplevel.resultstext"
        $textwidget tag bind intro <Enter> "$mytoplevel.statusbar \
	    configure -text \"Go back to the main help page\""
        $textwidget tag bind intro <Leave> "$mytoplevel.statusbar \
	    configure -text \"\""
        $textwidget tag bind libdirs <Button-1> "::dialog_helpbrowser2::build_libdirs \
	    $mytoplevel.resultstext"
        $textwidget tag bind libdirs <Enter> "$mytoplevel.statusbar configure \
	    -text \"Browse all external libraries that have the libdir format\""
        $textwidget tag bind libdirs <Leave> "$mytoplevel.statusbar configure \
	    -text \"\""
    }
    # hack to force new <Enter> events for tags and links next to each other
    for {set i 0} {$i<30} {incr i} {
	$mytoplevel.resultstext tag bind "metavalue$i" <Button-1> \
	    "::dialog_helpbrowser2::grab_metavalue %x %y $mytoplevel 1"
        $mytoplevel.resultstext tag bind "metavalue$i" <Enter> \
	    "::dialog_helpbrowser2::grab_metavalue %x %y $mytoplevel 0"
	$mytoplevel.resultstext tag bind "intro_link$i" <Enter> \
	    "::dialog_helpbrowser2::open_file %x %y $mytoplevel resultstext dir 0"
	$mytoplevel.resultstext tag bind "intro_link$i" <Leave> \
	    "$mytoplevel.statusbar configure -text \"\""
	$mytoplevel.resultstext tag configure "metavalue$i" -font \
	    "$searchfont 12"
	$mytoplevel.resultstext tag configure "intro_link$i" -font \
	    "$searchfont 12"
	$mytoplevel.resultstext tag bind "dir_title$i" <Enter> \
	    "::dialog_helpbrowser2::open_file %x %y $mytoplevel resultstext dir 0"
	$mytoplevel.resultstext tag bind "dir_title$i" <Leave> \
	    "$mytoplevel.resultstext configure -cursor xterm; \
	    $mytoplevel.statusbar configure -text \"\""
        $mytoplevel.resultstext tag configure "dir_title$i" \
	    -font "$searchfont 12" -underline on -spacing1 6
    }
    # this next tag configure comes after the metavalue stuff above so
    # that it has a higher priority (these are the keywords in the search
    # results)
    $mytoplevel.resultstext tag configure keywords -font "$searchfont 10"
    $mytoplevel.resultstext tag configure homepage_file -font "$searchfont 12"
    $mytoplevel.resultstext tag bind homepage_file <Button-1> "::dialog_helpbrowser2::open_file \
	%x %y $mytoplevel resultstext file 1"
    $mytoplevel.resultstext tag bind homepage_file <Enter> "::dialog_helpbrowser2::open_file \
	%x %y $mytoplevel resultstext file 0"
    $mytoplevel.resultstext tag bind homepage_file <Leave> "$mytoplevel.statusbar configure \
	-text \"\""
    $mytoplevel.resultstext tag bind title <Button-1> "::dialog_helpbrowser2::open_file %x %y \
	$mytoplevel resultstext file 1"
    $mytoplevel.resultstext tag bind title <Enter> "::dialog_helpbrowser2::open_file %x %y \
        $mytoplevel resultstext file 0"
    $mytoplevel.resultstext tag bind dir_title <Enter> "::dialog_helpbrowser2::open_file %x %y \
	$mytoplevel resultstext dir 0"
    $mytoplevel.resultstext tag bind dir_title <Leave> "$mytoplevel.resultstext configure \
	-cursor xterm; $mytoplevel.statusbar configure -text \"\""
    $mytoplevel.resultstext tag bind help_icon <Button-1> "::dialog_helpbrowser2::get_info %x %y \
	$mytoplevel"
    $mytoplevel.resultstext tag bind help_icon <Enter> "$mytoplevel.resultstext configure \
	-cursor hand2; $mytoplevel.statusbar configure -text \"Get info on this object's\
	libdir\""
    $mytoplevel.resultstext tag bind help_icon <Leave> "$mytoplevel.resultstext configure \
	-cursor xterm; $mytoplevel.statusbar configure -text \"\""
    $mytoplevel.resultstext tag bind folder_icon <Button-1> "::dialog_helpbrowser2::open_file %x %y \
	$mytoplevel resultstext dir_in_fm 1"
    $mytoplevel.resultstext tag bind folder_icon <Enter> "::dialog_helpbrowser2::open_file %x %y \
	$mytoplevel resultstext dir_in_fm 0"
    $mytoplevel.resultstext tag bind folder_icon <Leave> "$mytoplevel.resultstext configure \
	-cursor xterm; $mytoplevel.statusbar configure -text \"\""
    foreach textwidget [list "$mytoplevel.resultstext" "$mytoplevel.navtext"] {
        $textwidget tag bind clickable_dir <Button-1> "::dialog_helpbrowser2::click_dir \
	    $textwidget %x %y"
    }
    # another workaround: we can't just do a mouseover statusbar update with clickable_dir 
    # since it wouldn't register an <Enter> event when moving the mouse from one dir to an 
    # adjacent dir. So we have the intro_link$i hack above PLUS a separate binding for navbar 
    # links (which are not adjacent)
    $mytoplevel.navtext tag bind navbar_dir <Enter> "::dialog_helpbrowser2::open_file %x %y \
	$mytoplevel navtext dir 0"
    $mytoplevel.navtext tag bind navbar_dir <Leave> "$mytoplevel.statusbar configure \
	-text \"\""

    # search window widget bindings
    bind $mytoplevel <$::modifier-equal> "::dialog_helpbrowser2::font_size $mytoplevel.resultstext 1"
    bind $mytoplevel <$::modifier-plus> "::dialog_helpbrowser2::font_size $mytoplevel.resultstext 1"
    bind $mytoplevel <$::modifier-minus> "::dialog_helpbrowser2::font_size $mytoplevel.resultstext 0"
    bind $mytoplevel.f.searchtextentry <Return> "$mytoplevel.f.searchbutton invoke"
    bind $mytoplevel.f.searchtextentry <$::modifier-Key-BackSpace> \
	"::dialog_helpbrowser2::ctrl_bksp $mytoplevel.f.searchtextentry"
    bind $mytoplevel.f.searchtextentry <$::modifier-Key-a> \
        "$mytoplevel.f.searchtextentry selection range 0 end; break"
    bind $mytoplevel.f.genrebox <<ComboboxSelected>> "::dialog_helpbrowser2::filter_results \
	$mytoplevel.f.genrebox $mytoplevel.resultstext"
    bind $mytoplevel.f.matchall_check <Return> "$mytoplevel.f.searchbutton invoke"
    bind $mytoplevel.f.matchwords_check <Return> "$mytoplevel.f.searchbutton invoke"
    set advancedlabeltext [_ "Advanced search options"]
    bind $mytoplevel.f.advancedlabel <Enter> "$mytoplevel.f.advancedlabel configure \
	-cursor hand2; $mytoplevel.statusbar configure -text \"$advancedlabeltext\""
    bind $mytoplevel.f.advancedlabel <Leave> "$mytoplevel.f.advancedlabel configure \
	-cursor xterm; $mytoplevel.statusbar configure -text \"\""
    bind $mytoplevel.f.advancedlabel <Button-1> \
	{menu_doc_open doc/5.reference all_about_finding_objects.pd}
#   Right now we're suppressing dialog bindings because helpbrowser namespace
#   doesn't work unless all procs are prefixed with dialog_
    ::pd_bindings::dialog_bindings $mytoplevel "helpbrowser2"
#    bind $mytoplevel <KeyPress-Escape> "helpbrowser2::cancel $mytoplevel"
#    bind $mytoplevel <KeyPress-Return> "helpbrowser2::ok $mytoplevel"
#    bind $mytoplevel <$::modifier-Key-w> "helpbrowser2::cancel $mytoplevel"
    # these aren't supported in the dialog, so alert the user, then break so
    # that no other key bindings are run
    bind $mytoplevel <$::modifier-Key-s>       {bell; break}
    bind $mytoplevel <$::modifier-Shift-Key-S> {bell; break}
    bind $mytoplevel <$::modifier-Key-p>       {bell; break}

    bind $mytoplevel <$::modifier-Key-f> "break"

    # Add state and set focus
    $mytoplevel.f.searchtextentry insert 0 [_ "Enter search terms"]
    $mytoplevel.f.searchtextentry selection range 0 end
    # go ahead and set tags for the default genre
    filter_results $mytoplevel.f.genrebox $mytoplevel.resultstext
    focus $mytoplevel.f.searchtextentry
    ::dialog_helpbrowser2::intro $mytoplevel.resultstext
    set ::dialog_helpbrowser2::matchall 1
    set ::dialog_helpbrowser2::matchwords 1
}

# find_doc_files
# basedir - the directory to start looking in
proc ::dialog_helpbrowser2::find_doc_files { basedir recursive } {
    # Fix the directory name, this ensures the directory name is in the
    # native format for the platform and contains a final directory seperator
    set basedir [string trimright [file join $basedir { }]]
    set fileList {}

    # Look in the current directory for matching files, -type {f r}
    # means only readable normal files are looked at, -nocomplain stops
    # an error being thrown if the returned list is empty
    foreach fileName [glob -nocomplain -type {f r} -path $basedir $helpbrowser::doctypes] {
        lappend fileList $fileName
    }

    # If a recursive search is specified the look in
    # subdirectories for more files.  This is used for search
    # results and is filtered to make sure we don't list results twice
    # if one of our basedirs happens to be a subdirectory of something
    # in the search patch (i.e., this wouldn't be appropriate for building
    # a file browser
    if {$recursive} {
        foreach dirName [glob -nocomplain -type {d  r} -path $basedir *] {
            # Recusively call the routine on the sub directory
	    # (if it's not already in Pd's search path) and
	    # append any new files to the results
	    set nomatch [lsearch [concat [file join $::sys_libdir doc] \
		$::sys_searchpath $::sys_staticpath] $dirName]
	    if { $nomatch eq "-1" } {
                set subDirList [find_doc_files $dirName 1]
                if { [llength $subDirList] > 0 } {
                    foreach subDirFile $subDirList {
                        lappend fileList $subDirFile
                    }
                }
	    }
	}
    }
    return $fileList
}

proc ::dialog_helpbrowser2::open_file { xpos ypos mytoplevel text type clicked } {
    set textwidget [join [list $mytoplevel $text] .]
    set i [$textwidget index @$xpos,$ypos]
    set range [$textwidget tag nextrange filename $i]
    set filename [eval $textwidget get $range]
    set range [$textwidget tag nextrange basedir $i]
    set basedir [file normalize [eval $textwidget get $range]]
    if {$clicked eq "1"} {
	if {$type eq "file"} {
            menu_doc_open $basedir $filename
	} else {
	    menu_doc_open [file dirname [file join $basedir $filename]] {}
	}
    } else {
	$mytoplevel.resultstext configure -cursor hand2
	if {$type eq "file"} {
            $mytoplevel.statusbar configure -text \
	        [format [_ "Open %s"] [file join $basedir $filename]]
	} else {
	    set msg ""
	    if {$type eq "dir_in_fm"} {set msg {in external file browser: }}
	    $mytoplevel.statusbar configure -text [format [_ "Browse %s%s"] \
		$msg [file dirname [file join $basedir $filename]]]
	}
    }
}

# only does keywords for now-- maybe expand this to handle any meta tags
proc ::dialog_helpbrowser2::grab_metavalue { xpos ypos mytoplevel clicked } {
    set textwidget "$mytoplevel.resultstext"
    set i [$textwidget index @$xpos,$ypos]
    set range [$textwidget tag nextrange metavalue_h $i]
    set value [eval $textwidget get $range]
    set range [$textwidget tag prevrange metakey $i]
    set key [eval $textwidget get $range]
    regsub ":.*" $key {} key
    set key [string tolower $key]
    append text $key {[^;]*} $value {.*?;}
    if {$clicked eq "1"} {
        ::dialog_helpbrowser2::searchfor $text
    } else {
        $mytoplevel.statusbar configure -text [format [_ "Search for pattern: %s"] $text]
    }
}

proc ::dialog_helpbrowser2::searchfor {text} {
    set ::dialog_helpbrowser2::searchtext ""
    set ::dialog_helpbrowser2::searchtext $text
    ::dialog_helpbrowser2::search
}


# show/hide results based on genre
proc ::dialog_helpbrowser2::filter_results { combobox text } {
    variable genres
    # hack to add the navbar text widget
    foreach text [list "$text" .helpbrowser2.navtext] {
    set elide {}
    if { [$combobox current] eq "0" } {
    	foreach genre $genres {
    	    $text tag configure [join $genre "_"] -elide off
    	    set tag [join $genre "_"]
    	    append tag "_count"
    	    $text tag configure $tag -elide on
	}
	set tag [join [lindex $genres 0] "_"]
	append tag "_count"
	$text tag configure $tag -elide off
    } else {
    	foreach genre $genres {
    	    if { [$combobox get] ne $genre } {
    		$text tag configure [join $genre "_"] -elide on
    		set tag [join $genre "_"]
    		append tag "_count"
    		$text tag configure $tag -elide on
    	    } else {
    		$text tag configure [join $genre "_"] -elide off
    		set tag [join $genre "_"]
    		append tag "_count"
    		$text tag configure $tag -elide off
    	    }
    	}
    }
    }
    $combobox selection clear
    focus $text
}

proc ::dialog_helpbrowser2::readfile {filename} {
    set fp [open $filename]
    set file_contents [split [read $fp] \n]
    close $fp
    return $file_contents
}

# Here we're printing a pretty error message and
# explaining why it occurred for the user, plus
# giving a link to the tcl docs in case the
# user is trying to build a complex regex and
# needs guidance outside the scope of the help
# patch. Esp. since I knowingly ignored tcl's
# "quoting hell" and just convert lists to
# strings, I figure I owe the user a polite
# explanation if they run into trouble
proc ::dialog_helpbrowser2::error { fid error_type } {
    set widget .helpbrowser2.resultstext
    $widget configure -state normal
    $widget delete 0.0 end
    print_navbar $widget
    $widget insert end [_ "Error"] homepage_title
    $widget insert end "\n"
    $widget insert end [_ "The\
        Pd Search Tool can't use the search\
        term you entered. The tcl interpreter gave\
        the following error:"] description
    $widget insert end "\n\n$fid\n\n" description
    if { $error_type eq "badlist" } {
        $widget insert end [_ "The search\
            term you enter must be formatted as a proper\
            tcl list. This usually isn't an issue unless\
            you use some special characters like brackets\
            or unmatched quotes in your search. For more\
            info on tcl lists, see:"] description
        $widget insert end "\n\n" description
        $widget insert end \
        "http://www.tcl.tk/man/tcl/tutorial/Tcl14.html" description
    } elseif { $error_type eq "badregex" } {
        $widget insert end [_ "The search\
	    term you enter must have the proper syntax for a\
	    regular expression in Tcl. This usually isn't an\
	    issue unless you use special characters to create\
	    a complex regular expression. For more info on\
	    regular expressions in Tcl, see:"] description
	$widget insert end "\n\n" description
	$widget insert end \
	"http://www.tcl.tk/man/tcl8.5/TclCmd/re_syntax.htm"
    }
    $widget configure -state disabled
}

proc ::dialog_helpbrowser2::search { } {
    variable searchtext
    variable search_history
    variable progress
    variable navbar
    # Catch search text that isn't a proper list or
    # will break a regex before they cause any trouble
    if {[catch {llength $searchtext} fid]} {
        ::dialog_helpbrowser2::error $fid "badlist"
	return
    } elseif {[catch {regexp $searchtext "foo"} fid]} {
        ::dialog_helpbrowser2::error $fid "badregex"
	return
    }
    if {$searchtext eq ""} return
    if { [lsearch $search_history $searchtext] eq "-1" } {
    	lappend search_history $searchtext
    	.helpbrowser2.f.searchtextentry configure -values $search_history
    }
    .helpbrowser2.f.searchtextentry selection clear
    .helpbrowser2.f.searchtextentry configure -foreground gray -background gray90
    .helpbrowser2.resultstext configure -state normal
    .helpbrowser2.navtext configure -state normal
    .helpbrowser2.resultstext delete 0.0 end
    .helpbrowser2.navtext delete 0.0 end
    set widget .helpbrowser2.navtext
    set navbar {}
    print_navbar $widget
    $widget configure -state normal
    $widget insert 1.end "    "
    ttk::progressbar $widget.pbar -variable ::dialog_helpbrowser2::progress \
	-mode determinate
    $widget window create 1.end -window $widget.pbar
    $widget configure -state disabled
    ::dialog_helpbrowser2::do_search
    # todo: re-read http://wiki.tcl.tk/1526
    # after idle [list after 10 ::dialog_helpbrowser2::do_search]
}

proc ::dialog_helpbrowser2::do_search { } {
    variable searchtext
    variable formatted_searchtext
    variable count {}
    variable progress 0
    variable genres
    variable filelist {}
    variable i 0
    variable cancelled 0
    foreach genre $genres {
    	lappend count 0
    }

    # Get rid of pesky leading/trailing spaces...
    set formatted_searchtext [string trim $searchtext]
    # ...and double spaces between terms
    regsub -all {\s+} $formatted_searchtext { } formatted_searchtext
    set dirs [concat [file join $::sys_libdir doc] $::sys_searchpath $::sys_staticpath]
    foreach basedir $dirs {
        # Fix the directory name, this ensures the directory name is in the
        # native format for the platform and contains a final directory seperator
        set basedir [file normalize $basedir]
        foreach docfile [find_doc_files $basedir 1] {
	    set docname [string replace $docfile 0 [string length $basedir]]
	    lappend filelist [list "$docname" "$docfile" "$basedir"]
        }
    }
    set filelist [searchfile_sort $filelist]
    ::dialog_helpbrowser2::search_and_update
}

proc ::dialog_helpbrowser2::results_epilog {widget} { 
    variable genres
    variable count
    variable filelist
    .helpbrowser2.f.searchtextentry configure -foreground black -background white
    $widget configure -state normal
    $widget delete {1.0 lineend -1 chars} 1.end
    $widget insert 1.end [_ "Found "] "navbar"
    set i 0
    foreach genre $genres {
                set tag [join $genre "_"]
                append tag "_count"
                $widget insert 1.end [lindex $count $i] "$tag navbar"
                incr i
    }
    $widget insert 1.end " " "navbar"
    $widget insert 1.end \
        [format [_ "out of %s docs"] [llength $filelist]] "navbar"
    $widget configure -state disabled
    .helpbrowser2.resultstext configure -state disabled
}

# Recursive loop to search all files and keep the gui
# alive every 256 iterations.  This was tested searching
# a little over 9,000 docs and seems to work alright
proc ::dialog_helpbrowser2::search_and_update {} {
    variable formatted_searchtext
    variable filelist
    variable progress
    variable i
    variable cancelled
    if { $i < [llength $filelist]} {
	# get index of docfile docname and basedir
	set docname [lindex $filelist $i 0]
	set docfile [lindex $filelist $i 1]
	set basedir [lindex $filelist $i 2]
        # send it to searchfile
	::dialog_helpbrowser2::searchfile $formatted_searchtext \
	    [readfile $docfile] ".helpbrowser2.resultstext" $docname \
	    $basedir
	incr i
        # I changed '256' below to [llength $filelist]/8 in order
	# to keep the updates to 8 total regardless of the number
	# of files and tcl complained there were too many nested
	# loops. Hm...
        if { $i%256==0 } {
	    # if the user closed the window then quit searching. I'm
	    # using a global variable here in case we want to veer from
	    # the standard dialog behavior and stop a search with ESC
	    # without actually withdrawing the window 
	    if { $cancelled == 0 } {
                # update the progressbar variable and refresh gui
                set progress [expr $i*100.0/[llength $filelist]]
	        after idle ::dialog_helpbrowser2::search_and_update
	    } else {
		::dialog_helpbrowser2::results_epilog ".helpbrowser2.navtext"
	        return
	    }
	} else { ::dialog_helpbrowser2::search_and_update }
    } else {
	# we've gone throught the whole filelist so end the recursion
	set progress 100
	::dialog_helpbrowser2::results_epilog ".helpbrowser2.navtext"
	return
    }
}

# put all the stuff in 5.reference at the top of the results
proc ::dialog_helpbrowser2::searchfile_sort { list } {
    if {$list eq ""} {return}
    foreach triple $list {
        regsub {.*5\.reference[\\\/](.*)} [lindex $triple 0] { \1} key
	lappend list2 [list $key $triple]
    }
    foreach pair [lsort -index 0 -dictionary $list2] {
	lappend list3 [lindex $pair 1]
    }
    return $list3
} 

# put license.txt and readme.txt at the bottom of a directory listing
proc ::dialog_helpbrowser2::directory_sort { list } {
    if {$list eq ""} {return}
    foreach name $list {
        regsub -nocase {(license\.txt|readme\.txt)} $name {~~~\1} key
        lappend list2 [list $key $name]
    }
    foreach pair [lsort -index 0 -dictionary $list2] {
        lappend list3 [lindex $pair 1]
    }
    return $list3
}

proc ::dialog_helpbrowser2::searchfile {searchtext file_contents widget filename basedir} {
    variable count
    variable genres
    set match 0
    set terms_to_match 1
    if { $::dialog_helpbrowser2::matchall == 1 } {
	set terms_to_match [llength $searchtext]
    }
    # let's design our own word boundaries since tildes often end Pure Data words.
    # homemade left boundary isn't necessary, but makes it easy to change later 
    set lb {(?:^|[^[:alnum:]_])}
    set rb {(?![[:alnum:]_~])}
    foreach term $searchtext {
	if {$::dialog_helpbrowser2::matchwords == 1} {
	    set term [join [list $lb $term $rb] ""]
	}
	if {[regexp -nocase -- $term $filename] ||
	    [regexp -nocase -- $term [join $file_contents]]} {
	    incr match
	}
    }
    if { $match >= $terms_to_match } {
        ::dialog_helpbrowser2::printresult $filename $basedir $file_contents $widget 1
    }
}

proc ::dialog_helpbrowser2::printresult {filename basedir file_contents widget mixed_dirs} {
    variable count
    variable genres
    set description ""
    set keywords ""
    set genre ""
    set metadata ""
    set title ""
    if {[regexp -nocase -- ".*-help\.pd" $filename]} {
    	# object help
    	set genre 1
    	regsub -nocase -- "(?:^|(?:5.reference/))(.*)-help.pd" $filename {\1} title
    } elseif {[regexp -nocase -- "all_about_.*\.pd" $filename]} {
	regsub -nocase -- {(?:.*[/\\])?(.*)\.pd} $filename {\1} title
	regsub -all -- "_" $title " " title
	# all about pd
	set genre 2
    } elseif {[regexp -nocase -- "\.html?" $filename]} {
    	set title $filename
    	# Pd Manual (or some html page in the docs)
    	set genre 4
    } else {
    	set title $filename
    }
	if {[regexp -nocase {license\.txt} $filename]} {
	    set description [_ "text of the license for this software"]
	} elseif {[regexp -nocase {readme\.txt} $filename]} {
	    set description [_ "general information from the author"]
	} else {
    	    regexp -nocase -- "#X text \[0-9\]+ \[0-9\]+ description\[:\]? (.*?);.*" $file_contents -> description
    	    regsub -all {[{}\\]} $description {} description
	}
    	regexp -nocase -- "#X text \[0-9\]+ \[0-9\]+ keywords\[:\]? (.*?);.*" $file_contents -> keywords
    	regsub -all {[{}]} $keywords {} keywords
    	if {[regexp -nocase -- "#X text \[0-9\]+ \[0-9\]+ genre tutorial" $file_contents]} {
    	    set genre 3
    	}
    	if { $genre eq "" } {
    	    set genre 5
    	}
    	lset count $genre [expr [lindex $count $genre] + 1]
    	set genre_name [join [lindex $genres $genre] "_"]
    	lset count 0 [expr [lindex $count 0] + 1]    		
    	# print out an entry for the file
    	$widget insert end "$title" "title link $genre_name"
	if {$mixed_dirs} {
	    if { $genre == 1 } {
	        $widget insert end " "
	        $widget image create end -image ::dialog_helpbrowser2::help
	    }
	    $widget insert end " "
	    $widget image create end -image ::dialog_helpbrowser2::folder
	    if { $genre == 1 } {
	        $widget tag add help_icon "end -4indices" "end -3indices"
	        $widget tag add $genre_name "end -5indices" end
	    } else {
	        $widget tag add $genre_name "end -3indices" end
	    }
	    $widget tag add folder_icon "end -2indices" "end -1indices"
	}
	$widget insert end "$basedir" basedir
	$widget insert end "$filename" filename
    	if { $description eq "" } {
    	    set description [_ "No DESCRIPTION tag."]
    	}
    	$widget insert end "\n$description\n" "description $genre_name"
    	if { $keywords ne "" } {
    	    $widget insert end [_ "Keywords:"] "metakey $genre_name"
	    set i 0
    	    foreach value $keywords {
		set metavalue "metavalue$i"
		set i [expr {($i+1)%30}]
    		$widget insert end " " "link $genre_name"
    		$widget insert end $value "$metavalue keywords link $genre_name"
                # have to make an elided copy for use with "nextrange"
                # since I can't just get the tag's index underneath
                # the damn cursor!!!
                $widget insert end $value metavalue_h
    	    }
    	$widget insert end "\n" $genre_name
    	}
}

proc ::dialog_helpbrowser2::ok {mytoplevel} {
    # this is a placeholder for the standard dialog bindings
}

proc ::dialog_helpbrowser2::cancel {mytoplevel} {
    variable cancelled 1
    wm withdraw .helpbrowser2
}


# hack to select all because tk's default bindings apparently
# assume the user is going to want emacs shortcuts
proc ::dialog_helpbrowser2::sa { widget } {
    $widget selection range 0 end
    break
}

proc ::dialog_helpbrowser2::intro { t } {
    variable navbar {}
    .helpbrowser2.navtext configure -state normal
    .helpbrowser2.navtext delete 0.0 end
    .helpbrowser2.navtext insert end [_ "Search"] "navbar homepage_title"
    .helpbrowser2.navtext configure -state disabled
    $t configure -state normal
    $t delete 0.0 end
    $t insert end \
        [_ "Enter terms above. Use the dropdown menu to filter by category."] \
        homepage_description
    $t insert end "\n"
    $t insert end [_ "Browse the Documentation"] homepage_title
    $t insert end "\n"
    $t insert end [_ "The \"doc\" directory"] "link clickable_dir intro_link0"
    $t insert end [file join $::sys_libdir doc] basedir
    $t insert end "0" is_libdir
    $t insert end "\n"
    $t insert end [_ "External Pd libraries"] "link libdirs intro_libdirs"
    $t insert end "\n"
    $t insert end [_ "Browse Introductory Topics"] homepage_title
    $t insert end "\n"
    set intro_docs [list \
                 [_ "Pd Manual"] 1.manual [_ "HTML manual for Pure Data"] \
                 [_ "Control Structure"] 2.control.examples [_ "tutorials for control objects"] \
                 [_ "Audio Signals"] 3.audio.examples [_ "tutorials for audio signals"] \
                ]
    set i 1
    foreach {title dir desc} $intro_docs {
        $t insert end "$title" "link clickable_dir intro_link$i"
        $t insert end [file join $::sys_libdir doc $dir] basedir
        $t insert end "0" is_libdir
        $t insert end "dummy" filename
	$t insert end " $desc\n" description
	set i [expr {($i+1)%30}]
    }
    $t insert end [_ "All About Pd"] "link homepage_file"
    $t insert end [file join $::sys_libdir doc 5.reference] basedir
    $t insert end all_about.pd filename
    $t insert end " " description
    $t insert end \
        [_ "reference patches for key concepts and settings in Pd"] \
        description
    $t insert end "\n"
    $t insert end [_ "Browse Advanced Topics"] homepage_title
    $t insert end "\n"
    set advanced_docs [list \
	[_ "Networking"] [file join manuals 3.Networking] [_ "sending data over networks with Pd"] \
        [_ "Writing Externals"] 6.externs [_ "how to code control and signal objects in C"] \
        [_ "Data Structures"] 4.data.structures [_ "creating graphical objects in Pure Data"] \
	[_ "Dynamic Patching"] [file join manuals pd-msg] [_ "programmatically create/destroy Pd\
	    objects"] \
	[_ "Implementation Details"] [file join manuals Pd] [_ "file format specification, license text,\
	    etc."]
    ]
    set i 0
    foreach {title dir desc} $advanced_docs {
	$t insert end "$title" "link clickable_dir intro_link$i"
	$t insert end [file join $::sys_libdir doc $dir] basedir
	$t insert end "0" is_libdir
	$t insert end "dummy" filename
	$t insert end " $desc\n" description
	set i [expr {($i+1)%30}]
    }
    $t insert end [_ "Search by Category"] homepage_title
    $t insert end "\n"
    $t insert end [_ "Many help documents are categorized using tags. Click\
	a link below to find all documents with that tag."] \
	homepage_description
    $t insert end "\n"

    set keywords [list \
        "abstraction" [_ "abstraction"] [_ "object itself is written in Pure Data"] \
        "abstraction_op" [_ "abstraction_op"] \
	    [_ "object's behavior only makes sense inside an abstraction"] \
        "analysis" [_ "analysis"] [_ "analyze the incoming signal or value"] \
        "anything_op" [_ "anything_op"] [_ "store or manipulate any type of data"] \
        "array" [_ "array"] [_ "create or manipulate an array"] \
        "bandlimited" [_ "bandlimited"] [_ "object describes itself as being bandlimited"] \
        "block_oriented" [_ "block_oriented"] \
            [_ "signal object that performs block-wide operations (as opposed to\
	    repeating the same operation for each sample of the block)"] \
        "canvas_op" [_ "canvas_op"] \
            [_ "object's behavior only makes sense in context of a canvas"] \
        "control" [_ "control"] [_ "control rate objects"] \
        "conversion" [_ "conversion"] [_ "convert from one set of units to another"] \
        "data_structure" [_ "data_structure"] [_ "create or manage data structures"] \
        "dynamic_patching" [_ "dynamic_patching"] \
            [_ "dynamic instantiation/deletion of objects or patches"] \
        "filesystem" [_ "filesystem"] \
            [_ "object that reads from and/or writes to the file system"] \
        "filter" [_ "filter"] [_ "object that filters incoming data"] \
        "GUI" [_ "GUI"] [_ "graphical user interface"] \
        "list_op" [_ "list_op"] [_ "object that manipulates, outputs, or stores a list"] \
        "MIDI" [_ "MIDI"] [_ "object that provides MIDI functionality"] \
        "network" [_ "network"] [_ "provides access to or sends/receives data over a network"] \
        "nonlocal" [_ "nonlocal"] [_ "pass messages or data without patch wires"] \
        "orphan" [_ "orphan"] \
            [_ "help patches that cannot be accessed by right-clicking \"help\" for the corresponding object"] \
        "patchfile_op" [_ "patchfile_op"] \
            [_ "object whose behavior only makes sense in terms of a Pure Data patch"] \
        "pd_op" [_ "pd_op"] \
            [_ "object that can report on or manipulate global data\
	    associated with the running instance of Pd"] \
        "ramp" [_ "ramp"] [_ "create a ramp between a starting and ending value"] \
        "random" [_ "random"] [_ "output a random value, list, signal, or other random data"] \
        "signal" [_ "signal"] [_ "audiorate object (so called \"tilde\" object)"] \
        "soundfile" [_ "soundfile"] \
            [_ "object that can play, manipulate, and/or save a sound file (wav, ogg, flac, mp3, etc.)"] \
        "storage" [_ "storage"] [_ "object whose main function is to store data"] \
        "symbol_op" [_ "symbol_op"] [_ "manipulate or store a symbol"] \
        "time" [_ "time"] [_ "measure and/or manipulate time"] \
        "trigonometry" [_ "trigonometry"] [_ "provide trigonometric functionality"] \
        ]

    set i 0
    foreach {keyword name desc} $keywords {
        $t insert end "keywords" "metakey hide"
        $t insert end $name "metavalue$i link"
        $t insert end $keyword metavalue_h
        $t insert end " $desc\n" description
        set i [expr {($i+1)%30}]
    }
    $t configure -state disabled
}

# hack to get <ctrl-backspace> to delete the word to the left of the cursor
proc ::dialog_helpbrowser2::ctrl_bksp {mytoplevel} {
    set last [$mytoplevel index insert]
    set first $last
    while { $first > 0 } {
	set char [string index [$mytoplevel get] $first-1]
	set prev [string index [$mytoplevel get] $first]
	if { [regexp {[[:punct:][:space:]\|\^\~\`]} $char] &&
	     $first < $last &&
	     [regexp {[^[:punct:][:space:]\|\^\~\`]} $prev] ||
	     [$mytoplevel selection present] } { break }
	incr first -1
    }
    incr first
    $mytoplevel delete $first $last
}

proc ::dialog_helpbrowser2::font_size {text direction} {
    variable searchfont
    set offset {}
    set min_fontsize 8
    if {$direction == 1} {
	set offset 2
    } else {
	set offset -2
    }
    set update 1
    foreach tag [$text tag names] {
	set val [$text tag cget $tag -font]
	if {[string is digit -strict [lindex $val 1]] &&
	    [expr {[lindex $val 1]+$offset}] < $min_fontsize} {
		set update 0
	    }
    }
    if {$update} {
        foreach tag [$text tag names] {
	    set val [$text tag cget $tag -font]
	    if {[string is digit -strict [lindex $val 1]]} {
	        $text tag configure $tag -font "$searchfont \
		    [expr {max([lindex $val 1]+$offset,$min_fontsize)}]"
	    }
        }
    }
}

proc ::dialog_helpbrowser2::build_libdirs {textwidget} {
    set libdirs {} 
    foreach pathdir [concat $::sys_searchpath $::sys_staticpath] {
        if { ! [file isdirectory $pathdir]} {continue}
	# Fix the directory name, this ensures the directory name is in the 
	# native format for the platform and contains a final directory separator
	set dir [string trimright [file join [file normalize $pathdir] { }]]
	# find the libdirs
	foreach filename [glob -nocomplain -type d -path $dir "*"] {
	    # use [file tail $filename] to get the name of libdir
	    set dirname [file tail $filename]
	    set norm_filename [string trimright [file join [file normalize $filename] { }]]
	    if {[glob -nocomplain -type f -path $norm_filename "$dirname-meta.pd"] ne ""} {
		lappend libdirs [list "$norm_filename" "$dirname"]
	    }
	}
    }
    ::dialog_helpbrowser2::print_libdirs $textwidget $libdirs
}

proc ::dialog_helpbrowser2::print_libdirs {textwidget libdirs} {
    variable navbar
    $textwidget configure -state normal
    $textwidget delete 0.0 end
    set navbar [list [list [_ "External libraries"] "link libdirs navbar" {}]]
    print_navbar $textwidget
    # now clear out the navbar and then add "externals (flag) to it..."
    set i 0
    foreach libdir [lsort $libdirs] {
	set i [expr {($i+1)%30}]
	set description {}
	set author {}
	$textwidget insert end "[lindex $libdir 1]" "link clickable_dir dir_title$i"
	$textwidget insert end " "
        $textwidget image create end -image ::dialog_helpbrowser2::folder
	$textwidget tag add folder_icon "end -2indices" "end -1indices"
	$textwidget insert end "[lindex $libdir 0]" basedir
	$textwidget insert end "dummy" filename
	$textwidget insert end "1" is_libdir
	$textwidget insert end "\n"
	set file_contents [readfile [format %s%s [join $libdir ""] "-meta.pd"]]
	regexp -nocase -- "#X text \[0-9\]+ \[0-9\]+ description\[:\]? (.*?);.*" [join $file_contents] -> description
	if {$description ne {}} {
	    regsub -all { \\,} $description {,} description
	    $textwidget insert end "$description\n" description
	} else {
	    $textwidget insert end [_ "no DESCRIPTION tag or values."] description
            $textwidget insert end "\n"
	}
	foreach tag {Author License Version} {
	    if {[regexp -nocase -- "#X text \[0-9\]+ \[0-9\]+ $tag (.*?);.*" [join $file_contents] -> values]} {
	        $textwidget insert end [format "%s: " $tag] metakey
		if {$values ne {}} {
	            regsub -all { \\,} $values {,} values 
	            $textwidget insert end "$values" metakey
	        } else {
	            $textwidget insert end "no [string toupper $tag] tag or values." metakey
		}
	    $textwidget insert end "\n"
	    }
        }
    }
    $textwidget configure -state disabled
}

proc ::dialog_helpbrowser2::click_dir {textwidget xpos ypos} {
    set i [$textwidget index @$xpos,$ypos]
    set range [$textwidget tag nextrange basedir $i]
    set dir [eval $textwidget get $range]
    set range [$textwidget tag nextrange is_libdir $i]
    set is_libdir [eval $textwidget get $range]
    build_subdir .helpbrowser2.resultstext $dir $is_libdir
}

proc ::dialog_helpbrowser2::build_subdir {textwidget dir is_libdir} {
    variable navbar
    if {[lsearch -exact [join $navbar] $dir] == -1} {
    lappend navbar [list "$dir" "link clickable_dir navbar navbar_dir" "subdir"]
    } else {
        set newnav {}
	foreach {entry} $navbar {
	    lappend newnav $entry
	    if {[lindex $entry 0] eq $dir} {break}
	}
        set navbar $newnav
    }
    $textwidget configure -state normal
    $textwidget delete 0.0 end
    print_navbar .helpbrowser2.navtext
    # get any subdirs first
    set i 0
    foreach subdir [lsort -dictionary [glob -nocomplain -type d -directory $dir "*"]] {
        # get name of subdir
        set subdirname [file tail $subdir]
	$textwidget insert end "$subdirname" "link clickable_dir dir_title$i"
        set norm_subdir [string trimright [file join [file normalize $subdir] { }]]
	$textwidget insert end "0" is_libdir
        $textwidget insert end " "
        $textwidget image create end -image ::dialog_helpbrowser2::folder
	$textwidget tag add folder_icon "end -2indices" "end -1indices"
        $textwidget insert end "$norm_subdir" basedir
        $textwidget insert end "dummy" filename
	$textwidget insert end "\n"
	set i [expr {($i+1)%30}]
    }
    foreach docfile [directory_sort [find_doc_files [file normalize $dir] 0]] {
        # get name of file
	# if we're in a libdir, filter out pd patches that don't end in -help.pd
	if {[regexp {.*-help\.pd$} $docfile] ||
	    [string replace $docfile 0 [expr [string length $docfile] - 4]] ne ".pd" ||
	    !$is_libdir} {
            set docname [string replace $docfile 0 [string length [file normalize $dir]]]
	    ::dialog_helpbrowser2::printresult $docname $dir [readfile $docfile] $textwidget 0
	    }
    }
    $textwidget configure -state disabled
}

# fix this-- maybe print_navbar shouldn't need an argument
proc ::dialog_helpbrowser2::print_navbar {foo} {
    variable navbar
    set separator /
    set text .helpbrowser2.navtext
    $text configure -state normal
    $text delet 1.0 end
    $text insert 1.0 [_ "Home"] "link intro navbar"
    if {[llength $navbar] == 0} {
	$text configure -state disabled
	return
    }
    for {set i 0} {$i<[expr {[llength $navbar]-1}]} {incr i} {
        $text insert 1.end " $separator " navbar
        if {[lindex $navbar $i 2] eq "subdir"} {
	    $text insert 1.end [file tail [lindex $navbar $i 0]] \
		[lindex $navbar $i 1]
	    $text insert 1.end [lindex $navbar $i 0] basedir
	    $text insert 1.end dummy filename
	    $text insert 1.end "0" is_libdir
	} else {
	    $text insert 1.end [lindex $navbar $i 0] [lindex $navbar $i 1]
	}
    }
    if {[lindex $navbar end 2] eq "subdir"} {
        $text insert 1.end " $separator " navbar
	$text insert 1.end [file tail [lindex $navbar end 0]]
    } else {
	$text insert 1.end " $separator " navbar
        $text insert 1.end [lindex $navbar end 0]
    }
    $text configure -state disabled
}

proc ::dialog_helpbrowser2::get_info {xpos ypos mytoplevel} {
    set textwidget "$mytoplevel.resultstext"
    set i [$textwidget index @$xpos,$ypos]
    set range [$textwidget tag nextrange filename $i]
    set filename [eval $textwidget get $range]
    set range [$textwidget tag nextrange basedir $i]
    set basedir [file normalize [eval $textwidget get $range]]
    set match 0
    set fulldir [file dirname [file join $basedir $filename]]
    set meta [format "%s-meta.pd" [file tail $fulldir]]
    if {[regexp {5.reference} $fulldir]} {
	tk_messageBox -message {Internal Object} \
	    -detail [_ "This help patch is for an internal Pd class"] \
	    -parent $mytoplevel -title [_ "Search"]
	set match 1
    } else {
	# check for a readme file (use libname-meta.pd as a last resort)
	foreach docname [list Readme.txt README.txt readme.txt README $meta] {
	    if {[file exists [file join $fulldir $docname]]} {
		menu_doc_open $fulldir $docname
		set match 1
		break
	    }
	}
    }
    if {!$match} {
	tk_messageBox -message \
	    [_ "Sorry, can't find a README file for this object's library."] \
	    -title [_ "Search"]
    }    	
}

# create the menu item on load
 set mymenu .menubar.help
 # this can be buggy with translated text
 #set inserthere [$mymenu index [_ "Report a bug"]]
if {$::windowingsystem eq "aqua"} {
    set inserthere 3    
} else {
    set inserthere 4
}
 $mymenu insert $inserthere separator
 $mymenu insert $inserthere command -label [_ "Search"] \
    -command {::dialog_helpbrowser2::open_helpbrowser .helpbrowser2}
 bind all <$::modifier-Key-h> \
     {::dialog_helpbrowser2::open_helpbrowser .helpbrowser2}

# Folder icon "folder16"
# from kde klassic icons (license says GPL/LGPL)

image create photo ::dialog_helpbrowser2::folder -data {
   R0lGODlhEAAQAIMAAPwCBNSeBJxmBPz+nMzOZPz+zPzSBPz2nPzqnAAAAAAA
   AAAAAAAAAAAAAAAAAAAAACH5BAEAAAAALAAAAAAQABAAAARFEMhJ6wwYC3uH
   98FmBURpElkmBUXrvsVgbOxw3F8+A+zt/7ddDwgUFohFWgGB9BmZzcMTASUK
   DdisNisSeL9gMGdMJvsjACH+aENyZWF0ZWQgYnkgQk1QVG9HSUYgUHJvIHZl
   cnNpb24gMi41DQqpIERldmVsQ29yIDE5OTcsMTk5OC4gQWxsIHJpZ2h0cyBy
   ZXNlcnZlZC4NCmh0dHA6Ly93d3cuZGV2ZWxjb3IuY29tADs=
}

# Info icon "acthelp16"
# from kde slick icons (license says GPL/LGPL)

image create photo ::dialog_helpbrowser2::help -data {
   R0lGODlhEAAQAIYAAPwCBCSK7ASO9Bye9GTG/ITO/JzW/HTC/FS6/Bya/ARe
   3FS+/Jzi/LTm/Mzu/LTi/KTa/HzC/GSy/AR+/AQudGy+/MTq/Nzy/OT2/Lzm
   /KTi/ITK/Hy+/Fym/CSG/ARSzAQmZCyW9OTy/Pz+/Oz2/Dye/BR2/ARm/AQ2
   pPT+/Oz6/NTy/ESe/BR+/ARO3AQ+tAQWVAyW/HzK/NT2/DyW/ARa9ARC5AQ2
   rAQmhAyi/HzO/Jze/DSK/ARO7ARCzASa7HzS/HzG/ITG/CR2/AQ+zAQupAR6
   tDyu/Eyy/AQ+1AQaZASG/Fy2/CSe/ARC3AQytAQqlAQONBSO/Hyi3DRmzARm
   rARq5ARS3ARS5ARGzAQ2tAQmjARCpAQ6rAQ6tAQebAQaXAQqfAQqhAAAAAAA
   AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
   AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACH5BAEAAAAA
   LAAAAAAQABAAAAfFgACCgwABAoSIggMEBQYHCAkKiQALDA0ODxAREhMUiBUW
   FxgZGhscHR4fIIMhDyIjJA4jIyUhJicogwQPKSojK7MsLScuLzAAMTIzDiIr
   DgYcNCY1Njc4ADk6Fjs7DbMjPCc9PtYAPwgWBEBBQrND1ERF10ZHMghHSCyz
   4klFRUqCljBp0sSDh1k9nDx5AiXKIAFSJkz5NoLKExzHBlWxcuIKlixJtDzZ
   osQhIRAUuHTxgqLIli+TBIEJIwYHmIwxcwryEwgAIf5oQ3JlYXRlZCBieSBC
   TVBUb0dJRiBQcm8gdmVyc2lvbiAyLjUNCqkgRGV2ZWxDb3IgMTk5NywxOTk4
   LiBBbGwgcmlnaHRzIHJlc2VydmVkLg0KaHR0cDovL3d3dy5kZXZlbGNvci5j
   b20AOw==
}

