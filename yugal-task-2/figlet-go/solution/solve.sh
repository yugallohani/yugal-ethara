#!/bin/bash
# Oracle for figlet-go: writes a Go port of pyfiglet 1.0.4 into /workspace/repo,
# moves the .flf fonts into /workspace/repo/fonts (embedded with go:embed),
# deletes every .py file, and builds once as a check.
set -euo pipefail
cd /workspace/repo

mkdir -p fonts
if ls pyfiglet/fonts/*.flf >/dev/null 2>&1; then
  mv pyfiglet/fonts/*.flf fonts/
else
  cp pyfiglet/fonts-standard/*.flf fonts/
fi

cat > go.mod <<'FIGLET_GO_EOF'
module figlet

go 1.23
FIGLET_GO_EOF

cat > main.go <<'FIGLET_GO_EOF'
// Command figlet is a Go port of pyfiglet 1.0.4
// (github.com/pwaller/pyfiglet @ 255827efbc09d662875dad50fa0edc1e1263bf45).
// It prints the same bytes as `python -m pyfiglet` for the options
// -f, -w, -j, -D, -r, -F, -s and -n.
package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

const version = "1.0.4"
const defaultFont = "standard"

type options struct {
	font      string
	direction string
	justify   string
	width     int64
	reverse   bool
	normalize bool
	strip     bool
	flip      bool
	listFonts bool
	infoFont  bool
	load      string
	color     string
	help      bool
	version   bool
}

type optSpec struct {
	short, long string
	takesValue  bool
	set         func(o *options, v string) error
}

type usageError struct{ msg string }

func (e usageError) Error() string { return e.msg }

func choice(name string, allowed []string, dst func(o *options) *string) func(*options, string) error {
	return func(o *options, v string) error {
		for _, a := range allowed {
			if v == a {
				*dst(o) = v
				return nil
			}
		}
		quoted := make([]string, len(allowed))
		for i, a := range allowed {
			quoted[i] = pyRepr(a)
		}
		return usageError{fmt.Sprintf("option %s: invalid choice: %s (choose from %s)",
			name, pyRepr(v), strings.Join(quoted, ", "))}
	}
}

var specs = []optSpec{
	{"-f", "--font", true, func(o *options, v string) error { o.font = v; return nil }},
	{"-D", "--direction", true, choice("-D", []string{"auto", "left-to-right", "right-to-left"},
		func(o *options) *string { return &o.direction })},
	{"-j", "--justify", true, choice("-j", []string{"auto", "left", "center", "right"},
		func(o *options) *string { return &o.justify })},
	{"-w", "--width", true, func(o *options, v string) error {
		n, ok := optparseInt(v)
		if !ok {
			return usageError{fmt.Sprintf("option -w: invalid integer value: %s", pyRepr(v))}
		}
		o.width = n
		return nil
	}},
	{"-r", "--reverse", false, func(o *options, _ string) error { o.reverse = true; return nil }},
	{"-n", "--normalize-surrounding-newlines", false, func(o *options, _ string) error { o.normalize = true; return nil }},
	{"-s", "--strip-surrounding-newlines", false, func(o *options, _ string) error { o.strip = true; return nil }},
	{"-F", "--flip", false, func(o *options, _ string) error { o.flip = true; return nil }},
	{"-l", "--list_fonts", false, func(o *options, _ string) error { o.listFonts = true; return nil }},
	{"-i", "--info_font", false, func(o *options, _ string) error { o.infoFont = true; return nil }},
	{"-L", "--load", true, func(o *options, v string) error { o.load = v; return nil }},
	{"-c", "--color", true, func(o *options, v string) error { o.color = v; return nil }},
	{"-h", "--help", false, func(o *options, _ string) error { o.help = true; return nil }},
	{"", "--version", false, func(o *options, _ string) error { o.version = true; return nil }},
}

// optparseInt reproduces optparse's _parse_num(val, int).
func optparseInt(v string) (int64, bool) {
	l := strings.ToLower(v)
	switch {
	case strings.HasPrefix(l, "0x"):
		return pyInt(v, 16)
	case strings.HasPrefix(l, "0b"):
		v = v[2:]
		if v == "" {
			v = "0"
		}
		return pyInt(v, 2)
	case strings.HasPrefix(v, "0"):
		return pyInt(v, 8)
	}
	return pyInt(v, 10)
}

// parseArgs reproduces optparse with interspersed arguments allowed.
func parseArgs(argv []string) (*options, []string, error) {
	o := &options{font: defaultFont, direction: "auto", justify: "auto", width: 80, color: ":"}
	var args []string
	for i := 0; i < len(argv); i++ {
		a := argv[i]
		switch {
		case a == "--":
			args = append(args, argv[i+1:]...)
			return o, args, nil
		case strings.HasPrefix(a, "--"):
			name, val, hasVal := strings.Cut(a, "=")
			spec, err := matchLong(name)
			if err != nil {
				return nil, nil, err
			}
			if spec.takesValue {
				if !hasVal {
					if i+1 >= len(argv) {
						return nil, nil, usageError{name + " option requires 1 argument"}
					}
					i++
					val = argv[i]
				}
			} else if hasVal {
				return nil, nil, usageError{spec.long + " option does not take a value"}
			}
			if err := spec.set(o, val); err != nil {
				return nil, nil, err
			}
		case len(a) > 1 && a[0] == '-':
			rest := a[1:]
			for len(rest) > 0 {
				ch := rest[:1]
				rest = rest[1:]
				spec := matchShort("-" + ch)
				if spec == nil {
					return nil, nil, usageError{"no such option: -" + ch}
				}
				val := ""
				if spec.takesValue {
					if rest != "" {
						val, rest = rest, ""
					} else {
						if i+1 >= len(argv) {
							return nil, nil, usageError{"-" + ch + " option requires 1 argument"}
						}
						i++
						val = argv[i]
					}
				}
				if err := spec.set(o, val); err != nil {
					return nil, nil, err
				}
			}
		default:
			args = append(args, a)
		}
	}
	return o, args, nil
}

func matchShort(s string) *optSpec {
	for i := range specs {
		if specs[i].short == s {
			return &specs[i]
		}
	}
	return nil
}

func matchLong(name string) (*optSpec, error) {
	for i := range specs {
		if specs[i].long == name {
			return &specs[i], nil
		}
	}
	var hits []*optSpec
	for i := range specs {
		if strings.HasPrefix(specs[i].long, name) {
			hits = append(hits, &specs[i])
		}
	}
	switch len(hits) {
	case 1:
		return hits[0], nil
	case 0:
		return nil, usageError{"no such option: " + name}
	}
	names := make([]string, len(hits))
	for i, h := range hits {
		names[i] = h.long
	}
	return nil, usageError{fmt.Sprintf("ambiguous option: %s (%s?)", name, strings.Join(names, ", "))}
}

const usage = "Usage: pyfiglet [options] [text..]\n"

const helpText = usage + `
Options:
  --version             show program's version number and exit
  -h, --help            show this help message and exit
  -f FONT, --font=FONT  font to render with (default: standard)
  -D DIRECTION, --direction=DIRECTION
                        set direction text will be formatted in (default:
                        auto)
  -j SIDE, --justify=SIDE
                        set justification, defaults to print direction
  -w COLS, --width=COLS
                        set terminal width for wrapping/justification
                        (default: 80)
  -r, --reverse         shows mirror image of output text
  -n, --normalize-surrounding-newlines
                        output has one empty line before and after
  -s, --strip-surrounding-newlines
                        removes empty leading and trailing lines
  -F, --flip            flips rendered output text over
  -l, --list_fonts      show installed fonts list
  -i, --info_font       show font's information, use with -f FONT
  -L LOAD, --load=LOAD  load and install the specified font definition
  -c COLOR, --color=COLOR
                        prints text with passed foreground color,
                        --color=foreground:background
                        --color=:background                  # only background
                        --color=foreground | foreground:     # only foreground
                        --color=list                         # list all colors
                        COLOR = list[COLOR] | [0-255];[0-255];[0-255] (RGB)
`

var colorCodes = map[string]int{
	"BLACK": 30, "RED": 31, "GREEN": 32, "YELLOW": 33, "BLUE": 34, "MAGENTA": 35,
	"CYAN": 36, "LIGHT_GRAY": 37, "DEFAULT": 39, "DARK_GRAY": 90, "LIGHT_RED": 91,
	"LIGHT_GREEN": 92, "LIGHT_YELLOW": 93, "LIGHT_BLUE": 94, "LIGHT_MAGENTA": 95,
	"LIGHT_CYAN": 96, "WHITE": 97, "RESET": 0,
}

func colorToANSI(color string, background bool) string {
	if color == "" {
		return ""
	}
	color = strings.ToUpper(color)
	n := strings.Count(color, ";")
	if n > 0 && n != 2 {
		raise("InvalidColor", "Specified color '{}' not a valid color in R;G;B format")
	}
	code, known := colorCodes[color]
	if n == 0 && !known {
		raise("InvalidColor", fmt.Sprintf("Specified color '%s' not found in ANSI COLOR_CODES list", color))
	}
	if known {
		if background {
			code += 10
		}
		return fmt.Sprintf("\033[%dm", code)
	}
	base := 38
	if background {
		base = 48
	}
	return fmt.Sprintf("\033[%d;2;%sm", base, color)
}

func parseColor(c string) string {
	fg, bg, _ := strings.Cut(c, ":")
	return colorToANSI(fg, false) + colorToANSI(bg, true)
}

func resolveDirection(o *options, f *Font) string {
	if o.direction != "auto" {
		return o.direction
	}
	if f.printDirection != nil && *f.printDirection == 1 {
		return "right-to-left"
	}
	return "left-to-right"
}

func resolveJustify(o *options, direction string) string {
	if o.justify != "auto" {
		return o.justify
	}
	if direction == "left-to-right" {
		return "left"
	}
	if direction == "right-to-left" {
		return "right"
	}
	return "None"
}

// run returns the bytes for stdout and the exit code. Any pyfiglet exception
// becomes a panic that the caller turns into "no stdout, exit 1".
func run(argv []string) (string, int) {
	o, args, err := parseArgs(argv)
	if err != nil {
		fmt.Fprint(os.Stderr, usage+"\npyfiglet: error: "+err.Error()+"\n")
		return "", 2
	}
	if o.help {
		return helpText, 0
	}
	if o.version {
		return version + "\n", 0
	}
	if o.listFonts {
		return strings.Join(listFonts(), "\n") + "\n", 0
	}
	if o.color == "list" {
		keys := make([]string, 0, len(colorCodes))
		for k := range colorCodes {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		return "[0-255];[0-255];[0-255] # RGB\n" + strings.Join(keys, "\n") + "\n", 0
	}
	if o.infoFont {
		return infoFont(o.font) + "\n", 0
	}
	if o.load != "" {
		fmt.Fprintln(os.Stderr, "figlet: installing fonts (-L) is not supported")
		return "", 1
	}
	if len(args) == 0 {
		return helpText, 1
	}
	text := strings.Join(args, " ")

	font, notFound := loadFontOrNotFound(o.font)
	if notFound {
		return fmt.Sprintf("pyfiglet error: requested font %s not found.\n", pyRepr(o.font)), 1
	}
	direction := resolveDirection(o, font)
	justify := resolveJustify(o, direction)
	r := newBuilder(text, font, direction, o.width, justify).render()
	if o.reverse {
		r = figReverse(r)
	}
	if o.flip {
		r = figFlip(r)
	}
	if o.strip {
		r = figStripSurroundingNewlines(r)
	} else if o.normalize {
		r = figNormalizeSurroundingNewlines(r)
	}
	colors := parseColor(o.color)
	out := colors + r + "\n"
	if colors != "" {
		out += "\033[0m"
	}
	return out, 0
}

func loadFontOrNotFound(name string) (f *Font, notFound bool) {
	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(fontNotFound); ok {
				f, notFound = nil, true
				return
			}
			panic(r)
		}
	}()
	return LoadFont(name), false
}

func infoFont(name string) string {
	data := pySplitlines(preloadFont(name))
	if len(data) > 100 {
		data = data[:100]
	}
	starts := []string{"FONT", "COMMENT", "FONTNAME_REGISTRY", "FAMILY_NAME", "FOUNDRY",
		"WEIGHT_NAME", "SETWIDTH_NAME", "SLANT", "ADD_STYLE_NAME", "PIXEL_SIZE",
		"POINT_SIZE", "RESOLUTION_X", "RESOLUTION_Y", "SPACING", "AVERAGE_WIDTH",
		"FONT_DESCENT", "FONT_ASCENT", "CAP_HEIGHT", "X_HEIGHT", "FACE_NAME",
		"FULL_NAME", "COPYRIGHT", "_DEC_", "DEFAULT_CHAR", "NOTICE", "RELATIVE_"}
	var infos []string
	for _, l := range data {
		s := string(l)
		if isMagic(l) {
			continue
		}
		skip := false
		for _, p := range starts {
			if strings.HasPrefix(s, p) {
				skip = true
				break
			}
		}
		if skip {
			continue
		}
		if n := len(l); n > 0 && (l[n-1] == '@' || l[n-1] == '#' || l[n-1] == '$') {
			continue
		}
		infos = append(infos, s)
	}
	return strings.Join(infos, "\n")
}

func main() {
	code := 0
	out := ""
	func() {
		defer func() {
			if r := recover(); r != nil {
				out, code = "", 1
				if e, ok := r.(pyError); ok {
					fmt.Fprintf(os.Stderr, "Traceback (most recent call last):\npyfiglet.%s: %s\n", e.kind, e.msg)
				} else {
					fmt.Fprintf(os.Stderr, "Traceback (most recent call last):\nError: %v\n", r)
				}
			}
		}()
		out, code = run(os.Args[1:])
	}()
	if out != "" {
		os.Stdout.WriteString(out)
	}
	os.Exit(code)
}
FIGLET_GO_EOF

cat > font.go <<'FIGLET_GO_EOF'
package main

// Port of pyfiglet.FigletFont: font lookup and .flf parsing.

import (
	"archive/zip"
	"bytes"
	"embed"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed fonts/*.flf
var embeddedFonts embed.FS

const embeddedDir = "fonts"

var fontDirectories = []string{
	"/usr/local/share/pyfiglet/",
	"/usr/local/share/figlet",
	"/usr/share/figlet",
}

// pyError is raised (via panic) wherever pyfiglet would raise an exception.
type pyError struct{ kind, msg string }

func raise(kind, msg string) { panic(pyError{kind, msg}) }

type fontNotFound struct{ name string }

const (
	smEqual     = 1
	smLowline   = 2
	smHierarchy = 4
	smPair      = 8
	smBigX      = 16
	smHardblank = 32
	smKern      = 64
	smSmush     = 128
)

type Font struct {
	name           string
	height         int
	hardBlank      string
	hardBlankRune  rune // -3 if hardBlank is not exactly one character
	printDirection *int64
	smushMode      int64
	chars          map[rune][][]rune
	width          map[rune]int
}

func embeddedExists(name string) bool {
	p := path.Join(embeddedDir, name)
	if !fs.ValidPath(p) || strings.Contains(name, "/") {
		return false
	}
	st, err := fs.Stat(embeddedFonts, p)
	return err == nil && !st.IsDir()
}

func isFile(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular()
}

// preloadFont reproduces FigletFont.preloadFont, including its loop quirk:
// the inner break only leaves the location loop, so a later extension found
// in the package directory wins over an earlier one found on disk.
func preloadFont(font string) []rune {
	var data []byte
	found := false
	fromEmbed := false
	fontPath := ""
	for _, ext := range []string{"tlf", "flf"} {
		fn := font + "." + ext
		if embeddedExists(fn) {
			fontPath, fromEmbed, found = path.Join(embeddedDir, fn), true, true
			break
		}
		for _, loc := range append([]string{"./"}, fontDirectories...) {
			full := filepath.Join(loc, fn)
			if isFile(full) {
				fontPath, fromEmbed, found = full, false, true
				break
			}
		}
	}
	if found {
		var raw []byte
		var err error
		if fromEmbed {
			raw, err = embeddedFonts.ReadFile(fontPath)
		} else {
			raw, err = os.ReadFile(fontPath)
		}
		if err != nil {
			raise("OSError", err.Error())
		}
		data = raw
		if zr, zerr := zip.NewReader(bytes.NewReader(raw), int64(len(raw))); zerr == nil && len(zr.File) > 0 {
			f, err := zr.File[0].Open()
			if err != nil {
				raise("BadZipFile", err.Error())
			}
			data, err = io.ReadAll(f)
			f.Close()
			if err != nil {
				raise("BadZipFile", err.Error())
			}
		}
	}
	if len(data) == 0 {
		panic(fontNotFound{font})
	}
	return decodeUTF8Replace(data)
}

func isMagic(header []rune) bool {
	return len(header) >= 5 && (header[0] == 't' || header[0] == 'f') &&
		header[1] == 'l' && header[2] == 'f' && header[3] == '2' && header[4] != '\n'
}

func allSpace(s []rune) bool {
	for _, r := range s {
		if !pyIsSpace(r) {
			return false
		}
	}
	return true
}

// endMarker reproduces re.search(r'(.)\s*$', line).group(1).
func endMarker(line []rune) (rune, bool) {
	for p := 0; p < len(line); p++ {
		if line[p] != '\n' && allSpace(line[p+1:]) {
			return line[p], true
		}
	}
	return 0, false
}

// stripEnd reproduces re.sub(re.escape(end) + r'{1,2}\s*$', ”, line).
func stripEnd(line []rune, end rune) []rune {
	for s := 0; s < len(line); s++ {
		if line[s] != end {
			continue
		}
		if s+1 < len(line) && line[s+1] == end && allSpace(line[s+2:]) {
			return line[:s]
		}
		if allSpace(line[s+1:]) {
			return line[:s]
		}
	}
	return line
}

func joinEmpty(rows [][]rune) bool {
	for _, r := range rows {
		if len(r) > 0 {
			return false
		}
	}
	return true
}

func LoadFont(name string) *Font {
	f := &Font{name: name, chars: map[rune][][]rune{}, width: map[rune]int{}}
	raw := preloadFont(name)
	f.parse(raw)
	return f
}

func (f *Font) parse(text []rune) {
	defer func() {
		if r := recover(); r != nil {
			if nf, ok := r.(fontNotFound); ok {
				panic(nf)
			}
			raise("FontError", "problem parsing "+f.name+" font")
		}
	}()

	for i, r := range text {
		if r == 0x85 || r == 0x2028 || r == 0x2029 {
			text[i] = ' '
		}
	}
	data := pySplitlines(text)
	pop := func() []rune {
		if len(data) == 0 {
			raise("IndexError", "pop from empty list")
		}
		l := data[0]
		data = data[1:]
		return l
	}

	header := pop()
	if !isMagic(header) {
		raise("FontError", f.name+" is not a valid figlet font")
	}
	fields := pySplit(header[5:])
	if len(fields) < 6 {
		raise("FontError", "malformed header for "+f.name)
	}
	f.hardBlank = string(fields[0])
	f.hardBlankRune = -3
	if len(fields[0]) == 1 {
		f.hardBlankRune = fields[0][0]
	}
	nums := make([]int64, 5)
	for i := 0; i < 5; i++ {
		v, ok := pyInt(string(fields[1+i]), 10)
		if !ok {
			raise("ValueError", "invalid literal for int()")
		}
		nums[i] = v
	}
	height, oldLayout, commentLines := nums[0], nums[3], nums[4]
	var fullLayout *int64
	if len(fields) > 6 {
		v, ok := pyInt(string(fields[6]), 10)
		if !ok {
			raise("ValueError", "invalid literal for int()")
		}
		f.printDirection = &v
	}
	if len(fields) > 7 {
		v, ok := pyInt(string(fields[7]), 10)
		if !ok {
			raise("ValueError", "invalid literal for int()")
		}
		fullLayout = &v
	}
	if fullLayout == nil {
		var v int64
		switch {
		case oldLayout == 0:
			v = 64
		case oldLayout < 0:
			v = 0
		default:
			v = (oldLayout & 31) | 128
		}
		fullLayout = &v
	}
	f.height = int(height)
	f.smushMode = *fullLayout

	for i := int64(0); i < commentLines; i++ {
		pop()
	}

	readChar := func() (int, [][]rune) {
		var end rune
		haveEnd := false
		width := 0
		var rows [][]rune
		for i := int64(0); i < height; i++ {
			line := pop()
			if !haveEnd {
				e, ok := endMarker(line)
				if !ok {
					raise("AttributeError", "'NoneType' object has no attribute 'group'")
				}
				end, haveEnd = e, true
			}
			line = stripEnd(line, end)
			if len(line) > width {
				width = len(line)
			}
			rows = append(rows, line)
		}
		return width, rows
	}

	for i := rune(32); i < 127; i++ {
		w, letter := readChar()
		if i == 32 || !joinEmpty(letter) {
			f.chars[i] = letter
			f.width[i] = w
		}
	}
	if len(data) > 0 {
		for _, c := range "ÄÖÜäöüß" {
			w, letter := readChar()
			if !joinEmpty(letter) {
				f.chars[c] = letter
				f.width[c] = w
			}
		}
	}
	for len(data) > 0 {
		line := pyStrip(pop())
		tok := string(line)
		if k := strings.IndexByte(tok, ' '); k >= 0 {
			tok = tok[:k]
		}
		if tok == "" {
			continue
		}
		if len(tok) >= 2 && strings.EqualFold(tok[:2], "0x") {
			code, ok := pyInt(tok, 16)
			if !ok {
				raise("ValueError", "invalid literal for int() with base 16")
			}
			w, letter := readChar()
			if !joinEmpty(letter) {
				key := rune(-4) // a code no text character can have
				if code >= 0 && code <= 0x7fffffff {
					key = rune(code)
				}
				f.chars[key] = letter
				f.width[key] = w
			}
		}
	}
}

// listFonts reproduces FigletFont.getFonts() for the embedded font folder
// plus the system font directories.
func listFonts() []string {
	var names []string
	entries, _ := embeddedFonts.ReadDir(embeddedDir)
	for _, e := range entries {
		if !e.IsDir() && validFontName(e.Name()) {
			names = append(names, strings.SplitN(e.Name(), ".", 3)[0])
		}
	}
	for _, loc := range fontDirectories {
		ents, err := os.ReadDir(loc)
		if err != nil {
			continue
		}
		for _, e := range ents {
			if e.Type().IsRegular() && validFontName(e.Name()) {
				names = append(names, strings.SplitN(e.Name(), ".", 3)[0])
			}
		}
	}
	sort.Strings(names)
	return names
}

func validFontName(n string) bool {
	return strings.HasSuffix(n, ".flf") || strings.HasSuffix(n, ".tlf")
}
FIGLET_GO_EOF

cat > pystr.go <<'FIGLET_GO_EOF'
package main

// Helpers that reproduce the Python str semantics pyfiglet relies on.

import (
	"strings"
	"unicode/utf8"
)

// pyIsSpace matches Python's str.isspace() (and re's \s for str patterns).
func pyIsSpace(r rune) bool {
	switch {
	case r >= 0x09 && r <= 0x0d, r >= 0x1c && r <= 0x20:
		return true
	case r == 0x85, r == 0xa0, r == 0x1680:
		return true
	case r >= 0x2000 && r <= 0x200a:
		return true
	case r == 0x2028, r == 0x2029, r == 0x202f, r == 0x205f, r == 0x3000:
		return true
	}
	return false
}

// isLineBreak matches the characters Python's str.splitlines() splits on.
func isLineBreak(r rune) bool {
	switch r {
	case '\n', '\r', 0x0b, 0x0c, 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029:
		return true
	}
	return false
}

// pySplitlines reproduces str.splitlines() without keepends.
func pySplitlines(s []rune) [][]rune {
	var out [][]rune
	start := 0
	for i := 0; i < len(s); i++ {
		if !isLineBreak(s[i]) {
			continue
		}
		out = append(out, s[start:i])
		if s[i] == '\r' && i+1 < len(s) && s[i+1] == '\n' {
			i++
		}
		start = i + 1
	}
	if start < len(s) {
		out = append(out, s[start:])
	}
	return out
}

func pySplitlinesString(s string) []string {
	lines := pySplitlines([]rune(s))
	out := make([]string, len(lines))
	for i, l := range lines {
		out[i] = string(l)
	}
	return out
}

// pySplit reproduces str.split() with no arguments.
func pySplit(s []rune) [][]rune {
	var out [][]rune
	i := 0
	for i < len(s) {
		for i < len(s) && pyIsSpace(s[i]) {
			i++
		}
		if i >= len(s) {
			break
		}
		j := i
		for j < len(s) && !pyIsSpace(s[j]) {
			j++
		}
		out = append(out, s[i:j])
		i = j
	}
	return out
}

func pyStrip(s []rune) []rune {
	i, j := 0, len(s)
	for i < j && pyIsSpace(s[i]) {
		i++
	}
	for j > i && pyIsSpace(s[j-1]) {
		j--
	}
	return s[i:j]
}

func pyStripString(s string) string { return string(pyStrip([]rune(s))) }

func pyRstripString(s string) string {
	r := []rune(s)
	j := len(r)
	for j > 0 && pyIsSpace(r[j-1]) {
		j--
	}
	return string(r[:j])
}

// rstripSpaceLen / lstripSpaceLen: length after str.rstrip(' ') / str.lstrip(' ').
func rstripSpaceLen(s []rune) int {
	j := len(s)
	for j > 0 && s[j-1] == ' ' {
		j--
	}
	return j
}

func lstripSpaceLen(s []rune) int {
	i := 0
	for i < len(s) && s[i] == ' ' {
		i++
	}
	return len(s) - i
}

// decodeUTF8Replace reproduces bytes.decode('UTF-8', 'replace'): each maximal
// invalid subpart becomes one U+FFFD.
func decodeUTF8Replace(b []byte) []rune {
	out := make([]rune, 0, len(b))
	for i := 0; i < len(b); {
		r, size := utf8.DecodeRune(b[i:])
		if r != utf8.RuneError || size > 1 {
			out = append(out, r)
			i += size
			continue
		}
		// invalid: consume the maximal valid prefix of a multi-byte sequence
		lead := b[i]
		need, lo, hi := 0, byte(0x80), byte(0xbf)
		switch {
		case lead >= 0xc2 && lead <= 0xdf:
			need = 1
		case lead == 0xe0:
			need, lo = 2, 0xa0
		case (lead >= 0xe1 && lead <= 0xec) || lead == 0xee || lead == 0xef:
			need = 2
		case lead == 0xed:
			need, hi = 2, 0x9f
		case lead == 0xf0:
			need, lo = 3, 0x90
		case lead >= 0xf1 && lead <= 0xf3:
			need = 3
		case lead == 0xf4:
			need, hi = 3, 0x8f
		}
		j := i + 1
		for k := 0; k < need && j < len(b); k++ {
			c := b[j]
			if k == 0 {
				if c < lo || c > hi {
					break
				}
			} else if c < 0x80 || c > 0xbf {
				break
			}
			j++
		}
		out = append(out, utf8.RuneError)
		i = j
	}
	return out
}

// pyInt reproduces int(s, base) for the inputs pyfiglet feeds it: optional
// surrounding whitespace, optional sign, optional 0x/0o/0b prefix matching
// base, and single underscores between digits.
func pyInt(s string, base int) (int64, bool) {
	r := pyStrip([]rune(s))
	t := string(r)
	neg := false
	if strings.HasPrefix(t, "+") || strings.HasPrefix(t, "-") {
		neg = t[0] == '-'
		t = t[1:]
	}
	lower := strings.ToLower(t)
	prefixed := false
	if (base == 16 && strings.HasPrefix(lower, "0x")) ||
		(base == 8 && strings.HasPrefix(lower, "0o")) ||
		(base == 2 && strings.HasPrefix(lower, "0b")) {
		t = t[2:]
		prefixed = true
	}
	if prefixed && strings.HasPrefix(t, "_") {
		t = t[1:]
	}
	if t == "" || strings.HasPrefix(t, "_") || strings.HasSuffix(t, "_") || strings.Contains(t, "__") {
		return 0, false
	}
	var v int64
	overflow := false
	for _, c := range t {
		if c == '_' {
			continue
		}
		var d int
		switch {
		case c >= '0' && c <= '9':
			d = int(c - '0')
		case c >= 'a' && c <= 'z':
			d = int(c-'a') + 10
		case c >= 'A' && c <= 'Z':
			d = int(c-'A') + 10
		default:
			return 0, false
		}
		if d >= base {
			return 0, false
		}
		if v > (1<<62)/int64(base) {
			overflow = true
		}
		v = v*int64(base) + int64(d)
	}
	if overflow {
		v = 1<<62 + 1 // out of any rune range; behaves as "no such code"
	}
	if neg {
		v = -v
	}
	return v, true
}

// pyRepr reproduces repr() of a str closely enough for an error message.
func pyRepr(s string) string {
	quote := byte('\'')
	if strings.Contains(s, "'") && !strings.Contains(s, "\"") {
		quote = '"'
	}
	var b strings.Builder
	b.WriteByte(quote)
	for _, r := range s {
		switch {
		case r == rune(quote) || r == '\\':
			b.WriteByte('\\')
			b.WriteRune(r)
		case r == '\n':
			b.WriteString(`\n`)
		case r == '\r':
			b.WriteString(`\r`)
		case r == '\t':
			b.WriteString(`\t`)
		case r < 0x20 || r == 0x7f:
			b.WriteString(`\x`)
			b.WriteString(hex2(int(r)))
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte(quote)
	return b.String()
}

func hex2(v int) string {
	const digits = "0123456789abcdef"
	return string([]byte{digits[v>>4&0xf], digits[v&0xf]})
}
FIGLET_GO_EOF

cat > render.go <<'FIGLET_GO_EOF'
package main

// Port of pyfiglet.FigletBuilder / FigletRenderingEngine / FigletString.
// Every method mirrors the Python one of the same name. Rows are []rune
// (Python str indexes code points) and are never modified in place, because
// Python strings are immutable and saved buffers share them.

import "strings"

// noChar stands for the Python empty string ” used as a "character".
// Note that in Python  ” in "abc"  is True.
const noChar rune = -1

type marker struct {
	buffer   [][]rune
	iterator int
}

type Builder struct {
	text      []rune
	direction string
	width     int64
	font      *Font
	justify   string

	iterator          int
	maxSmush          int
	curCharWidth      int
	prevCharWidth     int
	currentTotalWidth int64

	blankMarkers []marker
	queue        [][][]rune
	buffer       [][]rune

	lastEmptyCut int // loop guard, see cutBufferAtLastChar
}

func newBuilder(text string, font *Font, direction string, width int64, justify string) *Builder {
	b := &Builder{
		text: []rune(text), direction: direction, width: width,
		font: font, justify: justify, lastEmptyCut: -2,
	}
	b.buffer = emptyBuffer(font.height)
	return b
}

func emptyBuffer(h int) [][]rune {
	if h < 0 {
		h = 0
	}
	return make([][]rune, h)
}

func copyBuffer(buf [][]rune) [][]rune {
	out := make([][]rune, len(buf))
	copy(out, buf)
	return out
}

func (b *Builder) render() string {
	for b.iterator < len(b.text) {
		b.addCharToProduct()
		b.iterator++
	}
	return b.returnProduct()
}

func (b *Builder) addCharToProduct() {
	if b.text[b.iterator] == '\n' {
		b.blankMarkers = append(b.blankMarkers, marker{copyBuffer(b.buffer), b.iterator})
		b.handleNewLine()
		return
	}
	curChar, ok := b.charAt(b.iterator)
	if !ok {
		return
	}
	w := b.font.width[b.text[b.iterator]]
	if b.width < int64(w) {
		raise("CharNotPrinted", "Width is not enough to print this character")
	}
	b.curCharWidth = w
	b.maxSmush = b.smushAmount(b.buffer, curChar)
	b.currentTotalWidth = int64(len(b.buffer[0]) + b.curCharWidth - b.maxSmush)

	if b.text[b.iterator] == ' ' {
		b.blankMarkers = append(b.blankMarkers, marker{copyBuffer(b.buffer), b.iterator})
	}

	if b.currentTotalWidth >= b.width {
		b.handleNewLine()
	} else {
		for row := 0; row < b.font.height; row++ {
			b.addCurCharRowToBufferRow(curChar, row)
		}
	}
	b.prevCharWidth = b.curCharWidth
}

func (b *Builder) returnProduct() string {
	if len(b.buffer) > 0 && len(b.buffer[0]) != 0 {
		b.queue = append(b.queue, b.buffer)
	} else if len(b.buffer) == 0 {
		raise("IndexError", "list index out of range")
	}
	return b.formatProduct()
}

func (b *Builder) formatProduct() string {
	var acc strings.Builder
	for _, buf := range b.queue {
		buf = b.justifyString(b.justify, buf)
		acc.WriteString(b.replaceHardblanks(buf))
	}
	return acc.String()
}

func (b *Builder) charAt(i int) ([][]rune, bool) {
	if i < 0 || i >= len(b.text) {
		return nil, false
	}
	c, ok := b.font.chars[b.text[i]]
	return c, ok
}

func (b *Builder) smushRow(curChar [][]rune, row int) ([]rune, []rune) {
	addLeft := b.buffer[row]
	addRight := curChar[row]
	if b.direction == "right-to-left" {
		addLeft, addRight = addRight, addLeft
	}
	for i := 0; i < b.maxSmush; i++ {
		idx := len(addLeft) - b.maxSmush + i
		left := noChar
		if idx >= 0 && idx < len(addLeft) {
			left = addLeft[idx]
		}
		if i >= len(addRight) {
			raise("IndexError", "string index out of range")
		}
		right := addRight[i]
		smushed, ok := b.smushChars(left, right)
		addLeft = updateSmushedCharInLeftBuffer(addLeft, idx, smushed, ok)
	}
	return addLeft, addRight
}

func updateSmushedCharInLeftBuffer(addLeft []rune, idx int, smushed rune, ok bool) []rune {
	if idx < 0 || idx > len(addLeft) {
		return addLeft
	}
	if idx == len(addLeft) {
		raise("IndexError", "list assignment index out of range")
	}
	if !ok {
		raise("TypeError", "sequence item: expected str instance, NoneType found")
	}
	out := make([]rune, 0, len(addLeft))
	out = append(out, addLeft[:idx]...)
	if smushed != noChar {
		out = append(out, smushed)
	}
	out = append(out, addLeft[idx+1:]...)
	return out
}

func (b *Builder) addCurCharRowToBufferRow(curChar [][]rune, row int) {
	addLeft, addRight := b.smushRow(curChar, row)
	tail := []rune{}
	if b.maxSmush < len(addRight) {
		tail = addRight[b.maxSmush:]
	}
	nr := make([]rune, 0, len(addLeft)+len(tail))
	nr = append(nr, addLeft...)
	nr = append(nr, tail...)
	b.buffer[row] = nr
}

func (b *Builder) cutBufferCommon() {
	b.currentTotalWidth = 0
	b.buffer = emptyBuffer(b.font.height)
	b.blankMarkers = nil
	b.prevCharWidth = 0
	// pyfiglet also recomputes maxSmush here; the value is always
	// recomputed before it is used, and the call has no side effects.
}

func (b *Builder) handleNewLine() {
	if n := len(b.blankMarkers); n > 0 {
		m := b.blankMarkers[n-1]
		b.blankMarkers = b.blankMarkers[:n-1]
		b.queue = append(b.queue, m.buffer)
		b.iterator = m.iterator
		b.cutBufferCommon()
		return
	}
	// cutBufferAtLastChar
	if joinEmpty(b.buffer) {
		// Cutting an empty buffer before the same character twice means
		// pyfiglet would repeat this forever. Stop instead of eating memory.
		if b.lastEmptyCut == b.iterator {
			raise("RecursionLoop", "pyfiglet never finishes on this input")
		}
		b.lastEmptyCut = b.iterator
	}
	b.queue = append(b.queue, b.buffer)
	b.iterator--
	b.cutBufferCommon()
}

func (b *Builder) justifyString(justify string, buf [][]rune) [][]rune {
	out := copyBuffer(buf)
	switch justify {
	case "right":
		for row := 0; row < b.font.height; row++ {
			out[row] = padLeft(out[row], b.width-int64(len(out[row]))-1)
		}
	case "center":
		for row := 0; row < b.font.height; row++ {
			out[row] = padLeft(out[row], (b.width-int64(len(out[row])))/2)
		}
	}
	return out
}

func padLeft(row []rune, n int64) []rune {
	if n <= 0 {
		return row
	}
	out := make([]rune, 0, int(n)+len(row))
	for i := int64(0); i < n; i++ {
		out = append(out, ' ')
	}
	return append(out, row...)
}

func (b *Builder) replaceHardblanks(buf [][]rune) string {
	parts := make([]string, len(buf))
	for i, r := range buf {
		parts[i] = string(r)
	}
	s := strings.Join(parts, "\n") + "\n"
	return strings.ReplaceAll(s, b.font.hardBlank, " ")
}

func (b *Builder) smushAmount(buffer [][]rune, curChar [][]rune) int {
	if b.font.smushMode&(smSmush|smKern) == 0 {
		return 0
	}
	maxSmush := b.curCharWidth
	for row := 0; row < b.font.height; row++ {
		lineLeft := buffer[row]
		lineRight := curChar[row]
		if b.direction == "right-to-left" {
			lineLeft, lineRight = lineRight, lineLeft
		}

		linebd := rstripSpaceLen(lineLeft) - 1
		if linebd < 0 {
			linebd = 0
		}
		ch1 := noChar
		if linebd < len(lineLeft) {
			ch1 = lineLeft[linebd]
		} else {
			linebd = 0
		}

		charbd := len(lineRight) - lstripSpaceLen(lineRight)
		ch2 := noChar
		if charbd < len(lineRight) {
			ch2 = lineRight[charbd]
		} else {
			charbd = len(lineRight)
		}

		amt := charbd + len(lineLeft) - 1 - linebd
		if ch1 == noChar || ch1 == ' ' {
			amt++
		} else if ch2 != noChar {
			if _, ok := b.smushChars(ch1, ch2); ok {
				amt++
			}
		}
		if amt < maxSmush {
			maxSmush = amt
		}
	}
	return maxSmush
}

// in reproduces Python's  c in s  for a one-character (or empty) string c.
func in(c rune, set string) bool {
	if c == noChar {
		return true
	}
	return strings.ContainsRune(set, c)
}

var hierarchy = [][2]string{
	{"|", `/\[]{}()<>`},
	{`\/`, "[]{}()<>"},
	{"[]", "{}()<>"},
	{"{}", "()<>"},
	{"()", "<>"},
}

var lowline = [2]string{"_", `|/\[]{}()<>`}

// smushChars returns (result, true), or (_, false) for Python's None.
func (b *Builder) smushChars(left, right rune) (rune, bool) {
	if left == ' ' {
		return right, true
	}
	if right == ' ' {
		return left, true
	}
	if b.prevCharWidth < 2 || b.curCharWidth < 2 {
		return 0, false
	}
	mode := b.font.smushMode
	if mode&smSmush == 0 {
		return 0, false
	}
	hb := b.font.hardBlankRune
	if mode&63 == 0 {
		if left == hb {
			return right, true
		}
		if right == hb {
			return left, true
		}
		if b.direction == "right-to-left" {
			return left, true
		}
		return right, true
	}
	if mode&smHardblank != 0 && left == hb && right == hb {
		return left, true
	}
	if left == hb || right == hb {
		return 0, false
	}
	if mode&smEqual != 0 && left == right {
		return left, true
	}
	var smushes [][2]string
	if mode&smLowline != 0 {
		smushes = append(smushes, lowline)
	}
	if mode&smHierarchy != 0 {
		smushes = append(smushes, hierarchy...)
	}
	for _, ab := range smushes {
		a, bb := ab[0], ab[1]
		if in(left, a) && in(right, bb) {
			return right, true
		}
		if in(right, a) && in(left, bb) {
			return left, true
		}
	}
	if mode&smPair != 0 && left != noChar && right != noChar {
		for _, pair := range []string{string([]rune{left, right}), string([]rune{right, left})} {
			if pair == "[]" || pair == "{}" || pair == "()" {
				return '|', true
			}
		}
	}
	if mode&smBigX != 0 {
		if left == '/' && right == '\\' {
			return '|', true
		}
		if right == '/' && left == '\\' {
			return 'Y', true
		}
		if left == '>' && right == '<' {
			return 'X', true
		}
	}
	return 0, false
}

// ---- FigletString ----

var reverseMap, flipMap [256]rune

func init() {
	for i := range reverseMap {
		reverseMap[i] = rune(i)
		flipMap[i] = rune(i)
	}
	for _, p := range []string{"()", ")(", `/\`, `\/`, "<>", "><", "[]", "][", "{}", "}{"} {
		reverseMap[p[0]] = rune(p[1])
	}
	for _, p := range []string{`/\`, `\/`, "AV", "VA", "MW", "WM", "Pb", "Rb", "bP",
		"^v", "v^", "_-", "mw", "wm"} {
		flipMap[p[0]] = rune(p[1])
	}
}

func translate(row string, table *[256]rune) []rune {
	r := []rune(row)
	for i, c := range r {
		if c >= 0 && c < 256 {
			r[i] = table[c]
		}
	}
	return r
}

func newFromList(rows []string) string {
	return strings.Join(rows, "\n") + "\n"
}

func figReverse(s string) string {
	var out []string
	for _, row := range pySplitlinesString(s) {
		r := translate(row, &reverseMap)
		for i, j := 0, len(r)-1; i < j; i, j = i+1, j-1 {
			r[i], r[j] = r[j], r[i]
		}
		out = append(out, string(r))
	}
	return newFromList(out)
}

func figFlip(s string) string {
	rows := pySplitlinesString(s)
	var out []string
	for i := len(rows) - 1; i >= 0; i-- {
		out = append(out, string(translate(rows[i], &flipMap)))
	}
	return newFromList(out)
}

func figStripSurroundingNewlines(s string) string {
	var out []string
	seen := false
	for _, row := range pySplitlinesString(s) {
		if pyStripString(row) != "" || seen {
			seen = true
			out = append(out, row)
		}
	}
	return pyRstripString(newFromList(out))
}

func figNormalizeSurroundingNewlines(s string) string {
	return "\n" + figStripSurroundingNewlines(s) + "\n"
}
FIGLET_GO_EOF

# No Python may remain in the repository.
find . -name '*.py' -type f -delete
find . -name '__pycache__' -type d -prune -exec rm -rf {} +

gofmt -l . || true
go vet ./...
go build -o /dev/null ./...
go build -o /tmp/figlet .
/tmp/figlet -f slant "oracle ready"
