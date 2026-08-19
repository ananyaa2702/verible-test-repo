#!/usr/bin/env vivado -mode batch -source
# ==========================================================
# Vivado Project Incremental Update Script
# Bulletproof version: Compatible with Vivado 2017.4 through 2026+
# Includes deep-path protection for dynamically generated IPs
# ==========================================================

# ========== SCRIPT INITIALIZATION ==========
set ::vivado_update_script_path [info script]
if {$::vivado_update_script_path ne "" && $::vivado_update_script_path ne "."} {
    set ::vivado_update_script_path [file normalize $::vivado_update_script_path]
    set ::vivado_update_script_dir [file dirname $::vivado_update_script_path]
} else {
    set ::vivado_update_script_path ""
    set ::vivado_update_script_dir ""
}

proc vivado_project_resolve_repo_root {yaml_file} {
    if {[info exists ::vivado_update_repo_root] && $::vivado_update_repo_root ne ""} {
        return [file normalize $::vivado_update_repo_root]
    }

    if {$yaml_file ne ""} {
        set yaml_candidate $yaml_file
        if {[file pathtype $yaml_candidate] eq "relative"} {
            set yaml_candidate [file normalize "[pwd]/$yaml_candidate"]
        } else {
            set yaml_candidate [file normalize $yaml_candidate]
        }

        if {[file exists $yaml_candidate]} {
            set scripts_dir [file dirname $yaml_candidate]
            return [file normalize "$scripts_dir/.."]
        }
    }

    if {[info exists ::vivado_update_script_dir] && $::vivado_update_script_dir ne ""} {
        return [file normalize "$::vivado_update_script_dir/../.."]
    }

    return [pwd]
}

proc vivado_project_make_abs_list {repo_root file_list} {
    set out_list {}
    foreach f $file_list {
        if {[file pathtype $f] eq "relative"} {
            lappend out_list [file normalize "$repo_root/$f"]
        } else {
            lappend out_list [file normalize $f]
        }
    }
    return $out_list
}

proc vivado_project_regen_config {repo_root yaml_file} {
    puts "INFO: Attempting to regenerate build_config.yaml..."
    set scripts_dir [file dirname $yaml_file]
    set gen_script "$scripts_dir/gen_build_config.sh"

    if {[file exists $gen_script]} {
        if {[catch {exec bash $gen_script} output]} {
            if {[catch {exec sh $gen_script} output2]} {
                puts "WARNING: Config regeneration failed. Continuing with existing YAML."
            } else {
                puts "INFO: Config regenerated using sh fallback."
            }
        } else {
            puts "INFO: Config regenerated successfully."
        }
    } else {
        puts "WARNING: gen_build_config.sh not found. Skipping auto-regeneration."
    }
}

proc vivado_project_load_config {yaml_file repo_root} {
    package require yaml

    if {[catch {set fp [open $yaml_file r]} err]} {
        puts "ERROR: Cannot open $yaml_file: $err"
        return [list {} {} {}]
    }
    set file_data [read $fp]
    close $fp

    regsub -all {\r} $file_data {} file_data

    if {[catch {set data_dict [::yaml::yaml2dict $file_data]} err]} {
        puts "ERROR: Failed to parse YAML: $err"
        return [list {} {} {}]
    }

    set rtl_files {}
    set tb_files {}
    set simdata_files {}

    if {[dict exists $data_dict rtl]} { set rtl_files [dict get $data_dict rtl] }
    if {[dict exists $data_dict tb]} { set tb_files [dict get $data_dict tb] }
    if {[dict exists $data_dict simdata]} { set simdata_files [dict get $data_dict simdata] }

    set rtl_files [vivado_project_make_abs_list $repo_root $rtl_files]
    set tb_files [vivado_project_make_abs_list $repo_root $tb_files]
    set simdata_files [vivado_project_make_abs_list $repo_root $simdata_files]

    return [list $rtl_files $tb_files $simdata_files]
}

proc vivado_project_get_current_files {fileset} {
    set current_files {}
    if {[catch {get_filesets $fileset} fs_obj] || $fs_obj eq ""} {
        return {}
    }

    if {[catch {set fileobjs [get_files -quiet -of_objects $fs_obj]} err]} {
        return {}
    }

    foreach fobj $fileobjs {
        set fname [get_property name $fobj]
        if {$fname ne ""} {
            lappend current_files [file normalize $fname]
        }
    }
    return $current_files
}

