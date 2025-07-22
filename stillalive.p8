; ---------------------------------------------
; | Portal's "Still Alive" credits sequence.  |
; | Features:                                 |
; |  - no IRQs used, instead coroutines.      |
; |    (up to 5 concurrent tasks are used)    |
; |  - 16 bit 22kHz adpcm music playback.     |
; |  - no assembly required (pure Prog8).     |
; ---------------------------------------------

%import palette
%import textio
%import coroutines
%import diskio
%zeropage basicsafe
%option no_sysinit
%encoding iso

main {
    sub start() {
        cx16.set_screen_mode(1)
        txt.color2(8,0)
        palette.set_color(0, $0000)     ; black
        palette.set_color(8, $0fa0)     ; amber
        txt.cp437()
        cbm.SETTIM(0,0,0)

        coroutines.killall()
        void coroutines.add(&frames.draw, 0)
        void coroutines.add(&music.player, 0)
        void coroutines.add(&credits.display, 0)
        void coroutines.add(&lyrics.display, 0)
        void coroutines.add(&images.display, 0)
        coroutines.run(0)       ; run everything until completion!

        cx16.set_screen_mode(0)
        txt.print("\n\n  I'm still alive!\n")
        txt.color(5)
        txt.print("\n\n  made in Prog8 by DesertFish.\n\n")
        txt.color(8)
    }
}

frames {
    sub draw() {
        txt.plot(0,0)
        repeat 37 txt.chrout('-')
        txt.plot(40,0)
        repeat 39 txt.chrout('-')
        txt.plot(0,29)
        repeat 37 txt.chrout('-')

        ubyte row
        for row in 1 to 28 {
            repeat 30  void coroutines.yield()
            txt.plot(0, row)
            txt.chrout('|')
            txt.plot(37, row)
            txt.chrout('|')
        }

        for row in 1 to 7 {
            repeat 30  void coroutines.yield()

            txt.plot(39, row)
            txt.chrout('|')
            txt.plot(79, row)
            txt.chrout('|')
        }

        txt.plot(40,8)
        repeat 39 txt.chrout('-')

        txt.plot(41, credits.MAX_ROW)
        txt.chrout('_')
    }
}

lyrics {
    sub display() {
        ubyte column = 2
        ubyte row = 2
        ubyte text_speed
        ubyte next_line_index
        uword line_timing
        uword line_ptr

        ; Don't use print() here, that is too slow.

        void next_line()
        repeat {
            if cbm.RDTIM16() >= line_timing {
                if line_ptr[0]=='~' {
                    ; clear the frame.
                    for row in 2 to 27 {
                        cx16.vaddr_autoincr(1, $b000 + 4 + row*256, 0, 2)
                        repeat 35  cx16.VERA_DATA0 = cp437:' '
                    }
                    column = 2
                    row = 2
                } else {
                    ; type out the line.
                    while @(line_ptr)!=0 {
                        uword letter_delay = cbm.RDTIM16() + text_speed
                        while cbm.RDTIM16() <= letter_delay
                            void coroutines.yield()

                        txt.plot(column, row)
                        txt.chrout(@(line_ptr))
                        txt.chrout('_')
                        line_ptr++
                        column++
                    }
                    txt.plot(column, row)
                    txt.spc()
                    column = 2
                    row++
                    txt.plot(column, row)
                    txt.chrout('_')
                }

                if not next_line()
                    return
            }
            void coroutines.yield()
        }

        sub next_line() -> bool {
            line_timing = stillalive.lyrics_timings[next_line_index]
            text_speed = stillalive.lyrics_durations[next_line_index]
            line_ptr = stillalive.lyrics[next_line_index]
            next_line_index++
            return line_timing!=0
        }
    }
}

