run:	stillalive.prg
	x16emu -scale 2 -prg stillalive.prg -run

stillalive.prg:	stillalive.p8
	prog8c -target cx16 stillalive.p8