proc vivado_project_update_fileset {fileset new_files old_files} {
    set to_add {}
    set to_remove {}

    # Strictly normalize both lists
    set norm_new {}
    foreach f $new_files { lappend norm_new [file normalize $f] }

    # Find files to ADD
    foreach f $norm_new {
        if {[lsearch -exact $old_files $f] == -1} {
            lappend to_add $f
        }
    }

    # Find files to REMOVE
    foreach f $old_files {
        # ========================================================
        # EXCLUSION FILTER: Protect dynamically generated elements
        # ========================================================
        # Match against the FULL PATH ($f), not just the filename.
        # This protects IP cores and version-specific sub-files
        # (e.g., blk_mem_gen_v8_4.v) residing inside auto-generated
        # project directories, rendering the script version-agnostic.
        if {[string match -nocase "*blk_mem_gen_0*" $f] ||
            [string match -nocase "*blk_mem_gen_1*" $f] ||
            [string match -nocase "*.xci" $f] ||
            [string match -nocase "*.xcix" $f] ||
            [string match -nocase "*.gen*" $f] ||
            [string match -nocase "*.srcs*/ip/*" $f]} {
            continue
        }

        if {[lsearch -exact $norm_new $f] == -1} {
            lappend to_remove $f
        }
    }

    # REMOVE PROCESS
    if {[llength $to_remove] > 0} {
        puts "\nINFO: Removing stale files from $fileset..."
        foreach f $to_remove {
            set fobj [get_files -quiet $f]
            if {$fobj ne ""} {
                if {[catch {remove_files -fileset $fileset $fobj} err]} {
                    puts "  WARNING: Failed to remove $f"
                } else {
                    puts "  REMOVED: [file tail $f]"
                }
            }
        }
    }

    # ADD PROCESS
    if {[llength $to_add] > 0} {
        puts "\nINFO: Adding new files to $fileset..."
        set valid_adds {}
        foreach f $to_add {
            if {[file exists $f]} {
                lappend valid_adds $f
            } else {
                puts "  WARNING: File missing on disk, skipped: $f"
            }
        }

        if {[llength $valid_adds] > 0} {
            if {[catch {add_files -fileset $fileset $valid_adds} err]} {
                puts "  WARNING: Bulk add failed, trying individually..."
                foreach f $valid_adds {
                    catch {add_files -fileset $fileset $f}
                }
            } else {
                foreach f $valid_adds { puts "  ADDED: [file tail $f]" }
            }
        }
    }

    # UPDATE COMPILE ORDER
    if {[llength $to_add] > 0 || [llength $to_remove] > 0} {
        catch {update_compile_order -fileset $fileset}
    }
}

proc vivado_project_apply_special_properties {repo_root} {
    puts "\nINFO: Verifying Global Includes..."

    set global_defines_path [file normalize "$repo_root/RTL/global_defines.v"]
    set global_def_obj [get_files -quiet $global_defines_path]

    if {[llength $global_def_obj] > 0} {
        catch {set_property is_global_include true $global_def_obj}
        puts "INFO: Enforced is_global_include=true for global_defines.v"
    }

    set uart_defines_path [file normalize "$repo_root/RTL/soc_uart_subsystem/uart_top/uart_defines.v"]
    set uart_def_obj [get_files -quiet $uart_defines_path]

    if {[llength $uart_def_obj] > 0} {
        catch {set_property is_global_include true $uart_def_obj}
        puts "INFO: Enforced is_global_include=true for uart_defines.v"
    }
}

proc vivado_project_apply_sim_settings {} {
    if {[catch {set_property -name {xsim.elaborate.xelab.more_options} -value {-notimingchecks} -objects [get_filesets sim_1]} errMsg]} {
        if {[catch {set_property -name {xelab.more_options} -value {-notimingchecks} -objects [get_filesets sim_1]} errMsg2]} {
            # Silent fallback
        }
    }
}

proc vivado_project_update {proj_name yaml_file} {
    puts "\n========================================================"
    puts "      VIVADO PROJECT ROBUST INCREMENTAL UPDATE"
    puts "========================================================"

    set repo_root [vivado_project_resolve_repo_root $yaml_file]
    if {[file pathtype $yaml_file] eq "relative"} {
        set yaml_file [file normalize "$repo_root/$yaml_file"]
    } else {
        set yaml_file [file normalize $yaml_file]
    }

    set proj_dir "$repo_root/vivado"
    set proj_file "$proj_dir/$proj_name.xpr"

    puts "INFO: Repo root : $repo_root"
    puts "INFO: Project   : $proj_file"

    vivado_project_regen_config $repo_root $yaml_file
    set config_data [vivado_project_load_config $yaml_file $repo_root]

    set new_rtl_files [lindex $config_data 0]
    set new_tb_files [lindex $config_data 1]
    set new_simdata_files [lindex $config_data 2]

    if {[llength $new_rtl_files] == 0} {
        puts "ERROR: No RTL files found or YAML parse failed. Aborting."
        return
    }

    if {[catch {current_project} current_proj] || $current_proj eq ""} {
        if {![file exists $proj_file]} {
            puts "ERROR: Project not found at $proj_file."
            puts "       Please run vivado_proj_build.tcl first."
            return
        }
        puts "INFO: Opening project..."
        if {[catch {open_project $proj_file} err]} {
            puts "ERROR: Could not open project: $err"
            return
        }
    } elseif {$current_proj ne $proj_name} {
        puts "INFO: Switching to project $proj_name..."
        catch {open_project $proj_file}
    }

    set current_rtl [vivado_project_get_current_files sources_1]
    set current_tb  [vivado_project_get_current_files sim_1]

    set combined_new_sim [concat $new_tb_files $new_simdata_files]

    vivado_project_update_fileset sources_1 $new_rtl_files $current_rtl
    vivado_project_update_fileset sim_1 $combined_new_sim $current_tb

    vivado_project_apply_special_properties $repo_root
    vivado_project_apply_sim_settings

    catch {save_project_as $proj_name $proj_dir -force}

    puts "\nINFO: Vivado project update complete."
    puts "========================================================\n"
}

# ========== MAIN EXECUTION ==========
if {[info exists argc] && $argc == 2} {
    if {[catch {vivado_project_update [lindex $argv 0] [lindex $argv 1]} main_err]} {
        puts "FATAL ERROR: $main_err"
    }
}
