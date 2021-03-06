module de.utfstring;

import std.traits : isNumeric, isSomeChar;
import std.range : ElementType;

char[] numberToString(T)(char[] buf, T number, size_t base = 10) if (isNumeric!T) {
	static string chars = "0123456789ABCDEF";
	assert(base <= chars.length);
	bool negative = number < 0;
	if (negative)
		number = -number;

	size_t count;
	while (number > 0) {
		buf[buf.length - ++count] = chars[number % base];
		number /= base;
	}
	if (negative)
		buf[buf.length - ++count] = '-';

	return buf[buf.length - count .. $];
}

private {
	mixin(import("getCharDisplayWidth.d"));
}

int getCharSize(dchar ch) {
	return getCharDisplayWidth(ch);
}

size_t getStringWidth(String)(String str) if (isSomeChar!(ElementType!String)) {
	import std.uni;
	import std.format;

	size_t len;

	foreach (Grapheme grapheme; str.byGrapheme) {
		foreach (ch; grapheme[])
			len += grapheme[0].getCharSize;
	}
	return len;
}

struct Character {
	import std.uni;

	Grapheme grapheme;

	alias grapheme this;

	@property size_t renderWidth() {
		import std.algorithm : max;

		return max(1, grapheme[0].getCharSize);
	}

	@property size_t dataSize() {
		import std.utf : codeLength;

		size_t size;

		foreach (ch; grapheme)
			size += ch.codeLength!char;

		return size;
	}
}

struct UTFString {
	import std.uni;
	import std.traits;
	import std.range : ElementType;

	private char[] _utf8Data;
	private size_t _position;
	size_t[] _lookupOffset;

	private Character _front;
	private size_t _length;
	private size_t _renderedWidth;

	private void _refreshData(bool recreateLookup = true) {
		import std.utf : byDchar;
		import std.range.primitives : walkLength;

		if (recreateLookup) {
			_lookupOffset.length = 0;

			size_t len;
			_lookupOffset ~= len;
			while (len < _utf8Data.length)
				_lookupOffset ~= (len += _utf8Data.graphemeStride(len));
			//_lookupOffset ~= len;

			_length = _utf8Data[toUTF8Offset(_position) .. $].byGrapheme.walkLength;
			_renderedWidth = _utf8Data.getStringWidth;
		}

		auto r = _utf8Data[toUTF8Offset(_position) .. $].byDchar;
		if (r.empty)
			_front = Character.init;
		else
			_front = decodeGrapheme(r).Character;
	}

	this(char[] utf8Data, size_t position) {
		_utf8Data = utf8Data;
		_position = position;
		_refreshData();
	}

	this(String)(String str) if (isSomeChar!(ElementType!String)) {
		import std.conv : to;

		_utf8Data = str.to!(char[]);
		_refreshData();
	}

	this(String)(String chars) if (is(ElementType!String == Character)) {
		import std.array : appender;

		auto app = appender!(char[]);
		foreach (ref Character c; chars)
			foreach (dchar ch; c.grapheme[])
				app.put(ch);

		_utf8Data = app.data;
		_refreshData();
	}

	private size_t toUTF8Offset(size_t idx) {
		return _lookupOffset.length ? _lookupOffset[idx] : 0;
	}

	/+private size_t fromUTF8Offset(size_t offset) {
		size_t len;
		size_t idx;

		while (idx && len < _utf8Data.length) {
			len += _utf8Data.graphemeStride(len);
			idx++;

			if (len == offset)
				return idx;
			else if (len > offset)
				return idx - 1;
		}

		return idx;
	}+/

	void insert(R)(size_t idx, R chars) if (isSomeChar!(ElementType!R)) {
		import std.utf : byChar;
		import std.utf : codeLength;
		import core.stdc.string : memmove;

		char[32] buf;

		auto offset = toUTF8Offset(idx);

		size_t len;
		auto r = chars.byChar;
		while (!r.empty) {
			buf[len++] = r.front;
			r.popFront;
		}

		assert(len);

		_utf8Data.length += len;
		if (offset + len < _utf8Data.length) {
			auto to = &_utf8Data[offset + len];
			auto from = &_utf8Data[offset];

			memmove(to, from, _utf8Data.length - len - offset);
		}

		memmove(&_utf8Data[offset], &buf[0], len);

		_refreshData();
	}

	void remove(size_t idx) {
		import std.utf : byDchar;
		import core.stdc.string : memmove;

		if (idx > _lookupOffset.length)
			return;

		auto offset = toUTF8Offset(idx);
		auto r = _utf8Data[offset .. $].byDchar;
		Character c = decodeGrapheme(r).Character;

		if (idx < _lookupOffset.length - 1 && _utf8Data.length - c.dataSize - offset) {
			auto to = &_utf8Data[offset];
			auto from = &_utf8Data[offset + c.dataSize];

			memmove(to, from, _utf8Data.length - c.dataSize - offset);
		}
		_utf8Data.length -= c.dataSize;
		_refreshData();
	}

	@property Character front() {
		return _front;
	}

	void popFront() {
		_renderedWidth -= front.renderWidth;

		_position++;
		_length--;

		_refreshData(false);
	}

	void reset() {
		import std.range.primitives : walkLength;

		_position = 0;

		_length = _utf8Data.byGrapheme.walkLength;
	}

	@property bool empty() {
		return !_length;
	}

	@property UTFString save() {
		return this;
	}

	@property size_t length() {
		return _length;
	}

	@property size_t renderedWidth() {
		return _renderedWidth;
	}

	size_t opDollar(size_t pos : 0)() {
		return length;
	}

	Character opIndex(size_t idx) {
		import std.utf : byDchar;

		auto r = _utf8Data[toUTF8Offset(_position + idx) .. $].byDchar;
		return decodeGrapheme(r).Character;
	}

	auto opSlice(size_t x, size_t y) {
		import std.range : takeExactly;
		import std.algorithm : map;

		return _utf8Data[toUTF8Offset(_position + x) .. $].byGrapheme.map!((c) => Character(c)).takeExactly(y - x);
	}

	int opApply(scope int delegate(ref Character) dg) {
		int result = 0;
		auto r = save();

		while (!r.empty) {
			auto ch = r.front;
			result = dg(ch);
			if (result)
				break;
			r.popFront;
		}

		return result;
	}

	int opApply(scope int delegate(size_t, ref Character) dg) {
		int result = 0;
		auto r = save();

		size_t idx;
		while (!r.empty) {
			auto ch = r.front;
			result = dg(idx++, ch);
			if (result)
				break;
			r.popFront;
		}

		return result;
	}

	@property void rawData(char[] data) {
		_utf8Data = data;
		_refreshData();
	}

	@property char[] rawData() {
		return _utf8Data[toUTF8Offset(_position) .. $];
	}

	void opOpAssign(string op : "~")(UTFString other) {
		_utf8Data ~= other._utf8Data;
		_refreshData();
	}
}
