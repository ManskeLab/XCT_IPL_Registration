 $!
$!         _/_/_/  _/_/_/    _/
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
$! 2014-09-22  Updated by Steven Boyd to generate a follow-up mask for the cortex
$!             that uses the baseline definition of the cortex.
$! 2014-10-31  Updated by Steven Boyd to accommodate images with different
$!             resolutions and using the latest registration v1.07
$! 2014-11-13  Updated to generate a common mask that can be used for
$!             registering multiple pairs of datasets.
$! 2019-05     Updated by Scott Brunet for MCP joints
$!Utilized in Brunet et al. BMC Med Imaging doi: 10.21203/rs.2.14575/v1
$!
$! Registration script for grey-level or segmented images
$! Requires VMS version V7.3-2 or higher!
$! Requires IPL registration v1.07 or higher!
$!
$! When using grey-level images the following parameters should be specified below:
$!
$  SIGMA_GAUSS    := 1.2
$  SUPPORT_GAUSS  := 2.0
$  THRESHOLD_SEG  := 240
$  THRESHOLD_UNIT := 2
$  COLOUR1        := 41
$  COLOUR2        := 82  ! sum (41 + 82 = 123) above low range
$  THRESHOLD_LOW  := 120 ! COLOUR1 + COLOUR2 must be between Threshold low and 127
$!
$! If registration takes long: remove the ! of the second line for testing
$! (but set it back for the final registration!)
$!
$  RESOLUTIONS     = "16 4 1"
$!  RESOLUTIONS     = "16 4 0"
$!==============================================================================
$!                            Start of script
$!==============================================================================
$ IF p3 .EQS. ""
$  THEN
$    WRITE SYS$OUTPUT "=============================================================================="
$    WRITE SYS$OUTPUT "This function will register two images: fixed (baseline) and moving (followup)."
$    WRITE SYS$OUTPUT "Requires VMS version V7.3-2 or higher."
$    WRITE SYS$OUTPUT "Images can be either both unsegmented (for best results) or both segmented."
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "Call the script as:"
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "@IPL_REGISTER.COM c0000001.aim c0000002.aim register.aim [c0000001.gobj c0000002.gobj]"
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "where:"
$    WRITE SYS$OUTPUT "c0000001.aim [input] is the fixed (baseline) image"
$    WRITE SYS$OUTPUT "c0000002.aim [input] is the moving (followup) image"
$    WRITE SYS$OUTPUT "register.aim [output] combines the resulting registered images, for QA"
$    WRITE SYS$OUTPUT "c0000001.GOBJ [input, optional] is the fixed (baseline) manual mask (not autoseg)"
$    WRITE SYS$OUTPUT "c0000002.GOBJ [input, optional] is the moving (followup) manual mask (not autoseg)"
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "Note: The optional GOBJ mask images must be provided if baseline and followup masks"
$    WRITE SYS$OUTPUT "      are required to be output representing the common region for analysis based"
$    WRITE SYS$OUTPUT "      on the results of the registration. Also, these masks ensure that the"
$    WRITE SYS$OUTPUT "      registration focuses only on the regions of interest in the images, and"
$    WRITE SYS$OUTPUT "      improves accuracy and reduces registration time."
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "Outputs from this script include:"
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "register.aim    A combination of the transformed moving image (41) and the"
$    WRITE SYS$OUTPUT "                baseline image (82), to produce a file for quality assurance."
$    WRITE SYS$OUTPUT "register.txt    A text file containing the 4x4 matrix transform from registration."
$    WRITE SYS$OUTPUT "register.tif    A TIF file of the image will be created automatically that can"
$    WRITE SYS$OUTPUT "                be viewed for convenient QA checking."
$    WRITE SYS$OUTPUT "c0000001_reg.gobj   Named as per input c0000001.aim filename except appended"
$    WRITE SYS$OUTPUT "                _reg.gobj. It represents the manual periosteal contour and is"
$    WRITE SYS$OUTPUT "                clipped based on the common region resulting from registration."
$    WRITE SYS$OUTPUT "                Note that this file is only output if c0000001.gobj is defined"
$    WRITE SYS$OUTPUT "                as an input, and it uses c0000001.aim as the base file name."
$    WRITE SYS$OUTPUT "c0000002_reg.gobj   Same as above, except based on input c0000002.aim."
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "Additional outputs are (these are based on the autoseg GOBJ files):"
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "c0000001_crtx_reg.gobj    Clipped files from common scan region from output"
$    WRITE SYS$OUTPUT "c0000002_crtx_reg.gobj    based on c0000001_crtx.gobj, c0000002_crtx.gobj"
$    WRITE SYS$OUTPUT "c0000002_crtx_fwd_reg.gobj    c0000001_crtx_reg.gobj forwarded to followup"
$    WRITE SYS$OUTPUT "c0000001_trab_reg.gobj    Clipped files from common scan region from output"
$    WRITE SYS$OUTPUT "c0000002_trab_reg.gobj    based on c0000001_trab.gobj, c0000002_trab.gobj"
$    WRITE SYS$OUTPUT "c0000002_trab_fwd_reg.gobj    c0000001_trab_reg.gobj forwarded to followup"
$    WRITE SYS$OUTPUT "c0000001_crtxpo_reg.gobj  Clipped files from common scan region from output"
$    WRITE SYS$OUTPUT "c0000002_crtxpo_reg.gobj  based on c0000001_crtxpo.gobj, c0000002_crtxpo.gobj"
$    WRITE SYS$OUTPUT "c0000002_crtxpo_fwd_reg.gobj    c0000001_crtxpo_reg.gobj forwarded to followup"
$    WRITE SYS$OUTPUT "c0000001_auto2_reg.gobj   Clipped files from common scan region from output"
$    WRITE SYS$OUTPUT "c0000002_auto2_reg.gobj   based on c0000001_auto2.gobj, c0000002_auto2.gobj"
$    WRITE SYS$OUTPUT "c0000002_auto2_fwd_reg.gobj     Simply a copy of c0000002_auto2_reg.gobj"
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "Recommended usage:"
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "The script can be run in its entirety, or it can be run with the registration"
$    WRITE SYS$OUTPUT "component separately from the part that generates the output GOBJ masks. If"
$    WRITE SYS$OUTPUT "the output GOBJ masks are to be generated, the script requires a valid register.txt"
$    WRITE SYS$OUTPUT "file as well as the temporary files that represent the common scan region at"
$    WRITE SYS$OUTPUT "baseline and follow-up called c0000001_common_reg.aim and c0000002_common_reg.aim"
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "If the results of the registration are unsatisfying, try different parameters. Good luck!
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "Note the meaning of the following file suffixes from the autocontour script:"
$    WRITE SYS$OUTPUT " _TRAB.GOBJ:   The endostreal surface of the bone."
$    WRITE SYS$OUTPUT " _AUTO2.GOBJ:  The periosteal surface of the bone."
$    WRITE SYS$OUTPUT " _CRTX.GOBJ:   The mask created by combining _AUTO2.GOBJ and _TRAB.GOBJ above."
$    WRITE SYS$OUTPUT " _CRTXPO.GOBJ: The 'refined' _CRTX.GOBJ mask that removes marrow space regions."
$    WRITE SYS$OUTPUT ""
$    WRITE SYS$OUTPUT "=============================================================================="
$    EXIT
$  ENDIF
$!
$  FILENAME1         = F$PARSE("''p1'",,,"NAME")
$  FILENAME2         = F$PARSE("''p2'",,,"NAME")
$  FILENAME3         = F$PARSE("''p3'",,,"NAME")
$  DEV               = F$PARSE("''p1'",,,"DEVICE")
$  DIR_READ1         = F$PARSE("''p1'",,,"DIRECTORY")
$  DIR_READ2         = F$PARSE("''p2'",,,"DIRECTORY")
$  DIR_WRITE         = F$PARSE("''p3'",,,"DIRECTORY")
$!
$  IN1_FILE          := 'DEV''DIR_READ1''FILENAME1'.AIM
$  IN2_FILE          := 'DEV''DIR_READ2''FILENAME2'.AIM
$  IN1_MASK_FILE     := 'DEV''DIR_READ1''FILENAME1'_PRXMASK.AIM
$  IN2_MASK_FILE     := 'DEV''DIR_READ2''FILENAME2'_PRXMASK.AIM
$  IN2_SEG_FILE      := 'DEV''DIR_READ2''FILENAME2'_SEG.AIM
$  COMBI_FILE        := 'DEV''DIR_WRITE''FILENAME3'.AIM
$  META1_FILE          := 'DEV''DIR_WRITE''FILENAME1'_META.AIM
$  META2_FILE          := 'DEV''DIR_WRITE''FILENAME2'_META.AIM
$  REG_FILE          := 'DEV''DIR_WRITE''FILENAME3'.TXT
$  FIXED_GOBJ        := 'DEV''DIR_WRITE''FILENAME1'_REG.GOBJ
$  MOVING_GOBJ       := 'DEV''DIR_WRITE''FILENAME2'_REG.GOBJ
$  DIL_MASK1         := 'DEV''DIR_READ1''FILENAME1'_PRXMASK_DIL.AIM
$  DIL_MASK2         := 'DEV''DIR_READ2''FILENAME2'_PRXMASK_DIL.AIM
$!
$!
$  GOBJ1_TRAB_FILE   := 'DEV''DIR_READ1''FILENAME1'_TRAB.GOBJ
$  GOBJ1_CORT_FILE   := 'DEV''DIR_READ1''FILENAME1'_CRTX.GOBJ
$  GOBJ1_CRTXPO_FILE     := 'DEV''DIR_READ1''FILENAME1'_CRTXPO.GOBJ
$  GOBJ1_AUTO2_FILE   := 'DEV''DIR_READ1''FILENAME1'_AUTO2.GOBJ
$!
$  GOBJ2_TRAB_FILE   := 'DEV''DIR_READ2''FILENAME2'_TRAB.GOBJ
$  GOBJ2_CORT_FILE   := 'DEV''DIR_READ2''FILENAME2'_CRTX.GOBJ
$  GOBJ2_CRTXPO_FILE     := 'DEV''DIR_READ2''FILENAME2'_CRTXPO.GOBJ
$  GOBJ2_AUTO2_FILE   := 'DEV''DIR_READ2''FILENAME2'_AUTO2.GOBJ
$!
$  FIXED_CRTX_GOBJ   := 'DEV''DIR_WRITE''FILENAME1'_CRTX_REG.GOBJ
$  FIXED_TRAB_GOBJ   := 'DEV''DIR_WRITE''FILENAME1'_TRAB_REG.GOBJ
$  FIXED_CRTXPO_GOBJ     := 'DEV''DIR_WRITE''FILENAME1'_CRTXPO_REG.GOBJ
$  FIXED_AUTO2_GOBJ   := 'DEV''DIR_WRITE''FILENAME1'_AUTO2_REG.GOBJ
$!
$  MOVING_CRTX_GOBJ  := 'DEV''DIR_WRITE''FILENAME2'_CRTX_REG.GOBJ
$  MOVING_FWD_CRTX_GOBJ  := 'DEV''DIR_WRITE''FILENAME2'_CRTX_FWD_REG.GOBJ
$  MOVING_TRAB_GOBJ  := 'DEV''DIR_WRITE''FILENAME2'_TRAB_REG.GOBJ
$  MOVING_FWD_TRAB_GOBJ  := 'DEV''DIR_WRITE''FILENAME2'_TRAB_FWD_REG.GOBJ
$  MOVING_CRTXPO_GOBJ    := 'DEV''DIR_WRITE''FILENAME2'_CRTXPO_REG.GOBJ
$  MOVING_FWD_CRTXPO_GOBJ    := 'DEV''DIR_WRITE''FILENAME2'_CRTXPO_FWD_REG.GOBJ
$  MOVING_AUTO2_GOBJ  := 'DEV''DIR_WRITE''FILENAME2'_AUTO2_REG.GOBJ
$  MOVING_FWD_AUTO2_GOBJ  := 'DEV''DIR_WRITE''FILENAME2'_AUTO2_FWD_REG.GOBJ
$!
$!  FIXED_COMMON_MASK        := 'DEV''DIR_WRITE''FILENAME1'_COMMON_REG.AIM
$!  FIXED_COMMON_MASK        := 'DEV''DIR_WRITE''FILENAME1'_COMMON_REG_R00.AIM
$  FIXED_COMMON_MASK        := 'DEV''DIR_WRITE''FILENAME1'_META_COMMON_REG_ALL.AIM
$  MOVING_COMMON_MASK       := 'DEV''DIR_WRITE''FILENAME2'_COMMON_REG.AIM
$!
$! NEW OUTPUTS
$  IN2_ROT		          := 'DEV''DIR_WRITE''FILENAME2'_ROT.AIM
$  MOVING_GOBJ_ROT        := 'DEV''DIR_WRITE''FILENAME2'_ROT.GOBJ
$
$! Files for debugging
$!
$  TRAB    :='DEV''DIR_WRITE'trab_fwd.aim
$  AUTO2   :='DEV''DIR_WRITE'auto2_fwd.aim
$  CRTX    :='DEV''DIR_WRITE'crtx_fwd.aim
$  CRTXPO  :='DEV''DIR_WRITE'crtxpo_fwd.aim
$!
$!
$! Check input files
$!
$  WRITE SYS$OUTPUT "The following files are used for in/output:
$
$  IF (F$SEARCH(IN1_FILE) .NES. "")
$  THEN
$     SHOW SYM IN1_FILE
$  ELSE
$     WRITE SYS$OUTPUT "Could not find file: "+IN1_FILE
$     EXIT
$  ENDIF
$!
$  IF (F$SEARCH(IN2_FILE) .NES. "")
$  THEN
$     SHOW SYM IN2_FILE
$  ELSE
$     WRITE SYS$OUTPUT "Could not find file: "+IN2_FILE
$     EXIT
$  ENDIF
$!
$  SHOW SYM REG_FILE
$!
$! The following checks if GOBJ files (p4, p5) are defined. These GOBJs would
$! isolate the ROI in the input images that are to be registered.
$!
$  IF (p4 .EQS. "")
$  THEN
$    WRITE SYS$OUTPUT "Warning. No GOBJ mask for baseline image defined."
$    WRITE SYS$OUTPUT "  Registration will proceed for entire reference image."
$    GOBJ1_FILE = "none"
$  ELSE
$    GOBJ1_FILE = p4
$    IF (F$SEARCH(GOBJ1_FILE) .NES. "")
$    THEN
$!      ok
$    ELSE
$      WRITE SYS$OUTPUT "Could not find file: "+GOBJ1_FILE
$      GOBJ1_FILE = "none"
$!     EXIT
$    ENDIF
$  ENDIF
$  SHOW SYM GOBJ1_FILE
$!
$  IF (p5 .EQS. "")
$  THEN
$    WRITE SYS$OUTPUT "Warning. No GOBJ mask for followup image defined."
$    WRITE SYS$OUTPUT "  Registration will proceed for entire reference image."
$    GOBJ2_FILE = "none"
$  ELSE
$    GOBJ2_FILE = p5
$    IF (F$SEARCH(GOBJ2_FILE) .NES. "")
$    THEN
$!      ok
$    ELSE
$      WRITE SYS$OUTPUT "Could not find file: "+GOBJ2_FILE
$      GOBJ2_FILE = "none"
$!      EXIT
$    ENDIF
$  ENDIF
$  SHOW SYM GOBJ2_FILE
$!
$! read the headers of the 2 input files to check if the images were segmented
$!
$ IN1_FILE_TYPE= 0
$ OPEN/READ TMPFILE 'p1'     ! open/close/open file
$ CLOSE TMPFILE              ! to rewind it
$ OPEN/READ TMPFILE 'p1'
$ READ/END_OF_FILE=END_SEARCH_FILE1 TMPFILE RECORD1
$ NREC= 1
$ SEARCH_FILE1:
$   READ/END_OF_FILE=END_SEARCH_FILE1 TMPFILE RECORD2
$   RECORD= RECORD1+RECORD2
$   NREC= NREC+1
$   IF (F$LOCATE("Thres",RECORD) .LT. F$LENGTH(RECORD))
$   THEN
$      WRITE SYS$OUTPUT "First aim file is segmented"
$      IN1_FILE_TYPE=1
$      GOTO END_SEARCH_FILE1
$   ENDIF
$   RECORD1= RECORD2
$ IF (NREC.LT.10) THEN GOTO SEARCH_FILE1
$ WRITE SYS$OUTPUT "First aim file is unsegmented"
$ END_SEARCH_FILE1:
$ CLOSE TMPFILE
$
$ IN2_FILE_TYPE= 0
$ OPEN/READ TMPFILE 'p2'     ! open/close/open file
$ CLOSE TMPFILE              ! to rewind it
$ OPEN/READ TMPFILE 'p2'
$ READ/END_OF_FILE=END_SEARCH_FILE2 TMPFILE RECORD1
$ NREC= 1
$ SEARCH_FILE2:
$   READ/END_OF_FILE=END_SEARCH_FILE2 TMPFILE RECORD2
$   RECORD= RECORD1+RECORD2
$   NREC= NREC+1
$   IF (F$LOCATE("Thres",RECORD) .LT. F$LENGTH(RECORD))
$   THEN
$      WRITE SYS$OUTPUT "Second aim file is segmented"
$      IN2_FILE_TYPE=1
$      GOTO END_SEARCH_FILE2
$   ENDIF
$   RECORD1= RECORD2
$ IF (NREC.LT.10) THEN GOTO SEARCH_FILE2
$ WRITE SYS$OUTPUT "Second aim file is unsegmented"
$ END_SEARCH_FILE2:
$ CLOSE TMPFILE
$!
$ IF (IN1_FILE_TYPE.EQS.0 .and. IN2_FILE_TYPE.EQS.0)
$ THEN
$!   both images are unsegmented. No need to change anything
$ ELSE
$    IF (IN1_FILE_TYPE.EQS.1 .and. IN2_FILE_TYPE.EQS.1)
$    THEN
$    WRITE SYS$OUTPUT "Both files are segmented"
$!      redefine the filtering values:
$       SIGMA_GAUSS    := 0
$       SUPPORT_GAUSS  := 0
$       THRESHOLD_SEG  := 500
$    ELSE
$       WRITE SYS$OUTPUT "ERROR: a mix of segmented and unsegmented images is not allowed"
$       EXIT
$    ENDIF
$ ENDIF
$!
$! Determine the element size for both input files
$!
$ PIPE AIX 'IN1_FILE' | SEARCH SYS$INPUT "element size in mm" | -
  (READ SYS$INPUT line ; DEFINE/JOB line_log &line)
