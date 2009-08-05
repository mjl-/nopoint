# file parsing is done by the nopoint library.
# this file just handles key/mouse events, and drawing on the canvas.
# we have a cache for previous,current,next slide.
# we pre-render the next slide, but cancel it on leaps.

implement Nopoint;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
	draw: Draw;
	Display, Image, Point, Rect, Pointer: import draw;
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "lists.m";
	lists: Lists;
include "keyboard.m";
	kb: Keyboard;
include "devpointer.m";
	devptr: Devpointer;
include "freetype.m";
	freetype: Freetype;
	Face: import freetype;
include "../lib/imageopen.m";
	imageopen: Imageopen;
include "../lib/nopoint.m";
	nop: Nopointlib;
	Slide, Style, Text, Word: import nop;

Nopoint: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};


Viewems: con 30;

dflag: int;
basecharsize: int;

slides: array of ref Slide;
cache: array of ref Image;
index: int;
renderpid := -1;
renderindex := -1;
renderc: chan of ref Image;

fontrfile := "/fonts/ttf/Vera.ttf";
fontbfile := "/fonts/ttf/VeraBd.ttf";
fontifile := "/fonts/ttf/VeraIt.ttf";
fontmonofile := "/fonts/ttf/VeraMono.ttf";

display: ref Display;
fontr, fontb, fonti, fontmono: ref Face;

pids: list of int;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	lists = load Lists Lists->PATH;
	devptr = load Devpointer Devpointer->PATH;
	freetype = load Freetype Freetype->PATH;
	imageopen = load Imageopen Imageopen->PATH;
	nop = load Nopointlib Nopointlib->PATH;

	arg->init(args);
	arg->setusage(arg->progname()+" [-d] file");
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	dflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();

	sys->pctl(Sys->NEWPGRP, nil);

	display = Display.allocate(nil);
	if(display == nil)
		fail(sprint("no display: %r"));
	imageopen->init(display);
	display.image.flush(Draw->Flushoff);
	fontr = freetype->newface(fontrfile, 0);
	fontb = freetype->newface(fontbfile, 0);
	fonti = freetype->newface(fontifile, 0);
	fontmono = freetype->newface(fontmonofile, 0);
	if(fontr == nil || fontb == nil || fonti == nil || fontmono == nil)
		fail(sprint("loading fonts: %r"));
	
	basecharsize = 32;
	fontsetcharsize(basecharsize);
	g := fontr.loadglyph('m');
	basecharsize = (basecharsize*display.image.r.dx()/Viewems)/g.width;
	say(sprint("basecharsize is %d", basecharsize));
	fontsetcharsize(basecharsize);

	nop->init(display);

	f := hd args;
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		fail(sprint("open %q: %r", f));
	err: string;
	(slides, err) = nop->parse(f, fd);
	if(err != nil)
		fail(err);
	if(len slides == 0)
		fail(sprint("%q: zero slides", f));
	fd = nil;
	cache = array[len slides] of ref Image;
	renderc = chan of ref Image;

	pidc := chan of int;
	spawn keyreader(keyc := chan of int, pidc);
	spawn mousereader(ptrc := chan of ref Pointer, pidc);
	pids = <-pidc::<-pidc::nil;

	show(1);

	buttons := 0;
	paintmouse := 0;
	paintcolor := display.color(Draw->Blue);
	dotsize := max(2, display.image.r.dx()/300);
	linesize := max(1, display.image.r.dx()/600);
	prevdown := 0;
	prevxy: Point;
	for(;;) alt {
	key := <-keyc =>
		redraw := 0;
		case key {
		0 or
		'q' or
		kb->Del =>	quit();
		'p' or
		kb->Left =>	index = max(0, index-1);
		' ' or
		'n' or
		kb->Right =>	index = min(index+1, len slides-1);
		kb->Home =>	index = 0;
		kb->End =>	index = len slides-1;
		kb->Up =>	index = min(index+max(1, len slides/10), len slides-1);
		kb->Down =>	index = max(0, index-max(1, len slides/10));
		kb->Pgup =>	index = min(index+max(1, len slides/3), len slides-1);
		kb->Pgdown =>	index = max(0, index-max(1, len slides/3));
		'l' =>	redraw = 1;
		'r' =>
			say("reloading...");
			fd = sys->open(f, Sys->OREAD);
			if(fd == nil)
				warn(sprint("reopen %q: %r", f));
			(nslides, nerr) := nop->parse(f, fd);
			fd = nil;
			if(nerr == nil && len nslides == 0)
				nerr = sprint("%q: zero slides", f);
			if(nerr != nil) {
				warn(nerr);
				continue;
			}
			say(sprint("installing new slides..."));
			slides = nslides;
			if(index >= len slides)
				index = len slides-1;
			cache = array[len slides] of ref Image;
			if(renderpid >= 0)
				kill(renderpid);
			renderpid = renderindex = -1;

			redraw = 1;
		'x' =>
			redraw = paintmouse;
			paintmouse = !paintmouse;
		* =>
			say(sprint("unknown key %c (%d)", key, key));
		}
		if(key != 'x')
			paintmouse = 0;
		show(redraw);

	p := <-ptrc =>
		if(p == nil)
			quit();
		B1: con 1<<0;
		B3: con 1<<2;
		Bmask: con B1|B3;
		if(paintmouse && p.buttons & B1) {
			if(prevdown)
				display.image.line(prevxy, p.xy, Draw->Enddisc, Draw->Enddisc, linesize, paintcolor, Point(0, 0));
			else
				display.image.draw(Rect(p.xy, p.xy.add(Point(dotsize, dotsize))), paintcolor, nil, Point(0, 0));
			display.image.flush(Draw->Flushnow);
			prevxy = p.xy;
			prevdown = 1;
		} else
			prevdown = 0;

		if(!paintmouse && (p.buttons & Bmask) != buttons) {
			b1release := (buttons & B1) && (p.buttons & B1) == 0;
			b3release := (buttons & B3) && (p.buttons & B3) == 0;
			if(b1release)
				index = min(index+1, len slides-1);
			if(b3release)
				index = max(0, index-1);
			buttons = p.buttons & Bmask;
			show(0);
		}
	}
}

