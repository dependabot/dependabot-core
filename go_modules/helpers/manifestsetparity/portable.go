package manifestsetparity

import (
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Bounds may not have leading zeros: Go treats {01} as literal text while Ruby treats it as a count.
var boundedRepeat = regexp.MustCompile(`\A\{(0|[1-9]\d{0,3})(,(0|[1-9]\d{0,3})?)?\}`)

const (
	escapableLiterals = `.^$|?*+()[]{}\/-`
	controlEscapes    = "tnvfr"
)

// CompilePortable checks that source stays within the regex subset documented in the catalog README
// and compiles it with Go's regexp package. It mirrors Dependabot::ManifestSets::PortableRegex.
func CompilePortable(ruleID, source string) (*regexp.Regexp, error) {
	if err := validatePortable(ruleID, source); err != nil {
		return nil, err
	}
	re, err := regexp.Compile(source)
	if err != nil {
		return nil, invalid("invalid_regex", "rule %q: %v", ruleID, err)
	}
	return re, nil
}

type portableScanner struct {
	ruleID     string
	chars      []rune
	pos        int
	groupDepth int
	repeatable bool
	// Largest product of nested {n,m} counts in the item being quantified (0 when there is none), in
	// finished items at the current group level, and in the enclosing levels.
	itemWeight   int
	levelWeight  int
	outerWeights []int
}

func validatePortable(ruleID, source string) error {
	reject := func(code, format string, args ...any) error {
		return invalid(code, "rule %q: "+format, append([]any{ruleID}, args...)...)
	}
	if len(source) > MaxRegexBytes {
		return reject("regex_too_long", "exceeds %d bytes", MaxRegexBytes)
	}
	if !utf8.ValidString(source) {
		return reject("non_portable_regex", "must be valid UTF-8")
	}
	if !strings.HasPrefix(source, `\A`) || !strings.HasSuffix(source, `\z`) || utf8.RuneCountInString(source) <= 3 {
		return reject("missing_anchor", `must start with \A and end with \z`)
	}
	body := source[2 : len(source)-2]
	trailing := len(body) - len(strings.TrimRight(body, `\`))
	if trailing%2 == 1 {
		return reject("missing_anchor", `the final \z is escaped`)
	}

	s := &portableScanner{ruleID: ruleID, chars: []rune(body), levelWeight: 1}
	if err := s.scan(); err != nil {
		return err
	}
	if s.groupDepth != 0 {
		return reject("non_portable_regex", "unbalanced group")
	}
	return nil
}

func (s *portableScanner) reject(format string, args ...any) error {
	return invalid("non_portable_regex", "rule %q: "+format, append([]any{s.ruleID}, args...)...)
}

func (s *portableScanner) at(i int) rune {
	if i < len(s.chars) {
		return s.chars[i]
	}
	return 0
}

func (s *portableScanner) scan() error {
	for s.pos < len(s.chars) {
		var err error
		switch c := s.chars[s.pos]; c {
		case '\\':
			err = s.escape()
		case '[':
			err = s.class()
		case '(':
			err = s.groupOpen()
		case ')':
			if s.groupDepth == 0 {
				return s.reject("unbalanced group")
			}
			s.groupDepth--
			s.pos++
			s.finishItem()
			groupWeight := s.levelWeight
			s.levelWeight = s.outerWeights[len(s.outerWeights)-1]
			s.outerWeights = s.outerWeights[:len(s.outerWeights)-1]
			s.startItem(groupWeight)
		case '|':
			if s.groupDepth == 0 {
				return s.reject("top-level alternation escapes the anchors")
			}
			s.pos++
			s.finishItem()
			s.repeatable = false
		case '*', '+', '?':
			if !s.repeatable {
				return s.reject("quantifier has nothing to repeat")
			}
			s.pos++
			err = s.followQuantifier()
		case '{':
			err = s.boundedRepeat()
		case '^', '$':
			return s.reject(`only \A and \z anchors are allowed`)
		case '}', ']':
			return s.reject("unescaped %c", c)
		default:
			s.pos++
			s.startItem(1)
		}
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *portableScanner) escape() error {
	if s.pos+1 >= len(s.chars) {
		return s.reject("dangling escape")
	}
	escaped := s.chars[s.pos+1]
	if !strings.ContainsRune(escapableLiterals, escaped) && !strings.ContainsRune(controlEscapes, escaped) {
		return s.reject(`unsupported escape \%c`, escaped)
	}
	s.pos += 2
	s.startItem(1)
	return nil
}

func (s *portableScanner) class() error {
	s.pos++
	if s.at(s.pos) == '^' {
		s.pos++
	}
	if s.at(s.pos) == ']' {
		return s.reject("character class may not start with ]")
	}
	members := 0
	for {
		if s.pos >= len(s.chars) {
			return s.reject("unterminated character class")
		}
		c := s.chars[s.pos]
		if c == ']' {
			break
		}
		switch c {
		case '\\':
			if err := s.escape(); err != nil {
				return err
			}
			members++
			continue
		case '[':
			return s.reject("nested classes and POSIX classes are not allowed")
		case '&':
			if s.at(s.pos+1) == '&' {
				return s.reject("class intersection is not allowed")
			}
		}
		s.pos++
		members++
	}
	if members == 0 {
		return s.reject("empty character class")
	}
	s.pos++
	s.startItem(1)
	return nil
}

func (s *portableScanner) groupOpen() error {
	if s.at(s.pos+1) == '?' {
		// Flags such as (?i: are excluded: they fold non-ASCII characters (U+212A matches k), so rules spell out ASCII classes.
		if s.at(s.pos+2) != ':' {
			return s.reject("only (...) and (?:...) groups are allowed")
		}
		s.pos += 3
	} else {
		s.pos++
	}
	s.groupDepth++
	s.finishItem()
	s.outerWeights = append(s.outerWeights, s.levelWeight)
	s.levelWeight = 1
	s.repeatable = false
	return nil
}

func (s *portableScanner) boundedRepeat() error {
	m := boundedRepeat.FindStringSubmatch(string(s.chars[s.pos:]))
	if m == nil {
		return s.reject("malformed {n,m} repetition")
	}
	if !s.repeatable {
		return s.reject("quantifier has nothing to repeat")
	}
	minimum, _ := strconv.Atoi(m[1])
	// {n} repeats exactly n times; only {n,} is open-ended.
	maximum := minimum
	if m[3] != "" {
		maximum, _ = strconv.Atoi(m[3])
	} else if m[2] != "" {
		maximum = -1
	}
	if minimum > MaxRepeat || maximum > MaxRepeat {
		return s.reject("repetition count exceeds %d", MaxRepeat)
	}
	if maximum >= 0 && maximum < minimum {
		return s.reject("repetition {n,m} requires n <= m")
	}
	if err := s.repeatWeight(minimum, maximum); err != nil {
		return err
	}
	s.pos += utf8.RuneCountInString(m[0])
	return s.followQuantifier()
}

func (s *portableScanner) startItem(weight int) {
	s.finishItem()
	s.itemWeight = weight
	s.repeatable = true
}

func (s *portableScanner) finishItem() {
	s.levelWeight = max(s.levelWeight, s.itemWeight)
	s.itemWeight = 0
}

// repeatWeight mirrors regexp/syntax repeatIsValid: {0} hides what it repeats, an open {n,} counts as n,
// and counts along any nesting path may not multiply past MaxRepeat.
func (s *portableScanner) repeatWeight(minimum, maximum int) error {
	if maximum == 0 {
		s.itemWeight = 1
		return nil
	}
	count := maximum
	if count < 0 {
		count = minimum
	}
	weight := max(count, 1) * s.itemWeight
	if weight > MaxRepeat {
		return s.reject("nested repetition counts exceed %d", MaxRepeat)
	}
	s.itemWeight = weight
	return nil
}

func (s *portableScanner) followQuantifier() error {
	if next := s.at(s.pos); next == '*' || next == '+' || next == '?' || next == '{' {
		return s.reject("lazy, possessive and stacked quantifiers are not allowed")
	}
	s.repeatable = false
	return nil
}