$ line_sym = F$TRNLNM("line_log")
$ line_sym = F$EDIT(line_sym,"TRIM,COMPRESS")
$ IN1_FILE_ELSIZE = line_sym - "!> element size in mm "
$ DEASSIGN/JOB line_log
$!
$ PIPE AIX 'IN2_FILE' | SEARCH SYS$INPUT "element size in mm" | -
  (READ SYS$INPUT line ; DEFINE/JOB line_log &line)
$ line_sym = F$TRNLNM("line_log")
$ line_sym = F$EDIT(line_sym,"TRIM,COMPRESS")
$ IN2_FILE_ELSIZE = line_sym - "!> element size in mm "
$ DEASSIGN/JOB line_log
$!
$!==============================================================================
$!                            Start of IPL script
$!==============================================================================
$!
$!  ipl_scanco_prog := $um:ipl_scanco_fe.exe
$  ipl_scanco_prog = IPLREG_BATCH
$!
$  ON ERROR THEN EXIT
$!
$! *** Step 1 ***
$! GOTO REGISTER_STEP
$! GOTO STEP2A
$!
$! *** Step 2 ***
$! GOTO CREATE_COMMON_MASKS_STEP
$! GOTO SPECIAL
$!
$! *** Step 3 ***
$! GOTO CREATE_PERIOSTEAL_MASKS_STEP
$!
$! *** Step 4: Autocontour masks ***
$! GOTO CREATE_TRAB_MASKS_STEP
$! GOTO CREATE_CRTX_MASKS_STEP
$! GOTO CREATE_CRTXPO_MASKS_STEP
$! GOTO CREATE_AUTO2_MASKS_STEP
$! GOTO CREATE_FWD_MASKS_STEP
$!
$!
$REGISTER_STEP:
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

