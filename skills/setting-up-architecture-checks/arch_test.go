package archtest_test

import (
	"fmt"
	"go/ast"
	"go/types"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"

	"golang.org/x/tools/go/packages"
)

// Architecture rules for the Go server layout (rules/go-server/architecture.md).
// It loads every package of the module, with tests, and checks each import and each use
// of a domain identifier from inbound adapters.

var modulePattern = regexp.MustCompile(`^internal/modules/([^/]+)(?:/(.*))?$`)

// Drivers and frameworks the core never sees.
var technical = []string{
	"github.com/jackc/pgx",
	"go.mongodb.org/mongo-driver",
	"github.com/danielgtaylor/huma",
	"net/http",
}

type place struct {
	module string // "" outside internal/modules
	layer  string // root, domain, application, in, out, sqlcgen, testkit, or the top folder outside modules
}

func locate(rel string) place {
	m := modulePattern.FindStringSubmatch(rel)
	if m == nil {
		top, _, _ := strings.Cut(strings.TrimPrefix(rel, "internal/"), "/")
		return place{layer: top}
	}
	rest := m[2]
	switch {
	case rest == "":
		return place{m[1], "root"}
	case under(rest, "domain"):
		return place{m[1], "domain"}
	case under(rest, "application"):
		return place{m[1], "application"}
	case under(rest, "testkit"):
		return place{m[1], "testkit"}
	case strings.Contains(rest, "/sqlcgen"):
		return place{m[1], "sqlcgen"}
	case under(rest, "adapters/in"):
		return place{m[1], "in"}
	case under(rest, "adapters/out"):
		return place{m[1], "out"}
	}
	return place{m[1], rest}
}

func under(path, dir string) bool { return path == dir || strings.HasPrefix(path, dir+"/") }

func isStdlib(path string) bool {
	first, _, _ := strings.Cut(path, "/")
	return !strings.Contains(first, ".")
}

type edge struct {
	from, to string // paths relative to the module, or the full path for packages outside it
	file     string
	test     bool
	internal bool // to is inside the module
	stdlib   bool
}

func TestArchitecture(t *testing.T) {
	cfg := &packages.Config{
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedImports | packages.NeedSyntax |
			packages.NeedTypes | packages.NeedTypesInfo | packages.NeedModule,
		Dir:   "../..",
		Tests: true,
	}
	pkgs, err := packages.Load(cfg, "./...")
	if err != nil {
		t.Fatalf("load packages: %v", err)
	}
	var violations []string
	seen := map[string]bool{}
	report := func(rule int, msg string) {
		line := fmt.Sprintf("rule %d: %s", rule, msg)
		if !seen[line] {
			seen[line] = true
			violations = append(violations, line)
		}
	}

	for _, pkg := range pkgs {
		if pkg.Module == nil || strings.HasSuffix(pkg.PkgPath, ".test") {
			continue
		}
		mod := pkg.Module.Path + "/"
		from := strings.TrimSuffix(strings.TrimPrefix(pkg.PkgPath, mod), "_test")
		for _, file := range pkg.Syntax {
			name := pkg.Fset.Position(file.Pos()).Filename
			isTest := strings.HasSuffix(name, "_test.go")
			for _, spec := range file.Imports {
				path, _ := strconv.Unquote(spec.Path.Value)
				e := edge{from: from, to: path, file: shortName(name), test: isTest, stdlib: isStdlib(path)}
				if rel, ok := strings.CutPrefix(path, mod); ok {
					e.to, e.internal = rel, true
				}
				checkImport(e, report)
			}
			if locate(from).layer == "in" && !isTest {
				checkDomainUses(pkg, file, mod+"internal/modules/"+locate(from).module+"/domain", report)
			}
		}
	}

	slices.Sort(violations)
	for _, v := range violations {
		t.Error(v)
	}
}

