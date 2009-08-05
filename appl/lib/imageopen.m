Imageopen: module
{
	PATH: con "/dis/lib/imageopen.dis";
	init:	fn(disp: ref Draw->Display);

	openimage:	fn(fd: ref Sys->FD, path: string): (ref Draw->Image, string);
	resample:	fn(i: ref Draw->Image, w, h: int): ref Draw->Image;
};