quit()
{
	for(; pids != nil; pids = tl pids)
		kill(hd pids);
	if(renderpid >= 0)
		kill(renderpid);
	fail("quit");
}

keyreader(keyc: chan of int, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	b := bufio->open("/dev/keyboard", bufio->OREAD);
	if(b == nil) {
		warn(sprint("open /dev/keyboard: %r"));
		keyc <-= 0;
		return;
	}
	for(;;) {
		case c := b.getc() {
		bufio->ERROR =>
			warn(sprint("reading keyboard: %r"));
			c = 0;
		bufio->EOF =>
			warn(sprint("keyboard eof"));
			c = 0;
		}
		keyc <-= c;
	}
}

mousereader(ptrc: chan of ref Pointer, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	fd := sys->open("/dev/pointer", Sys->OREAD);
	if(fd == nil) {
		warn(sprint("open /dev/pointer: %r"));
		ptrc <-= nil;
		return;
	}
	buf := array[devptr->Size] of byte;
	for(;;) {
		n := sys->readn(fd, buf, len buf);
		if(n < 0) {
			warn(sprint("reading /dev/pointer: %r"));
			ptrc <-= nil;
			return;
		}
		if(n != len buf) {
			fail(sprint("short read on /dev/pointer"));
			ptrc <-= nil;
			return;
		}
		ptrc <-= devptr->bytes2ptr(buf);
	}
}

# try to get slide from cache.
# if not there, and we previously spawned the pre-renderer,
# wait until it is done.  otherwise, render immediately and wait.
# afterwards, if next slide is not in cache, spawn a prog to render that.
previndex := -1;
show(redraw: int)
{
	if(!redraw && index == previndex)
		return;

	previndex = index;
	for(j := 0; j < index-1; j++)
		cache[j] = nil;
	for(j = index+2; j < len slides; j++)
		cache[j] = nil;

	if(renderindex == index)
		cache[index] = <-renderc;
	else if(renderpid >= 0)
		kill(renderpid);
	renderpid = renderindex = -1;
	i := cache[index];
	if(i == nil)
		i = cache[index] = render(slides[index]);
	display.image.draw(i.r, i, nil, Point(0,0));
	display.image.flush(Draw->Flushnow);

	if(index+1 < len cache && cache[index+1] == nil) {
		renderindex = index+1;
		spawn prerender(slides[renderindex], pidc := chan of int);
		renderpid = <-pidc;
	}
}

prerender(sl: ref Slide, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	renderc <-= render(sl);
}


getfont(ft, defft: int): ref Face
{
	if(ft == -1)
		ft = defft;
	case ft {
	nop->Regular =>		return fontr;
	nop->Bold =>		return fontb;
	nop->Italic =>		return fonti;
	nop->Monospace =>	return fontmono;
	}
	raise "missing case";
}