!!==============================================================================
!!Pre-processing
!!==============================================================================

!read in Images

/read
  -name                      in1
  -filename                  "IN1_FILE

/read
  -name                       in2
  -filename                   "IN2_FILE

! read in and dilate dstmasks of  to use for cropping

/read
  -name                      mask1
  -filename                  "IN1_MASK_FILE

/read
  -name                       mask2
  -filename                   "IN2_MASK_FILE

/dilation
  -input                     mask1
  -output                    dil_mask1
  -dilate_distance           5
  -continuous_at_boundary    0 0 0
  -use_previous_margin       false
  -metric                    101

/write_v020
  -name                      dil_mask1
  -filename                  "DIL_MASK1
  -compress_type             bin
  -version_020               true

/dilation
  -input                     mask2
  -output                    dil_mask2
  -dilate_distance           5
  -continuous_at_boundary    0 0 0
  -use_previous_margin       false
  -metric                    101

/write_v020
  -name                      dil_mask2
  -filename                  "DIL_MASK2
  -compress_type             bin
  -version_020               true

! crop the phalange bone using the dst gobj file

/gobj_maskaimpeel_ow
  -input_output              in1
  -gobj_filename             "DIL_MASK1
  -peel_iter                 -1

/write_v020
  -name                      in1
  -filename                  "META1_FILE
  -compress_type             bin
  -version_020               true

