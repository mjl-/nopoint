Nopointlib: module
{
	PATH:	con "/dis/lib/nopoint.dis";
	init:	fn(disp: ref Draw->Display);

	Regular, Bold, Italic, Monospace:	con iota;
	Left, Center, Right:	con iota;
	Top, Middle, Bottom:	con iota;
	Wrap, Nowrap:	con iota;

	Word: adt {
		font:	int;
		color:	ref Draw->Image;
		isws:	int;
		s:	string;
	};

	Text: adt {
		l:	list of ref Word;
	};

	Elem: adt {
		pick {
		Text =>
			t:	ref Text;
		List =>
			l:	list of ref (int, ref Text);  # depth, text
		Image =>
			fd:	ref Sys->FD;
			path:	string;
			width:	real;
			height:	real;
			keepratio:	int;
			i:	ref Draw->Image;
		Table =>
			widths:	array of real;
			aligns:	array of int;
			rows:	array of array of ref Text;
		Vspace =>
			r:	real;
		Color =>
			c:	ref Draw->Image;
		Bgcolor =>
			c:	ref Draw->Image;
		Font =>
			ft:	int;
		Fontsize =>
			ftsize:	real;
		Align =>
			align:	int;
		Valign =>
			valign:	int;
		Indent =>
			r:	real;
		}
	};

	Style: adt {
		fgc:	ref Draw->Image;
		bgc:	ref Draw->Image;
		ft:	int;
		ftsize:	real;
		align:	int;
		valign:	int;
		font:	ref Freetype->Face;
		fontsize0:	int;
		indent:	real;
		indent0:	int;
	};

	Slide: adt {
		index:	int;
		style:	ref Style;
		titlestyle:	ref Style;
		title:	ref Text;
		notitle:	int;
		e:	list of ref Elem;
	};


        parse:	fn(path: string, fd: ref Sys->FD): (array of ref Slide, string);
};