drawline0(img: ref Image, al: int, wrap: int, x, xe, y: int, l: list of ref Word, st: ref Style): (int, int, list of ref Word)
{
	r := Rect((0, 0), (img.r.dx(), st.font.height));
	gimg := img.display.newimage(r, Draw->GREY8, 0, Draw->Black);
	lineimg := img.display.newimage(r, Draw->RGBA32, 0, Draw->Transparent);
	lx := 0;
	lr := Rect((lx, 0), lineimg.r.max);
	nwords := 0;
	while(l != nil) {
		w := *hd l;
		clr := w.color;
		if(clr == nil)
			clr = st.fgc;
		sx := lx;
		f := getfont(w.font, st.ft);
		s := w.s;
		for(i := 0; i < len s; i++) {
			c := s[i];
			if(c == '\t')
				c = ' ';
			g := f.loadglyph(c);
			if(g == nil)
				fail(sprint("missing glyph for %c (%d)", c, c));
			gr: Rect;
			gr.min = Point(g.left, f.ascent-g.top);
			gr.max = gr.min.add(Point(g.width, g.height));
			gimg.draw(gimg.r, display.black, nil, gimg.r.min);
			gimg.writepixels(gr, g.bitmap);

			lx += g.advance.x>>6;
			llr := lr;
			llr.max.x = llr.min.x+lx;
			lineimg.draw(llr, clr, gimg, Point(0,0));
			lr.min.x = lx;
		}
		if(wrap == nop->Wrap && lx > xe-x) {
			if(nwords == 0)
				l = tl l;
			else
				lx = sx;
			while(l != nil && (hd l).isws)
				l = tl l;
			break;
		}
		l = tl l;
		nwords++;
	}
	ir := lineimg.r;
	ir.max.x = lx;
	ir = ir.addpt(Point(x, y));
	case al {
	nop->Left =>	;
	nop->Center =>	ir = ir.addpt(Point((xe-x)/2-lx/2, 0));
	nop->Right =>	ir = ir.addpt(Point(xe-lx-x, 0));
	* =>	raise "missing case";
	}
	img.draw(ir, lineimg, nil, lineimg.r.min);
	x += lx;
	y += lineimg.r.dy();
	return (x, y, l);
}

drawline(img: ref Image, al: int, wrap: int, x, xe, y: int, t: ref Text, st: ref Style): (int, int)
{
	l := t.l;
	nx: int;
	do
		(nx, y, l) = drawline0(img, al, wrap, x, xe, y, l, st);
	while(l != nil);
	return (nx, y);
}

fontsetcharsize(size: int)
{
	fontr.setcharsize(size<<6, 96, 96);
	fontb.setcharsize(size<<6, 96, 96);
	fonti.setcharsize(size<<6, 96, 96);
	fontmono.setcharsize(size<<6, 96, 96);
}

setstyle(st: ref Style)
{
	st.font = getfont(st.ft, st.ft);
	st.fontsize0 = int (st.ftsize*real basecharsize);
	fontsetcharsize(st.fontsize0);
}

