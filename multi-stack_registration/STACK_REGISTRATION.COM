_/_/_/  _/_/_/    _/
$!          _/    _/    _/  _/           Image Processing Language
$!         _/    _/_/_/    _/
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zurich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!
$!
$!==============================================================================
$!
$! 2014-03-03  Written by Jenn Bhatla and Sarah Manske, based on script provided by
$!             Bert van Rietbergen.
$! 2014-10-31  Updated by Steven Boyd to accommodate images with different
$!             resolutions and using the latest registration v1.07
$! 2018-05-28  Updated by Sophie Lemay and Jenn Bhatla to register and align multiple stacks
$!
$! Called by SUBMIT_STACK_REGISTRATION.COM
$! Utilized in Brunet et al. BMC Med Imaging doi: 10.21203/rs.2.14575/v1
$!
$  SIGMA_GAUSS    := 1.2
$  SUPPORT_GAUSS  := 2
$  THRESHOLD_SEG  := 100
$  COLOUR1        := 41
$  COLOUR2        := 82  ! sum (41 + 82 = 123) above low range
$  THRESHOLD_LOW  := 120 ! COLOUR1 + COLOUR2 must be between Threshold low and 127
$!
$! If registration takes long: remove the ! of the second line for testing
$! (but set it back for the final registration!)
$!
$  RESOLUTIONS     = "8 4 1"
$!  RESOLUTIONS     = "16 4 0"
$!==============================================================================
$!                            Start of script
$!==============================================================================
$!
$  FILENAME1         = F$PARSE("''p1'",,,"NAME")
$  DEV               = F$PARSE("''p1'",,,"DEVICE")
$  DIR               = F$PARSE("''p1'",,,"DIRECTORY")
$!
$  DST_FILE     := 'DEV''DIR''FILENAME1'_DST.AIM
$  MID_FILE     := 'DEV''DIR''FILENAME1'_MID.AIM
$  PRX_FILE      := 'DEV''DIR''FILENAME1'_PRX.AIM
$
$  RAMHA_GOBJ_DST         := 'DEV''DIR''FILENAME1'_DST.GOBJ
$  RAMHA_GOBJ_MID         := 'DEV''DIR''FILENAME1'_MID.GOBJ
$  RAMHA_GOBJ_PRX         := 'DEV''DIR''FILENAME1'_PRX.GOBJ
$  RAMHA_GOBJ_MID_FIX     := 'DEV''DIR''FILENAME1'_MID_FIX.AIM
$  RAMHA_GOBJ_DIS_FIX     := 'DEV''DIR''FILENAME1'_DST_FIX.AIM
$  RAMHA_GOBJ_PRX_FIX     := 'DEV''DIR''FILENAME1'_PRX_FIX.AIM
$  RAMHA_GOBJ_FIX         := 'DEV''DIR''FILENAME1'_FIX.AIM
$
$  REG_FILE_PRX       := 'DEV''DIR''FILENAME1'_PRX_REG.TXT
$  REG_FILE_DST       := 'DEV''DIR''FILENAME1'_DST_REG.TXT
$
$ COMBI_PRX_MID_DOWN := 'DEV''DIR''FILENAME1'_PRX_MID_DOWN.AIM
$ COMBI_DST_MID_TOP   := 'DEV''DIR''FILENAME1'_DST_MID_TOP.AIM
$ COMBI_FULL          := 'DEV''DIR''FILENAME1'_COMBI.AIM
$ COMBI_TEST          := 'DEV''DIR''FILENAME1'_COMBI_TEST.AIM
$
$ RAMHA_FINAL_IMAGE   := 'DEV''DIR''FILENAME1'_FINAL_IMAGE.AIM
$ RAMHA_FINAL_IMAGE_SEG    := 'DEV''DIR''FILENAME1'_FINAL_IMAGE_SEG.AIM
$
$!
$!==============================================================================
$!                            Start of IPL script
$!==============================================================================
$!
$!  ipl_scanco_prog := $um:ipl_scanco_fe.exe
$  ipl_scanco_prog = IPLREG_BATCH
$!
$  ON ERROR THEN EXIT
$! GOTO PROXIMAL_STEP
$! GOTO DISTAL_STEP
$! GOTO COMMON_STEP
$! GOTO RECONSTRUCT_STEP
$!
$!==============================================================================
$!                    Step One Register Top Proximal and Middle Stacks
$!==============================================================================
$!
$!
$!
$PROXIMAL_STEP:
$!

