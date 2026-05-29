/*
 * test_interpreters.c — regression + feature test harness for the
 * bundled C / C++ / Fortran tree-walking interpreters
 * (gcc/offlinai_cc.c, cpp/offlinai_cpp.c, fortran/offlinai_fortran.c).
 *
 * Build & run (from repo root):
 *     ./interpreter_tests/run.sh
 * or manually:
 *     clang -O0 -g -Igcc -Icpp -Ifortran \
 *         interpreter_tests/test_interpreters.c \
 *         gcc/offlinai_cc.c cpp/offlinai_cpp.c fortran/offlinai_fortran.c \
 *         -o /tmp/test_interpreters && /tmp/test_interpreters
 *
 * Exit code 0 = all passed, 1 = at least one failure.
 *
 * Each case runs a snippet and asserts the program (a) ran without
 * error and (b) produced output containing an expected substring.
 * The cases tagged [bug] guard a specific bug fixed in this repo —
 * if one regresses, this harness goes red.
 */

#include <stdio.h>
#include <string.h>

#include "offlinai_cc.h"      /* occ_*   */
#include "offlinai_cpp.h"     /* ocpp_*  */
#include "offlinai_fortran.h" /* ofort_* */

static int g_pass = 0, g_fail = 0;

/* ── generic assertion ─────────────────────────────────────────────
 * want == NULL  → expect a clean run (rc==0), output unchecked
 * want != NULL  → expect rc==0 AND output contains `want`
 * want has prefix "ERR:" → expect rc!=0 (error case)
 */
static void check(const char *lang, const char *name, int rc,
                  const char *out, const char *err, const char *want) {
    int ok;
    if (want && strncmp(want, "ERR:", 4) == 0) {
        ok = (rc != 0);
    } else {
        ok = (rc == 0) && (want == NULL || (out && strstr(out, want)));
    }
    if (ok) {
        g_pass++;
        printf("  \033[32mPASS\033[0m [%s] %s\n", lang, name);
    } else {
        g_fail++;
        printf("  \033[31mFAIL\033[0m [%s] %s\n", lang, name);
        printf("        rc=%d want=%s\n", rc, want ? want : "(clean)");
        if (out && *out) printf("        out=%.200s\n", out);
        if (rc != 0 && err && *err) printf("        err=%.200s\n", err);
    }
}

/* ── per-language runners ──────────────────────────────────────── */
static void c_case(const char *name, const char *src, const char *want) {
    OccInterpreter *I = occ_create();
    int rc = occ_execute(I, src);
    check("C", name, rc, occ_get_output(I), occ_get_error(I), want);
    occ_destroy(I);
}
static void cpp_case(const char *name, const char *src, const char *want) {
    OcppInterpreter *I = ocpp_create();
    int rc = ocpp_execute(I, src);
    check("C++", name, rc, ocpp_get_output(I), ocpp_get_error(I), want);
    ocpp_destroy(I);
}
static void f_case(const char *name, const char *src, const char *want) {
    OfortInterpreter *I = ofort_create();
    int rc = ofort_execute(I, src);
    check("Fortran", name, rc, ofort_get_output(I), ofort_get_error(I), want);
    ofort_destroy(I);
}

