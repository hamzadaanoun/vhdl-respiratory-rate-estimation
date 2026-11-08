# Executer depuis le dossier racine du projet.
if {[catch {quit -sim}]} {}
set cwd [pwd]
if {![file exists "video_rgb_515frames.txt"]} {error "Entree absente: lancer PREPARER_ENTREE.ps1"}
if {![file exists "work/_info"]} {vlib work}
vmap work ./work
foreach f {
    Grayscale_Pipeline.vhd
    Box_Blur_Pipeline.vhd
    Sobel_Pipeline.vhd
    Threshold_Pipeline.vhd
    Morphology_Pipeline.vhd
    Region_detector.vhd
    roi_generator.vhd
    rgb_roi_extractor.vhd
    rgb_mean_calculator.vhd
    skin_roi_tracker.vhd
    Image_Processing_Pipeline.vhd
    image_processing_pipeline_8blocks.vhd
    image_processing_pipeline_9blocks.vhd
    rgb_temporal_buffer.vhd
    pca_rgb.vhd
    respiratory_pipeline_11blocks.vhd
    bandpass_filter.vhd
    fft_512.vhd
    bpm_calculator.vhd
    respiratory_processing_12to14.vhd
    respiratory_pipeline_14blocks.vhd
    tb_video_reelle_14blocks_export.vhd
} {
    puts "COMPILATION : $f"
    if {[catch {vcom -2008 -work work [file join VHDL $f]} msg]} {error "ECHEC $f : $msg"}
}
vsim work.tb_respiratory_pipeline_14blocks
view wave
foreach s {clk rst valid_in frame_start mean_valid_out pca_valid pca_last input_overflow bpm_valid bpm_out peak_bin_out peak_found processing_done} {
    add wave sim:/tb_respiratory_pipeline_14blocks/$s
}
run 55 ms
puts "Simulation terminee; verifier le bilan et les fichiers de sortie."
