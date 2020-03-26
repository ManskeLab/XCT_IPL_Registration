$!!=============================================================
$!! BONE_REMODELLING.COM
$!! For RAMHA study, after registration (REGISTER_LONGITUDINAL.COM)
$!! Make difference image after (followup - baseline) from grey-scale images (DIF.AIM)
$!! 2019-05 Scott Brunet
$!!Utilized in Brunet et al. BMC Med Imaging doi: 10.21203/rs.2.14575/v1
$!!=============================================================
$!!=============================================================
$!! Inputs
$!!=============================================================
$
$  SIGMA_GAUSS    := 1.2
$  SUPPORT_GAUSS  := 2
$  THRESHOLD_SEG  := 125 !CONFIRM THIS THRESHOLD!!! !value from paper is 225
$  THRESHOLD_UNIT := 2	 !mg HA/cm
$!
$! thresh for mu_scaling 8192
$  trab_threshold       := 200
$  cl_nr_min            := 5
$
$  COLOUR1        := 11 !PURPLE
$  COLOUR2        := 10  !GREEN
$  COLOUR3		  := 9  !RED
$  NSLICES		  := 40	 !to be included in analysis of difference image
$  OFFSET		  := 5	 !slices between 'tip' of phalanx and start of analysis region
$
$  DEV               = F$PARSE("''p1'",,,"DEVICE")
$  DIR_READ          = F$PARSE("''p1'",,,"DIRECTORY")
$  DIR_GOBJ          = F$PARSE("''p4'",,,"DIRECTORY")
$  FILENAME1         = F$PARSE("''p1'",,,"NAME")
$  FILENAME2         = F$PARSE("''p2'",,,"NAME")
$  FILENAME3         = F$PARSE("''p3'",,,"NAME")
$  FILENAME4         = F$PARSE("''p4'",,,"NAME")
$
$  IN1_FILE          := 'DEV''DIR_READ''FILENAME1'.AIM
$  IN2_FILE          := 'DEV''DIR_READ''FILENAME2'.AIM
$  IN1_GOBJ			     := 'DEV''DIR_GOBJ''FILENAME4'.GOBJ
$  IN2_GOBJ			     := 'DEV''DIR_READ''FILENAME2'.GOBJ
$  COMMON_GOBJ			 := 'DEV''DIR_READ''FILENAME1'_COMMON_REG_ALL.AIM
$
$
$! EXTRACT DETAILS FROM FILENAME
$ STUDY		=	F$EXTRACT(0,3,FILENAME1)
$ STUDYID	=	F$EXTRACT(5,2,FILENAME1)
$ JOINT		=	F$EXTRACT(16,3,FILENAME1)
$ EXT		=	F$EXTRACT(20,6,FILENAME1)
$! FOR BOTH TIMEPOINTS
$ TIME1		=	F$EXTRACT(8,4,FILENAME1)
$ REV1		=	F$EXTRACT(13,2, FILENAME1)
$ SHORTTIME1 = 	TIME1 - "O"
$ TIME2		=	F$EXTRACT(8,4,FILENAME2)
$ REV2		=	F$EXTRACT(13,2, FILENAME2)
$ SHORTTIME2 = 	TIME2 - "O"
$!
$!!=============================================================
$!! Outputs
$!!=============================================================
$  DIF_FILE	    	  := 'DEV''DIR_READ''FILENAME3'_DIF.AIM
$  DIF_MASK			  := 'DEV''DIR_READ''FILENAME3'_DIF_MASK.AIM
$  COMBI_FILE		      := 'DEV''DIR_READ''FILENAME3'_ADD_SEG.AIM
$  FORM_FILE	      := 'DEV''DIR_READ''FILENAME3'_FORMATION.AIM
$  RESORB_FILE	      := 'DEV''DIR_READ''FILENAME3'_RESORPTION.AIM
$
$
$ SHOW SYM IN1_FILE
$ SHOW SYM IN2_FILE
$ SHOW SYM IN1_GOBJ
$ SHOW SYM IN2_GOBJ
$
$! GOTO SUB
$! GOTO RESORPTION
$
$ ON ERROR THEN CONTINUE
$
$ ipl_batch

/read
  -name                      in1
  -filename                  "IN1_FILE

!is this step necassary
/gobj_maskaimpeel_ow
  -input_output              in1
  -gobj_filename             "IN1_GOBJ
  -peel_iter                 0

/read
  -name                      in2
  -filename                  "IN2_FILE

