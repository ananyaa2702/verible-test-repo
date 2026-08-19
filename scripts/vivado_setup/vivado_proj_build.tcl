#!/usr/bin/env vivado -mode batch -source
# ==========================================================
# Generic Portable Vivado Project Setup Script
# ==========================================================

set ::vivado_proj_build_script_path [info script]
if {$::vivado_proj_build_script_path ne "" && $::vivado_proj_build_script_path ne "."} {
    set ::vivado_proj_build_script_path [file normalize $::vivado_proj_build_script_path]
    set ::vivado_proj_build_script_dir [file dirname $::vivado_proj_build_script_path]
} else {
    set ::vivado_proj_build_script_path ""
    set ::vivado_proj_build_script_dir ""
}

proc vivado_project_resolve_repo_root {yaml_file} {
    # 1) Highest priority: explicit user override from Tcl console
    if {[info exists ::vivado_proj_build_repo_root] && $::vivado_proj_build_repo_root ne ""} {
        return [file normalize $::vivado_proj_build_repo_root]
    }

    # 2) Derive from YAML path when provided (scripts/build_config.yaml -> repo root)
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

    # 3) Derive from this script path (scripts/vivado_setup -> repo root)
    if {[info exists ::vivado_proj_build_script_dir] && $::vivado_proj_build_script_dir ne ""} {
        return [file normalize "$::vivado_proj_build_script_dir/../.."]
    }

    # 4) Final fallback: current working directory
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

proc vivado_project_build {proj_name yaml_file} {
    # Load the yaml package from Tcllib
    package require yaml

    puts "INFO: Starting Vivado project setup..."

    # ----------------------------------------------------------
    # Resolve paths (portable, repo-relative)
    # ----------------------------------------------------------
    set repo_root [vivado_project_resolve_repo_root $yaml_file]
    set proj_dir "$repo_root/vivado" ; #sets proj_dir path - folder where all vivado projects would reside

    if {[file pathtype $yaml_file] eq "relative"} {
        set yaml_file [file normalize "$repo_root/$yaml_file"]
    } else {
        set yaml_file [file normalize $yaml_file]
    }

    file mkdir $proj_dir

    if {[info exists ::vivado_proj_build_script_dir] && $::vivado_proj_build_script_dir ne ""} {
        puts "INFO: Script dir : $::vivado_proj_build_script_dir"
    } else {
        puts "INFO: Script dir : <not available in current Tcl context>"
    }
    puts "INFO: Repo root : $repo_root"
    puts "INFO: Project   : $proj_dir/$proj_name"

    # ----------------------------------------------------------
    # Create / overwrite project
    # ----------------------------------------------------------
    create_project $proj_name $proj_dir -force

    # ----------------------------------------------------------
    # Automatically Generate BRAM IPs
    # ----------------------------------------------------------
    puts "INFO: Instantiating BRAM IPs (blk_mem_gen_0 and blk_mem_gen_1)..."

    # Instantiate BRAM for Bootrom (blk_mem_gen_0)
    create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name blk_mem_gen_0
    set_property -dict [list \
        CONFIG.Write_Width_A {32} \
        CONFIG.Read_Width_A {32} \
        CONFIG.Write_Depth_A {4096} \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
        CONFIG.Use_RSTA_Pin {true} \
    ] [get_ips blk_mem_gen_0]

    # Instantiate BRAM for SRAM (blk_mem_gen_1)
    create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name blk_mem_gen_1
    set_property -dict [list \
        CONFIG.Write_Width_A {32} \
        CONFIG.Read_Width_A {32} \
        CONFIG.Write_Depth_A {4096} \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
        CONFIG.Use_RSTA_Pin {true} \
    ] [get_ips blk_mem_gen_1]

    # Generate target files for the IPs so they are ready for compilation
    generate_target all [get_ips blk_mem_gen_0]
    generate_target all [get_ips blk_mem_gen_1]

    # -------------------------------------------------------------------------------------------
    # Reading build_config.yaml file - containing filepaths for all sources to be used in project
    # -------------------------------------------------------------------------------------------

    #get rtl and tb file paths
    set fp [open $yaml_file r]
    set file_data [read $fp]
    close $fp

    # Clean Windows carriage returns (\r) so paths parse correctly on Linux
    regsub -all {\r} $file_data {} file_data

    set data_dict [::yaml::yaml2dict $file_data]
    set rtl_files {}
    set tb_files {}
    set simdata_files {}

    if {[dict exists $data_dict rtl]} {
        set rtl_files [dict get $data_dict rtl]
    }
    if {[dict exists $data_dict tb]} {
        set tb_files [dict get $data_dict tb]
    }
    if {[dict exists $data_dict simdata]} {
        set simdata_files [dict get $data_dict simdata]
    }

    # Convert any repo-relative paths from YAML into absolute paths.
    set rtl_files [vivado_project_make_abs_list $repo_root $rtl_files]
    set tb_files [vivado_project_make_abs_list $repo_root $tb_files]
    set simdata_files [vivado_project_make_abs_list $repo_root $simdata_files]


    # -----------------------------------------------------------
    # Adding RTL sources
    # -----------------------------------------------------------
    if {[llength $rtl_files] == 0} {
        puts "ERROR: No RTL files found in build_config.yaml"
        return
    }
    add_files -fileset sources_1 $rtl_files
    update_compile_order -fileset sources_1

    foreach rtl_f $rtl_files {
        puts "RTL file: $rtl_f added to project"
    }

    # Safe application of global_include (Prevents 2025.2 from halting early)
    set global_defines_path [file normalize "$repo_root/RTL/global_defines.v"]
    set global_def_obj [get_files -quiet $global_defines_path]

    if {[llength $global_def_obj] > 0} {
        set_property is_global_include true $global_def_obj
        puts "INFO: Set is_global_include to true for global_defines.v"
    } else {
        if {[file exists $global_defines_path]} {
            add_files -fileset sources_1 $global_defines_path
            set_property is_global_include true [get_files $global_defines_path]
            puts "INFO: global_defines.v wasn't in YAML but was found on disk, added, and set as global include."
        } else {
            puts "WARNING: global_defines.v could not be located. Skipping global include configuration."
        }
    }

    # Safe application of global_include (Prevents 2025.2 from halting early)
    set uart_defines_path [file normalize "$repo_root/RTL/soc_uart_subsystem/uart_top/uart_defines.v"]
    set uart_def_obj [get_files -quiet $uart_defines_path]

    if {[llength $uart_def_obj] > 0} {
        set_property is_global_include true $uart_def_obj
        puts "INFO: Set is_global_include to true for uart_defines.v"
    } else {
        if {[file exists $uart_defines_path]} {
            add_files -fileset sources_1 $uart_defines_path
            set_property is_global_include true [get_files $uart_defines_path]
            puts "INFO: uart_defines.v wasn't in YAML but was found on disk, added, and set as global include."
        } else {
            puts "WARNING: uart_defines.v could not be located. Skipping global include configuration."
        }
    }

    # -----------------------------------------------------------
    # Adding TB sources
    # -----------------------------------------------------------
    if {[llength $tb_files] == 0} {
        puts "ERROR: No TB files found in build_config.yaml"
        return
    }
    add_files -fileset sim_1 $tb_files
    update_compile_order -fileset sim_1

    foreach tb_f $tb_files {
        puts "TB file: $tb_f added to project"
    }

    # -----------------------------------------------------------
    # Adding simulation data files (memory/text files)
    # -----------------------------------------------------------
    if {[llength $simdata_files] > 0} {
        add_files -fileset sim_1 $simdata_files
        foreach simdata_f $simdata_files {
            puts "SIMDATA file: $simdata_f added to project"
        }
    }

    # ----------------------------------------------------------
    # Set TOP modules (edit only these when needed)
    # ----------------------------------------------------------
    set_property top system [get_filesets sources_1]

    # ----------------------------------------------------------
    # Simulator Settings (Universal -notimingchecks)
    # ----------------------------------------------------------
    puts "INFO: Configuring simulation settings (-notimingchecks)..."

    # Use explicit -name, -value, -objects syntax so Tcl doesn't mistake the leading hyphen for a command flag
    if {[catch {set_property -name {xsim.elaborate.xelab.more_options} -value {-notimingchecks} -objects [get_filesets sim_1]} errMsg]} {
        # Fallback for older Vivado versions where the prefix might be omitted
        if {[catch {set_property -name {xelab.more_options} -value {-notimingchecks} -objects [get_filesets sim_1]} errMsg2]} {
            puts "WARNING: Failed to set xelab.more_options. Reason: $errMsg2"
        } else {
            puts "INFO: Successfully applied -notimingchecks to sim_1 (legacy property name)."
        }
    } else {
        puts "INFO: Successfully applied -notimingchecks to sim_1."
    }

    puts "INFO: Vivado project setup complete."
}

if {[info exists argc] && $argc == 2} {
    vivado_project_build [lindex $argv 0] [lindex $argv 1]
}