func checkImport(e edge, report func(int, string)) {
	src, dst := locate(e.from), place{}
	if e.internal {
		dst = locate(e.to)
	}
	sameModule := e.internal && src.module != "" && src.module == dst.module
	where := fmt.Sprintf("%s (%s) imports %s", e.from, e.file, e.to)

	// 8: a module's testkit serves only that module's tests.
	if e.internal && dst.layer == "testkit" && (!e.test || !sameModule) {
		report(8, where+": testkit is imported only by the same module's _test.go files")
	}
	// 9: generated rows stay in their persistence package.
	ownPersistence := sameModule && (src.layer == "out" || src.layer == "sqlcgen")
	if e.internal && dst.layer == "sqlcgen" && !ownPersistence {
		report(9, where+": sqlcgen is imported only by its own module's persistence package")
	}
	if e.test {
		return
	}
	// 5: outside a module, only its root package is visible, except to the composition root.
	if e.internal && dst.module != "" && dst.layer != "root" && !sameModule && src.layer != "app" && src.layer != "archtest" {
		report(5, where+": another module is reached only through its root package internal/modules/"+dst.module)
	}
	// 7: shared kernels and technical packages know no module and no composition root.
	if slices.Contains([]string{"shared", "infrastructure", "common", "libs"}, src.layer) && src.module == "" &&
		e.internal && (dst.module != "" || dst.layer == "app") {
		report(7, where+": "+src.layer+" never imports modules or app")
	}

	toShared := e.internal && dst.layer == "shared"
	toOwn := func(layers ...string) bool { return sameModule && slices.Contains(layers, dst.layer) }

	switch src.layer {
	case "domain":
		// 1: the domain is plain Go: stdlib, internal/shared and itself.
		if allowed := e.stdlib || toShared || toOwn("domain"); !allowed {
			report(1, where+": domain imports only the standard library, internal/shared and its own domain")
		}
		if isTechnical(e.to) {
			report(1, where+": no driver, framework or net/http in the domain")
		}
	case "application":
		// 2: use cases depend on their own domain, shared and stdlib.
		if allowed := e.stdlib || toShared || toOwn("domain", "application"); !allowed {
			report(2, where+": application imports only its own domain, internal/shared and the standard library")
		}
		if isTechnical(e.to) {
			report(2, where+": no driver, framework or net/http in application")
		}
	case "in":
		// 3: inbound adapters call their own use cases; never infrastructure, drivers or outbound adapters.
		if (e.internal && (dst.layer == "infrastructure" || dst.layer == "app" || dst.layer == "config" ||
			(sameModule && (dst.layer == "out" || dst.layer == "sqlcgen")) || (dst.module != "" && !sameModule))) ||
			strings.HasPrefix(e.to, "github.com/jackc/pgx") || strings.HasPrefix(e.to, "go.mongodb.org/mongo-driver") {
			report(3, where+": inbound adapters use their own application, shared, common, libs and huma")
		}
	case "out":
		// 4: outbound adapters implement ports; other modules only through their root package.
		if e.internal && (dst.layer == "app" || dst.layer == "common" || dst.layer == "config" ||
			(sameModule && dst.layer == "in") || (dst.module != "" && !sameModule && dst.layer != "root")) {
			report(4, where+": outbound adapters use their own application and domain, shared, infrastructure, libs and other modules' root packages")
		}
	case "root":
		// 6: the module root re-exports its use cases and errors; importing an adapter would close a cycle.
		if allowed := e.stdlib || toOwn("application", "domain"); !allowed {
			report(6, where+": the module root imports only its own application and domain")
		}
	}
}

func isTechnical(path string) bool {
	for _, p := range technical {
		if path == p || strings.HasPrefix(path, p+"/") {
			return true
		}
	}
	return false
}

// checkDomainUses enforces rule 3's second half: from its domain an inbound adapter uses only
// value lists — constants, their named types and the package-level slices that list them.
func checkDomainUses(pkg *packages.Package, file *ast.File, domainPath string, report func(int, string)) {
	ast.Inspect(file, func(n ast.Node) bool {
		id, ok := n.(*ast.Ident)
		if !ok {
			return true
		}
		obj := pkg.TypesInfo.Uses[id]
		if obj == nil || obj.Pkg() == nil || obj.Pkg().Path() != domainPath || isValueList(obj) {
			return true
		}
		pos := pkg.Fset.Position(id.Pos())
		report(3, fmt.Sprintf("%s:%d uses domain.%s: inbound adapters use only the domain's value lists",
			shortName(pos.Filename), pos.Line, obj.Name()))
		return true
	})
}

func isValueList(obj types.Object) bool {
	switch o := obj.(type) {
	case *types.Const:
		return true
	case *types.TypeName:
		_, basic := o.Type().Underlying().(*types.Basic)
		return basic
	case *types.Var:
		if o.Parent() != o.Pkg().Scope() {
			return false
		}
		s, ok := o.Type().(*types.Slice)
		if !ok {
			return false
		}
		_, basic := s.Elem().Underlying().(*types.Basic)
		_, named := s.Elem().(*types.Named)
		return basic && named
	}
	return false
}

func shortName(path string) string {
	if i := strings.Index(path, "/internal/"); i >= 0 {
		return path[i+1:]
	}
	return path
}
