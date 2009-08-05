implement Imageopen;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
	draw: Draw;
	Display, Image, Rect, Point: import draw;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "imagefile.m";
	Rawimage: import RImagefile;
	gifrd, jpgrd, pngrd: RImagefile;
	imageremap: Imageremap;
include "imageopen.m";

display: ref Display;

init(disp: ref Display)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	bufio = load Bufio Bufio->PATH;
	bufio->open("/dev/null", Sys->OREAD);
	str = load String String->PATH;
	gifrd = load RImagefile RImagefile->READGIFPATH;
	jpgrd = load RImagefile RImagefile->READJPGPATH;
	pngrd = load RImagefile RImagefile->READPNGPATH;
	imageremap = load Imageremap Imageremap->PATH;
	gifrd->init(bufio);
	jpgrd->init(bufio);
	pngrd->init(bufio);
	display = disp;
}

openimage(fd: ref Sys->FD, path: string): (ref Image, string)
{
	sys->seek(fd, big 0, Sys->SEEKSTART);

	imgmod: RImagefile;
	case str->splitstrr(path, ".").t1 {
	"png" =>	imgmod = pngrd;
	"jpg" =>	imgmod = jpgrd;
	"gif" =>	imgmod = gifrd;
	}

	if(imgmod == nil) {
		i := display.readimage(fd);
		if(i == nil)
			return (nil, sprint("reading image: %r"));
	}

	b := bufio->fopen(fd, Bufio->OREAD);
        (rawimg, err) := imgmod->read(b);
	i: ref Image;
        if(err == nil)
                (i, err) = rawimage2image(rawimg);
        return (i, err);
}

rawimage2image(rw: ref Rawimage): (ref Image, string)
{
	case rw.chandesc {
	RImagefile->CRGB =>
		if(rw.nchans != 3)
                        return (nil, sprint("expect 3 channels, saw %d", rw.nchans));

		img := display.newimage(rw.r, Draw->RGB24, 0, Draw->Nofill);
		if(img == nil)
			return (nil, sprint("newimage: %r"));
		
                rd := rw.chans[0];
                gd := rw.chans[1];
                bd := rw.chans[2];
		d := array[3*rw.r.dx()*rw.r.dy()] of byte;
		o := 0;
		for(i := 0; i < len rd; i++) {
			d[o++] = bd[i];
			d[o++] = gd[i];
			d[o++] = rd[i];
		}
		n := img.writepixels(img.r, d);
		if(n != len d)
			return (nil, sprint("readpixels returned %d, expected %d", n, len d));
		return (img, nil);

	RImagefile->CRGB1 =>
		if(rw.nchans != 1)
			return (nil, sprint("expect 1 channel, saw %d", rw.nchans));

		img := display.newimage(rw.r, Draw->RGB24, 0, Draw->Nofill);
		if(img == nil)
			return (nil, sprint("newimage: %r"));

		d := array[3*rw.r.dx()*rw.r.dy()] of byte;
		o := 0;
		ch := rw.chans[0];
		for(i := 0; i < len ch; i++) {
			co := int ch[i]*3;
			d[o++] = rw.cmap[co+2];
			d[o++] = rw.cmap[co+1];
			d[o++] = rw.cmap[co+0];
		}
		n := img.writepixels(img.r, d);
		if(n != len d)
			return (nil, sprint("readpixels returned %d, expected %d", n, len d));
		return (img, nil);
	* =>
		# handle RImagefile->CY too?
		return imageremap->remap(rw, display, 0);
	}
}

# resample o into an image of w by h
resample(o: ref Image, w, h: int): ref Image
{
	(ow, oh) := (o.r.dx(), o.r.dy());
	odepth := ((o.depth+7)/8);
	d := array[ow*oh*odepth] of byte;
	n := o.readpixels(o.r, d);
	if(n != len d) {
		sys->werrstr(sprint("readpixels, n %d, len d %d, depth %d", n, len d, odepth));
		return nil;
	}

	ni := display.newimage(Rect(Point(0, 0), Point(w, h)), o.chans, 0, Draw->Nofill);
	if(ni == nil) {
		sys->werrstr(sprint("newimage: %r"));
		return nil;
	}
	nd := array[w*h*odepth] of byte;

	# nearest neighbour.  we should do something better than this.
	# but the code should be in an external module.
	for(i := 0; i < h; i++) {
		row := i*w*odepth;
		orow := ((oh*i)/h)*ow*odepth;
		for(j := 0; j < w; j++) {
			oj := ((ow*j)/w)*odepth;
			nd[row:] = d[orow+oj:orow+oj+odepth];
			row += odepth;
		}
	}

	nn := ni.writepixels(ni.r, nd);
	if(nn != len nd) {
		sys->werrstr(sprint("writepixels, nn %d, len nd %d", nn, len nd));
		return nil;
	}
	return ni;
}
