# Ejecutar desde Vivado: source /ruta/al/repositorio/vivado/crear_proyecto.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists ::env(NEORV32_HOME)]} { error "Defina NEORV32_HOME con la dependencia indicada en docs/reproduccion.md" }
set neorv32 [file normalize $::env(NEORV32_HOME)]
set manifest [file join $neorv32 rtl file_list_core.f]
if {![file isfile $manifest]} { error "No existe $manifest" }
set sources {}
set fp [open $manifest r]
foreach line [split [read $fp] \n] {
    set line [string trim $line]
    if {[string match {$NEORV32_HOME/*} $line]} {
        set path [string map [list {$NEORV32_HOME} $neorv32] $line]
        if {![file isfile $path]} { close $fp; error "Falta fuente: $path" }
        lappend sources $path
    }
}
close $fp
if {![llength $sources]} { error "Lista NEORV32 vacia" }
set out [file join $root build vivado]
if {[file exists [file join $out mpei_basys3.xpr]]} { error "Proyecto existente en $out; abrala o use una copia limpia para regenerar" }
create_project mpei_basys3 $out -part xc7a35tcpg236-1
set_property target_language VHDL [current_project]
add_files -norecurse $sources
set_property library neorv32 [get_files $sources]
set local_sources {}
foreach name {def_package Adder_INT Multiplier_INT DPU_TOP_INT TC_INT_top tcu_wrapper neorv32_tcu_top} {
    lappend local_sources [file join $root rtl ${name}.vhd]
}
add_files -norecurse $local_sources
set_property file_type {VHDL 2008} [get_files -filter {FILE_TYPE =~ "VHDL*"}]
add_files -fileset constrs_1 -norecurse [file join $root vivado basys3_neorv32.xdc]
set_property top neorv32_tcu_top [current_fileset]
update_compile_order -fileset sources_1
puts "Proyecto preparado: [file join $out mpei_basys3.xpr]"