/gobj_maskaimpeel_ow
  -input_output              in2
  -gobj_filename             "IN2_GOBJ
  -peel_iter                 0

! subtract BL image from FU image to represent bone gain

/subtract_aims
  -input1                    in2
  -input2                    in1
  -output                    gain

!XT2 segmentation for 'gain' image

/gobj_maskaimpeel_ow
  -input_output              gain
  -gobj_filename             "COMMON_GOBJ
  -peel_iter                 0

/threshold
  -input                     gain
  -output                    gain2
  -lower_in_perm_aut_al      "THRESHOLD_SEG
  -upper_in_perm_aut_al      100000.000000
  -value_in_range            127
  -unit                      2

/gobj_maskaimpeel_ow
  -input_output              gain2
  -gobj_filename             "COMMON_GOBJ
  -peel_iter                 0

/cl_nr_extract
  -input                     gain2
  -output                    gain3
  -min_number                "cl_nr_min
  -max_number                0
  -value_in_range            127

/set_value
  -input                     gain3
  -value_object              "COLOUR2
  -value_background

/write_v020
  -name                      gain3
  -filename                  "FORM_FILE
  -compress_type             bin
  -version_020               true

/voxgobj_scanco_param
  -input                     gain3
  -gobj_filename             "IN1_GOBJ
  -peel_iter                 1
  -region_number             0

! subtract FU image from BL image to represent bone loss

/subtract_aims
  -input1                    in1
  -input2                    in2
  -output                    loss

/gobj_maskaimpeel_ow
  -input_output              loss
  -gobj_filename             "COMMON_GOBJ
  -peel_iter                 0


!XT2 segmentation for 'loss' image

/threshold
  -input                     loss
  -output                    loss2
  -lower_in_perm_aut_al      "THRESHOLD_SEG
  -upper_in_perm_aut_al      100000.000000
  -value_in_range            127
  -unit                      2

/gobj_maskaimpeel_ow
  -input_output              loss2
  -gobj_filename             "COMMON_GOBJ
  -peel_iter                 0

/cl_nr_extract
  -input                     loss2
  -output                    loss3
  -min_number                "cl_nr_min
  -max_number                0
  -value_in_range            127

/gobj_maskaimpeel_ow
  -input_output              loss
  -gobj_filename             "IN1_GOBJ
  -peel_iter                 5

/set_value
  -input                     loss3
  -value_object              "COLOUR3
  -value_background          0

/write_v020
  -name                      loss3
  -filename                  "RESORB_FILE
  -compress_type             bin
  -version_020               true

/voxgobj_scanco_param
  -input                     loss3
  -gobj_filename             "IN1_GOBJ
  -peel_iter                 1
  -region_number             0

!start XT2 segmentaion for baseline image then concatenate with gain/loss aims


/sup_divide
  -input                     in1
  -suppos_pixels_local       0 0 0
  -supdim_numbers            0 0 0
  -subdim_pixels             0 0 0
  -testoff_pixels            0 0 0

/seg_gauss
  -input                     in1
  -output                    seg
  -sigma                     "SIGMA_GAUSS
  -support                   "SUPPORT_GAUSS
  -lower_in_perm_aut_al      "THRESHOLD_SEG
  -upper_in_perm_aut_al      100000.000000
  -value_in_range            127
  -unit                      2

/gobj
  -input_output              seg
  -gobj_filename             "IN1_GOBJ
  -peel_iter                 0

/cl_nr_extract
  -input                     seg
  -output                    cl
  -min_number                "cl_nr_min
  -max_number                0
  -value_in_range            127

/set_value
  -input                     cl
  -value_object              "COLOUR1
  -value_background          0


! combine with gain image
/concat
  -input1                    cl
  -input2                    gain3
  -output                    comb1
  -common_region_only        false
  -add_not_overlay           true
  -make_edge                 false
  -shift_ofin2               0 0 0
  -turnangle                 0.000000
  -turnpoint_global          -1 -1

! combine with loss image
/concat
  -input1                    comb1
  -input2                    loss3
  -output                    comb2
  -common_region_only        false
  -add_not_overlay           true
  -make_edge                 false
  -shift_ofin2               0 0 0
  -turnangle                 0.000000
  -turnpoint_global          -1 -1

/gobj
  -input_output              comb2
  -gobj_filename             "COMMON_GOBJ
  -peel_iter                 0

/write_v020
  -name                      comb2
  -filename                  "COMBI_FILE
  -compress_type             bin
  -version_020               true

..
$EXIT
