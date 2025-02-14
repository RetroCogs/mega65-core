;===============================================================================
;Option list definitions
;-----------------------
;
;Configuration option lists definitions.
;
;
;Using the option lists
;----------------------
;
;The input options are defined by a type and a list of details for that type.
;They usually have an offset and flag byte followed by a set of pascal-style
;strings.  The option is defined in the type byte high nybble and the low nybble
;used to set the current value (except for string and button input types, see
;below).  Pascal strings are used to speed up various operations (list
;traversal, on-screen manipulation).  Use .defPStr to declare a Pascal string.
;
;The options are defined in a list for each page and grouped under six tabs.
;Each list is therefore an on-screen page worth of options and can be navigated
;by the user.  Each list must be a maximum of 256 bytes due to a limitation in
;the current implementation.  This limitation is checked with compile asserts.
;
;Each page (or list) is defined to belong to one of six tabs, as already
;mentioned.  These tabs are:  System, Disk, Video, Audio, Network and Save.
;The Save tab options must not be changed as the code relies on them being
;defined in a particular way (although the text of the buttons can be changed).
;
;The number of screen lines used to display a page's options must not exceed 20.
;
;The pages are listed in an index for each tab such that the code can traverse
;the lists as defined here.  The number of pages in a tab must also be defined.
;
;Furthermore, two magic bytes are defined here to determine the system version
;compatibility.
;
;
;The input types are:
;	00	-	end of list, no data bytes
;	10	-	button, requires 1 string: label
;	20	-	option (on/off, one of two enabled)
;			followed by word offset and byte flags
;			requires 3 strings:  label, option unset, option set.
;	30	-	string input.
;			followed by word offset and byte for string
;			length requires 1 string:  label
;			requires data area of string length for storage.
;			input string will be null or length terminated.
;	40	- 	Blank line, no data
;	50	-	MAC Address input.  requires 1 string (label), word
;			offset and data	area of 6 bytes for storage of address.
;
;===============================================================================


;-------------------------------------------------------------------------------
configMagicByte0	=	$01
configMagicByte1	=	$01
;-------------------------------------------------------------------------------



;-------------------------------------------------------------------------------
;Input tab
;-------------------------------------------------------------------------------
inputPageCnt	=	1

inputOptions0:

	.byte		$20			;option input type
	.word		$0005			;offset into config table
;	.byte		$02			;bits for testing/setting
	.byte		$01			;bits for testing/setting
	.defPStr	"joy 1 mouse mode:"	;label
	.defPStr	'normal'		;option unset
	.defPStr	"amiga to 1351 enabled"	;option set

	.byte		$20			;option input type
	.word		$0005			;offset into config table
;	.byte		$08			;bits for testing/setting
	.byte		$04			;bits for testing/setting
	.defPStr	"joy 1 1351 de-jitter:"	;label
	.defPStr	'on'		;option unset
	.defPStr	"off"	;option set

	.byte		$20			;option input type
	.word		$0005			;offset into config table
;	.byte		$01			;bits for testing/setting
	.byte		$02			;bits for testing/setting
	.defPStr	"joy 2 mouse mode:"	;label
	.defPStr	'normal'		;option unset
	.defPStr	"amiga to 1351 enabled"	;option set

	.byte		$20			;option input type
	.word		$0005			;offset into config table
;	.byte		$04			;bits for testing/setting
	.byte		$08			;bits for testing/setting
	.defPStr	"joy 2 1351 de-jitter:"	;label
	.defPStr	'on'		;option unset
	.defPStr	"off"	;option set


	.byte		$00			;end of list type
inputOptions0_end:
	.assert		(inputOptions0_end - inputOptions0) < 256, error, "Input Options too large!"

inputPageIndex:
	.word		inputOptions0


;-------------------------------------------------------------------------------
;Chipset tab
;-------------------------------------------------------------------------------
chipsetPageCnt 	=	2

chipsetOptions0:
	.byte		$60
	.word		$01f0
	.defPStr	"time (hh:mm:ss):"
	.byte		$00, $00, $00

	.byte		$70
	.word		$01f3
	.defPStr	"date (dd-mmm-yyyy):"
	.byte		$00, $00, $00

	.byte		$20			;option input type
	.word		$0004			;offset into config table
	.byte		$01			;bits for testing/setting
	.defPStr	"f011 disk controller:"	;label
	.defPStr	"sdcard disk image";option unset
	.defPStr	'3.5" floppy drive';option set

	.byte		$30			;string input type
	.word		$0010			;offset into config table
	.byte		$10			;input string length
	.defPStr	"default disk image:"	;label

	.byte		$00, $00, $00, $00	;storage for value
	.byte		$00, $00, $00, $00
	.byte		$00, $00, $00, $00
	.byte		$00, $00, $00, $00

	.byte		$20			;option input type
	.word		$0004			;offset into config table
	.byte		$08			;bits for testing/setting
	.defPStr	"disk image drive noise:"
	.defPStr	"enable"		;option unset
	.defPStr	"disable"		;option set
	
	.byte		$00			;end of list type
chipsetOptions0_end:
	.assert		(chipsetOptions0_end - chipsetOptions0) < 256, error, "Chipset Options 0 too large!"