credits {
    ubyte next_letter_index, line_index
    uword line_ptr
    ubyte column
    const ubyte MAX_ROW = 7
    uword slowness

    sub init() {
        next_letter_index = line_index = 0
        line_ptr = stillalive.credits[0]
        column = 41
    }

    sub display() {
        init()

        ; initial delay: 5 seconds
        slowness = cbm.RDTIM16() + 60*5
        while cbm.RDTIM16() < slowness
            void coroutines.yield()

        slowness = cbm.RDTIM16() + 4

        repeat {
            if cbm.RDTIM16() >= slowness {
                slowness = cbm.RDTIM16()  + 4

                ubyte letter
                bool finished
                letter, finished = next_letter()
                if finished {
                    ; post delay: 5 seconds
                    slowness = cbm.RDTIM16() + 60*5
                    while cbm.RDTIM16() < slowness
                        void coroutines.yield()
                    return
                }

                output(letter)
            }
            void coroutines.yield()
        }

        sub output(ubyte ltr) {
            txt.plot(column, MAX_ROW)
            if ltr=='\n' {
                txt.spc()
                scrollup()
                column = 40
            } else {
                txt.chrout(ltr)
                txt.chrout('_')
            }
            column++
        }

        sub scrollup() {
            ubyte row
            for row in 1 to MAX_ROW-1 {
                cx16.vaddr_autoincr(1, $b000 + 41*2 + row*256, 0, 2)
                cx16.vaddr_autoincr(1, $b000 + 41*2 + (row+1)*256, 1, 2)
                repeat 37 cx16.VERA_DATA0 = cx16.VERA_DATA1
            }
            txt.plot(41, row)
            repeat 38 txt.chrout(' ')
        }

        sub next_letter() -> ubyte, bool {
            if line_ptr[next_letter_index] == 0 {
                ; go to next line
                next_letter_index = 0
                line_index++
                line_ptr = stillalive.credits[line_index]
                if line_ptr==0 {
                    return '\n', true
                }
                return '\n', false
            }
            next_letter_index++
            return line_ptr[next_letter_index-1], false
        }
    }
}

images {
    ubyte next_image_index
    uword next_image_jiffies

    sub init() {
        next_image_index = 0
        next_image_jiffies = stillalive.images_times[0]
    }

    sub display() {
        ubyte row
        ubyte image

        init()

        repeat {
            if cbm.RDTIM16()>=next_image_jiffies {
                image = stillalive.images_indexes[next_image_index]
                uword stringarrayptr = stillalive.images[image]

                if stringarrayptr==0 {
                    clear()
                    return
                }
                for row in 9 to 28 {
                    ; don't use plot/print here, that is too slow.
                    ; txt.plot(39,row)
                    ; txt.print(peekw(stringarrayptr))

                    cx16.vaddr_autoincr(1, $b000 + 39*2 + row*256, 0, 2)
                    cx16.r1 = peekw(stringarrayptr)
                    for cx16.r0L in 0 to 39
                        cx16.VERA_DATA0 = cx16.r1[cx16.r0L]
                    stringarrayptr += 2

                    if row==19
                        void coroutines.yield()     ; don't claim too much time; draw the image "in 2 halves"
                }

                next_image_index++
                next_image_jiffies = stillalive.images_times[next_image_index]
                if next_image_jiffies==0
                    return
            }

            void coroutines.yield()
        }

        sub clear() {
            for row in 9 to 29 {
                txt.plot(39,row)
                txt.print(" " * 40)
            }
        }
    }
}

music {
    ubyte[256] adpcm_buffer

    sub init() {
        cx16.VERA_AUDIO_RATE = 0                ; halt playback

        void diskio.fastmode(1)
        if not diskio.f_open("stillalive.song")
            return
        void diskio.f_read(&adpcm_buffer, 256)
        adpcm.decode_block_mono(&adpcm_buffer)
        cx16.VERA_AUDIO_CTRL = %10101100        ; mono 16 bit, volume 12
        cx16.VERA_AUDIO_RATE = 58               ; start audio playback, 22125 Hz
    }

    sub player() {
        init()

        repeat {
            if cx16.VERA_ISR & %00001000 != 0  {
                ; AFLOW:  fifo is less than 25% full, feed me more data!

                adpcm.decode_block_mono(&adpcm_buffer)
                if diskio.f_read(&adpcm_buffer, 256) != 256 {
                    diskio.f_close()
                    return
                }

                ; we read directly from sdcard into the audio fifo buffer.
;                diskio.reset_read_channel()
;                cx16.r15 = 1024     ; read 1 Kb of PCM data
;                while cx16.r15 != 0 {
;                    void, cx16.r14 = cx16.MACPTR(lsb(cx16.r15), &cx16.VERA_AUDIO_DATA, true)
;                    cx16.r15 -= cx16.r14
;                    if cbm.READST()!=0 {
;                        diskio.f_close()
;                        return
;                    }
;                }
            }

            void coroutines.yield()
        }
    }
}