render(sl: ref Slide): ref Image
{
	st := ref *sl.style;
	img := display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Nofill);
	img.draw(img.r, st.bgc, nil, Point(0,0));
	padding := img.r.dx()/20;
	y := 0;
	setstyle(sl.titlestyle);
	if(sl.title != nil) {
		ty := y+int (0.1*real sl.titlestyle.font.height);
		x := padding+int (sl.titlestyle.indent * real img.r.dx());
		xe := img.r.dx()-padding;
		drawline(img, sl.titlestyle.align, nop->Nowrap, x, xe, ty, sl.title, sl.titlestyle);
	}
	if(!sl.notitle)
		y += int (1.2 * real sl.titlestyle.font.height);
	mainr := Rect((0,0), (img.r.dx(), img.r.dy()-y));
	mainimg := img.display.newimage(mainr, Draw->RGBA32, 0, Draw->Transparent);
	my := 0;

	setstyle(st);

	for(l := sl.e; l != nil; l = tl l)
		pick e := hd l {
		Text =>
			x := padding+st.indent0;
			xe := img.r.dx()-padding;
			(nil, my) = drawline(mainimg, st.align, nop->Wrap, x, xe, my, e.t, st);
		List =>
			for(el := e.l; el != nil; el = tl el) {
				(depth, t) := *hd el;
				st.fontsize0 = int (st.ftsize * 0.9**depth * real basecharsize);
				fontsetcharsize(st.fontsize0);
				x := padding+st.indent0;
				xe := img.r.dx()-padding;
				x += depth*2*st.font.loadglyph('m').width;
				bt := ref Text (ref (nop->Regular, st.fgc, 0, "• ")::nil);
				(x, nil) = drawline(mainimg, nop->Left, nop->Nowrap, x, xe, my, bt, st);
				(nil, my) = drawline(mainimg, nop->Left, nop->Wrap, x, xe, my, t, st);
			}
		Image =>
			if(e.i == nil) {
				nheight: int;
				(i, err) := imageopen->openimage(e.fd, e.path);
				if(err == nil) {
					nwidth := int (e.width*real display.image.r.dx());
					nheight = int (e.height*real display.image.r.dy());
					if(e.keepratio) {
						xscale := real nwidth / real i.r.dx();
						yscale := real nheight / real i.r.dy();
						scale := xscale;
						if(yscale < scale)
							scale = yscale;
						nwidth = int (scale * real i.r.dx());
						nheight = int (scale * real i.r.dy());
					}

					i = imageopen->resample(i, nwidth, nheight);
					if(i == nil)
						err = sprint("resampling image: %r");
				}
				if(err != nil) {
					warn(err);
					x := padding+st.indent0;
					xe := img.r.dx()-padding;
					t := ref Text (ref Word (nop->Bold, display.color(Draw->Red), 0, err)::nil);
					drawline(mainimg, nop->Center, nop->Wrap, x, xe, my, t, st);
					my += nheight;
					continue;
				}
				e.i = i;
			}

			x := padding+st.indent0;
			r := mainimg.r.addpt(Point(x, my));
			width := mainimg.r.dx()-2*padding;
			space := width-e.i.r.dx();
			xoff: int;
			case st.align {
			nop->Left =>	xoff = 0;
			nop->Center =>	xoff = space/2;
			nop->Right =>	xoff = space;
			}
			r = r.addpt(Point(xoff, 0));
			say(sprint("drawing image at %d,%d, image size %dx%d, xoff %d", r.min.x, r.min.y, e.i.r.dx(), e.i.r.dy(), xoff));
			mainimg.draw(r, e.i, nil, mainimg.r.min);
			my += e.i.r.dy();
		Table =>
			dx := real (mainimg.r.dx()-st.indent0-padding);
			space := 1.0;
			for(i := 0; i < len e.widths; i++)
				space -= e.widths[i];
			colpad := 0.0;
			if(len e.rows > 1)
				colpad = dx * space / (real (len e.rows-1));
			if(colpad > 1.0/30.0)
				colpad = 1.0/30.0;
			for(i = 0; i < len e.rows; i++) {
				xo := real (st.indent0+padding);
				row := e.rows[i];
				maxy := my+st.font.height;
				for(j := 0; j < len row; j++) {
					t := row[j];
					coldx := dx * e.widths[j];
					xe := int (xo+coldx);
					align := e.aligns[j];
					(nil, newy) := drawline(mainimg, align, nop->Wrap, int xo, xe, my, t, st);
					maxy = max(maxy, newy);
					xo += coldx+colpad;
				}
				my = maxy;
			}
		Vspace =>
			my += int (real st.font.height*e.r);
		Color =>
			st.fgc = e.c;
		Bgcolor =>
			st.bgc = e.c;
		Font =>
			st.ft = e.ft;
		Fontsize =>
			st.ftsize = e.ftsize;
			st.fontsize0 = int (st.ftsize*real basecharsize);
			fontsetcharsize(st.fontsize0);
		Align =>
			st.align = e.align;
		Valign =>
			st.valign = e.valign;
		Indent =>
			st.indent = e.r;
			st.indent0 = int (real img.r.dx()*st.indent);
		* =>
			raise "missing case";
		}

	yspace := mainimg.r.dy()-my;
	yoff: int;
	case st.valign {
	nop->Top =>	yoff = 0;
	nop->Middle =>	yoff = yspace/2;
	nop->Bottom =>	yoff = yspace;
	* =>	raise "missing case";
	}
	img.draw(img.r.addpt(Point(0, y+yoff)), mainimg, nil, Point(0, 0));
	img.flush(Draw->Flushnow);
	return img;
}

textstr(t: ref Text): string
{
	s := "";
	for(l := t.l; l != nil; l = tl l)
		s += (hd l).s;
	return s;
}

max(a, b: int): int
{
	if(a >= b) return a;
	return b;
}

min(a, b: int): int
{
	if(a <= b) return a;
	return b;
}

abs(a: int): int
{
	if(a < 0)
		a = -a;
	return a;
}

kill(pid: int)
{
	if(sys->fprint(sys->open(sprint("/prog/%d/ctl", pid), Sys->OWRITE), "kill") < 0)
		warn(sprint("kill %d: %r", pid));
}

warn(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
}

say(s: string)
{
	if(dflag)
		warn(s);
}

fail(s: string)
{
	warn(s);
	raise "fail:"+s;
}