$ipl_scanco_prog

! Read in greyscale files
/read
  -name                       mid
  -filename                   "MID_FILE

/read
  -name                       prx
  -filename                   "PRX_FILE

! Apply approximate gobj for registration
/gobj_maskaimpeel_ow
  -input_output           mid
  -gobj_filename          "RAMHA_GOBJ_MID
  -peel_iter              0

/gobj_maskaimpeel_ow
  -input_output           prx
  -gobj_filename          "RAMHA_GOBJ_PRX
  -peel_iter              0

! Get 25% overlay
/sub_get
  -input                    mid
  -output                   small_mid_down
  -pos                      0 0 126
  -dim                      -1 -1 -1
  -global_pos_flag          false

/sub_get
  -input                    prx
  -output                   small_prx
  -pos                      0 0 0
  -dim                      -1 -1 42
  -global_pos_flag          false

/bounding_box_cut
  -input                    small_prx
  -output                   small_prx_box
  -z_only                    false
  -border                    0 0 0

/bounding_box_cut
  -input                    small_mid_down
  -output                   small_mid_down_box
  -z_only                    false
  -border                    0 0 0

! Register the two
/register
-in1                        small_mid_down_box
!-gobj_filename_in1
-in2                        small_prx_box
! -gobj_filename_in2
-Tmat_file_name             "REG_FILE_PRX
-orientation_search         2
-initial_rotation           0.0  0.0  0.0
-initial_translation        0.0  0.0  0.0
-delta_rotation             0.10 0.10 0.50
-delta_translation          0.10 0.10 0.50
-resolution_scaling         "RESOLUTIONS
-delta_scaling              1.00 0.10 0.10
-tolerance                  0.00001
-min_corr_coef              0.5
-min_method                 1
-object_func                1
-max_nr_iter                1000
-output_option              2

! Transform proximal to check registration
/transform
-in                         small_prx_box
-out                        reg_small_prx
-Tmat_file_name             "REG_FILE_PRX
-img_interpol_option        2                  ! linear interpolation
-el_size_mm_out             -1 -1 -1
-Tmat_invert               false

! Segment both for easier checking
/sup
-input                      reg_small_prx
-supdim_numbers             4 4 1
-testoff_pixels             "SUPPORT_GAUSS
-suppos_pixels_local        -1 -1 -1
-subdim_pixels              -1 -1 -1

/seg_gauss
-input                      reg_small_prx
-output                     reg_seg_small_prx
-sigma                      "SIGMA_GAUSS
-support                    "SUPPORT_GAUSS
-lower_in_perm              "THRESHOLD_SEG
-upper_in_perm              1000
-value_in_range             "COLOUR1

/sup
-input                      small_mid_down_box
-supdim_numbers             4 4 1
-testoff_pixels             "SUPPORT_GAUSS
-suppos_pixels_local        -1 -1 -1
-subdim_pixels              -1 -1 -1

/seg_gauss
-input                      small_mid_down_box
-output                     reg_small_mid_down
-sigma                      "SIGMA_GAUSS
-support                    "SUPPORT_GAUSS
-lower_in_perm              "THRESHOLD_SEG
-upper_in_perm              1000
-value_in_range             "COLOUR2

! Concatenate middle + transformed proximal and write out
/concat
-input1                     reg_seg_small_prx
-input2                     reg_small_mid_down
-output                     comb
-common_region_only         false
-add_not_overlay            true
-make_edge                  false
-shift_ofin2                0 0 0
-turnangle                  0.0
-turnpoint_global           -1 -1