/* ════════════════════════════════════════════════════════════════ */
static void test_c(void) {
    printf("\n=== C interpreter (offlinai_cc.c) ===\n");

    /* [bug] switch/case must compare via val_to_int, not raw union */
    c_case("switch char case [bug]",
        "int main(){char c='B';switch(c){case 'A':printf(\"A\");break;"
        "case 'B':printf(\"gotB\");break;default:printf(\"D\");}return 0;}",
        "gotB");
    c_case("switch int + fallthrough",
        "int main(){int x=1;switch(x){case 1:case 2:printf(\"onetwo\");break;"
        "default:printf(\"d\");}return 0;}", "onetwo");

    /* [bug] memset / memcpy were no-ops */
    c_case("memset zero [bug]",
        "int main(){int a[5];memset(a,0,5);a[2]=7;printf(\"%d-%d\",a[0],a[2]);return 0;}",
        "0-7");
    c_case("memcpy [bug]",
        "int main(){int s[3];s[0]=1;s[1]=2;s[2]=3;int d[3];memcpy(d,s,3);"
        "printf(\"%d%d%d\",d[0],d[1],d[2]);return 0;}", "123");
    c_case("malloc + memset [bug]",
        "int main(){int*p=malloc(3);memset(p,9,3);printf(\"%d%d\",p[0],p[2]);return 0;}",
        "99");

    /* [bug] 2-D arrays: flat assignment + dims > 255 stride */
    c_case("2D small assign [bug]",
        "int main(){int m[2][3];m[1][2]=42;printf(\"%d\",m[1][2]);return 0;}", "42");
    c_case("2D large stride [bug]",
        "int main(){int m[2][300];m[1][299]=42;printf(\"%d\",m[1][299]);return 0;}", "42");

    /* general features */
    c_case("1D array + for",
        "int main(){int a[4];for(int i=0;i<4;i++)a[i]=i*i;"
        "printf(\"%d%d%d%d\",a[0],a[1],a[2],a[3]);return 0;}", "0149");
    c_case("arithmetic + modulo",
        "int main(){int a=7,b=3;printf(\"%d %d %d\",a+b,a*b,a%b);return 0;}", "10 21 1");
    c_case("recursion (factorial)",
        "int fact(int n){return n<=1?1:n*fact(n-1);}"
        "int main(){printf(\"%d\",fact(5));return 0;}", "120");
    c_case("pointer deref",
        "int main(){int x=5;int*p=&x;*p=11;printf(\"%d\",x);return 0;}", "11");
    c_case("while loop",
        "int main(){int i=0,s=0;while(i<5){s+=i;i++;}printf(\"%d\",s);return 0;}", "10");

    /* [feat] newly added math builtins */
    c_case("math hypot/trunc [feat]",
        "int main(){printf(\"%d %d\",(int)hypot(3.0,4.0),(int)trunc(3.9));return 0;}", "5 3");
    c_case("math isnan/isinf [feat]",
        "int main(){printf(\"%d%d\",isnan(0.0),isinf(0.0));return 0;}", "00");
    c_case("math lround/copysign [feat]",
        "int main(){printf(\"%d %d\",(int)lround(2.6),(int)copysign(3.0,-1.0));return 0;}", "3 -3");
}