/read
  -name                      in2
  -filename                  "IN2_FILE

/gobj_maskaimpeel_ow
  -input_output              in2
  -gobj_filename             "DIL_MASK2
  -peel_iter                 -1

/write_v020
  -name                      in2
  -filename                  "META2_FILE
  -compress_type             bin
  -version_020               true

!!==============================================================================
!!Step 1: IMAGE REGISTRATION STEP
!!==============================================================================


/register
  -in1                        in1
  -gobj_filename_in1          "GOBJ1_FILE
  -in2                        in2
  -gobj_filename_in2          "GOBJ2_FILE
  -Tmat_file_name             "REG_FILE
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

/transform
  -in                         in2
  -out                        out
  -Tmat_file_name             "REG_FILE
  -img_interpol_option        1                  ! linear interpolation
  -el_size_mm_out             "IN1_FILE_ELSIZE   ! 0.082 0.082 0.082
  -Tmat_invert                false

!/del in2

! segment the baseline image; set value to 41 (redish in 3D viewer)

/sup
  -input                      in1
  -supdim_numbers             4 4 1
  -testoff_pixels             "SUPPORT_GAUSS
  -suppos_pixels_local        -1 -1 -1
  -subdim_pixels              -1 -1 -1

/seg_gauss
  -input                      in1
  -output                     in1_seg
  -sigma                      "SIGMA_GAUSS
  -support                    "SUPPORT_GAUSS
  -lower_in_perm              "THRESHOLD_SEG
  -upper_in_perm              3000
  -value_in_range             "COLOUR1
  -unit                       "THRESHOLD_UNIT

/del in1

! segment the transformed follow-up image; set value to 82 (greenish)

/sup
  -input                      out
  -supdim_numbers             4 4 1
  -testoff_pixels             "SUPPORT_GAUSS
  -suppos_pixels_local        -1 -1 -1
  -subdim_pixels              -1 -1 -1

/seg_gauss
  -input                      out
  -output                     out_seg
  -sigma                      "SIGMA_GAUSS
  -support                    "SUPPORT_GAUSS
  -lower_in_perm              "THRESHOLD_SEG
  -upper_in_perm              3000
  -value_in_range             "COLOUR2
  -unit                       "THRESHOLD_UNIT

/del out

! add the segmented images; common regions will get a value of 123 (blueish)

/concat
  -input1                     in1_seg
  -input2                     out_seg
  -output                     comb
  -common_region_only         false
  -add_not_overlay            true
  -make_edge                  false
  -shift_ofin2                0 0 0
  -turnangle                  0.0
  -turnpoint_global           -1 -1

/write comb "COMBI_FILE