/write comb "COMBI_PRX_MID_DOWN

..
$!==============================================================================
$!                    Step Two Register Top Distal and Middle Stacks
$!==============================================================================
$!
$!
$!
$DISTAL_STEP:
$!
$ipl_scanco_prog

! Read in images
/read
-name                       dst
-filename                   "DST_FILE

/read
-name                       mid
-filename                   "MID_FILE

! Apply approximate gobj for registration
/gobj_maskaimpeel_ow
  -input_output           dst
  -gobj_filename          "RAMHA_GOBJ_DST
  -peel_iter              0

/gobj_maskaimpeel_ow
  -input_output           mid
  -gobj_filename          "RAMHA_GOBJ_MID
  -peel_iter              0

! Get 25% overlap regions
/sub_get
  -input                    dst
  -output                   small_dst
  -pos                      0 0 126
  -dim                      -1 -1 -1
  -global_pos_flag          false

/sub_get
  -input                    mid
  -output                   small_mid_top
  -pos                      0 0 0
  -dim                      -1 -1 42
  -global_pos_flag          false

/bounding_box_cut
  -input                    small_dst
  -output                   small_dst_box
  -z_only                    false
  -border                    0 0 0

/bounding_box_cut
  -input                    small_mid_top
  -output                   small_mid_top_box
  -z_only                    false
  -border                    0 0 0

! Register two regions
/register
-in1                        small_mid_top_box
! -gobj_filename_in1
-in2                        small_dst_box
! -gobj_filename_in2
-Tmat_file_name             "REG_FILE_DST
-orientation_search         2
-initial_rotation           0.0  0.0  0.0
-initial_translation        0.0  0.0  0.0
-delta_rotation             0.10 0.10 0.50
-delta_translation          0.10 0.10 0.50
-resolution_scaling         8 4 1 ! "RESOLUTIONS
-delta_scaling              1.00 0.10 0.10
-tolerance                  0.00001
-min_corr_coef              0.1
-min_method                 1
-object_func                1
-max_nr_iter                1000
-output_option              2

! Transform through to check overlap
/transform
-in                         small_dst_box
-out                        reg_small_dst
-Tmat_file_name             "REG_FILE_DST
-img_interpol_option        2                  ! cubic interpolation
-el_size_mm_out             -1 -1 -1
-Tmat_invert               false

! Threshold both for easier checking
/sup
  -input                     reg_small_dst
  -supdim_numbers             4 4 1
  -testoff_pixels             "SUPPORT_GAUSS
  -suppos_pixels_local        -1 -1 -1
  -subdim_pixels              -1 -1 -1

/seg_gauss
  -input                      reg_small_dst
  -output                     reg_seg_small_dst
  -sigma                      "SIGMA_GAUSS
  -support                    "SUPPORT_GAUSS
  -lower_in_perm              "THRESHOLD_SEG
  -upper_in_perm              1000
  -value_in_range             "COLOUR1

/sup
  -input                      small_mid_top_box
  -supdim_numbers             4 4 1
  -testoff_pixels             "SUPPORT_GAUSS
  -suppos_pixels_local        -1 -1 -1
  -subdim_pixels              -1 -1 -1

/seg_gauss
  -input                      small_mid_top_box
  -output                     reg_small_mid_top
  -sigma                      "SIGMA_GAUSS
  -support                    "SUPPORT_GAUSS
  -lower_in_perm              "THRESHOLD_SEG
  -upper_in_perm              1000
  -value_in_range             "COLOUR2

! Concatenate and write out testing file
/concat
  -input1                     reg_seg_small_dst
  -input2                     reg_small_mid_top
  -output                     comb
  -common_region_only         false
  -add_not_overlay            true
  -make_edge                  false
  -shift_ofin2                0 0 0
  -turnangle                  0.0
  -turnpoint_global           -1 -1

/write comb "COMBI_DST_MID_TOP

