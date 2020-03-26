$!-------------------------
$!SUBMIT_STARTER_SEG_AUTOK_JSW.COM
$!-------------------------
$!Source unknown
$!Edited by Scott Brunet May 2019 for JSW Autocontour
$!Scanco JSW Analysis toolkit must be installed in UE DIRECTORY
$!
$! History:
$! Edited 08-SEPT-2016, to send batches to 1 queue with new 'cluster' scripts in UE
$! Edited May 2019 by Scott Brunet for MCP autocontour (from JSW Analysis)
$!
$! Ensure the following before running this script:
$! 1. You are the correct user: 'xtremect2' or 'xt2recalib'.
$! 2. You set the GOTO to work on the correct disk (DISK2 or DISK6, respectively).
$! 3. You have set JOB and END correctly.
$!
$!
$ MODELS_DIR = "DISK4:[BONELAB.PROJECTS.RAMHA.MODELS]"
$ LOG_DIR = "DISK4:[BONELAB.PROJECTS.RAMHA.LOG]"
$ JOB_SEG_AUTOK_JSW = "SUBMIT/QUEUE=SYS$FAST/NOPRINT/NONOTIFY/PRIORITY=90/LOG=SYS$SCRATCH: DISK4:[BONELAB.PROJECTS.RAMHA.COM]STARTER_SEG_AUTOK_RAMHA.COM /PARAM=("
$!
$ END = ")"
$!
$ GOTO TEST
$!
$TEST:
$ define DK0 DISK6
$ 'JOB_SEG_AUTOK_JSW'11575, 'MODELS_DIR'01_6M_J3.AIM,01_6M_J3, 2004'END' /LOG = ('LOG_DIR'STARTER_SEG_AUTOK_RAMHA.LOG)
$
$
$!
$EXIT