..
$!  WRITE SYS$OUTPUT "Registered version of image: "+IN2_FILE+" is written to file: "+REG_FILE
$  WRITE SYS$OUTPUT "An overlay test image is written to file: "+COMBI_FILE
$!
$!
$ WRITE SYS$OUTPUT "Create TIFs of registered 3D volume for visualization
$ @COM:PRINT_REG_TIF.COM 'COMBI_FILE'
$!
$!
$!
$!==============================================================================
$! End Step 1
$!==============================================================================
$!
$!
$!
$!==============================================================================
$! Step 2A: Transform moving image into fixed image space
$!!!might still need to crop out slices that didn't align
$!==============================================================================
$ STEP2A:
$ ipl_scanco_prog

/read pp2 "META2_FILE

/transform
  -in                         pp2
  -out                        out
  -Tmat_file_name             "REG_FILE
  -img_interpol_option        2                  ! cubic interpolation because we will used transformed grey-scale image for analysis
  -el_size_mm_out             "IN1_FILE_ELSIZE   ! 0.082 0.082 0.082
  -Tmat_invert                false

!!write out transformed grey scale image with only slices that align with baseline
/write		out				  "IN2_ROT

/gobj_to_aim
  -gobj_filename             "GOBJ2_FILE
  -output                    in
  -peel_iter                 0

/transform
  -in                         in
  -out                        out
  -Tmat_file_name             "REG_FILE
  -img_interpol_option        0                  ! nearest-neighbour transformation for mask
  -el_size_mm_out             "IN1_FILE_ELSIZE   ! 0.082 0.082 0.082
  -Tmat_invert                false

!!write out transformed grey scale image with only slices that align with baseline
/togobj_from_aim
  -input                     out
  -gobj_filename             "MOVING_GOBJ_ROT
  -min_elements              0
  -max_elements              0
  -curvature_smooth          1
..
$
$!
$!==============================================================================
$! Step 2: Create common regions of interest for fixed and moving space.
$!==============================================================================
$!
$CREATE_COMMON_MASKS_STEP:
$!
$!
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

/read
  -name                       pp1
  -filename                   "META1_FILE

/norm_max
  -input                      pp1
  -output                     mask1
  -max                        127
  -type_out                   char     ! The input may be type 'short', but we need 'char'

/set_value
  -input                      mask1
  -value_object               "COLOUR1
  -value_background           "COLOUR1

/delete                       pp1

/read
  -name                       pp2
  -filename                   "META2_FILE

/norm_max
  -input                      pp2
  -output                     mask2
  -max                        127
  -type_out                   char

/set_value
  -input                      mask2
  -value_object               "COLOUR2
  -value_background           "COLOUR2

/delete                       rot

! First create the common mask for the fixed image space.
! (We transform the moving image into the fixed image space.)

/transform
  -in                         mask2
  -out                        mask2_rot
  -Tmat_file_name             "REG_FILE
  -img_interpol_option        0                   !  nearest neighbour
  -el_size_mm_out             "IN1_FILE_ELSIZE   ! 0.082 0.082 0.082
  -Tmat_invert                false

/concat
  -input1                     mask1
  -input2                     mask2_rot
  -output                     comb
  -common_region_only         false
  -add_not_overlay            true      ! common region adds to 41+82=123
  -make_edge                  false
  -shift_ofin2                0 0 0
  -turnangle                  0.0
  -turnpoint_global           -1 -1

/threshold
  -input                      comb
  -output                     seg
  -lower_in_perm_aut_al       "THRESHOLD_LOW   ! gets rid of values less than 41+82=123 (i.e. not union)
  -upper_in_perm_aut_al       100000
  -value_in_range             127
  -unit                       5         ! native units

/delete comb

/write seg "FIXED_COMMON_MASK 			! For use in creating cort&trab gobjs

..
$! Start IPL again to create the moving mask.
$! EXIT
$IP:
$ ON ERROR THEN EXIT
$!
$  ipl_scanco_prog

/read fixed_mask "FIXED_COMMON_MASK

! Second, the common mask for the moving image, so we simply
! transform it into the moving image space.

/transform
  -in                         fixed_mask
  -out                        seg_rot
  -Tmat_file_name             "REG_FILE
  -img_interpol_option        0                   ! nearest neighbour
  -el_size_mm_out             "IN2_FILE_ELSIZE    ! 0.0607 0.0607 0.0607
  -Tmat_invert                true

/write seg_rot "MOVING_COMMON_MASK  		! For use in creating cort&trab gobjs

/delete seg_rot
/delete fixed_mask
..
$!
$
$ !EXIT
$
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$  WRITE SYS$OUTPUT "Common region mask created for fixed and moving images."
$  WRITE SYS$OUTPUT "  Fixed Common Mask:  " + FIXED_COMMON_MASK
$  WRITE SYS$OUTPUT "  Moving Common Mask: " + MOVING_COMMON_MASK
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$!
$!==============================================================================
$! Step 3: For each periosteal mask that can be found, create clipped versions.
$!==============================================================================
$!
$CREATE_PERIOSTEAL_MASKS_STEP:
$!
$  ON ERROR THEN EXIT
$!
$! Check if we have full (periosteal) gobj available
$!
$  IF (p4 .EQS. "")
$  THEN
$    WRITE SYS$OUTPUT "No baseline GOBJ file defined. Masks will not be generated."
$    EXIT
$  ELSE
$    GOBJ1_FILE = p4
$    IF (F$SEARCH(GOBJ1_FILE) .NES. "")
$    THEN
$!      ok
$    ELSE
$      WRITE SYS$OUTPUT "Could not find file: "+GOBJ1_FILE
$      EXIT
$    ENDIF
$  ENDIF
$  SHOW SYM GOBJ1_FILE
$!
$  IF (p5 .EQS. "")
$  THEN
$    WRITE SYS$OUTPUT "No followup GOBJ file defined. Masks will not be generated."
$    EXIT
$  ELSE
$    GOBJ2_FILE = p5
$    IF (F$SEARCH(GOBJ2_FILE) .NES. "")
$    THEN
$!      ok
$    ELSE
$      WRITE SYS$OUTPUT "Could not find file: "+GOBJ2_FILE
$      EXIT
$    ENDIF
$  ENDIF
$  SHOW SYM GOBJ2_FILE
$!
$!
$!
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