..
$!==============================================================================
$!        STEP 3: Create common gobj
$!==============================================================================
$!
$!
$!
$COMMON_STEP:
$!
$ipl_scanco_prog

!!!!! Create colour for distal
/read
  -name                       dst
  -filename                   "DST_FILE

/norm_max
  -input                      dst
  -output                     mask_dst
  -max                        127
  -type_out                   char     ! The input may be type 'short', but we need 'char'

/set_value
  -input                      mask_dst
  -value_object               "COLOUR1
  -value_background           "COLOUR1

/gobj_maskaimpeel_ow
  -input_output             mask_dst
  -gobj_filename            "RAMHA_GOBJ_DST
  -peel_iter                 0

/delete                       dst

!!!!! Create colour for Proximal
/read
  -name                       prx
  -filename                   "PRX_FILE

/norm_max
  -input                      prx
  -output                     mask_prx
  -max                        127
  -type_out                   char     ! The input may be type 'short', but we need 'char'

/set_value
  -input                      mask_prx
  -value_object               "COLOUR1
  -value_background           "COLOUR1

/gobj_maskaimpeel_ow
  -input_output             mask_prx
  -gobj_filename            "RAMHA_GOBJ_PRX
  -peel_iter                 0

/delete                       prx

!!!!! Create colour for middle
/read
  -name                       mid
  -filename                   "MID_FILE

/norm_max
  -input                      mid
  -output                     mask_mid
  -max                        127
  -type_out                   char     ! The input may be type 'short', but we need 'char'

/set_value
  -input                      mask_mid
  -value_object               "COLOUR2
  -value_background           "COLOUR2

/gobj_maskaimpeel_ow
  -input_output             mask_mid
  -gobj_filename            "RAMHA_GOBJ_MID
  -peel_iter                 0

/delete                       mid

! First create the common mask for the distal
/transform
  -in                         mask_dst
  -out                        mask_dst_rot
  -Tmat_file_name             "REG_FILE_DST
  -img_interpol_option        2
  -Tmat_invert                false

/concat
  -input1                     mask_mid
  -input2                     mask_dst_rot
  -output                     comb_dst
  -common_region_only         false
  -add_not_overlay            true      ! common region adds to 41+82=123
  -make_edge                  false
  -shift_ofin2                0 0 0
  -turnangle                  0.0
  -turnpoint_global           -1 -1

/threshold
  -input                      comb_dst
  -output                     fixed_dst_rot
  -lower_in_perm_aut_al       40
  -upper_in_perm_aut_al       42
  -value_in_range             127
  -unit                       5         ! native units

/threshold
  -input                      comb_dst
  -output                     temp_middle_dst
  -lower_in_perm_aut_al       81
  -upper_in_perm_aut_al       100000
  -value_in_range             127
  -unit                       5         ! native units

! Create the common mask for the proximal
/transform
  -in                         mask_prx
  -out                        mask_prx_rot
  -Tmat_file_name             "REG_FILE_PRX
  -img_interpol_option        2
  -Tmat_invert                false

/concat
  -input1                     mask_mid
  -input2                     mask_prx_rot
  -output                     comb_prx
  -common_region_only         false
  -add_not_overlay            true      ! common region adds to 41+82=123
  -make_edge                  false
  -shift_ofin2                0 0 0
  -turnangle                  0.0
  -turnpoint_global           -1 -1

/threshold
  -input                      comb_prx
  -output                     fixed_prx_rot
  -lower_in_perm_aut_al       40
  -upper_in_perm_aut_al       42
  -value_in_range             127
  -unit                       5         ! native units

/threshold
  -input                      comb_prx
  -output                     temp_middle_prx
  -lower_in_perm_aut_al       81
  -upper_in_perm_aut_al       100000
  -value_in_range             127
  -unit                       5         ! native units

! At this point:
!   fixed_dst_rot excluding middle overlap
!   fixed_prx_rot excluding middle overlap
!   temp_middle_dst including distal overlap
!   temp_middle_prx including proximal overlap

