.PHONY: all clean run


all:  stillalive.prg stillalive.song

clean:
	rm stillalive.prg stillalive.song

run:  all
	x16emu -scale 2 -prg stillalive.prg -run

stillalive.prg:	 stillalive.p8
	prog8c -target cx16 $<

stillalive.song:  stillalive.wav
	adpcm-xq -b8 -n -y -r $< $@