static void test_cpp(void) {
    printf("\n=== C++ interpreter (offlinai_cpp.c) ===\n");

    /* [bug] unary operators must bind looser than postfix */
    cpp_case("neg of index [bug]",
        "#include <iostream>\nint main(){int a[3]={5,6,7};std::cout<<(-a[1]);return 0;}", "-6");
    cpp_case("not of method [bug]",
        "#include <iostream>\n#include <vector>\nint main(){std::vector<int> v;"
        "std::cout<<(!v.empty());return 0;}", "0");
    cpp_case("neg of call [bug]",
        "#include <iostream>\nint f(){return 5;}int main(){std::cout<<(-f());return 0;}", "-5");

    /* [bug] unary minus must evaluate operand once */
    cpp_case("neg single-eval [bug]",
        "#include <iostream>\nint main(){int x=5;int y=-(x=x+1);std::cout<<y<<\" \"<<x;return 0;}",
        "-6 6");

    /* [bug] sort / reverse / swap */
    cpp_case("sort begin/end [bug]",
        "#include <iostream>\n#include <vector>\n#include <algorithm>\nint main(){"
        "std::vector<int> v;v.push_back(3);v.push_back(1);v.push_back(2);"
        "std::sort(v.begin(),v.end());std::cout<<v[0]<<v[1]<<v[2];return 0;}", "123");
    cpp_case("reverse begin/end [bug]",
        "#include <iostream>\n#include <vector>\n#include <algorithm>\nint main(){"
        "std::vector<int> v;v.push_back(1);v.push_back(2);v.push_back(3);"
        "std::reverse(v.begin(),v.end());std::cout<<v[0]<<v[1]<<v[2];return 0;}", "321");
    cpp_case("swap [bug]",
        "#include <iostream>\nint main(){int a=5,b=9;std::swap(a,b);std::cout<<a<<\" \"<<b;return 0;}",
        "9 5");

    /* [bug] index arg passed to function must evaluate once */
    cpp_case("arg index single-eval [bug]",
        "#include <iostream>\nint g(int x){return x;}int main(){int a[3]={10,20,30};int i=0;"
        "int r=g(a[i++]);std::cout<<r<<\" \"<<i;return 0;}", "10 1");

    /* [bug] lambda many captures+params must not overflow */
    cpp_case("lambda many captures [bug]",
        "#include <iostream>\nint main(){int a=1,b=2,c=3,d=4,e=5,f=6,g=7,h=8,i=9,j=10;"
        "auto L=[a,b,c,d,e,f,g,h,i,j](int p,int q,int r,int s,int t,int u){return a+p;};"
        "std::cout<<L(100,0,0,0,0,0);return 0;}", "101");

    /* general features */
    cpp_case("cout chaining",
        "#include <iostream>\nint main(){int a=2,b=3;std::cout<<a<<\"+\"<<b<<\"=\"<<(a+b);return 0;}",
        "2+3=5");
    cpp_case("vector push_back/size",
        "#include <iostream>\n#include <vector>\nint main(){std::vector<int> v;v.push_back(10);"
        "v.push_back(20);std::cout<<v[0]<<\" \"<<v[1]<<\" \"<<v.size();return 0;}", "10 20 2");
    cpp_case("lambda capture",
        "#include <iostream>\nint main(){int base=10;auto add=[base](int x){return base+x;};"
        "std::cout<<add(5);return 0;}", "15");
    cpp_case("for-loop sum",
        "#include <iostream>\nint main(){int s=0;for(int i=1;i<=5;i++)s+=i;std::cout<<s;return 0;}",
        "15");
    cpp_case("simple class",
        "#include <iostream>\nclass P{public:int x;int get(){return x;}};"
        "int main(){P p;p.x=7;std::cout<<p.get();return 0;}", "7");

    /* [feat] newly added <numeric>/<algorithm> reductions */
    cpp_case("accumulate [feat]",
        "#include <iostream>\n#include <vector>\n#include <numeric>\nint main(){"
        "std::vector<int> v;v.push_back(3);v.push_back(1);v.push_back(4);"
        "std::cout<<accumulate(v.begin(),v.end(),0);return 0;}", "8");
    cpp_case("count [feat]",
        "#include <iostream>\n#include <vector>\n#include <algorithm>\nint main(){"
        "std::vector<int> v;v.push_back(1);v.push_back(2);v.push_back(1);"
        "std::cout<<count(v.begin(),v.end(),1);return 0;}", "2");
    cpp_case("max_element/min_element [feat]",
        "#include <iostream>\n#include <vector>\n#include <algorithm>\nint main(){"
        "std::vector<int> v;v.push_back(3);v.push_back(9);v.push_back(2);"
        "std::cout<<max_element(v.begin(),v.end())<<\" \"<<min_element(v.begin(),v.end());return 0;}",
        "9 2");
    cpp_case("fill [feat]",
        "#include <iostream>\n#include <vector>\n#include <algorithm>\nint main(){"
        "std::vector<int> v;v.push_back(0);v.push_back(0);fill(v.begin(),v.end(),7);"
        "std::cout<<v[0]<<v[1];return 0;}", "77");
}