adpcm {
    sub decode_block_mono(uword @requirezp nibblesptr) {
        ; refill the fifo buffer with one decoded adpcm block (1010 bytes of pcm data)
        init(peekw(nibblesptr), @(nibblesptr+2))
        cx16.VERA_AUDIO_DATA = lsb(predict)
        cx16.VERA_AUDIO_DATA = msb(predict)
        nibblesptr += 4
        ubyte @zp nibble
        repeat 252/2 {
            unroll 2 {
                nibble = @(nibblesptr)
                ; note: when calling decode_nibble(), the upper nibble in the argument needs to be zero
                decode_nibble(nibble & 15)     ; first word
                cx16.VERA_AUDIO_DATA = lsb(predict)
                cx16.VERA_AUDIO_DATA = msb(predict)
                decode_nibble(nibble>>4)       ; second word
                cx16.VERA_AUDIO_DATA = lsb(predict)
                cx16.VERA_AUDIO_DATA = msb(predict)
                nibblesptr++
            }
        }
    }

    ; IMA ADPCM decoder.  Supports mono and stereo streams.
    ; https://wiki.multimedia.cx/index.php/IMA_ADPCM
    ; https://wiki.multimedia.cx/index.php/Microsoft_IMA_ADPCM

    ; IMA ADPCM encodes two 16-bit PCM audio samples in 1 byte (1 word per nibble)
    ; thus compressing the audio data by a factor of 4.
    ; The encoding precision is about 13 bits per sample so it's a lossy compression scheme.
    ;
    ; HOW TO CREATE IMA-ADPCM ENCODED AUDIO? Use sox or ffmpeg like so (example):
    ; $ sox --guard source.mp3 -r 8000 -c 1 -e ima-adpcm out.wav trim 01:27.50 00:09
    ; $ ffmpeg -i source.mp3 -ss 00:01:27.50 -to 00:01:36.50  -ar 8000 -ac 1 -c:a adpcm_ima_wav -block_size 256 -map_metadata -1 -bitexact out.wav
    ; And/or use a tool such as https://github.com/dbry/adpcm-xq  (make sure to set the correct block size, -b8)
    ;
    ; NOTE: for speed reasons this implementation doesn't guard against clipping errors.
    ;       if the output sounds distorted, lower the volume of the source waveform to 80% and try again etc.


    ; IMA-ADPCM file data stream format:
    ; If the IMA data is mono, an individual chunk of data begins with the following preamble:
    ; bytes 0-1:   initial predictor (in little-endian format)
    ; byte 2:      initial index
    ; byte 3:      unknown, usually 0 and is probably reserved
    ; If the IMA data is stereo, a chunk begins with two preambles, one for the left audio channel and one for the right channel.
    ; (so we have 8 bytes of preamble).
    ; The remaining bytes in the chunk are the IMA nibbles. The first 4 bytes, or 8 nibbles,
    ; belong to the left channel and -if it's stereo- the next 4 bytes belong to the right channel.


    byte[] t_index = [ -1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]
    uword[] t_step = [
            7, 8, 9, 10, 11, 12, 13, 14,
            16, 17, 19, 21, 23, 25, 28, 31,
            34, 37, 41, 45, 50, 55, 60, 66,
            73, 80, 88, 97, 107, 118, 130, 143,
            157, 173, 190, 209, 230, 253, 279, 307,
            337, 371, 408, 449, 494, 544, 598, 658,
            724, 796, 876, 963, 1060, 1166, 1282, 1411,
            1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024,
            3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484,
            7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
            15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
            32767]

    uword @requirezp predict       ; decoded 16 bit pcm sample for first channel.
    ubyte @requirezp index
    uword @requirezp pstep

    sub init(uword startPredict, ubyte startIndex) {
        ; initialize first decoding channel.
        predict = startPredict
        index = startIndex
        pstep = t_step[index]
    }

    sub decode_nibble(ubyte @zp nibble) {
        ; Decoder for a single nibble for the first channel. (value of 'nibble' needs to be strictly 0-15 !)
        ; This is the hotspot of the decoder algorithm!
        ; Note that the generated assembly from this is pretty efficient,
        ; rewriting it by hand in asm seems to improve it only ~10%.
        cx16.r0s = 0                ; difference
        if nibble & %0100 !=0
            cx16.r0s += pstep
        pstep >>= 1
        if nibble & %0010 !=0
            cx16.r0s += pstep
        pstep >>= 1
        if nibble & %0001 !=0
            cx16.r0s += pstep
        pstep >>= 1
        cx16.r0s += pstep
        if nibble & %1000 !=0
            predict -= cx16.r0
        else
            predict += cx16.r0

        ; NOTE: the original C/Python code uses a 32 bits prediction value and clips it to a 16 bit word
        ;       but for speed reasons we only work with 16 bit words here all the time (with possible clipping error)
        ; if predicted > 32767:
        ;    predicted = 32767
        ; elif predicted < -32767:
        ;    predicted = - 32767

        index += t_index[nibble] as ubyte
        if_neg
            index = 0
        else if index >= len(t_step)-1
            index = len(t_step)-1
        pstep = t_step[index]
    }
}