/concat
  -input1                     temp_middle_dst
  -input2                     temp_middle_prx
  -output                     fixed_middle
  -common_region_only         false
  -add_not_overlay            true      ! common region adds to 41+82=123
  -make_edge                  false
  -shift_ofin2                0 0 0
  -turnangle                  0.0
  -turnpoint_global           -1 -1

/set_value fixed_middle 127 0

/write fixed_middle "RAMHA_GOBJ_MID_FIX
/write fixed_dst_rot "RAMHA_GOBJ_DIS_FIX
/write fixed_prx_rot "RAMHA_GOBJ_PRX_FIX

! Create a quick file for checking
/set_value fixed_middle 40 0
/set_value fixed_dst_rot 20 0
/set_value fixed_prx_rot 10 0

/concat
  -input1                     fixed_middle
  -input2                     fixed_dst_rot
  -output                     concat
  -common_region_only         false
  -add_not_overlay            true      ! common region adds to 41+82=123
  -make_edge                  false
  -shift_ofin2                0 0 0
  -turnangle                  0.0
  -turnpoint_global           -1 -1

/concat
  -input1                     concat
  -input2                     fixed_prx_rot
  -output                     concat2
  -common_region_only         false
  -add_not_overlay            true      ! common region adds to 41+82=123
  -make_edge                  false
  -shift_ofin2                0 0 0
  -turnangle                  0.0
  -turnpoint_global           -1 -1

/write concat2 "RAMHA_GOBJ_FIX

..

$!==============================================================================
$!        STEP 4: PUT DISTAL, MID AND PROXIMAL STACKS BACK TOGETHER
$!==============================================================================
$!
$!
$!
$RECONSTRUCT_STEP:
$!
$ipl_scanco_prog

! Read in dst, transform, mask
/read
  -name                       dst
  -filename                   "DST_FILE

/transform
  -in                         dst
  -out                        dst_trans
  -Tmat_file_name             "REG_FILE_DST
  -img_interpol_option        2                  ! linear interpolation
  -Tmat_invert                false

/gobj_maskaimpeel_ow
  -input_output             dst_trans
  -gobj_filename            "RAMHA_GOBJ_DIS_FIX
  -peel_iter                 0

/del dst

! Read in prx, transform, mask
/read
  -name                       prx
  -filename                   "PRX_FILE

/transform
  -in                         prx
  -out                        prx_trans
  -Tmat_file_name             "REG_FILE_PRX
  -img_interpol_option        2                 ! linear interpolation
  -Tmat_invert                false

/gobj_maskaimpeel_ow
  -input_output             prx_trans
  -gobj_filename            "RAMHA_GOBJ_PRX_FIX
  -peel_iter                 0

/del prx

! Read in mid
/read
  -name                       mid
  -filename                   "MID_FILE

/gobj_maskaimpeel_ow
  -input_output             mid
  -gobj_filename            "RAMHA_GOBJ_MID_FIX
  -peel_iter                 0

! Concatenate all files
/concat
  -input1                     mid
  -input2                     prx_trans
  -output                     comb1
  -common_region_only         false
  -add_not_overlay            true
  -make_edge                  false
  -shift_ofin2                0 0 0
  -turnangle                  0.0
  -turnpoint_global           -1 -1

/concat
  -input1                     comb1
  -input2                     dst_trans
  -output                     comb2
  -common_region_only         false
  -add_not_overlay            true
  -make_edge                  false
  -shift_ofin2                0 0 0
  -turnangle                  0.0
  -turnpoint_global           -1 -1

/write comb2 "RAMHA_FINAL_IMAGE

!/seg_gauss
!-input                      comb2
!-output                     comb3
!-sigma                      "SIGMA_GAUSS
!-support                    "SUPPORT_GAUSS
!-lower_in_perm              100
!-upper_in_perm              1000

!/write comb3 "RAMHA_FINAL_IMAGE_SEG
..
$!
$ EXIT
$!