static void test_fortran(void) {
    printf("\n=== Fortran interpreter (offlinai_fortran.c) ===\n");

    /* [bug] SELECT CASE value lists + ranges */
    f_case("select case value-list [bug]",
        "program p\n integer::x=2\n select case(x)\n  case(1,2,3)\n   print *,'low'\n"
        "  case default\n   print *,'other'\n end select\nend program p\n", "low");
    f_case("select case mixed range [bug]",
        "program p\n integer::x=7\n select case(x)\n  case(1,5:10,20)\n   print *,'hit'\n"
        "  case default\n   print *,'miss'\n end select\nend program p\n", "hit");
    f_case("select case default",
        "program p\n integer::x=99\n select case(x)\n  case(1,2)\n   print *,'a'\n"
        "  case default\n   print *,'def'\n end select\nend program p\n", "def");

    /* [bug] whole-array = scalar must BROADCAST, not replace */
    f_case("array broadcast [bug]",
        "program p\n integer::a(3)\n a=7\n a(2)=99\n print *,a(1),a(2),a(3)\nend program p\n",
        "7");
    f_case("broadcast then element read [bug]",
        "program p\n integer::a(3)\n a=0\n print *,a(2)\nend program p\n", "0");

    /* [bug] pass-by-reference write-back */
    f_case("pass-by-ref scalar [bug]",
        "program p\n integer::x\n x=5\n call dbl(x)\n print *,x\ncontains\n"
        " subroutine dbl(a)\n  integer::a\n  a=a*2\n end subroutine\nend program p\n", "10");
    f_case("pass-by-ref whole array [bug]",
        "program p\n integer::arr(3)\n arr=0\n call fill(arr)\n print *,arr(1),arr(2),arr(3)\n"
        "contains\n subroutine fill(v)\n  integer::v(3)\n  v(1)=10;v(2)=20;v(3)=30\n"
        " end subroutine\nend program p\n", "10");
    f_case("pass-by-ref array element [bug]",
        "program p\n integer::arr(3)\n arr=0\n call setit(arr(2))\n print *,arr(2)\n"
        "contains\n subroutine setit(a)\n  integer::a\n  a=99\n end subroutine\nend program p\n",
        "99");

    /* general features */
    f_case("scalar assign + print",
        "program p\n integer::x\n x=42\n print *,x\nend program p\n", "42");
    f_case("do loop sum",
        "program p\n integer::i,s\n s=0\n do i=1,5\n  s=s+i\n end do\n print *,s\nend program p\n",
        "15");
    f_case("array element assign",
        "program p\n integer::a(3)\n a(1)=10;a(2)=20;a(3)=30\n print *,a(1),a(2),a(3)\nend program p\n",
        "10");
    f_case("function call",
        "program p\n integer::y\n y=sq(6)\n print *,y\ncontains\n integer function sq(a)\n"
        "  integer::a\n  sq=a*a\n end function\nend program p\n", "36");
    f_case("real arithmetic",
        "program p\n real::x\n x=3.0\n print *,x*2.0\nend program p\n", "6");
    f_case("if-then-else",
        "program p\n integer::x=5\n if (x>3) then\n  print *,'big'\n else\n  print *,'small'\n"
        " end if\nend program p\n", "big");

    /* [feat] newly added intrinsics */
    f_case("modulo [feat]",
        "program p\n print *, modulo(-3,5)\nend program p\n", "2");
    f_case("bit ops iand/ior/ieor [feat]",
        "program p\n print *, iand(12,10), ior(12,10), ieor(12,10)\nend program p\n", "8");
    f_case("ishft [feat]",
        "program p\n print *, ishft(1,4)\nend program p\n", "16");
    f_case("maxloc/minloc [feat]",
        "program p\n integer::a(4)\n a(1)=3;a(2)=9;a(3)=1;a(4)=5\n print *, maxloc(a), minloc(a)\n"
        "end program p\n", "2");
    f_case("merge [feat]",
        "program p\n print *, merge(100,200,1>0)\nend program p\n", "100");
    f_case("sinh/cosh [feat]",
        "program p\n print *, nint(cosh(0.0))\nend program p\n", "1");
}

int main(void) {
    printf("==================================================\n");
    printf(" Interpreter regression + feature tests\n");
    printf(" ([bug] = guards a specific fixed bug)\n");
    printf("==================================================\n");

    test_c();
    test_cpp();
    test_fortran();

    printf("\n==================================================\n");
    printf(" RESULT: %d passed, %d failed\n", g_pass, g_fail);
    printf("==================================================\n");
    return g_fail == 0 ? 0 : 1;
}