!!==============================================================================
!! Create the fixed and moving periosteal masks using registration output.
!! These are masks based on the standard GOBJ files that are manually created
!! and not the autosegmentation masks (i.e. AUTO2)
!!==============================================================================

/read seg "FIXED_COMMON_MASK

/gobj_maskaimpeel_ow
  -input_output               seg
  -gobj_filename              "GOBJ1_FILE
  -peel_iter                  1   ! This is because using 0 we get a % overlap
                                  ! over 100% so the baseline must have been
                                  ! peeled using 1
/bounding_box_cut
  -input                      seg
  -output                     mask

/togobj_from_aim
  -input    		      mask               ! write gobj file from mask
  -gobj_filename 	      "FIXED_GOBJ

/delete seg
/delete mask


/read seg "MOVING_COMMON_MASK

/gobj_maskaimpeel_ow
  -input_output               seg
  -gobj_filename              "GOBJ2_FILE
  -peel_iter                  1   ! This is because using 0 we get a % overlap
                                  ! over 100% so the baseline must have been
                                  ! peeled using 1

/bounding_box_cut
  -input                      seg
  -output                     mask
  -z_only                     false

/togobj_from_aim
  -input    		      mask
  -gobj_filename 	      "MOVING_GOBJ

/delete seg
/delete mask
..
$ EXIT
$!
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$  WRITE SYS$OUTPUT "Common region GOBJ mask created for fixed and moving images."
$  WRITE SYS$OUTPUT "  Fixed Full gobj:  " + FIXED_GOBJ
$  WRITE SYS$OUTPUT "  Moving Full gobj: " + MOVING_GOBJ
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$ EXIT
$!
$!==============================================================================
$! The next sections use the common region blocks defined for the fixed and moving
$! spaces from the registration. They are applied to the autosegmentation masks
$! that were generated independently for the fixed and moving images. The four
$! masks are:
$! _TRAB.GOBJ:   The endosteal surface of the bone."
$! _CRTX.GOBJ:   The mask created by combining _AUTO2.GOBJ and _TRAB.GOBJ above."
$! _CRTXPO.GOBJ: The 'refined' _CRTX.GOBJ mask that removes marrow space regions."
$! _AUTO2.GOBJ:  The periosteal surface of the bone."
$! This section generates eight output masks (fixed and moving for each of the
$! four above).
$!==============================================================================
$!
$!==============================================================================
$! Step 4.1: Create the trabecular (TRAB) masks
$!==============================================================================
$CREATE_TRAB_MASKS_STEP:
$!
$! Check if we have trabecular gobj available for CREATE_TRAB_MASKS_STEP
$!
$  IF (F$SEARCH (GOBJ1_TRAB_FILE) .NES. "")
$  THEN
$     SHOW SYM GOBJ1_TRAB_FILE
$  ELSE
$     WRITE SYS$OUTPUT "Could not find file: "+GOBJ1_TRAB_FILE
$     GOTO  CREATE_CRTX_MASKS_STEP
$  ENDIF
$!
$  IF (F$SEARCH(GOBJ2_TRAB_FILE) .NES. "")
$  THEN
$     SHOW SYM GOBJ2_TRAB_FILE
$  ELSE
$     WRITE SYS$OUTPUT "Could not find file: "+GOBJ2_CORT_FILE
$     GOTO CREATE_CRTX_MASKS_STEP
$  ENDIF
$!
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

! Create gobj for fixed trabecular mask
/read
  -name                       seg
  -filename                   "FIXED_COMMON_MASK

/gobj_maskaimpeel_ow
  -input_output               seg
  -gobj_filename              "GOBJ1_TRAB_FILE

/bounding_box_cut
  -input                      seg
  -output                     mask
  -z_only                     false

/togobj_from_aim
  -input    		      mask
  -gobj_filename 	      "FIXED_TRAB_GOBJ

/delete seg
/delete mask

! Create gobj for moving trabecular mask
/read
  -name                       seg
  -filename                   "MOVING_COMMON_MASK

/gobj_maskaimpeel_ow
  -input_output               seg
  -gobj_filename              "GOBJ2_TRAB_FILE

/bounding_box_cut
  -input                      seg
  -output                     mask
  -z_only                     true

/togobj_from_aim
  -input    		      mask
  -gobj_filename 	      "MOVING_TRAB_GOBJ

/delete seg
/delete mask
..
$!
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$  WRITE SYS$OUTPUT "Common region GOBJ mask created for fixed and moving images."
$  WRITE SYS$OUTPUT "  Fixed Trab gobj:  " + FIXED_TRAB_GOBJ
$  WRITE SYS$OUTPUT "  Moving Trab gobj: " + MOVING_TRAB_GOBJ
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$!
$!
$!==============================================================================
$! Step 4.2: Create the cortical (CRTX) masks
$!==============================================================================
$CREATE_CRTX_MASKS_STEP:
$!
$! Check if we have cortical gobj available for CREATE_CRTX_MASKS_STEP
$
$  IF (F$SEARCH (GOBJ1_CORT_FILE) .NES. "")
$  THEN
$     SHOW SYM GOBJ1_CORT_FILE
$  ELSE
$     WRITE SYS$OUTPUT "Could not find file: "+GOBJ1_CORT_FILE
$     GOTO  CREATE_CRTXPO_MASKS_STEP
$  ENDIF
$!
$  IF (F$SEARCH(GOBJ2_CORT_FILE) .NES. "")
$  THEN
$     SHOW SYM GOBJ2_CORT_FILE
$  ELSE
$     WRITE SYS$OUTPUT "Could not find file: "+GOBJ2_CORT_FILE
$     GOTO CREATE_CRTXPO_MASKS_STEP
$  ENDIF
$!
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

!First write fixed gobj for cortical

/read
  -name                       seg
  -filename                   "FIXED_COMMON_MASK

/gobj_maskaimpeel_ow
  -input_output               seg
  -gobj_filename              "GOBJ1_CORT_FILE

/bounding_box_cut
  -input                      seg
  -output                     mask
  -z_only                     false