chipsetOptions1:
	.byte		$20			;option input type
	.word		$0020			;offset into config table
	.byte		$01			;bits for testing/setting
	.defPStr	"dmagic revision:"	;label
	.defPStr	'f018 (rom < 910523)'	;option unset
	.defPStr	"f018b"			;option set

	.byte		$20			;option input type
	.word		$000F			;offset into config table
	.byte		$80			;bits for testing/setting
	.defPStr	"long fn support:"	;label
	.defPStr	"disable"		;option unset
	.defPStr	'enable'		;option set

	.byte 		$00			;end of list type

chipsetOptions1_end:
	.assert		(chipsetOptions1_end - chipsetOptions1) < 256, error, "Chipset Options 1 too large!"


chipsetPageIndex:
	.word		chipsetOptions0
	.word		chipsetOptions1		


;-------------------------------------------------------------------------------
;Video tab
;-------------------------------------------------------------------------------
videoPageCnt	=	1

videoOptions0:
	.byte		$20
	.word		$0002
	.byte		$80
	.defPStr	"video mode:"
	.defPStr	"pal  50hz (720*576)"
	.defPStr	"ntsc 60hz (720*480)"

	.byte		$20
	.word		$000D
	.byte		$02
	.defPStr	"digital video:"
	.defPStr	"enhanced (with audio)"
	.defPStr	"dvi only (no audio)"

	.byte		$20
	.word		$0021
	.byte		$20
	.defPStr	"crt emulation:"
	.defPStr	"off"
	.defPStr	"on"

	.byte		$00
videoOptions0_end:
	.assert		(videoOptions0_end - videoOptions0) < 256, error, "Video Options 0 too large!"

videoPageIndex:
	.word		videoOptions0


;-------------------------------------------------------------------------------
;Audio tab
;-------------------------------------------------------------------------------
audioPageCnt	=	2

audioOptions0:
	.byte		$20
	.word		$0003
	.byte		$40
	.defPStr	"audio output:"
	.defPStr	"stereo"
	.defPStr	"mono"

	.byte		$20
	.word		$0022
	.byte		$01
	.defPStr	"sid generation:"
	.defPStr	"6581"
	.defPStr	"8580"

	.byte		$20
	.word		$0003
	.byte		$20
	.defPStr	"swap stereo channels:"
	.defPStr	"no"
	.defPStr	"yes"

	.byte		$20
	.word		$0003
	.byte		$01
	.defPStr	"audio amplifier:"
	.defPStr	"off"
	.defPStr	"on"

	.byte		$00
audioOptions0_end:
	.assert		(audioOptions0_end - audioOptions0) < 256, error, "Audio Options 0 too large!"

audioOptions1:
	.byte		$20
	.word		$0003
	.byte		$80
	.defPStr	"dac algorithm:"
	.defPStr	"pdm"
	.defPStr	"pwm"

	.byte		$00

audioOptions1_end:
	.assert		(audioOptions1_end - audioOptions1) < 256, error, "Audio Options 1 too large!"


audioPageIndex:
	.word		audioOptions0
	.word		audioOptions1


;-------------------------------------------------------------------------------
;Network tab
;-------------------------------------------------------------------------------
networkPageCnt	=	1

networkOptions0:
	.byte		$50
	.word		$0006
	.defPStr	"mac address:"
	.byte		$00, $00, $00, $00, $00, $00

	.byte		$10
	.defPStr	"press 'r' for random mac"
	.byte		$10
	.defPStr	"press 'u' to validate mac"
	.byte		$00
networkOptions0_end:
	.assert		(networkOptions0_end - networkOptions0) < 256, error, "Network Options 0 too large!"

networkPageIndex:
	.word		networkOptions0


;-------------------------------------------------------------------------------
;Save tab
;-------------------------------------------------------------------------------
savePageCnt	=	1

;*******************************************************************************
;Do not change the order or number of options in these lists without code change!
;*******************************************************************************
saveOptions0:
	.byte		$10
	.defPStr	"exit without saving"
	.byte		$10
	.defPStr	"restore factory defaults"
	.byte		$10
	.defPStr	"exit and reboot to onboarding"
	.byte		$10
	.defPStr	"save as defaults and exit"
	.byte		$00

saveOptions1:
	.byte		$40
	.byte		$40
	.byte		$40
	.byte		$10
	.defPStr	"cancel"
	.byte		$10
	.defPStr	"ok"
	.byte		$00

saveOptions2:
	.byte		$00

savePageIndex:
	.word		saveOptions0, saveOptions1, saveOptions2


;-------------------------------------------------------------------------------
;Help tab
;-------------------------------------------------------------------------------
helpPageCnt	=	1

;*******************************************************************************
;Do not change the order or number of options in these lists!
;*******************************************************************************
helpOptions0:
	.byte		$40
	.byte		$40
	.byte		$40
	.byte		$40
	.byte		$40
	.byte		$40
	.byte		$40
	.byte		$40
	.byte		$40
	.byte		$10
	.defPStr	"ok"

	.byte		$00

helpPageIndex:
	.word		helpOptions0