stillalive {
    ; see https://github.com/Christopher-Hayes/portal-1-credits/blob/master/main.js
    ubyte[89] lyrics_durations = [
        1, 1, 0, 0, 3, 4, 4, 5, 6, 4, 3, 5, 7, 4, 0, 4, 4, 3, 4, 4, 4, 3, 5, 0,
        1, 1, 0, 2, 0, 5, 7, 6, 4, 0, 4, 8, 7, 2, 0, 3, 5, 4, 4, 3, 4, 4, 4, 0,
        2, 2, 0, 2, 0, 4, 8, 6, 4, 4, 7, 7, 4, 3, 4, 3, 4, 3, 4, 3, 3, 0, 3, 3,
        4, 3, 3, 3, 0, 0, 3, 3, 0, 0, 4, 3, 0, 0, 3, 0, 0
        ]

    uword[89] lyrics_timings = [
        20, 120, 442, 443, 462, 692, 813, 984, 1121, 1415, 1640, 1729, 1949, 2151,
        2264, 2283, 2400, 2512, 2618, 2754, 2878, 2988, 3079, 3216, 3246, 3281, 3329,
        3335, 3406, 3546, 3783, 4105, 4297, 4406, 4494, 4726, 5052, 5253, 5317, 5377,
        5463, 5617, 5718, 5853, 5957, 6087, 6197, 6311, 6329, 6400, 6472, 6579, 6650,
        6663, 6877, 7195, 7387, 7601, 7832, 8124, 8351, 8476, 8580, 8706, 8814, 8949,
        9062, 9187, 9291, 9371, 9421, 9510, 9652, 9746, 9871, 9960, 10043, 10049,
        10122, 10243, 10317, 10329, 10364, 10460, 10537, 10543, 10560, 10686, 0
        ]

    str[89] lyrics = [
        "Forms FORM-29827281-12:",
        "Test Assessment Report",
        "",
        "",
        "This was a triumph.",
        "I'm making a note here:",
        "HUGE SUCCESS",
        "It's hard to overstate",
        "my satisfaction.",
        "Aperture Science",
        "We do what we must",
        "because we can.",
        "For the good of all of us.",
        "Except the ones who are dead.",
        "",
        "But there's no sense crying",
        "over every mistake.",
        "You just keep on trying",
        "till you run out of cake.",
        "And the science gets done.",
        "And you make a neat gun.",
        "For the people who are",
        "still alive.",
        "~",
        "Forms FORM-55551-5:",
        "Personnel File Addendum:",
        "",
        "Dear <<Subject Name Here>>,",
        "",
        "I'm not even angry.",
        "I'm being so sincere right now.",
        "Even though you broke my heart.",
        "And killed me.",
        "",
        "And tore me to pieces.",
        "And threw every piece into a fire.",
        "As they burned it hurt because",
        "I was so happy for you!",
        "",
        "Now these points of data",
        "make a beautiful line.",
        "And we're out of beta.",
        "We're releasing on time.",
        "So I'm GLaD. I got burned!",
        "Think of all the things we learned",
        "for the people who are",
        "still alive.",
        "~",
        "Forms FORM-55551-5:",
        "Personnel File Addendum:",
        "",
        "One last thing:",
        "",
        "Go ahead and leave me.",
        "I think I'd prefer to stay inside.",
        "Maybe you'll find someone else",
        "to help you.",
        "Maybe Black Mesa...",
        "THAT WAS A JOKE. FAT CHANCE.",
        "Anyway, this cake is great.",
        "It's so delicious and moist.",
        "Look at me still talking",
        "when there's science to do.",
        "When I look out there,",
        "it makes me GLaD I'm not you.",
        "I've experiments to run.",
        "There is research to be done.",
        "On the people who are",
        "still alive.",
        "~",
        "PS: And believe me I am",
        "still alive.",
        "PPS: I'm doing science and I'm",
        "still alive.",
        "PPPS: I feel FANTASTIC and I'm",
        "still alive.",
        "",
        "FINAL THOUGHT:",
        "While you're dying I'll be",
        "still alive.",
        "",
        "FINAL THOUGHT PS:",
        "And when you're dead I will be",
        "still alive",
        "",
        "",
        "STILL ALIVE",
        "~",
        0
    ]

    str[] credits = [
    ">LIST PERSONNEL",
    "",
    "",
    "Gautam Babbar",
    "Ted Backman",
    "Kelly Bailey",
    "Jeff Ballinger",
    "Aaron Barber",
    "Jeep Barnett",
    "Jeremy Bennett",
    "Dan Berger",
    "Yahn Bernier",
    "Ken Birdwell",
    "Derrick Birum",
    "Mike Blazszak",
    "Iestyn Bleasdale-Shepherd",
    "Chris Bohitch",
    "Steve Bond",
    "Matt Boone",
    "Antoine Bourdon",
    "Jamaal Bradley",
    "Jason Brashill",
    "Charlie Brown",
    "Charlie Burgin",
    "Andrew Burke",
    "Augusta Butlin",
    "Julie Caldwell",
    "Dario Casali",
    "Chris Chin",
    "Jess Cliffe",
    "Phil Co",
    "John Cook",
    "Christen Coomer",
    "Greg Coomer",
    "Scott Dalton",
    "Kerry Davis",
    "Jason Deakins",
    "Joe Demers",
    "Ariel Diaz",
    "Quintin Doroquez",
    "Jim Dose",
    "Chris Douglass",
    "Laura Dubuk",
    "Mike Dunkle",
    "Mike Durand",
    "Mike Dussault",
    "Dhabih Eng",
    "Katie Engel",
    "Chet Faliszak",
    "Adrian Finol",
    "Bill Fletcher",
    "Moby Francke",
    "Stephane Gaudette",
    "Kathy Gehrig",
    "Vitaliy Genkin",
    "Paul Graham",
    "Chris Green",
    "Chris Grinstead",
    "John Guthrie",
    "Aaron Halifax",
    "Reagan Halifax",
    "Leslie Hall",
    "Jeff Hameluck",
    "Joe Han",
    "Don Holden",
    "Jason Holtman",
    "Gray Horsfield",
    "Keith Huggins",
    "Jim Hughes",
    "Jon Huisingh",
    "Brian Jacobson",
    "Lars Jensvold",
    "Erik Johnson",
    "Jakob Jungels",
    "Rich Kaethler",
    "Steve Kalning",
    "Aaron Kearly",
    "Iikka Keranen",
    "David Kircher",
    "Eric Kirchmer",
    "Scott Klintworth",
    "Alden Kroll",
    "Marc Laidlaw",
    "Jeff Lane",
    "Tim Larkin",
    "Dan LeFree",
    "Isabelle LeMay",
    "Tom Leonard",
    "Jeff Lind",
    "Doug Lombardi",
    "Bianca Loomis",
    "Richard Lord",
    "Realm Lovejoy",
    "Randy Lundeen",
    "Scott Lynch",
    "Ido Magal",
    "Nick Maggiore",
    "John McCaskey",
    "Patrick McClard",
    "Steve McClure",
    "Hamish McKenzie",
    "Gary McTaggart",
    "Jason Mitchell",
    "Mike Morasky",
    "John Morello II",
    "Bryn Moslow",
    "Arsenio Navarro",
    "Gabe Newell",
    "Milton Ngan",
    "Jake Nicholson",
    "Martin Otten",
    "Nick Papineau",
    "Karen Prell",
    "Bay Raitt",
    "Tristan Reidford",
    "Alfred Reynolds",
    "Matt Rhoten",
    "Garret Rickey",
    "Dave Riller",
    "Elan Ruskin",
    "Matthew Russell",
    "Jason Ruymen",
    "David Sawyer",
    "Marc Scaparro",
    "Wade Schin",
    "Matthew Scott",
    "Aaron Seeler",
    "Jennifer Seeley",
    "Taylor Sherman",
    "Eric Smith",
    "Jeff Sorenson",
    "David Speyrer",
    "Jay Stelly",
    "Jeremy Stone",
    "Eric Strand",
    "Kim Swift",
    "Kelly Thornton",
    "Eric Twelker",
    "Carl Uhlman",
    "Doug Valente",
    "Bill Van Buren",
    "Gabe Van Engel",
    "Alex Vlachos",
    "Robin Walker",
    "Joshua Weier",
    "Andrea Wicklund",
    "Greg Winkler",
    "Erik Wolpaw",
    "Doug Wood",
    "Matt T. Wood",
    "Danika Wright",
    "Matt Wright",
    "Shawn Zabecki",
    "Torsten Sabka",
    "",
    "",
    "",
    "'Still Alive' by:",
    "Jonathan Coulon",
    "",
    "",
    "Voice:",
    "Ellen McLain - GlaDOS, Turrets",
    "Mike Patton - THE ANGER SPHERE",
    "",
    "",
    "Voice Casting:",
    "Shana Landsburg / Teri Fiddleman",
    "",
    "",
    "Voice Recording:",
    "Pure Audio, Seattle, WA",
    "",
    "",
    "Voice recording",
    "scheduling and logistics:",
    "Pat Cockburn, Pure Audio",
    "",
    "",
    "Translations:",
    "SDL",
    "",
    "",
    "Crack Legal Team:",
    "Liam Lavery",
    "Karl Quackenbush",
    "Kristen Boraas",
    "Kevin Rosenfield",
    "Alan Bruggeman",
    "Dennis Tessier",
    "",
    "",
    "Thanks for the use of their face:",
    "Alesia Glidewell - Chell",
    "",
    "",
    "Special thanks to everyone at:",
    "Alienware",
    "ATI",
    "Dell",
    "Falcon Northwest",
    "Havok",
    "SOFTIMAGE",
    "and Don Demmis, SLK Technologies",
    "",
    "",
    "",
    "",
    "THANK YOU FOR PARTICIPATING",
    "IN THIS",
    "ENRICHMENT CENTER ACTIVITY!!",
    "",
    "",
    0
    ]


    uword[] images = [
        &aperture,
        &radiation,
        &atom,
        &heart,
        &fire,
        &check,
        &blackmesa,
        &explosion,
        &cake,
        &glados
    ]

    ubyte[21] images_indexes = [
         0, ; Aperture Science
         1, ; Radioactive
         0, ; Aperture Science
         2, ; Science
         0, ; Aperture Science
         3, ; Broken Heart
         7, ; Destruction
         4, ; Fire
         5, ; Checkmark
         7, ; Destruction
         2, ; Science
         0, ; Aperture Science
         6, ; Black Mesa
         8, ; Cake
         9, ; GlaDOS
         1, ; Radioactive
         0, ; Aperture Science
         2, ; Science
         7, ; Destruction
         0, ; Aperture Science
         0 ; sentinel
     ]

    uword[21] images_times = [
        1395,  ; Aperture Science
        2145,  ; Radioactive
        2278,  ; Aperture Science
        2756,  ; Science
        2991,  ; Aperture Science
        4189,  ; Broken Heart
        4528,  ; Destruction
        4890,  ; Fire
        5296,  ; Checkmark
        5919,  ; Destruction
        6009,  ; Science
        6142,  ; Aperture Science
        7680,  ; Black Mesa
        8247,  ; Cake
        8568,  ; GlaDOS
        8677,  ; Radioactive
        8804,  ; Aperture Science
        9051,  ; Science
        9166,  ; Destruction
        9293,  ; Aperture Science
        0      ; sentinel
    ]


    str[20] @nosplit aperture = [
    "              .,-:;//;:=,               ",
    "          . :H@@@MM@M#H/.,+%;,          ",
    "       ,/X+ +M@@M@MM%=,-%HMMM@X/,       ",
    "     -+@MM; $M@@MH+-,;XMMMM@MMMM@+-     ",
    "    ;@M@@M- XM@X;. -+XXXXXHHH@M@M#@/.   ",
    "  ,%MM@@MH ,@%=            .---=-=:=,.  ",
    "  =@#@@@MX .,              -%HX$$%%%+;  ",
    " =-./@M@M$                  .;@MMMM@MM: ",
    " X@/ -$MM/                    .+MM@@@M$ ",
    ",@M@H: :@:                    . =X#@@@@-",
    ",@@@MMX, .                    /H- ;@M@M=",
    ".H@@@@M@+,                    %MM+..%#$.",
    " /MMMM@MMH/.                  XM@MH; =; ",
    "  /%+%$XHH@$=              , .H@@@@MX,  ",
    "   .=--------.           -%H.,@@@@@MX,  ",
    "   .%MM@@@HHHXX$$$%+- .:$MMX =M@@MM%.   ",
    "     =XMMM@MM@MM#H;,-+HMM@M+ /MMMX=     ",
    "       =%@M@M#@$-.=$@MM@@@M; %M%=       ",
    "         ,:+$+-,/H#MMMMMMM@= =,         ",
    "               =++%%%%+/:=              "
    ]

    str[20] @nosplit radiation = [
    "             =+$HM####@H%;,             ",
    "          /H###############M$,          ",
    "          ,@################+           ",
    "           .H##############+            ",
    "             X############/             ",
    "              $##########/              ",
    "               %########/               ",
    "                /X/;;+X/                ",
    "                                        ",
    "                 -XHHX-                 ",
    "                ,######,                ",
    "#############X  .M####M.  X#############",
    "##############-   -//-   -##############",
    "X##############%,      ,+##############X",
    "-##############X        X##############-",
    " %############%          %############% ",
    "  %##########;            ;##########%  ",
    "   ;#######M=              =M#######;   ",
    "    .+M###@,                ,@###M+     ",
    "       ;XH                    HX;       "
    ]

    str[20] @nosplit atom = [
    "                 =/;;/-                 ",
    "                +:    //                ",
    "               /;      /;               ",
    "              -X        H.              ",
    ".//;;;:;;-,   X=        :+   .-;:=;:;%;.",
    "M-       ,=;;;#:,      ,:#;;:=,       ,@",
    ":%           :%.=/++++/=.$=           %=",
    " ,%;         %/:+/;,,/++:+/         ;+. ",
    "   ,+/.    ,;@+,        ,%H;,    ,/+,   ",
    "      ;+;;/= @.  .H##X   -X :///+;      ",
    "      ;+=;;;.@,  .XM@$.  =X.//;=%/.     ",
    "   ,;:      :@%=        =$H:     .+%-   ",
    " ,%=         %;-///==///-//         =%, ",
    ";+           :%-;;;:;;;;-X-           +:",
    "@-      .-;;;;M-        =M/;;;-.      -X",
    " :;;::;;-.    %-        :+    ,-;;-;:== ",
    "              ,X        H.              ",
    "               ;/      %=               ",
    "                //    +;                ",
    "                  ////                  "
    ]

    str[20] @nosplit heart = [
    "                          .,---.        ",
    "                        ,/XM#MMMX;,     ",
    "                      -%##########M%,   ",
    "                     -@######%  $###@=  ",
    "      .,--,         -H#######$   $###M: ",
    "   ,;$M###MMX;     .;##########$;HM###X=",
    ",/@###########H=      ;################+",
    "-+#############M/,      %##############+",
    "%M###############=      /##############:",
    "H################      .M#############;.",
    "@###############M      ,@###########M:. ",
    "X################,      -$=X#######@:   ",
    "/@##################%-     +######$-    ",
    ".;##################X     .X#####+,     ",
    " .;H################/     -X####+.      ",
    "   ,;X##############,       .MM/        ",
    "      ,:+$H@M#######M#$-    .$$=        ",
    "           .,-=;+$@###X:    ;/=.        ",
    "                  .,/X$;   .::,         ",
    "                      .,    ..          "
    ]

    str[20] @nosplit explosion = [
    "            .+                          ",
    "             /M;                        ",
    "              H#@:              ;,      ",
    "              -###H-          -@/       ",
    "               %####$.  -;  .%#X        ",
    "                M#####+;#H :M#M.        ",
    "..          .+/;%#############-         ",
    " -/%H%+;-,    +##############/          ",
    "    .:$M###MH$%+############X  ,--=;-   ",
    "        -/H#####################H+=.    ",
    "           .+#################X.        ",
    "         =%M####################H;.     ",
    "            /@###############+;;/%%;,   ",
    "         -%###################$         ",
    "       ;H######################M=       ",
    "    ,%#####MH$%;+#####M###-/@####%      ",
    "  :$H%+;=-      -####X.,H#   -+M##@-    ",
    " .              ,###;    ;      =$##+   ",
    "                .#H,               :XH, ",
    "                 +                   .;-"
    ]

    str[20] @nosplit fire = [
    "                     -$-                ",
    "                    .H##H,              ",
    "                   +######+             ",
    "                .+#########H.           ",
    "              -$############@.          ",
    "            =H###############@  -X:     ",
    "          .$##################:  @#@-   ",
    "     ,;  .M###################;  H###;  ",
    "   ;@#:  @###################@  ,#####: ",
    " -M###.  M#################@.  ;######H ",
    " M####-  +###############$   =@#######X ",
    " H####$   -M###########+   :#########M, ",
    "  /####X-   =########%   :M########@/.  ",
    "    ,;%H@X;   .$###X   :##MM@%+;:-      ",
    "                 ..                     ",
    "  -/;:-,.              ,,-==+M########H ",
    " -##################@HX%%+%%$%%%+:,,    ",
    "    .-/H%%%+%%$H@###############M@+=:/+:",
    "/XHX%:#####MH%=    ,---:;;;;/&&XHM,:###$",
    "$@#MX %+;-                           .  "
    ]

    str[20] @nosplit check = [
    "                                     :X-",
    "                                  :X### ",
    "                                ;@####@ ",
    "                              ;M######X ",
    "                            -@########$ ",
    "                          .$##########@ ",
    "                         =M############-",
    "                        +##############$",
    "                      .H############$=. ",
    "         ,/:         ,M##########M;.    ",
    "      -+@###;       =##########M;       ",
    "   =%M#######;     :#########M/         ",
    "-$M###########;   :########/            ",
    " ,;X###########; =#######$.             ",
    "     ;H#########+######M=               ",
    "       ,+#############+                 ",
    "          /M########@-                  ",
    "            ;M#####%                    ",
    "              +####:                    ",
    "               ,$M-                     "
    ]

    str[20] @nosplit blackmesa = [
    "           .-;+$XHHHHHHX$+;-.           ",
    "        ,;X@@X%/;=----=:/%X@@X/,        ",
    "      =$@@%=.              .=+H@X:      ",
    "    -XMX:                      =XMX=    ",
    "   /@@:                          =H@+   ",
    "  %@X,                            .$@$  ",
    " +@X.                               $@% ",
    "-@@,                                .@@=",
    "%@%                                  +@$",
    "H@:                                  :@H",
    "H@:         :HHHHHHHHHHHHHHHHHHX,    =@H",
    "%@%         ;@M@@@@@@@@@@@@@@@@@H-   +@$",
    "=@@,        :@@@@@@@@@@@@@@@@@@@@@= .@@:",
    " +@X        :@@@@@@@@@@@@@@@M@@@@@@:%@% ",
    "  $@$,      ;@@@@@@@@@@@@@@@@@M@@@@@@$. ",
    "   +@@HHHHHHH@@@@@@@@@@@@@@@@@@@@@@@+   ",
    "    =X@@@@@@@@@@@@@@@@@@@@@@@@@@@@X=    ",
    "      :$@@@@@@@@@@@@@@@@@@@M@@@@$:      ",
    "        ,;$@@@@@@@@@@@@@@@@@@X/-        ",
    "           .-;+$XXHHHHHX$+;-.           "
    ]

    str[20] @nosplit cake = [
    "            ,:/+/-                      ",
    "            /M/              .,-=;//;-  ",
    "       .:/= ;MH/,    ,=/+%$XH@MM#@:     ",
    "      -$##@+$###@H@MMM#######H:.    -/H#",
    " .,H@H@ X######@ -H#####@+-     -+H###@X",
    "  .,@##H;      +XM##M/,     =%@###@X;-  ",
    "X%-  :M##########$.    .:%M###@%:       ",
    "M##H,   +H@@@$/-.  ,;$M###@%,          -",
    "M####M=,,---,.-%%H####M$:          ,+@##",
    "@##################@/.         :%H##@$- ",
    "M###############H,         ;HM##M$=     ",
    "#################.    .=$M##M$=         ",
    "################H..;XM##M$=          .:+",
    "M###################@%=           =+@MH%",
    "@#################M/.         =+H#X%=   ",
    "=+M###############M,      ,/X#H+:,      ",
    "  .;XM###########H=   ,/X#H+:;          ",
    "     .=+HM#######M+/+HM@+=.             ",
    "         ,:/%XM####H/.                  ",
    "              ,.:=-.                    "
    ]

    str[20] @nosplit glados = [
    "       #+ @      # #              M#@   ",
    " .    .X  X.%##@;# #   +@#######X. @H%  ",
    "   ,==.   ,######M+  -#####%M####M-    #",
    "  :H##M%:=##+ .M##M,;#####/+#######% ,M#",
    " .M########=  =@#@.=#####M=M#######=  X#",
    " :@@MMM##M.  -##M.,#######M#######. =  M",
    "             @##..###:.    .H####. @@ X,",
    "   ############: ###,/####;  /##= @#. M ",
    "           ,M## ;##,@#M;/M#M  @# X#% X# ",
    ".%=   ######M## ##.M#:   ./#M ,M #M ,#$ ",
    "##/         $## #+;#: #### ;#/ M M- @# :",
    "#+ #M@MM###M-;M #:$#-##$H# .#X @ + $#. #",
    "      ######/.: #%=# M#:MM./#.-#  @#: H#",
    "+,.=   @###: /@ %#,@  ##@X #,-#@.##% .@#",
    "#####+;/##/ @##  @#,+       /#M    . X, ",
    "   ;###M#@ M###H .#M-     ,##M  ;@@; ###",
    "   .M#M##H ;####X ,@#######M/ -M###$  -H",
    "    .M###%  X####H  .@@MM@;  ;@#M@      ",
    "      H#M    /@####/      ,++.  / ==-,  ",
    "               ,=/:, .+X@MMH@#H  #####$="
    ]

}