/togobj_from_aim
  -input    		      mask
  -gobj_filename 	      "FIXED_CRTX_GOBJ

/delete seg
/delete mask

! Create gobj for moving cortical mask
/read
  -name                       seg
  -filename                   "MOVING_COMMON_MASK

/gobj_maskaimpeel_ow
  -input_output               seg
  -gobj_filename              "GOBJ2_CORT_FILE

/bounding_box_cut
  -input                      seg
  -output                     mask
  -z_only                     true

/togobj_from_aim
  -input    		      mask
  -gobj_filename 	      "MOVING_CRTX_GOBJ

/delete seg
/delete mask
..
$!
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$  WRITE SYS$OUTPUT "Common region GOBJ mask created for fixed and moving images."
$  WRITE SYS$OUTPUT "  Fixed cort gobj:  " + FIXED_CRTX_GOBJ
$  WRITE SYS$OUTPUT "  Moving cort gobj: " + MOVING_CRTX_GOBJ
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$!
$!
$!==============================================================================
$! Step 4.3: Create the cortical porosity (CRTXPO) masks
$!==============================================================================
$CREATE_CRTXPO_MASKS_STEP:
$!
$! Check if we have cortical porosity gobj available for CREAT_CORTPO_MASKS_STEP
$
$  IF (F$SEARCH (GOBJ1_CRTXPO_FILE) .NES. "")
$  THEN
$     SHOW SYM GOBJ1_CRTXPO_FILE
$  ELSE
$     WRITE SYS$OUTPUT "Could not find file: "+GOBJ1_CRTXPO_FILE
$     GOTO CREATE_AUTO2_MASKS_STEP
$  ENDIF
$!
$  IF (F$SEARCH(GOBJ2_CRTXPO_FILE) .NES. "")
$  THEN
$     SHOW SYM GOBJ2_CRTXPO_FILE
$  ELSE
$     WRITE SYS$OUTPUT "Could not find file: "+GOBJ2_CRTXPO_FILE
$     GOTO CREATE_AUTO2_MASKS_STEP
$  ENDIF
$!
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

! First write fixed gobj for cortical porosity

/read
  -name                       seg
  -filename                   "FIXED_COMMON_MASK

/gobj_maskaimpeel_ow
  -input_output               seg
  -gobj_filename              "GOBJ1_CRTXPO_FILE

/bounding_box_cut
  -input                      seg
  -output                     mask
  -z_only                     false

/togobj_from_aim
  -input    		      mask
  -gobj_filename 	      "FIXED_CRTXPO_GOBJ

/delete seg
/delete mask

! Create gobj for moving cortical porosity mask

/read
  -name                       seg
  -filename                   "MOVING_COMMON_MASK

/gobj_maskaimpeel_ow
  -input_output               seg
  -gobj_filename              "GOBJ2_CRTXPO_FILE

/bounding_box_cut
  -input                      seg
  -output                     mask
  -z_only                     true

/togobj_from_aim
  -input    		      mask
  -gobj_filename 	      "MOVING_CRTXPO_GOBJ

/delete seg
/delete mask
..
$!
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$  WRITE SYS$OUTPUT "Common region GOBJ mask created for fixed and moving images."
$  WRITE SYS$OUTPUT "  Fixed cortical porosity gobj:  " + FIXED_CRTXPO_GOBJ
$  WRITE SYS$OUTPUT "  Moving cortical porosity gobj: " + MOVING_CRTXPO_GOBJ
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$!
$!
$!==============================================================================
$! Step 4.4: Create the periosteal (AUTO2) masks
$!==============================================================================
$CREATE_AUTO2_MASKS_STEP:
$!
$! Check if we have auto gobj available for CREATE_AUTO2_MASKS_STEP
$
$  IF (F$SEARCH (GOBJ1_AUTO2_FILE) .NES. "")
$  THEN
$     SHOW SYM GOBJ1_AUTO2_FILE
$  ELSE
$     WRITE SYS$OUTPUT "Could not find file: "+GOBJ1_AUTO2_FILE
$     GOTO CLEANUP
$  ENDIF
$!
$  IF (F$SEARCH(GOBJ2_AUTO2_FILE) .NES. "")
$  THEN
$     SHOW SYM GOBJ2_AUTO2_FILE
$  ELSE
$     WRITE SYS$OUTPUT "Could not find file: "+GOBJ2_AUTO2_FILE
$     GOTO CLEANUP
$  ENDIF
$!
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

! First write fixed gobj for auto2

/read
  -name                       seg
  -filename                   "FIXED_COMMON_MASK

/gobj_maskaimpeel_ow
  -input_output               seg
  -gobj_filename              "GOBJ1_AUTO2_FILE

/bounding_box_cut
  -input                      seg
  -output                     mask
  -z_only                     false

/togobj_from_aim
  -input    		      mask
  -gobj_filename 	      "FIXED_AUTO2_GOBJ

/delete seg
/delete mask

! Create gobj for moving auto2 mask
/read
  -name                       seg
  -filename                   "MOVING_COMMON_MASK

/gobj_maskaimpeel_ow
  -input_output               seg
  -gobj_filename              "GOBJ2_AUTO2_FILE

/bounding_box_cut
  -input                      seg
  -output                     mask
  -z_only                     true

/togobj_from_aim
  -input    		      mask
  -gobj_filename 	      "MOVING_AUTO2_GOBJ

/delete seg
/delete mask
..
$!
$!
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$  WRITE SYS$OUTPUT "Common region GOBJ mask created for fixed and moving images."
$  WRITE SYS$OUTPUT "  Fixed auto gobj:  " + FIXED_AUTO2_GOBJ
$  WRITE SYS$OUTPUT "  Moving auto gobj: " + MOVING_AUTO2_GOBJ
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$!
$!
$!==============================================================================
$! Step 4.5: Create the FORWARD masks
$!
$! Create all of the masks in the moving space by simply transforming forward
$! the baseline masks into the follow-up space. This is done in the following
$! steps:
$! 1. The TRAB mask is copied from baseline, and transformed to the followup
$!    space. It is expected that the endocortical margin has probably changed
$!    in followup from baseline.
$! 2. The AUTO2 mask is simply a copy of the moving image AUTO2 mask. We ensure
$!    the periosteal surface is fully captured this way.
$! 3. The CRTX mask is generated by the subtraction of the two masks above, and
$!    represents the cortical envelope, almost identically to how it was defined
$!    at baseline.
$! 4. The CRTXPO mask takes the moving CRTXPO mask, fills it in and the carves
$!    out the TRAB region that came from #1 above.
$!
$! This section generates four output masks.
$!==============================================================================
$CREATE_FWD_MASKS_STEP:
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

! TRAB mask
! Create forward gobj for moving image from the fixed gobj that is transformed
! forward. Read in the GOBJ1_TRAB_FILE, transform it forward, then write it as
! the MOVING_FWD_TRAB_GOBJ.
! Note that we don't need to clip by the MOVING_COMMON_MASK because
! theoretically the TRAB mask we are transforming forward already conforms to
! the moving space and was previously clipped.

/gobj_to_aim
  -gobj_filename              "FIXED_TRAB_GOBJ
  -output                     mask
  -peel_iter                  0

/transform                    ! into moving image space
  -in                         mask
  -out                        mask_rot
  -Tmat_file_name             "REG_FILE
  -img_interpol_option        0                   !  nearest neighbour
  -el_size_mm_out             "IN2_FILE_ELSIZE    !  0.0607 0.0607 0.0607
  -Tmat_invert                true

/togobj_from_aim mask_rot "MOVING_FWD_TRAB_GOBJ

!/write mask_rot "TRAB  ! For debugging

/delete mask
/delete mask_rot

..
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

! AUTO2 mask
! This is simply a copy of the moving AUTO2 gobj from registration because
! we want to ensure our periosteal mask fits to the moving cortex perfectly.

/gobj_to_aim
  -gobj_filename              "MOVING_AUTO2_GOBJ
  -output                     mask
  -peel_iter                  0

/togobj_from_aim mask "MOVING_FWD_AUTO2_GOBJ

!/write mask "AUTO2  ! For debugging

/delete mask

..
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

! CRTX mask
! This is done by reading the auto2 mask from the moving image
! and subtracting the trab mask forwarded from the fixed image.
! Sometimes the trab mask is bigger than the auto2 mask, so we
! remove that part of the mask by thresholding -127 values.

/gobj_to_aim
  -gobj_filename              "MOVING_AUTO2_GOBJ
  -output                     cort
  -peel_iter                  0

/gobj_to_aim
  -gobj_filename              "MOVING_FWD_TRAB_GOBJ
  -output                     trab
  -peel_iter                  0

/subtract_aims
  -input1                     cort
  -input2                     trab
  -output                     diff

/threshold                    ! trab ROI can expand beyond cort ROI, resulting in negative numbers
  -input                      diff
  -output                     crtx
  -lower_in_perm_aut_al       127
  -upper_in_perm_aut_al       100000
  -value_in_range             127
  -unit                       5         ! native units

/togobj_from_aim crtx "MOVING_FWD_CRTX_GOBJ

!/write crtx "CRTX ! For debugging

/delete cort
/delete trab
/delete out

..
$ ON ERROR THEN EXIT
$  ipl_scanco_prog

! CRTXPO mask
! This is done by reading the crtxpo mask from the moving image
! filling it in so that the trabecular region is solid, then
! subtracting the forwarded trab mask. Again, we remove any
! -127 values that are due to the trab mask being bigger than
! the cortical mask.

/gobj_to_aim
  -gobj_filename              "MOVING_CRTXPO_GOBJ
  -output                     cort
  -peel_iter                  0

/gobj_to_aim
  -gobj_filename              "MOVING_TRAB_GOBJ
  -output                     trab
  -peel_iter                  0

/add_aims
  -input1                     cort
  -input2                     trab
  -output                     sum

/set_value
  -input                     sum
  -value_object              0
  -value_background          127

/cl_slicewise_extractow
  -input_output              sum
  -lo_vol_fract_in_perc      2.0
  -up_vol_fract_in_perc      100.0
  -value_in_range            127

/set_value
  -input                     sum
  -value_object              0
  -value_background          127

/gobj_to_aim
  -gobj_filename              "MOVING_FWD_TRAB_GOBJ
  -output                     trab_fwd
  -peel_iter                  0

/subtract_aims
  -input1                     sum
  -input2                     trab_fwd
  -output                     diff

/threshold                    ! trab ROI can expand beyond cort ROI, resulting in negative numbers
  -input                      diff
  -output                     crtxpo
  -lower_in_perm_aut_al       127
  -upper_in_perm_aut_al       100000
  -value_in_range             127
  -unit                       5         ! native units

/togobj_from_aim crtxpo "MOVING_FWD_CRTXPO_GOBJ

!/write crtxpo "CRTXPO ! For debugging

/delete cort
/delete trab
/delete sum
/delete trab_fwd
/delete diff
/delete crtxpo

..
$!
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$  WRITE SYS$OUTPUT "Forward transform GOBJ masks created for moving images."
$  WRITE SYS$OUTPUT "  Forward moving trab gobj: " + MOVING_FWD_TRAB_GOBJ
$  WRITE SYS$OUTPUT "  Forward moving auto2 gobj: " + MOVING_FWD_AUTO2_GOBJ
$  WRITE SYS$OUTPUT "  Forward moving crtx gobj: " + MOVING_FWD_CRTX_GOBJ
$  WRITE SYS$OUTPUT "  Forward moving crtxpo gobj: " + MOVING_FWD_CRTXPO_GOBJ
$  WRITE SYS$OUTPUT "------------------------------------------------------------"
$GOTO CLEANUP
$!
$!
$!
$!==============================================================================
$! Delete temporary files and clean up
$!==============================================================================
$CLEANUP:
$! NOTE: These two 'common' masks are useful if we want to register more than two images
$!       eventually. We would want the masks for each pair of registered images
$!       and then find the common mask for all pairs of registered images and
$!       use those for analyses.
$! DELETE 'FIXED_COMMON_MASK';*
$! DELETE 'MOVING_COMMON_MASK';*
$! DELETE 'FIXED_GOBJ';*
$! DELETE 'MOVING_GOBJ';*
$!
$ EXIT
